# =====================================================================
# Healthcare Intelligence app (Streamlit in Snowflake)
#   KPI tabs read the small MARTS tables (fast).
#   AI Insights asks the agent; AI_REDACT removes personal data from every question first.
#   Cortex AI functions used:
#     AI_REDACT    - removes personal data from questions (AI Insights, Governance)
#     AI_COMPLETE  - writes a short summary of the headline numbers (Overview)
#     AI_CLASSIFY  - tags every question with a topic (AI Insights -> Governance chart)
#     AI_SENTIMENT - reads the feedback users give on answers (AI Insights -> Governance)
#     DATA_AGENT_RUN - calls the Cortex Agent (AI Insights)
#   Role-based PII: the Patients tab shows FULL / PARTIAL / NO personal data depending on the role.
#   Report: the sidebar builds a downloadable report with only the sections the role may see.
#   Each role only sees the tabs listed for it in APP_ROLE_PERMISSIONS.
# =====================================================================
import html
import json
import time
from datetime import datetime

import altair as alt
import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

import config

DB = config.DATABASE
MARTS = f"{DB}.{config.MARTS}"
GOV = f"{DB}.{config.GOVERNANCE}"
AGENT = f"{DB}.{config.ANALYTICS}.{config.AGENT}"
REDACT = ("ARRAY_CONSTRUCT('NAME', 'EMAIL', 'PHONE_NUMBER', 'DATE_OF_BIRTH', 'ADDRESS', 'NATIONAL_ID', "
          "'PASSPORT', 'TAX_IDENTIFIER', 'PAYMENT_CARD_DATA', 'DRIVERS_LICENSE', 'IP_ADDRESS')")   # age + gender kept on purpose
AI_MODEL = getattr(config, "AI_MODEL", "claude-sonnet-4-5")       # model for AI_COMPLETE
TOPICS = ["Clinical", "Hospital", "Pharmacy & Vaccines", "Claims & Cost", "Other"]   # labels for AI_CLASSIFY
SAMPLE_QUESTIONS = [
    "What is the 30-day readmission rate by age group?",
    "How many living adults are in each BMI category?",
    "How many patients have had a heart attack, and how many of them are currently on blood pressure medication?",
    "How many patients received a flu vaccine each year?",
    "Which insurers have the most open claims?",
]
TABS = {
    "TAB.OVERVIEW": "📊 Overview", "TAB.CLINICAL": "🩺 Clinical", "TAB.HOSPITAL": "🏥 Hospital",
    "TAB.PHARMACY_VACCINES": "💊 Pharmacy & Vaccines", "TAB.CLAIMS_COST": "💰 Claims & Cost",
    "TAB.PATIENTS": "👤 Patients", "TAB.AI_INSIGHTS": "🤖 AI Insights", "TAB.GOVERNANCE": "🔐 Governance",
    "TAB.QUALITY": "✅ Quality",
}
PII_TEXT = {"FULL": "Full personal data (engineer)",
            "PARTIAL": "Partial: names and date of birth; SSN last 4 digits; address hidden",
            "NONE": "None: all personal data masked"}
HISTORY_DAYS, HISTORY_SIZE = 7, 5                                  # 'your recent questions' box

st.set_page_config(page_title="Healthcare Intelligence", page_icon="🩺", layout="wide")
session = get_active_session()


@st.cache_data(ttl=600, show_spinner=False)          # cache every query for 10 minutes
def q(sql, params=None):
    return session.sql(sql, params=params).to_pandas()


def business_headers(df):
    """PATIENT_COUNT -> Patient Count: no raw column names on screen."""
    return df.rename(columns=lambda c: str(c).replace("_", " ").title())


def table(df):
    df = business_headers(df)
    try:
        st.dataframe(df, hide_index=True, use_container_width=True)
    except TypeError:                                 # older Streamlit versions
        st.dataframe(df, use_container_width=True)


# ---------------------------------------------------------------------
# Number formats (mentor's rules): K / mn / bn with 2 decimals, percentages with 2 decimals
# ---------------------------------------------------------------------
def short(n):
    """61820 -> 61.82K, 64535917 -> 64.54mn, 845 -> 845"""
    if n is None or pd.isna(n):
        return "–"
    n = float(n)
    for size, suffix in ((1e9, "bn"), (1e6, "mn"), (1e3, "K")):
        if abs(n) >= size:
            return f"{n / size:.2f}{suffix}"
    return f"{n:,.0f}"


def money(n):
    """174250000000 -> $174.25bn, 850.75 -> $850.75"""
    if n is None or pd.isna(n):
        return "–"
    return f"${short(n)}" if abs(float(n)) >= 1e3 else f"${float(n):,.2f}"


def pct(fraction):
    """0.1706 -> 17.06%"""
    return "–" if fraction is None or pd.isna(fraction) else f"{100 * float(fraction):.2f}%"


# The same rules for chart axes (Vega expressions)
AXIS_SHORT = ("abs(datum.value) >= 1e9 ? format(datum.value / 1e9, '.2f') + 'bn' : "
              "abs(datum.value) >= 1e6 ? format(datum.value / 1e6, '.2f') + 'mn' : "
              "abs(datum.value) >= 1e3 ? format(datum.value / 1e3, '.2f') + 'K' : format(datum.value, ',.0f')")
