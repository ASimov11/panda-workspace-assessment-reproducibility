
%% PANDA v2.10 - POSE-MATCHED REPRODUCTION
%
% Reproduces spherical R1 30% selection contrasts:
%
% 1. Pose-matched:
%    selected minus unselected within (target_index, roll_index)
%
% 2. Target-only on exactly the same eligible targets:
%    selected minus unselected, pooling all rolls
%
% Input:
%    PANDA_CONFIGURATION_AUDIT ZIP
%
% No IK, MEX, robot dynamics, or new simulations.
% No Robotics System Toolbox required.
%
% IMPORTANT:
%    Use D_n_R1 (current normalization).
%    Never use D_n_R1_frozen_ref.

clearvars;
clc;

%% 1. SELECT THE ORIGINAL ZIP

[file, folder] = uigetfile('*.zip', ...
    'Select PANDA_CONFIGURATION_AUDIT ZIP');

if isequal(file, 0)
    error('No ZIP archive selected.');
end

zipPath = fullfile(folder, file);

tempDir = tempname;
mkdir(tempDir);

cleanupTemp = onCleanup(@() ...
    removeTemporaryFolder(tempDir));

fprintf('\nExtracting original numerical archive...\n');

unzip(zipPath, tempDir);

surface = 'CURVED200_MINUS_N';

cfgPath = fullfile(tempDir, surface, ...
    'PER_CONFIGURATION.csv');

ledgerPath = fullfile(tempDir, surface, ...
    'FULL_TARGET_LEDGER_AND_METRICS.csv');

assert(isfile(cfgPath), ...
    'Spherical configuration CSV not found.');

assert(isfile(ledgerPath), ...
    'Spherical full-target ledger not found.');

outDir = fullfile(folder, ...
    'PANDA_REPRODUCIBILITY_PACKAGE', 'results');

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% 2. READ THE SPHERICAL TARGET LEDGER

opts = detectImportOptions(ledgerPath);

opts.SelectedVariableNames = { ...
    'target_index', ...
    'reachable', ...
    'area_weight'};

L = readtable(ledgerPath, opts);

assert(height(L) == 40000, ...
    'Expected 40000 spherical targets.');

assert(numel(unique(L.target_index)) == 40000, ...
    'Duplicate target_index in ledger.');

assert(nnz(L.reachable == 1) == 39898, ...
    'Unexpected reachable target count.');

assert(all(isfinite(L.area_weight)) && ...
       all(L.area_weight > 0), ...
    'Invalid surface area weights.');

%% 3. SCREENING CONSTANTS

tau = 0.30;

% Confirmed six-surface ICN threshold reference
ICNmax = 0.122791686207514;
tauICN = tau * ICNmax;

% Use the archived current normalized values:
%   W_n
%   A_n_R1
%   D_n_R1

fprintf('\n=== SCREENING SETTINGS ===\n');

fprintf('ICN reference: %.15g\n', ICNmax);
fprintf('ICN threshold: %.15g\n', tauICN);
fprintf('W/A/D threshold: %.2f\n', tau);

%% 4. LOAD ONLY REQUIRED CONFIGURATION COLUMNS

ds = tabularTextDatastore(cfgPath, ...
    'ReadSize', 25000);

ds.SelectedVariableNames = { ...
    'target_index', ...
    'roll_index', ...
    'metric_valid', ...
    'normal_metric_valid', ...
    'ICN', ...
    'W_n', ...
    'A_n_R1', ...
    'D_n_R1', ...
    'normal_inertia_R1_kg', ...
    'normal_mobility_R1_invkg'};

parts = cell(0,1);
totalRecords = 0;

fprintf('\nReading spherical configurations...\n');

while hasdata(ds)

    T = read(ds);

    totalRecords = totalRecords + height(T);

    parts{end+1,1} = T; %#ok<SAGROW>

end

C = vertcat(parts{:});
clear parts;

assert(totalRecords == 650473, ...
    'Spherical population does not match manuscript.');

%% 5. VALIDATE CONFIGURATION DATA

assert(all(C.metric_valid == 1), ...
    'Invalid screening metric encountered.');

assert(all(C.normal_metric_valid == 1), ...
    'Invalid normal-direction metric encountered.');

values = [ ...
    C.ICN, ...
    C.W_n, ...
    C.A_n_R1, ...
    C.D_n_R1, ...
    C.normal_inertia_R1_kg, ...
    C.normal_mobility_R1_invkg];

