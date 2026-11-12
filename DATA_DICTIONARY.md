# PANDA v2.10 — Data Dictionary

## Dataset organization

Each surface directory provides:

- PER_CONFIGURATION.csv: one record per retained configuration.
- FULL_TARGET_LEDGER_AND_METRICS.csv: one record per sampled Cartesian target.
- NORMALIZATION_REPORT.json: reference and normalization metadata.

The spherical folder additionally contains BASELINE_TARGET_LEDGER_AND_METRICS.csv.

There are 40,000 target-ledger records per surface.

## Population and identifiers

| Field | Meaning |
|---|---|
| target_index | Target identifier within a surface |
| configuration_key | Recorded retained-configuration identifier, where present |
| roll_index | Spherical sampled tool-axis roll identifier |
| roll_rad | Spherical sampled roll angle, rad |
| q1 ... q7 | Robot joint coordinates, rad |
| reachable | Boolean target reachability flag |
| retained_count | Retained configurations associated with a target |
| area_weight | Physical surface quadrature weight, m^2 |
| metric_valid | Configuration metric validity flag |
| normal_metric_valid | Normal-direction metric validity flag |

Planar and spherical per-configuration schemas are not identical. Code selects columns by their exact names.

## Kinematic indicators

| Field | Meaning |
|---|---|
| ICN | Raw inverse condition number, dimensionless |
| W_raw | Raw six-dimensional Yoshikawa manipulability |
| W_n | Yoshikawa manipulability normalized by the common W_max |

## Inertial indicators

| Field | Meaning |
|---|---|
| A_R0, A_R1 | Raw Asada-type inertial isotropy values |
| A_n_R0, A_n_R1 | Common-reference normalized Asada-type indices |
| D_vol_R0, D_vol_R1 | Raw inertia-weighted mobility-volume indicators |
| D_n_R0, D_n_R1 | Current common-reference normalized mobility-volume indicators |
| D_n_R0_frozen_ref, D_n_R1_frozen_ref | Historical normalization fields; do not use for current screening |

## Directional physical measures

| Field | Meaning | Units |
|---|---|---|
| normal_inertia_R0_kg | R0 projected normal inertia | kg |
| normal_inertia_R1_kg | R1 projected normal inertia | kg |
| normal_mobility_R0_invkg | R0 normal mobility | kg^-1 |
| normal_mobility_R1_invkg | R1 normal mobility | kg^-1 |
| paired_normal_inertia_change_pct | Paired R0-to-R1 normal inertia change | % |
| paired_normal_mobility_change_pct | Paired R0-to-R1 normal mobility change | % |

## Surface-normal geometry

normal_x, normal_y, normal_z denote the task-surface normal expressed in the robot-base frame {0}.

## Normalization references

ICN_max = 0.122791686207514
W_max = 8.56235473224922e-5
A_max = 0.0107948076153145
D_max = 0.00629241406275165

For screening with fraction tau, the ICN threshold is tau * ICN_max; the thresholds applied to W_n, A_n and D_n equal tau.

## Model interpretation

R0 and R1 use identical configurations and geometry. Differences in inertia-dependent metrics result from the two modeled inertia conditions.

## Qualified-target semantics

A target qualifies for a model if at least one retained configuration satisfies all active screening criteria at that same configuration.

Common qualification requires an identical configuration satisfying the R0 and R1 criteria simultaneously. Intersecting separately qualified target masks is not an equivalent operation.

## Pose-matched contrasts

An eligible (target_index, roll_index) group contains at least one R1-qualified and one R1-unqualified configuration.

Within each eligible group, the contrast equals the median selected value minus the median unselected value.

The ordinary median of eligible roll-level contrasts is calculated at each target.

The target-only comparison pools all roll configurations at the same eligible target, including configurations from non-mixed roll groups.

Both spatial summaries use the SAME 1,317 eligible targets and original surface area weights.

## Spatial median

The spatial median is defined as the first value at which the weighted empirical cumulative distribution reaches or exceeds 0.5. It is not interpolated.

## Coordinate notation

Legacy spherical transformation fields T_W_TCP_BASELINE_11 through T_W_TCP_BASELINE_44 encode elements of a 4-by-4 TCP baseline transformation.

The historical symbol W denotes the fixed robot-base frame {0}, not a distinct world frame.

Original CSV names must remain unchanged to preserve source-file checksums.

## Dataset integrity

Each full target ledger contains 40,000 rows.
Reachability flags agree with retained_count > 0 for all six surfaces.
Total retained configurations: 762,275.
Total reachable targets: 107,356.

This dictionary describes the analysis-critical fields; other archived fields retain their original header names and are not silently reinterpreted.