AXIS = {"count": AXIS_SHORT, "money": "'$' + (" + AXIS_SHORT + ")", "pct": "format(datum.value, '.2f') + '%'"}
LABEL = {"count": short, "money": money, "pct": lambda v: f"{float(v):.2f}%"}   # pct charts hold 0-100 values


# ---------------------------------------------------------------------
# Who is viewing, and which tabs may they see?
# ---------------------------------------------------------------------
def viewer_name():
    user = getattr(st, "user", None) or getattr(st, "experimental_user", None)
    try:
        return str(user["user_name"]).upper()
    except Exception:
        return str(getattr(user, "user_name", "UNKNOWN")).upper()


VIEWER = viewer_name()
roles = q(f"SELECT app_role FROM {GOV}.APP_USER_ROLES WHERE UPPER(user_name) = ?", [VIEWER])["APP_ROLE"].tolist()
permissions = q(f"SELECT role_name, permission FROM {GOV}.APP_ROLE_PERMISSIONS")

with st.sidebar:
    st.title("🩺 Healthcare Intelligence")
    st.caption(f"Signed in as **{VIEWER}**")
    if not roles:
        st.error("You have no role for this app.")
        st.stop()
    ROLE = st.selectbox("Viewing as role", roles,
                        index=roles.index(config.ENGINEER_ROLE) if config.ENGINEER_ROLE in roles else 0)
    ALLOWED = set(permissions[permissions["ROLE_NAME"] == ROLE]["PERMISSION"])
    PII_LEVEL = "FULL" if "PII.FULL" in ALLOWED else "PARTIAL" if "PII.PARTIAL" in ALLOWED else "NONE"
    st.caption(f"🔐 Personal data: **{PII_TEXT[PII_LEVEL]}**")

    st.markdown("---")
    GRAIN = st.radio("Show trends by", ["Year", "Month"], horizontal=True)
    span = q(f"SELECT MIN(VISIT_MONTH) AS LO, MAX(VISIT_MONTH) AS HI FROM {MARTS}.KPI_VISITS_MONTHLY").iloc[0]
    MONTHS = list(pd.date_range(pd.Timestamp(span["LO"]), pd.Timestamp(span["HI"]), freq="MS"))
    default_from = max(MONTHS[0], pd.Timestamp("2015-01-01"))
    PERIOD_FROM, PERIOD_TO = st.select_slider("Period (month and year)", options=MONTHS,
                                              value=(default_from, MONTHS[-1]),
                                              format_func=lambda d: d.strftime("%b %Y"))
    PERIOD = [PERIOD_FROM.strftime("%Y-%m-%d"), PERIOD_TO.strftime("%Y-%m-%d")]
    st.caption(f"Trends: {PERIOD_FROM:%b %Y} – {PERIOD_TO:%b %Y}, by {GRAIN.lower()}")
    st.caption("Synthetic data · not medical advice")


def can(permission):
    return permission in ALLOWED


def by_period(month_column):
    """SQL for the chosen grain: groups a month column by year or by month."""
    return f"DATE_TRUNC('{GRAIN.lower()}', {month_column})::DATE"


IN_PERIOD = "BETWEEN ? AND ?"


# ---------------------------------------------------------------------
# Charts (Altair): business titles, formatted axes and tooltips, no gridlines
# ---------------------------------------------------------------------
def trend_chart(df, value, kind="count", series=None, mark="line", title=""):
    if df.empty:
        st.info("No data for this period.")
        return
    df = df.copy()
    df["PERIOD"] = pd.to_datetime(df["PERIOD"])
    df["VALUE_LABEL"] = df[value].map(LABEL[kind])
    df["PERIOD_LABEL"] = df["PERIOD"].dt.strftime("%Y" if GRAIN == "Year" else "%b %Y")
    x = alt.X("PERIOD:T", title=GRAIN, axis=alt.Axis(format="%Y" if GRAIN == "Year" else "%b %Y", grid=False))
    y = alt.Y(f"{value}:Q", title=title, axis=alt.Axis(labelExpr=AXIS[kind], grid=False))
    tooltip = [alt.Tooltip("PERIOD_LABEL:N", title=GRAIN), alt.Tooltip("VALUE_LABEL:N", title=title)]
    chart = alt.Chart(df).mark_line(point=True) if mark == "line" else alt.Chart(df).mark_bar()
    encoding = {"x": x, "y": y, "tooltip": tooltip}
    if series:
        encoding["color"] = alt.Color(f"{series}:N", title=None, legend=alt.Legend(orient="right"))
        encoding["tooltip"] = [alt.Tooltip(f"{series}:N")] + tooltip
    st.altair_chart(chart.encode(**encoding).configure_view(stroke=None), use_container_width=True)