assert(all(isfinite(values), 'all'), ...
    'Nonfinite metric values encountered.');

assert(all(C.normal_inertia_R1_kg > 0), ...
    'Nonpositive projected normal inertia.');

assert(all(C.normal_mobility_R1_invkg > 0), ...
    'Nonpositive normal mobility.');

[found, ledgerRows] = ismember( ...
    C.target_index, L.target_index);

assert(all(found), ...
    'Configuration refers to an unknown target.');

assert(all(L.reachable(ledgerRows) == 1), ...
    'Configuration refers to an unreachable target.');

%% 6. RECONSTRUCT THE R1 30% SCREEN

selected = ...
    (C.ICN >= tauICN) & ...
    (C.W_n >= tau) & ...
    (C.A_n_R1 >= tau) & ...
    (C.D_n_R1 >= tau);

nSelected = nnz(selected);

nSelectedTargets = numel( ...
    unique(C.target_index(selected)));

fprintf('\n=== SCREENING CHECK ===\n');

fprintf('All spherical configurations: %d\n', ...
    totalRecords);

fprintf('R1-selected configurations: %d\n', ...
    nSelected);

fprintf('R1-selected targets: %d\n', ...
    nSelectedTargets);

assert(nSelected == 302155, ...
    'R1 configuration selection mismatch.');

assert(nSelectedTargets == 38568, ...
    'R1 selected-target count mismatch.');

%% 7. FIND MIXED TARGET-ROLL GROUPS
%
% A target-roll group is eligible only when it contains:
%    at least one selected configuration AND
%    at least one unselected configuration.

fprintf('\nIdentifying mixed target-roll groups...\n');

[G, groupTargetIDs, groupRollIDs] = findgroups( ...
    C.target_index, C.roll_index);

nGroups = numel(groupTargetIDs);

passCounts = accumarray( ...
    G, double(selected), [nGroups, 1], @sum, 0);

failCounts = accumarray( ...
    G, double(~selected), [nGroups, 1], @sum, 0);

mixedGroup = ...
    (passCounts > 0) & (failCounts > 0);

nMixedRollGroups = nnz(mixedGroup);

% Select all configuration rows from eligible groups
rowsInMixedGroups = mixedGroup(G);

assert(any(rowsInMixedGroups), ...
    'No mixed target-roll groups found.');

%% 8. CALCULATE CONTRAST WITHIN EACH ELIGIBLE ROLL
%
% Contrast = median(selected) - median(unselected)
%
% Both populations have the SAME target and SAME roll.

[Ge, eligibleGroupTargets, eligibleGroupRolls] = ...
    findgroups( ...
    C.target_index(rowsInMixedGroups), ...
    C.roll_index(rowsInMixedGroups));

rollContrastInertia = splitapply( ...
    @selectedMinusUnselected, ...
    C.normal_inertia_R1_kg(rowsInMixedGroups), ...
    selected(rowsInMixedGroups), ...
    Ge);

rollContrastMobility = splitapply( ...
    @selectedMinusUnselected, ...
    C.normal_mobility_R1_invkg(rowsInMixedGroups), ...
    selected(rowsInMixedGroups), ...
    Ge);

assert(numel(eligibleGroupTargets) == ...
       nMixedRollGroups, ...
    'Eligible roll-group count inconsistency.');

assert(all(isfinite(rollContrastInertia)) && ...
       all(isfinite(rollContrastMobility)), ...
    'Invalid roll-level contrast.');

%% 9. AGGREGATE ELIGIBLE ROLLS WITHIN EACH TARGET
%
% If a target has multiple eligible roll groups,
% use the ordinary median of the roll-level contrasts.
%
% Each target contributes only once to the spatial median.

[Gt, eligibleTargetIDs] = ...
    findgroups(eligibleGroupTargets);

poseTargetInertia = splitapply( ...
    @median, rollContrastInertia, Gt);

poseTargetMobility = splitapply( ...
    @median, rollContrastMobility, Gt);

nEligibleTargets = numel(eligibleTargetIDs);

fprintf('\n=== POSE-MATCHED POPULATION ===\n');

fprintf('Mixed target-roll groups: %d\n', ...
    nMixedRollGroups);

fprintf('Eligible spatial targets: %d\n', ...
    nEligibleTargets);

assert(nEligibleTargets == 1317, ...
    ['Eligible target count differs from ', ...
     'the manuscript reference.']);

