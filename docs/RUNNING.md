# Running locally

1. Extract the package and open mpc-robot-calibration as MATLAB Current Folder.
2. Run `run('matlab/calibration/mainMultiplaner.m')`. By default it uses the supplied preselected workbook, audited to contain 100 measurements from each corresponding raw plane. Defaults are 300 maximum iterations, 80/20 selected-pool split per plane, seed 1. Final metrics and training curves are exported to outputs/.
3. Inspect the training/test residuals, convergence flag and train/test row indices in the saved MAT file. Row indices refer to the selected workbook, not raw workbook rows; the provided-selection audit maps them back to the raw data.
4. Optional observability sweep: `run('matlab/selection/mainObservabilityIndex.m')`.
5. Optional regeneration: `run('matlab/selection/mainO60.m')`. Wait for all three planes to finish. Defaults: population 50, 150 generations, 100 measurements per plane, Excel A201:H400 and seed 1. The generated workbook under data/selected/ is replaced only after all sheets succeed. Change `provided_selection` to `selected` in the calibration script's `dataFile` setting to use the new selection. The supplied selection is not overwritten.

Target: MATLAB R2020a+. The entry points use built-in matrix and spreadsheet APIs. Availability of the configured spreadsheet reader/writer can depend on the host environment; this has not been tested here. Do not run original reference scripts by accident: their path assumptions are retained for provenance. Curated script/helper pairs live together, so running each with MATLAB `run` resolves the corresponding helpers; avoid adding all reference folders to the path.

`mainSingleplane.m` is optional and defaults to HSR-P1 from the regenerated selection. It has no held-out test evaluation and no added automated export. It is retained as a single-plane exploratory comparison.

Optional kinematics check: `run('matlab/tests/check_kinematics.m')`. It tests the actual MATLAB position Jacobian against central differences, the d6 direction and contact-point length compensation. It has not been executed in this environment.

Optional data audit regeneration: Python 3.11+ with numpy and openpyxl (`python -m pip install -r requirements-audit.txt`), then `python tools/audit_data.py`. This audit does not train the MATLAB model. The README plots are prepared views of supplied data/published tables, not execution screenshots.

The candidate selection step can be expensive. Reducing population/generations is useful for a smoke check but changes the experiment and must be reported. Do not report the published accuracy numbers as your local execution results.