def category_chart(df, category, value, kind="count", title="", order=None):
    """Horizontal bars with a printed label on every bar."""
    if df.empty:
        st.info("No data.")
        return
    df = df.copy()
    df["VALUE_LABEL"] = df[value].map(LABEL[kind])
    sort = order if order else "-x"
    base = alt.Chart(df).encode(
        y=alt.Y(f"{category}:N", title=None, sort=sort),
        x=alt.X(f"{value}:Q", title=title, axis=alt.Axis(labelExpr=AXIS[kind], grid=False)),
        tooltip=[alt.Tooltip(f"{category}:N"), alt.Tooltip("VALUE_LABEL:N", title=title)])
    bars = base.mark_bar()
    labels = base.mark_text(align="left", dx=3).encode(text="VALUE_LABEL:N")
    st.altair_chart((bars + labels).configure_view(stroke=None), use_container_width=True)


# ---------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------
def headline():
    """Headline numbers used by the Overview tab and the report."""
    p = q(f"SELECT SUM(PATIENT_COUNT) AS ALL_P, SUM(IFF(NOT IS_DECEASED, PATIENT_COUNT, 0)) AS LIVING FROM {MARTS}.KPI_PATIENT_SEGMENTS").iloc[0]
    v = q(f"SELECT SUM(VISIT_COUNT) AS VISITS, SUM(TOTAL_CLAIM_AMOUNT) AS COST FROM {MARTS}.KPI_VISITS_MONTHLY").iloc[0]
    h = q(f"SELECT SUM(READMISSION_COUNT) / SUM(ADMISSION_COUNT) AS RATE FROM {MARTS}.KPI_HOSPITAL_MONTHLY").iloc[0]
    return p, v, h


def facts_list(p, v, h):
    facts = [f"Patients: {short(p['ALL_P'])}", f"Living patients: {short(p['LIVING'])}",
             f"Visits: {short(v['VISITS'])}", f"30-day readmission rate: {pct(h['RATE'])}"]
    return facts + ([f"Total claim amount: {money(v['COST'])}"] if can("CHART.COST") else [])


def facts_text(p, v, h):
    return "; ".join(facts_list(p, v, h))


def tab_overview():
    p, v, h = headline()
    c = st.columns(5 if can("CHART.COST") else 4)
    c[0].metric("Patients", short(p["ALL_P"]), help=f"Exact: {int(p['ALL_P']):,}")
    c[1].metric("Living patients", short(p["LIVING"]), help=f"Exact: {int(p['LIVING']):,}")
    c[2].metric("Visits", short(v["VISITS"]), help=f"Exact: {int(v['VISITS']):,}")
    c[3].metric("30-day readmission rate", pct(h["RATE"]))
    if can("CHART.COST"):
        c[4].metric("Total claim amount", money(v["COST"]))
    st.caption("Headline numbers cover all years. Charts follow the period and Year/Month choice in the sidebar.")

    if st.button("✨ AI summary of these numbers"):
        st.info(ai_summary(facts_text(p, v, h)))

    st.subheader(f"Visits per {GRAIN.lower()} by care setting")
    df = q(f"""SELECT {by_period('VISIT_MONTH')} AS PERIOD, CARE_SETTING, SUM(VISIT_COUNT) AS VISITS
               FROM {MARTS}.KPI_VISITS_MONTHLY WHERE VISIT_MONTH {IN_PERIOD} GROUP BY 1, 2 ORDER BY 1""", PERIOD)
    trend_chart(df, "VISITS", series="CARE_SETTING", title="Visits")

    if can("CHART.COST"):
        st.subheader(f"Claim amount per {GRAIN.lower()} (USD)")
        df = q(f"""SELECT {by_period('VISIT_MONTH')} AS PERIOD, SUM(TOTAL_CLAIM_AMOUNT) AS CLAIM_AMOUNT
                   FROM {MARTS}.KPI_VISITS_MONTHLY WHERE VISIT_MONTH {IN_PERIOD} GROUP BY 1 ORDER BY 1""", PERIOD)
        trend_chart(df, "CLAIM_AMOUNT", kind="money", mark="bar", title="Claim amount")


def tab_clinical():
    st.caption("Latest measurement per patient · living adults (18+)")
    adults = f"FROM {MARTS}.KPI_PATIENT_SEGMENTS WHERE NOT IS_DECEASED AND AGE_GROUP <> '0-17'"
    charts = [("BMI category", "BMI_CATEGORY", ["Underweight", "Normal weight", "Overweight", "Obese", "No measurement"]),
              ("Blood pressure category", "BLOOD_PRESSURE_CATEGORY",
               ["Normal", "Elevated", "Stage 1 hypertension range", "Stage 2 hypertension range", "No measurement"]),
              ("HbA1c category", "HBA1C_CATEGORY", ["Normal", "Prediabetic range", "Diabetic range", "No measurement"])]
    for col, (title, field, order) in zip(st.columns(3), charts):
        with col:
            st.subheader(title)
            category_chart(q(f"SELECT {field}, SUM(PATIENT_COUNT) AS PATIENTS {adults} GROUP BY 1"),
                           field, "PATIENTS", title="Patients", order=order)
    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Top 10 active diagnoses")
        category_chart(q(f"SELECT DIAGNOSIS_NAME, PATIENTS_WITH_DIAGNOSIS AS PATIENTS FROM {MARTS}.KPI_DIAGNOSES ORDER BY 2 DESC LIMIT 10"),
                       "DIAGNOSIS_NAME", "PATIENTS", title="Patients")
    with c2:
        st.subheader("Top 10 allergies")
        category_chart(q(f"SELECT ALLERGEN_NAME, PATIENTS_WITH_ALLERGY AS PATIENTS FROM {MARTS}.KPI_ALLERGIES ORDER BY 2 DESC LIMIT 10"),
                       "ALLERGEN_NAME", "PATIENTS", title="Patients")


