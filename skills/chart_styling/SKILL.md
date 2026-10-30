---
name: chart_styling
description: Visual rules for every chart - visible data labels on every point, no gridlines, business titles and axis names, one accent color for single series, legend on the right. Load before drawing any chart.
---
# Chart Styling

Applies to every chart. Chart type is chosen by `chart_types`; number formats come from `number_formatting`.

## Data labels: always visible
- Every bar, line point and pie slice shows its value. Nobody should have to hover.
- Bar: label at the end of the bar. Line: label above each point. Pie: category name + percentage.
- Labels use the `number_formatting` rules: `61.82K`, `$1.42mn`, `17.10%`.
- If labels overlap: switch to horizontal bars, make the chart larger or show fewer groups. Never remove labels.

## Gridlines and clutter
- No gridlines (horizontal or vertical), no background fill, no borders, no 3D, no shadows.
- Keep the category axis. The value axis may be hidden on bar and pie charts because labels show the values.

## Titles and axes
- Every chart has a plain-English title: "30-Day Readmission Rate by Age Group", "Flu Vaccinations per Year".
- Axis names use business words and units: "Patients", "Readmission Rate (%)", "Claim Amount ($)", "Year".
- Never show raw column names (`ADMISSION_YEAR`, `PATIENT_COUNT`).
- Do not cut names with "...": shorten meaningfully or use horizontal bars.

## Legend
- Single series: no legend.
- Pie, grouped bar or several lines: legend on the right, one entry per line, full names, business labels.
- When the chart is a specification, set it explicitly:
```json
{
  "config": {
    "legend": { "orient": "right", "direction": "vertical", "columns": 1, "labelLimit": 0, "title": null },
    "axis": { "grid": false, "domain": true },
    "view": { "stroke": null }
  }
}
```

## Color
- One accent color for a single series. Do not color bars differently when they are the same measure.
- Distinct colors only when they mean something (different series or slices). Maximum 8 colors.
- For "previous vs current", use a muted color for previous and a strong color for current.
- Never rely on color alone: the labels carry the values.

## Sorting
- Rankings: highest first (lowest first only for "bottom" or "lowest" questions).
- Time: oldest to newest.
- Natural groups keep their natural order: age groups, BMI categories, blood pressure categories.

## Final check before showing a chart
1. Every value has a visible label.
2. No gridlines.
3. Numbers follow `number_formatting` (K / mn / bn, `$`, 2-decimal percentages).
4. Title and axes in business language; no raw column names.
5. Only data returned by healthcare_analyst is shown.
If any check fails, fix the chart before returning it.
