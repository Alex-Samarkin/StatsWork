# Descriptive statistics

**Categories:** exploratory / summary

Computes basic descriptive statistics for workbook variables.

The analysis inspects numeric workbook variables and summarizes central tendency, spread and missingness.

## Workbook variables

- Inputs: age, height_cm, weight_kg, sbp_mmhg, dbp_mmhg
- Outputs: -

## Formulas

- `mean = sum(x) / n`
  Average over non-missing values.
- `std = sqrt(sum((x - mean)^2) / (n - 1))`
  Sample standard deviation.

## Interpretation

Compare means, medians and variability across variables. Large missingness or strong gaps between mean and median may indicate skewness or data quality issues.

## Summary statistics

Each row corresponds to one numeric workbook variable.

| Variable | N | Missing | Mean | Median | Std | Min | Max | Comment |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| age | 3500 | 0 | 47.25 | 47.0 | 15.1312 | 18.0 | 85.0 |  |
| height_cm | 3500 | 0 | 169.5101 | 169.4 | 9.1857 | 145.1 | 199.7 |  |
| weight_kg | 3500 | 0 | 67.8902 | 67.3 | 10.6192 | 41.9 | 112.9 |  |
| sbp_mmhg | 3500 | 0 | 134.0097 | 134.0 | 10.6626 | 100.0 | 160.0 |  |
| dbp_mmhg | 3500 | 0 | 78.5769 | 79.0 | 5.7027 | 60.0 | 100.0 |  |

## Notes

- Only numeric values participate in the calculations.
- Missing values are counted separately and excluded from summary statistics.