def tab_hospital():
    k = q(f"""SELECT SUM(ADMISSION_COUNT) AS ADMISSIONS, SUM(READMISSION_COUNT) / SUM(ADMISSION_COUNT) AS RATE,
                     SUM(AVERAGE_LENGTH_OF_STAY * ADMISSION_COUNT) / SUM(ADMISSION_COUNT) AS ALOS
              FROM {MARTS}.KPI_HOSPITAL_MONTHLY""").iloc[0]
    c = st.columns(3)
    c[0].metric("Admissions", short(k["ADMISSIONS"]), help=f"Exact: {int(k['ADMISSIONS']):,}")
    c[1].metric("30-day readmission rate", pct(k["RATE"]))
    c[2].metric("Average length of stay", f"{float(k['ALOS']):.1f} days")

    st.subheader(f"30-day readmission rate per {GRAIN.lower()}")
    df = q(f"""SELECT {by_period('ADMISSION_MONTH')} AS PERIOD,
                      100 * SUM(READMISSION_COUNT) / SUM(ADMISSION_COUNT) AS READMISSION_PCT
               FROM {MARTS}.KPI_HOSPITAL_MONTHLY WHERE ADMISSION_MONTH {IN_PERIOD} GROUP BY 1 ORDER BY 1""", PERIOD)
    trend_chart(df, "READMISSION_PCT", kind="pct", title="Readmission rate")

    st.subheader("30-day readmission rate by age group")
    df = q(f"""SELECT AGE_GROUP, 100 * SUM(READMISSION_COUNT) / SUM(ADMISSION_COUNT) AS READMISSION_PCT
               FROM {MARTS}.KPI_HOSPITAL_MONTHLY WHERE ADMISSION_MONTH {IN_PERIOD} GROUP BY 1""", PERIOD)
    category_chart(df, "AGE_GROUP", "READMISSION_PCT", kind="pct", title="Readmission rate",
                   order=["0-17", "18-34", "35-49", "50-64", "65+"])


def tab_pharmacy_vaccines():
    st.subheader("Top 10 medications by patients")
    category_chart(q(f"""SELECT MEDICATION_NAME, PATIENTS_ON_MEDICATION AS PATIENTS FROM {MARTS}.KPI_PRESCRIPTIONS
                         ORDER BY 2 DESC LIMIT 10"""), "MEDICATION_NAME", "PATIENTS", title="Patients")
    if can("CHART.COST"):
        st.subheader("Top 10 medications by total cost (USD)")
        category_chart(q(f"""SELECT MEDICATION_NAME, TOTAL_MEDICATION_COST AS COST FROM {MARTS}.KPI_PRESCRIPTIONS
                             ORDER BY 2 DESC LIMIT 10"""), "MEDICATION_NAME", "COST", kind="money", title="Total cost")
    st.subheader(f"Vaccine doses per {GRAIN.lower()}")
    df = q(f"""SELECT {by_period('VACCINATION_MONTH')} AS PERIOD,
                      CASE WHEN IS_FLU_VACCINE THEN 'Flu' WHEN IS_COVID_VACCINE THEN 'COVID-19' ELSE 'Other' END AS VACCINE,
                      SUM(DOSES_GIVEN) AS DOSES
               FROM {MARTS}.KPI_VACCINATIONS_MONTHLY WHERE VACCINATION_MONTH {IN_PERIOD} GROUP BY 1, 2 ORDER BY 1""", PERIOD)
    trend_chart(df, "DOSES", series="VACCINE", title="Doses")


def tab_claims_cost():
    k = q(f"SELECT SUM(CLAIM_COUNT) AS CLAIMS, SUM(OPEN_CLAIM_COUNT) AS OPEN_CLAIMS FROM {MARTS}.KPI_CLAIMS_MONTHLY").iloc[0]
    c = st.columns(3)
    c[0].metric("Claims", short(k["CLAIMS"]), help=f"Exact: {int(k['CLAIMS']):,}")
    c[1].metric("Open claims", short(k["OPEN_CLAIMS"]), help=f"Exact: {int(k['OPEN_CLAIMS']):,}")
    c[2].metric("Open claim rate", pct(k["OPEN_CLAIMS"] / k["CLAIMS"]))
    st.caption("Claim dollar balances are $0 in this dataset, so open claims are counted, not summed.")

    st.subheader(f"Claims per {GRAIN.lower()}")
    df = q(f"""SELECT {by_period('SERVICE_MONTH')} AS PERIOD, 'All claims' AS SERIES, SUM(CLAIM_COUNT) AS CLAIMS
               FROM {MARTS}.KPI_CLAIMS_MONTHLY WHERE SERVICE_MONTH {IN_PERIOD} GROUP BY 1
               UNION ALL
               SELECT {by_period('SERVICE_MONTH')}, 'Open claims', SUM(OPEN_CLAIM_COUNT)
               FROM {MARTS}.KPI_CLAIMS_MONTHLY WHERE SERVICE_MONTH {IN_PERIOD} GROUP BY 1
               ORDER BY 1""", PERIOD + PERIOD)
    trend_chart(df, "CLAIMS", series="SERIES", title="Claims")

    if can("CHART.COST"):
        st.subheader(f"Claim amount by insurer ({PERIOD_FROM:%b %Y} – {PERIOD_TO:%b %Y})")
        df = q(f"""SELECT COALESCE(INSURER_NAME, 'Unknown') AS INSURER, SUM(TOTAL_CLAIM_AMOUNT) AS CLAIM_AMOUNT
                   FROM {MARTS}.KPI_VISITS_MONTHLY WHERE VISIT_MONTH {IN_PERIOD} GROUP BY 1""", PERIOD)
        category_chart(df, "INSURER", "CLAIM_AMOUNT", kind="money", title="Claim amount")
        st.caption("NO_INSURANCE = uninsured patients, not an insurance company.")


