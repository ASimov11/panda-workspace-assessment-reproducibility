# PANDA v2.10 — Reproducibility Package

## Associated research

Configuration-Consistent Kinematic and Inertial Workspace Assessment for Robotic Surface Finishing

Numerical postprocessing package supporting a research manuscript intended for MDPI Robotics.

## Scientific scope

This repository provides MATLAB scripts that reproduce screening, paired inertial loading, pose-matched contrasts, and threshold sensitivity results from archived configuration-level numerical data.

The analysis concerns a modeled Franka Emika Panda with a Mirka AIROS 150S finishing tool and adapter. Joint 7 is fixed at pi/4. R0 and R1 use identical kinematic geometry but differ in modeled external assembly inertia.

This is postprocessing reproducibility. The repository does not independently regenerate IK solutions, robot dynamics, or experimental surface-finishing outcomes.

## Dataset

- Six task surfaces: five planar surfaces and one exterior spherical patch.
- 240,000 sampled Cartesian targets.
- 107,356 reachable targets.
- 762,275 retained configurations.
- 650,473 configurations for the spherical patch.
- 24 sampled tool-axis roll orientations for the spherical task.

The source archive contains 19 files: six PER_CONFIGURATION.csv files, six FULL_TARGET_LEDGER_AND_METRICS.csv files, six NORMALIZATION_REPORT.json files, and one spherical BASELINE_TARGET_LEDGER_AND_METRICS.csv.

Dataset DOI: pending Zenodo deposit.

## Reproduction scripts

1. code/reproduce_screening_30pct.m
2. code/reproduce_paired_loading.m
3. code/reproduce_pose_matched.m
4. code/reproduce_threshold_sensitivity.m
5. code/verify_reproduction_suite.m
6. code/generate_sha256_manifest.m

The first four scripts reconstruct postprocessing results from the numerical archive. The fifth checks saved outputs against numerical regression checkpoints. The sixth generates file provenance hashes.

## MATLAB environment

The scripts were executed in a MATLAB environment supporting tabularTextDatastore, readtable, writetable, findgroups, and splitapply.

The postprocessing scripts do not require Robotics System Toolbox.

The SHA-256 generation script uses Windows certutil and is Windows-specific.

## Screening definition

The four screening criteria are evaluated at the SAME retained joint configuration.

- ICN >= tau * ICN_max
- W_n >= tau
- A_n_Rm >= tau
- D_n_Rm >= tau

Here Rm denotes R0 or R1 and tau = 0.30 for the primary analysis.

The common R0/R1 mask is formed by intersecting configuration-level masks before aggregating qualified configurations into targets.

Normalization references:

- ICN_max = 0.122791686207514
- W_max = 8.56235473224922e-5
- A_max = 0.0107948076153145
- D_max = 0.00629241406275165

Current D_n_R0 and D_n_R1 columns must be used. Legacy frozen_ref variants must not be substituted.

## Spatial aggregation

Each eligible target receives an ordinary median of its eligible configuration or roll-level results, as appropriate to the analysis.

Spatial aggregation uses physical surface quadrature weights and the first crossing of the weighted empirical cumulative distribution at 50%.

## Key reproduced checkpoints

- Primary R1 screen: 322,486 configurations and 54,237 targets across all six surfaces.
- Spherical R1 screen: 302,155 configurations and 38,568 targets.
- Spherical R1 full-area coverage: 97.521429%.
- Spherical R1 reachable-area coverage: 97.760221%.
- Spherical common R0/R1 full-area coverage: 34.824878%.
- Paired normal inertia change: +14.212642%.
- Paired normal mobility change: -29.836821%.
- Pose-matched eligible targets: 1,317.
- Mixed target-roll groups: 1,326.
- Pose-matched inertia contrast: -4.120129 kg.
- Target-only inertia contrast: +0.535486 kg.
- Pose-matched mobility contrast: +0.05295537 kg^-1.
- Target-only mobility contrast: -0.00296119 kg^-1.

The saved-output regression suite previously passed 46 of 46 numerical checks.

## Run order

1. Obtain the original numerical ZIP archive.
2. Run the four reproduction scripts in the order listed above.
3. Place generated results in results/.
4. Run verify_reproduction_suite.m.
5. Freeze code and results.
6. Generate and verify SHA-256 manifests.

The analysis scripts use local file-selection dialogs; no absolute path inside this repository should be assumed.

## Coordinate frames

All task-space geometric quantities use the fixed robot-base frame {0}. Historical archived fields beginning with T_W_TCP_BASELINE retain W in their names for source-data integrity. W denotes the robot-base frame {0} in this archive.

## Limitations

- No independent regeneration of retained IK configurations.
- No independent dynamics-model validation.
- No experimental contact-force tracking validation.
- No measured material removal or surface-quality validation.
- No claim of continuous collision-free finishing trajectories.
- No independent convergence study of spatial or roll discretization.

## Provenance

SOURCE_ARCHIVE_SHA256.txt records the complete numerical ZIP checksum.
ARCHIVE_MEMBERS_SHA256.txt records checksums for all 19 archived members.
SHA256SUMS.txt records checksums for the repository code, results, and included documentation.

These files must be regenerated after any changes to the release contents.

## Publication metadata

Software version: v0.1.0-rc1 (provisional).
GitHub URL: https://github.com/ASimov11/panda-workspace-assessment-reproducibility
Dataset DOI: pending Zenodo deposit.
Software DOI: pending release archival.
Authors: Aleksandar Simov and Tanio Tanev.
Software license: MIT. Original numerical dataset license: CC BY 4.0.

Release status: verified local release candidate; publication identifiers are pending.

## Licensing

MATLAB postprocessing code: MIT License (LICENSE).

Original numerical dataset: Creative Commons Attribution 4.0 International (DATA_LICENSE.md).

Third-party materials retain their own licensing and are not relicensed by this repository.