%% 10. TARGET-ONLY CONTRAST ON THE SAME TARGETS
%
% Retain exactly the 1317 eligible targets.
% Pool ALL roll configurations within each target.
%
% Do not restrict this calculation to mixed roll groups.

fprintf('\nCalculating target-only contrasts...\n');

rowsOnEligibleTargets = ismember( ...
    C.target_index, eligibleTargetIDs);

[Gonly, targetOnlyIDs] = findgroups( ...
    C.target_index(rowsOnEligibleTargets));

targetOnlyInertiaRaw = splitapply( ...
    @selectedMinusUnselected, ...
    C.normal_inertia_R1_kg(rowsOnEligibleTargets), ...
    selected(rowsOnEligibleTargets), ...
    Gonly);

targetOnlyMobilityRaw = splitapply( ...
    @selectedMinusUnselected, ...
    C.normal_mobility_R1_invkg(rowsOnEligibleTargets), ...
    selected(rowsOnEligibleTargets), ...
    Gonly);

% Align all results to eligibleTargetIDs.
[found, order] = ismember( ...
    eligibleTargetIDs, targetOnlyIDs);

assert(all(found), ...
    'Target-only population does not match eligible targets.');

targetOnlyInertia = targetOnlyInertiaRaw(order);
targetOnlyMobility = targetOnlyMobilityRaw(order);

%% 11. ATTACH THE ORIGINAL AREA WEIGHTS

[found, ledgerPos] = ismember( ...
    eligibleTargetIDs, L.target_index);

assert(all(found), ...
    'Eligible target absent from full ledger.');

weights = L.area_weight(ledgerPos);

assert(all(weights > 0) && all(isfinite(weights)), ...
    'Invalid weights on eligible targets.');

%% 12. AREA-WEIGHTED SPATIAL MEDIANS
%
% Weighted empirical CDF:
% first observation crossing 50% cumulative area.
%
% No interpolation.

poseInertiaMedian = weightedQuantileFirst( ...
    poseTargetInertia, weights, 0.50);

poseMobilityMedian = weightedQuantileFirst( ...
    poseTargetMobility, weights, 0.50);

targetOnlyInertiaMedian = weightedQuantileFirst( ...
    targetOnlyInertia, weights, 0.50);

targetOnlyMobilityMedian = weightedQuantileFirst( ...
    targetOnlyMobility, weights, 0.50);

%% 13. PRINT REPRODUCTION RESULTS

fprintf('\n');
fprintf('============================================\n');
fprintf('POSE-MATCHED REPRODUCTION RESULTS\n');
fprintf('============================================\n');

fprintf('Eligible targets: %d (expected 1317)\n', ...
    nEligibleTargets);

fprintf('\nPROJECTED NORMAL INERTIA (kg)\n');

fprintf('Pose-matched calculated:  %+0.6f\n', ...
    poseInertiaMedian);

fprintf('Pose-matched expected:    -4.120129\n');

fprintf('Target-only calculated:   %+0.6f\n', ...
    targetOnlyInertiaMedian);

fprintf('Target-only expected:     +0.535486\n');

fprintf('\nNORMAL MOBILITY (kg^-1)\n');

fprintf('Pose-matched calculated:  %+0.8f\n', ...
    poseMobilityMedian);

fprintf('Pose-matched expected:    +0.05295540\n');

fprintf('Target-only calculated:   %+0.8f\n', ...
    targetOnlyMobilityMedian);

fprintf('Target-only expected:     -0.00296119\n');

%% 14. COMPARE WITH MANUSCRIPT CHECKPOINTS

% The reference values are rounded published results.
% Tolerances are absolute in the indicated physical units.

tolInertia = 5e-6;      % kg
tolMobility = 5e-7;     % kg^-1

passPoseInertia = ...
    abs(poseInertiaMedian - (-4.120129)) ...
    < tolInertia;

passTargetInertia = ...
    abs(targetOnlyInertiaMedian - 0.535486) ...
    < tolInertia;

passPoseMobility = ...
    abs(poseMobilityMedian - 0.0529554) ...
    < tolMobility;

passTargetMobility = ...
    abs(targetOnlyMobilityMedian - (-0.00296119)) ...
    < tolMobility;

allPassed = ...
    passPoseInertia && ...
    passTargetInertia && ...
    passPoseMobility && ...
    passTargetMobility && ...
    nEligibleTargets == 1317;

