# Method and implementation scope

The paper proposes a measurement configuration selection (MCS) stage followed by an alternating-direction-method-of-multipliers solver with multi-planar constraints (AMPC). Here MPC means multi-planar constraints, not model predictive control.

## Selection

The supplied selector evaluates an O6 observability criterion using the first 17 columns of its analytic Jacobian. Differential evolution searches subsets of 100 distinct poses from a 200-pose candidate window separately on each of three planes. The curated entry point fixes the random seed and exports the selected measurements plus search metadata.

A small O6 value can reflect near-singular directions. Selecting the first 17 columns does not guarantee 17 identifiable parameters. Inspect singular values before drawing parameter-identifiability conclusions. The selector and calibrator retain their supplied, different nominal parameter vectors and anchor conventions; this packaging does not assert those modeling choices have been reconciled or that the analytic selection Jacobian equals the calibration helper in every convention.

## Calibration

The supplied calibration helper computes standard-DH forward kinematics for six joints, with 24 parameters ordered a1...a6, d1...d6, alpha1...alpha6, theta01...theta06. Position Jacobians are 3×24. Three planes share one robot parameter vector and one probe body length. Each plane has its own anchor, unit normal and offset. Anchor fitting uses nominal robot parameters and training cable lengths; anchors remain fixed during the subsequent joint update.

Two residual families are used: predicted cable distance minus measured cable length; and signed distance of the dial-compensated contact point to its fitted plane. The code uses auxiliary residual and multiplier variables for noisy plane constraints, regularization toward nominal robot/probe parameters, and damped inner Gauss–Newton updates.

The supplied mainMultiplaner implementation has 34 local update coordinates: 24 robot parameters, one probe length, and three plane coordinates per plane (two normal tangent coordinates plus one offset). Its stopping condition checks primal/dual residuals, objective and parameter changes, and stationarity. Hitting the iteration cap is not convergence.

## Results and units

The main script's final RMSE, MAX and MEAN are cable residual statistics in metres, using the held-out set if one exists. MEAN is mean absolute error. Training curve arrays named MSE_store actually contain RMSE. Plane curves measure a different residual family. These are not automatically Cartesian XYZ position errors or orientation errors.

## Repository edits

The numerical solver and helper formulas remain as supplied. Changes to curated scripts cover project-relative paths, fixed selection RNG, separate raw/provided/regenerated data locations, selection metadata, and calibration CSV/MAT/PNG exports. One selector comment has been corrected to identify raw Excel rows. Original files remain available byte-for-byte under reference. No claim is made that this supplied implementation exactly recreates every solver setting, ensemble result or experiment in the published paper.
