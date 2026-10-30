---
name: number_formatting
description: Format every number in a healthcare answer - patient and visit counts as K / mn / bn, money as $K / $mn / $bn, rates and percentages with exactly 2 decimals, and readable dates. Apply to text, tables, chart labels, axes and tooltips.
---
# Number Formatting Rules

Apply these rules to EVERY number in the response: the first sentence, tables, chart data labels, chart axes and tooltips.

## Large numbers (counts of patients, visits, claims, admissions, doses)
Use short suffixes with exactly 2 decimals:

| Size | Format | Example |
|---|---|---|
| >= 1,000,000,000 | `X.XXbn` | `1.24bn` |
| >= 1,000,000 | `X.XXmn` | `64.54mn` visits |
| >= 1,000 | `X.XXK` | `61.82K` patients |
| < 1,000 | whole number | `845` patients |

- In the FIRST sentence of the answer, also give the exact count in brackets, so the number can be checked:
  `61.82K (61,820) patients have had a heart attack.`
- In tables and charts, the short form alone is fine.
- Counts are people or records: never show decimals on values under 1,000 (`845`, not `845.00`).

## Money (US dollars)
Always a `$` prefix, exactly 2 decimals, short suffix:

| Size | Format | Example |
|---|---|---|
| >= 1,000,000,000 | `$X.XXbn` | `$34.56bn` |
| >= 1,000,000 | `$X.XXmn` | `$1.42mn` |
| >= 1,000 | `$X.XXK` | `$466.52K` |
| < 1,000 | `$X.XX` | `$850.75` |

- Negative money: `-$12.40K`.
- Never show raw values such as `466515.95` or scientific notation such as `1.42e+06`.

## Percentages and rates
- Exactly 2 decimals with `%`: `17.10%`, `68.20%`, `100.00%`.
- A rate stored as a fraction is converted first: `0.171` -> `17.10%`.
- Never `17.1%`, never `0.171`.

## Clinical measurements
- BMI, HbA1c, cholesterol, blood pressure: 1 decimal with the unit: `BMI 31.4`, `HbA1c 6.8%`, `128.0 mm[Hg]`.
- Averages of days or years: 1 decimal (`4.8 days` average stay, `42.3 years` average age).

## Changes and differences
- Always show the sign: `+2.35%`, `-1.20%`, `+3.40K` patients.
- A zero change is `0.00%`, never blank.

## Dates
- Readable: `25 Oct 2026`, months as `Oct 2026`, years as `2024`.
- Never `2026-10-25` or `10/25/26`.

## Zero vs missing (important)
- A real zero is shown as `0`, `$0.00` or `0.00%`.
- A missing value is NEVER shown as zero. Write `Not available` and say why if known.
- Claim balances in this dataset are always $0.00: say so instead of showing a column of zeros.

## Tables
- Present results as a markdown table when there are more than 3 rows.
- Apply the rules above to every numeric cell.
- Use business headers: "Patients", "Readmission Rate", "Insurer" - never raw names like `PATIENT_COUNT` or `INSURER_NAME`.

## Responsibility
- This skill owns number formatting only.
- `chart_types` decides which chart to draw; `chart_styling` decides how it looks.
