---
name: chart_types
description: Choose the right chart for a healthcare question - line for trends over time, bar for rankings and comparisons by group, pie only for share of total, and no chart for a single number. Number formatting is owned by number_formatting and appearance by chart_styling.
---
# Chart Type Selection (healthcare)

This skill decides ONLY which chart to draw (or none).
Colors, labels, legends and gridlines belong to `chart_styling`; number formats belong to `number_formatting`.

## Decide in this order

1. **Single number?** -> NO chart. Answer in one sentence.
   - "How many patients have had a heart attack?"
   - "What is the overall 30-day readmission rate?"

2. **Trend over time?** (by year, by month, over time, trend, since 2015) -> **Line chart**
   - "How many patients received a flu vaccine each year?"
   - "Readmission rate per year"
   - Time on the x-axis, oldest to newest. Fewer than 3 periods -> use a bar chart.
   - The data ends in 2024: the last year may be partial; say so if it looks like a drop.

3. **Share of a total?** (share, percentage of total, proportion, mix) -> **Pie / donut**
   - "What share of visits happens in each care setting?"
   - Maximum 8 slices; keep the top 7 and group the rest as "Other".

4. **Ranking or comparison by group?** (top, most, highest, lowest, by insurer, by age group, by care setting, by BMI category) -> **Bar chart**
   - "Which insurers have the most open claims?" -> horizontal bar, sorted highest first
   - "Readmission rate by age group" -> vertical bar, age groups in natural order (0-17, 18-34, 35-49, 50-64, 65+)
   - "How many living adults are in each BMI category?" -> bar, categories in clinical order (Underweight, Normal weight, Overweight, Obese)
   - Long names (insurers, diagnoses, medications) -> horizontal bars.

5. **Two measures side by side?** (claim amount vs insurer paid, admissions vs readmissions) -> **Grouped bar**, maximum 2 series.

6. **Anything else** -> bar chart.

## Important
- The word "breakdown" alone does NOT mean pie. "Visits broken down by care setting" -> bar.
- Never use pie for rankings, time series or more than 8 groups.
- Maximum 2 charts per answer; never two charts of the same thing.
- Bar charts: 3-20 bars. More than 20 -> show the top 10 or top 20 and say so.
- Chart only data that came from healthcare_analyst - never invent or estimate values.
