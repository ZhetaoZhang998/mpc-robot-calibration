# Data and provenance

## Raw measurements

`data/raw/HSR-P.xlsx` is an unchanged copy of the supplied workbook. Columns are q1...q6 (joint angles, degrees), L (measured cable length, mm), D (dial indicator reading, mm). MATLAB converts angles to radians and lengths to metres. The calibration variable `L` is the probe body length, not the input workbook's cable-length column; see source comments.

| Sheet | Complete numeric records | Unique records | Paper count |
|---|---:|---:|---:|
| HSR-P1 | 800 | 800 | 800 |
| HSR-P2 | 800 | 800 | 800 |
| HSR-P3 | 803 | 803 | 800 |

Formatting extends the apparent sheet dimensions beyond valid data. Count actual numeric rows, not Excel's maximum row index. The three additional P3 records are Excel rows 802–804; they are preserved. No HSR-AC worksheet or separately identified 200-point after-compensation dataset was supplied. Do not claim the full physical recalibration experiment is bundled.

## Supplied selection audit

The two supplied copies of HSR-P_DE_top100.xlsx have identical bytes. Each sheet has 100 records. Exact matching across all eight columns confirms that **all 100 records per plane match their same-name raw sheet**, with no mismatched labels. Row-level evidence is in `results/audit/provided_selection_matches.csv`.

The default calibration input is the unchanged supplied workbook under `data/provided_selection/`. Optional regeneration uses `matlab/selection/mainO60.m`, which processes each raw sheet independently and exports unique selections to `data/selected/`. To use the regenerated selection for calibration, change the `dataFile` path in the calibration entry point from `provided_selection` to `selected`.

Default candidate rows are A201:H400 (200 per plane), with 100 chosen per plane. Recorded source indices are relative to this window: source Excel row = selected index + 200. The curated selector comment reflects that mapping. Original source comments remain unchanged in reference/.

## Evaluation scope

The multi-plane script splits the selected observations 80/20 within each plane with seed 1. Anchors and planes are fitted on training observations. Selection is performed before this split and uses the joint configurations of the selected pool. The result evaluates the selected measurement distribution, not a wholly untouched selection-independent test cohort. For a stronger study, reserve test configurations before any selection and select only inside the training pool.

The single-plane script fits and reports on its chosen training rows; it is not an independent test benchmark. The full 9-method paper comparison and physical after-compensation robot experiment are not reimplemented here.

## Source preservation

`data/manifest.json` records source-to-repository paths and SHA-256 hashes for copied materials. Original MATLAB code is preserved under `reference/`. Generated plots and curated entry points are separate. Temporary lock files, Origin/Visio editing files and the 37.6 MB manufacturer manual are omitted from the upload package; the uploaded source archive remains unchanged.