%% 15. SAVE OUTPUTS

summary = table( ...
    nEligibleTargets, ...
    nMixedRollGroups, ...
    poseInertiaMedian, ...
    targetOnlyInertiaMedian, ...
    poseMobilityMedian, ...
    targetOnlyMobilityMedian, ...
    allPassed, ...
    'VariableNames', { ...
        'EligibleTargets', ...
        'MixedTargetRollGroups', ...
        'PoseMatchedInertia_kg', ...
        'TargetOnlyInertia_kg', ...
        'PoseMatchedMobility_invkg', ...
        'TargetOnlyMobility_invkg', ...
        'AllCheckpointsPassed'});

targetDiagnostics = table( ...
    eligibleTargetIDs, ...
    weights, ...
    poseTargetInertia, ...
    targetOnlyInertia, ...
    poseTargetMobility, ...
    targetOnlyMobility, ...
    'VariableNames', { ...
        'target_index', ...
        'area_weight', ...
        'pose_inertia_contrast_kg', ...
        'target_only_inertia_contrast_kg', ...
        'pose_mobility_contrast_invkg', ...
        'target_only_mobility_contrast_invkg'});

rollDiagnostics = table( ...
    eligibleGroupTargets, ...
    eligibleGroupRolls, ...
    rollContrastInertia, ...
    rollContrastMobility, ...
    'VariableNames', { ...
        'target_index', ...
        'roll_index', ...
        'inertia_contrast_kg', ...
        'mobility_contrast_invkg'});

summaryFile = fullfile(outDir, ...
    'pose_matched_summary_30pct.csv');

targetFile = fullfile(outDir, ...
    'pose_matched_target_diagnostics_30pct.csv');

rollFile = fullfile(outDir, ...
    'pose_matched_roll_diagnostics_30pct.csv');

matFile = fullfile(outDir, ...
    'pose_matched_reproduction_30pct.mat');

writetable(summary, summaryFile);
writetable(targetDiagnostics, targetFile);
writetable(rollDiagnostics, rollFile);

save(matFile, ...
    'summary', ...
    'targetDiagnostics', ...
    'rollDiagnostics', ...
    'tau', ...
    'ICNmax', ...
    'tauICN', ...
    '-v7.3');

fprintf('\nOUTPUT FILES:\n');

fprintf('%s\n', summaryFile);
fprintf('%s\n', targetFile);
fprintf('%s\n', rollFile);
fprintf('%s\n', matFile);

%% 16. FINAL REPRODUCTION STATUS

if allPassed

    fprintf('\n');
    fprintf('============================================\n');
    fprintf('PASS: POSE-MATCHED ANALYSIS REPRODUCED\n');
    fprintf('============================================\n');

else

    fprintf('\n');
    fprintf('============================================\n');
    fprintf('FAIL: POSE-MATCHED CHECKPOINT MISMATCH\n');
    fprintf('============================================\n');

    warning(['The archived results do not match ', ...
        'all manuscript checkpoints. ', ...
        'Investigate before publication.']);

end

%% 17. REMOVE TEMPORARY EXTRACTION

clear cleanupTemp;

fprintf('\nPose-matched reproduction completed.\n');

%% ================================================================
% LOCAL FUNCTIONS
% ================================================================

function delta = selectedMinusUnselected(values, selected)

    selected = logical(selected);

    if ~any(selected) || ~any(~selected)
        error('Contrast requires both selected and unselected data.');
    end

    delta = median(values(selected)) ...
          - median(values(~selected));

end

function qValue = weightedQuantileFirst(values, weights, p)

    values = values(:);
    weights = weights(:);

    assert(numel(values) == numel(weights), ...
        'Values and weights must have equal lengths.');

    assert(all(isfinite(values)), ...
        'Nonfinite quantile input.');

    assert(all(isfinite(weights)) && ...
           all(weights > 0), ...
        'Invalid quantile weights.');

    assert(p >= 0 && p <= 1);

    [sortedValues, order] = sort(values);

    sortedWeights = weights(order);

    cumulative = cumsum(sortedWeights) ...
               / sum(sortedWeights);

    idx = find(cumulative >= p, 1, 'first');

    qValue = sortedValues(idx);

end

function removeTemporaryFolder(folderPath)

    if exist(folderPath, 'dir')
        try
            rmdir(folderPath, 's');
        catch ME
            warning('Temporary cleanup failed: %s', ME.message);
        end
    end

end
