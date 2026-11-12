
%% PANDA v2.10 - Reproduce paired normal loading
% Spherical R1-selected configurations, 30% threshold.
%
% Input: PANDA_CONFIGURATION_AUDIT ZIP
% No IK, MEX, Robotics System Toolbox or simulations.
%
% Output: paired_loading_sphere_30pct.csv

clearvars;
clc;

%% 1. Select original ZIP

[file, folder] = uigetfile('*.zip', ...
    'Select PANDA_CONFIGURATION_AUDIT ZIP');

if isequal(file, 0)
    error('No ZIP selected.');
end

zipPath = fullfile(folder, file);

tempDir = tempname;
mkdir(tempDir);

cleanupObj = onCleanup(@() ...
    rmdir(tempDir, 's'));

fprintf('\nExtracting archive...\n');
unzip(zipPath, tempDir);

surface = 'CURVED200_MINUS_N';

cfgPath = fullfile(tempDir, surface, ...
    'PER_CONFIGURATION.csv');

ledgerPath = fullfile(tempDir, surface, ...
    'FULL_TARGET_LEDGER_AND_METRICS.csv');

%% 2. Load spherical target ledger

opts = detectImportOptions(ledgerPath);
opts.SelectedVariableNames = { ...
    'target_index', ...
    'reachable', ...
    'area_weight'};

L = readtable(ledgerPath, opts);

assert(height(L) == 40000);
assert(nnz(L.reachable == 1) == 39898);
assert(numel(unique(L.target_index)) == 40000);

%% 3. Fixed published 30% screening references

tau = 0.30;

ICNmax = 0.122791686207514;
ICNthreshold = tau * ICNmax;

% Current six-surface normalized columns:
% W_n, A_n_R1, D_n_R1
%
% NEVER use D_n_R1_frozen_ref.

%% 4. Read configurations in chunks

ds = tabularTextDatastore(cfgPath, ...
    'ReadSize', 25000);

ds.SelectedVariableNames = { ...
    'target_index', ...
    'metric_valid', ...
    'normal_metric_valid', ...
    'ICN', ...
    'W_n', ...
    'A_n_R1', ...
    'D_n_R1', ...
    'paired_normal_inertia_change_pct', ...
    'paired_normal_mobility_change_pct'};

selectedTargets = [];
deltaInertia = [];
deltaMobility = [];

totalRecords = 0;
selectedRecords = 0;

fprintf('\nEvaluating R1 selection...\n');

while hasdata(ds)

    T = read(ds);

    totalRecords = totalRecords + height(T);

    assert(all(T.metric_valid == 1), ...
        'Invalid screening metric detected.');

    % Apply all four criteria at the same configuration

    selected = ...
        T.ICN >= ICNthreshold & ...
        T.W_n >= tau & ...
        T.A_n_R1 >= tau & ...
        T.D_n_R1 >= tau;

    selectedRecords = ...
        selectedRecords + nnz(selected);

    % Normal metrics must be valid for selected records
    assert(all(T.normal_metric_valid(selected) == 1), ...
        'Invalid normal metric in selected population.');

    dI = T.paired_normal_inertia_change_pct(selected);
    dM = T.paired_normal_mobility_change_pct(selected);

    assert(all(isfinite(dI)) && all(isfinite(dM)), ...
        'Nonfinite paired change in selected records.');

    selectedTargets = [selectedTargets; ...
        T.target_index(selected)];

    deltaInertia = [deltaInertia; dI];
    deltaMobility = [deltaMobility; dM];

end

assert(totalRecords == 650473, ...
    'Unexpected spherical configuration count.');

assert(selectedRecords == 302155, ...
    'R1 selected configuration count mismatch.');

%% 5. Ordinary median within each target

[G, targetIDs] = findgroups(selectedTargets);

medianInertia = splitapply(@median, ...
    deltaInertia, G);

medianMobility = splitapply(@median, ...
    deltaMobility, G);

nSelectedTargets = numel(targetIDs);

assert(nSelectedTargets == 38568, ...
    'Selected target count mismatch.');

%% 6. Match target weights

[found, loc] = ismember(targetIDs, ...
    L.target_index);

assert(all(found), ...
    'Selected target not found in target ledger.');

weights = L.area_weight(loc);

assert(all(weights > 0) && all(isfinite(weights)));

% Each target contributes its physical-area weight once.

%% 7. Area-weighted spatial median
% First crossing of the weighted empirical CDF.
% No interpolation between adjacent values.

[sortedI, orderI] = sort(medianInertia);
weightsI = weights(orderI);

cdfI = cumsum(weightsI) / sum(weightsI);

idxI = find(cdfI >= 0.5, 1, 'first');

weightedMedianInertia = sortedI(idxI);

[sortedM, orderM] = sort(medianMobility);
weightsM = weights(orderM);

cdfM = cumsum(weightsM) / sum(weightsM);

idxM = find(cdfM >= 0.5, 1, 'first');

weightedMedianMobility = sortedM(idxM);

%% 8. Print numerical comparison

fprintf('\n=== PAIRED LOADING REPRODUCTION ===\n');

fprintf('Total spherical configurations: %d\n', ...
    totalRecords);

fprintf('R1-selected configurations: %d\n', ...
    selectedRecords);

fprintf('R1-selected targets: %d\n', ...
    nSelectedTargets);

fprintf('\nProjected normal inertia change:\n');

fprintf('Calculated: %+0.6f %%\n', ...
    weightedMedianInertia);

fprintf('Expected:   +14.213 %%\n');

fprintf('\nNormal mobility change:\n');

fprintf('Calculated: %+0.6f %%\n', ...
    weightedMedianMobility);

fprintf('Expected:   -29.837 %%\n');

%% 9. Reproduction checks

% Article figures are rounded to three decimal places
tol = 0.00051;

passInertia = ...
    abs(weightedMedianInertia - 14.213) < tol;

passMobility = ...
    abs(weightedMedianMobility + 29.837) < tol;

%% 10. Save results

outDir = fullfile(folder, ...
    'PANDA_REPRODUCIBILITY_PACKAGE', 'results');

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

result = table( ...
    selectedRecords, ...
    nSelectedTargets, ...
    weightedMedianInertia, ...
    weightedMedianMobility, ...
    'VariableNames', { ...
    'SelectedConfigurations', ...
    'SelectedTargets', ...
    'InertiaChange_pct', ...
    'MobilityChange_pct'});

outFile = fullfile(outDir, ...
    'paired_loading_sphere_30pct.csv');

writetable(result, outFile);

fprintf('\nSaved: %s\n', outFile);

if passInertia && passMobility

    fprintf('\n====================================\n');
    fprintf('PASS: PAIRED LOADING REPRODUCED\n');
    fprintf('====================================\n');

else

    fprintf('\n====================================\n');
    fprintf('FAIL: PAIRED LOADING MISMATCH\n');
    fprintf('====================================\n');

    warning(['Do not accept these results ', ...
        'as reproduced until investigated.']);

end

clear cleanupObj;