# ---------------------------------------------------------------------
# Patients: role-based PII (the function applies the role's PII level)
# ---------------------------------------------------------------------
def tab_patients():
    st.subheader("Patient lookup")
    st.caption(f"Your role **{ROLE}** sees: {PII_TEXT[PII_LEVEL]}")
    states = q(f"SELECT DISTINCT HOME_STATE FROM {MARTS}.KPI_PATIENT_SEGMENTS WHERE HOME_STATE IS NOT NULL ORDER BY 1")["HOME_STATE"].tolist()
    c1, c2 = st.columns(2)
    state = c1.selectbox("State", states)
    city = c2.text_input("City contains", "")
    table(q(f"""SELECT PATIENT_NUMBER, FIRST_NAME, LAST_NAME, SOCIAL_SECURITY_NUMBER, STREET_ADDRESS,
                       DATE_OF_BIRTH, AGE_IN_YEARS, PATIENT_GENDER, HOME_CITY, HOME_STATE
                FROM TABLE({GOV}.PATIENTS_WITH_PII('{PII_LEVEL}'))
                WHERE HOME_STATE = ? AND HOME_CITY ILIKE ? LIMIT 20""", [state, f"%{city}%"]))


# ---------------------------------------------------------------------
# Cortex AI functions (each one is a single SQL call)
# ---------------------------------------------------------------------
def ai_summary(facts):
    """AI_COMPLETE: 3 short bullet points about the headline numbers (cached 10 minutes)."""
    prompt = ("You are a healthcare analyst. Write 3 short bullet points for an executive about these numbers. "
              "Use only these numbers, keep their exact format, do not give medical advice. Numbers: " + facts)
    try:
        return q("SELECT AI_COMPLETE(?, ?) AS SUMMARY", [AI_MODEL, prompt]).iloc[0]["SUMMARY"]
    except Exception as error:
        return f"AI_COMPLETE is not available here: {error}"


def classify(text):
    """AI_CLASSIFY: which topic is this question about?"""
    try:
        labels = "ARRAY_CONSTRUCT(" + ", ".join(f"'{t}'" for t in TOPICS) + ")"
        return session.sql(f"SELECT AI_CLASSIFY(?, {labels}):labels[0]::STRING", params=[text]).collect()[0][0]
    except Exception:
        return None


def sentiment(text):
    """AI_SENTIMENT: positive / negative / neutral / mixed"""
    try:
        return session.sql("SELECT AI_SENTIMENT(?):categories[0]:sentiment::STRING", params=[text]).collect()[0][0]
    except Exception:
        return None


# ---------------------------------------------------------------------
# AI Insights: question -> AI_REDACT -> AI_CLASSIFY -> agent -> answer -> log -> feedback (AI_SENTIMENT)
# ---------------------------------------------------------------------
def redact(text):
    try:
        return session.sql(f"SELECT AI_REDACT(?, {REDACT})", params=[text]).collect()[0][0] or text
    except Exception:
        return text


def ask_agent(messages):
    """Send the conversation to the agent and return its full response (JSON)."""
    body = json.dumps({"messages": [{"role": m["role"], "content": [{"type": "text", "text": m["text"]}]}
                                    for m in messages[-7:]]}).replace("$$", "$ $")   # last 3 Q&A + new question
    raw = session.sql(f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('{AGENT}', $${body}$$)").collect()[0][0]
    return json.loads(raw) if raw else {}


def read_response(response):
    """Pick out everything the agent returned: answer, thinking, tools, SQL, tables and charts."""
    out = {"text": [], "thinking": [], "tools": [], "sql": [], "tables": [], "charts": []}
    for item in response.get("content") or []:
        kind = item.get("type")
        if kind == "text":
            out["text"].append(item.get("text", ""))
        elif kind == "thinking":
            out["thinking"].append((item.get("thinking") or {}).get("text", ""))
        elif kind == "tool_use":
            out["tools"].append((item.get("tool_use") or {}).get("name"))

    def walk(obj):                                   # SQL, result tables and chart specs can sit deep inside
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == "sql" and isinstance(value, str):
                    out["sql"].append(value)
                elif key == "chart_spec" and value:
                    out["charts"].append(json.loads(value) if isinstance(value, str) else value)
                elif key == "result_set" and isinstance(value, dict):
                    out["tables"].append(value)
                else:
                    walk(value)
        elif isinstance(obj, list):
            for value in obj:
                walk(value)

    walk(response)
    out["answer"] = "\n\n".join(t for t in out["text"] if t) or "The agent did not return an answer."
    out["tools"] = list(dict.fromkeys(t for t in out["tools"] if t))
    out["sql"] = list(dict.fromkeys(out["sql"]))
    return out


def to_dataframe(result_set):
    columns = [c.get("name") for c in (result_set.get("resultSetMetaData") or {}).get("rowType", [])]
    return pd.DataFrame(result_set.get("data") or [], columns=columns or None)


def show_answer(result):
    """Show an agent answer like the agent's own chat screen: text, chart, table, then how it was made."""
    st.markdown(result["answer"])
    for spec in result["charts"][:2]:
        try:
            st.vega_lite_chart(spec, use_container_width=True)
        except Exception:
            pass
    if result["tables"] and not result["charts"]:
        table(to_dataframe(result["tables"][-1]))
    with st.expander("How the agent answered"):
        if result["thinking"]:
            st.markdown("**Thinking steps**")
            for step in result["thinking"]:
                st.caption(step)
        st.markdown(f"**Tools used:** {', '.join(result['tools']) or 'none'}  ·  **Time:** {result.get('seconds', '–')} s")
        for sql in result["sql"]:
            st.code(sql, language="sql")
        if result["tables"] and result["charts"]:
            st.markdown("**Data behind the chart**")
            table(to_dataframe(result["tables"][-1]))


def tab_ai_insights():
    st.subheader("Ask the Healthcare Intelligence Assistant")
    st.caption("Names, SSNs, addresses and other identifiers are removed from your question before the agent sees it.")
    st.session_state.setdefault("messages", [])

    pick_col, ask_col = st.columns([5, 1])                # dropdown with the 5 sample questions
    pick = pick_col.selectbox("Sample questions", ["Choose one of 5 sample questions…"] + SAMPLE_QUESTIONS,
                              label_visibility="collapsed")
    if ask_col.button("Ask", use_container_width=True) and pick in SAMPLE_QUESTIONS:
        st.session_state.pending = pick

    history_box()
    if st.session_state.messages and st.button("Clear conversation"):
        st.session_state.messages = []

    for m in st.session_state.messages:                # show the conversation so far
        with st.chat_message(m["role"]):
            if m["role"] == "assistant":
                show_answer(m["result"])
            else:
                st.markdown(m["text"])

    try:
        prompt = st.chat_input("🔎 Search or ask: patients, visits, admissions, medications, vaccines, claims…")
    except Exception:                                  # older Streamlit: chat box not allowed inside tabs
        with st.form("ask", clear_on_submit=True):
            typed = st.text_input("🔎 Search or ask a question")
            prompt = typed if st.form_submit_button("Ask") else None
    prompt = st.session_state.pop("pending", None) or prompt
    if prompt:
        answer_question(prompt)
    if st.session_state.messages and st.session_state.messages[-1]["role"] == "assistant":
        feedback_box(st.session_state.messages[-1])


def history_box():
    """The viewer's last 5 questions from the past 7 days, with the saved answer (no new agent call)."""
    history = session.sql(f"""SELECT asked_at, question, answer FROM {GOV}.APP_QUESTION_LOG
                               WHERE viewer_name = ? AND asked_at >= DATEADD('day', -{HISTORY_DAYS}, CURRENT_TIMESTAMP())
                               ORDER BY asked_at DESC LIMIT {HISTORY_SIZE}""", params=[VIEWER]).to_pandas()
    with st.expander(f"🕘 Your recent questions (last {HISTORY_DAYS} days): {len(history)}"):
        if history.empty:
            st.caption("No questions in the last 7 days.")
        for i, row in history.iterrows():
            st.markdown(f"**{pd.Timestamp(row['ASKED_AT']):%d %b %Y %H:%M}** · {row['QUESTION']}")
            st.caption((row["ANSWER"] or "")[:400])
            if st.button("Ask again", key=f"again_{i}"):
                st.session_state.pending = row["QUESTION"]
            st.markdown("---")


def answer_question(prompt):
    safe = redact(prompt)
    topic = classify(safe)
    st.session_state.messages.append({"role": "user", "text": safe})
    with st.chat_message("user"):
        st.markdown(safe)
        if topic:
            st.caption(f"Topic (AI_CLASSIFY): {topic}")
        if safe.strip() != prompt.strip():
            st.warning("Personal identifiers were removed from your question.")

    with st.chat_message("assistant"):
        with st.spinner("Searching clinical terms and querying the data…"):
            started = time.time()
            try:
                result = read_response(ask_agent(st.session_state.messages))
            except Exception as error:
                result = read_response({})
                result["answer"] = f"Something went wrong calling the agent: {error}"
            result["seconds"] = round(time.time() - started, 1)
        show_answer(result)
    st.session_state.messages.append({"role": "assistant", "text": result["answer"], "result": result, "question": safe})
    session.sql(f"""INSERT INTO {GOV}.APP_QUESTION_LOG (viewer_name, persona_role, question, topic, pii_removed, answer, latency_seconds)
                    SELECT ?, ?, ?, ?, ?, ?, ?""",
                params=[VIEWER, ROLE, safe, topic, safe.strip() != prompt.strip(), result["answer"], result["seconds"]]).collect()


def feedback_box(message):
    """Users say what they think of the last answer; AI_SENTIMENT reads it."""
    with st.form("feedback", clear_on_submit=True):
        text = st.text_input("How was this answer? (optional feedback)")
        if st.form_submit_button("Send feedback") and text.strip():
            safe = redact(text)
            mood = sentiment(safe)
            session.sql(f"""INSERT INTO {GOV}.APP_ANSWER_FEEDBACK (viewer_name, persona_role, question, feedback, sentiment)
                            SELECT ?, ?, ?, ?, ?""",
                        params=[VIEWER, ROLE, message.get("question"), safe, mood]).collect()
            st.success(f"Thank you. Sentiment (AI_SENTIMENT): {mood or 'not available'}")


# ---------------------------------------------------------------------
# Governance and Quality (engineer only)
# ---------------------------------------------------------------------
def tab_governance():
    st.subheader("Agent usage (audit log)")
    k = q(f"""SELECT COUNT(*) AS N, COALESCE(SUM(total_tokens), 0) AS TOKENS, COALESCE(AVG(latency_seconds), 0) AS SECS
              FROM {GOV}.AGENT_CONVERSATION_HISTORY""").iloc[0]
    c = st.columns(3)
    c[0].metric("Questions", short(k["N"]))
    c[1].metric("Total tokens", short(k["TOKENS"]))
    c[2].metric("Avg response time", f"{float(k['SECS']):.1f} s")
    if st.button("Refresh audit log"):
        session.sql(f"EXECUTE TASK {GOV}.LOAD_AGENT_EVENTS").collect()
        st.cache_data.clear()
        st.info("Refresh started. New questions appear in about a minute: click Refresh again or reload the page.")
    if int(k["N"]) == 0:
        st.info("The audit log is empty. It is copied from the agent once a day; click 'Refresh audit log' to copy it now.")
    table(q(f"""SELECT asked_at, user_name, AI_REDACT(question, {REDACT}) AS question, latency_seconds, total_tokens
                FROM {GOV}.AGENT_CONVERSATION_HISTORY WHERE question IS NOT NULL ORDER BY asked_at DESC LIMIT 20"""))

    st.subheader("Questions asked in this app (stored already redacted)")
    table(q(f"""SELECT asked_at, viewer_name, persona_role, question, topic, pii_removed
                FROM {GOV}.APP_QUESTION_LOG ORDER BY asked_at DESC LIMIT 20"""))

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Questions by topic (AI_CLASSIFY)")
        category_chart(q(f"""SELECT COALESCE(topic, 'Not classified') AS TOPIC, COUNT(*) AS QUESTIONS
                            FROM {GOV}.APP_QUESTION_LOG GROUP BY 1"""), "TOPIC", "QUESTIONS", title="Questions")
    with c2:
        st.subheader("Answer feedback (AI_SENTIMENT)")
        category_chart(q(f"""SELECT COALESCE(sentiment, 'unknown') AS SENTIMENT, COUNT(*) AS FEEDBACK
                            FROM {GOV}.APP_ANSWER_FEEDBACK GROUP BY 1"""), "SENTIMENT", "FEEDBACK", title="Feedback")
    table(q(f"""SELECT given_at, viewer_name, question, feedback, sentiment
                FROM {GOV}.APP_ANSWER_FEEDBACK ORDER BY given_at DESC LIMIT 20"""))

    st.subheader("Masking: what the app sees in PATIENTS")
    st.caption(f"The app does not run as {config.ENGINEER_ROLE}, so personal data is masked.")
    table(q(f"""SELECT FIRST_NAME, LAST_NAME, SOCIAL_SECURITY_NUMBER, STREET_ADDRESS, DATE_OF_BIRTH, HOME_CITY
                FROM {DB}.{config.ANALYTICS}.PATIENTS LIMIT 5"""))

    st.subheader("Try AI_REDACT")
    text = st.text_area("Text with personal data", "Check John Smith, SSN 123-45-6789, 12 Oak Street. He is 67 and male.")
    if st.button("Redact"):
        st.code(redact(text))


def tab_quality():
    st.subheader("Evaluation: 13 test questions")
    runs = q(f"""SELECT run_id, MIN(started_at) AS run_started, COUNT_IF(result = 'PASS') AS passed, COUNT(*) AS total
                 FROM {GOV}.EVAL_SCORECARD GROUP BY 1 ORDER BY 2 DESC""")
    if runs.empty:
        st.info("No evaluation runs yet.")
        return
    latest = runs.iloc[0]
    st.metric("Latest run", f"{int(latest['PASSED'])} / {int(latest['TOTAL'])} passed")
    table(q(f"""SELECT question_id, question, result, reason, latency_seconds FROM {GOV}.EVAL_SCORECARD
                WHERE run_id = ? ORDER BY question_id""", [latest["RUN_ID"]]))


# ---------------------------------------------------------------------
# Report: one HTML file with only the sections this role may see
# ---------------------------------------------------------------------
def html_table(df, formats):
    df = df.copy()
    for column, fmt in formats.items():
        df[column] = df[column].map(fmt)
    return business_headers(df).to_html(index=False, border=0, classes="t")


def build_report():
    p, v, h = headline()
    facts = facts_text(p, v, h)
    parts = [f"<h1>Healthcare Intelligence Report</h1>",
             f"<p class='m'>Generated {datetime.now():%d %b %Y %H:%M} · by {html.escape(VIEWER)} · role {html.escape(ROLE)} · "
             f"trends {PERIOD_FROM:%b %Y} – {PERIOD_TO:%b %Y} · synthetic data, not medical advice</p>",
             "<h2>Headline numbers</h2><ul>" + "".join(f"<li>{html.escape(x)}</li>" for x in facts_list(p, v, h)) + "</ul>",
             "<h2>AI summary</h2><p>" + html.escape(str(ai_summary(facts))).replace(chr(10), "<br>") + "</p>"]
    if can("TAB.CLINICAL"):
        df = q(f"SELECT DIAGNOSIS_NAME, PATIENTS_WITH_DIAGNOSIS AS PATIENTS FROM {MARTS}.KPI_DIAGNOSES ORDER BY 2 DESC LIMIT 10")
        parts.append("<h2>Top 10 active diagnoses</h2>" + html_table(df, {"PATIENTS": short}))
    if can("TAB.HOSPITAL"):
        df = q(f"""SELECT AGE_GROUP, SUM(READMISSION_COUNT) / SUM(ADMISSION_COUNT) AS READMISSION_RATE
                   FROM {MARTS}.KPI_HOSPITAL_MONTHLY WHERE ADMISSION_MONTH {IN_PERIOD} GROUP BY 1 ORDER BY 1""", PERIOD)
        parts.append("<h2>30-day readmission rate by age group</h2>" + html_table(df, {"READMISSION_RATE": pct}))
    if can("TAB.PHARMACY_VACCINES"):
        df = q(f"SELECT MEDICATION_NAME, PATIENTS_ON_MEDICATION AS PATIENTS FROM {MARTS}.KPI_PRESCRIPTIONS ORDER BY 2 DESC LIMIT 10")
        parts.append("<h2>Top 10 medications</h2>" + html_table(df, {"PATIENTS": short}))
    if can("TAB.CLAIMS_COST"):
        df = q(f"""SELECT COALESCE(INSURER_NAME, 'Unknown') AS INSURER, SUM(TOTAL_CLAIM_AMOUNT) AS CLAIM_AMOUNT
                   FROM {MARTS}.KPI_VISITS_MONTHLY WHERE VISIT_MONTH {IN_PERIOD} GROUP BY 1 ORDER BY 2 DESC LIMIT 10""", PERIOD)
        parts.append("<h2>Claim amount by insurer</h2>" + html_table(df, {"CLAIM_AMOUNT": money}))
    answers = [m for m in st.session_state.get("messages", []) if m["role"] == "assistant"][-HISTORY_SIZE:]
    if answers:
        parts.append("<h2>AI Insights from this session</h2>")
        for m in answers:
            parts.append(f"<p><b>Q: {html.escape(m.get('question') or '')}</b><br>"
                         + html.escape(m["text"]).replace(chr(10), "<br>") + "</p>")
    style = ("<style>body{font-family:Arial,sans-serif;max-width:900px;margin:32px auto;color:#1f2937}"
             "h1{color:#0f4c81}h2{border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin-top:28px}"
             ".m{color:#6b7280}.t{border-collapse:collapse;width:100%}.t th,.t td{padding:6px 10px;"
             "border-bottom:1px solid #e5e7eb;text-align:left}.t th{background:#f3f4f6}</style>")
    return f"<html><head><meta charset='utf-8'><title>Healthcare Report</title>{style}</head><body>{''.join(parts)}</body></html>"


with st.sidebar:
    st.markdown("---")
    if st.button("📄 Generate report", use_container_width=True):
        with st.spinner("Building the report…"):
            st.session_state.report = build_report()
    if st.session_state.get("report"):
        st.download_button("⬇️ Download report", st.session_state.report, use_container_width=True,
                           file_name=f"healthcare_report_{datetime.now():%Y%m%d_%H%M}.html", mime="text/html")
        st.caption("Open the file and use Print → Save as PDF for a PDF.")


# ---------------------------------------------------------------------
# Page: only the tabs this role may see are created
# ---------------------------------------------------------------------
RENDER = {"TAB.OVERVIEW": tab_overview, "TAB.CLINICAL": tab_clinical, "TAB.HOSPITAL": tab_hospital,
          "TAB.PHARMACY_VACCINES": tab_pharmacy_vaccines, "TAB.CLAIMS_COST": tab_claims_cost,
          "TAB.PATIENTS": tab_patients, "TAB.AI_INSIGHTS": tab_ai_insights, "TAB.GOVERNANCE": tab_governance,
          "TAB.QUALITY": tab_quality}

st.title("Healthcare Intelligence Platform")
visible = [key for key in TABS if can(key)]
for key, tab in zip(visible, st.tabs([TABS[k] for k in visible])):
    with tab:
        try:
            RENDER[key]()
        except Exception as error:
            st.error(f"This section could not load: {error}")
