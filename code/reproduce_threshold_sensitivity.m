
%% PANDA v2.10 - THRESHOLD SENSITIVITY REPRODUCTION
%
% Reproduces:
%   1. Joint threshold sweep: 20% to 50%
%   2. One-at-a-time (OAT) sensitivity
%   3. Leave-one-criterion-out ablation
%
% Input:
%   PANDA_CONFIGURATION_AUDIT ZIP
%
% Output:
%   joint_threshold_sweep.csv
%   oat_threshold_sensitivity.csv
%   leave_one_criterion_out.csv
%
% No IK, MEX or robot simulations.
% No Robotics System Toolbox required.
%
% IMPORTANT:
%   Use current D_n_R0 and D_n_R1.
%   NEVER use D_n_R0_frozen_ref or D_n_R1_frozen_ref.

clearvars;
clc;

%% 1. SELECT ORIGINAL ZIP

[file, folder] = uigetfile('*.zip', ...
    'Select PANDA_CONFIGURATION_AUDIT ZIP');

if isequal(file, 0)
    error('No ZIP selected.');
end

zipPath = fullfile(folder, file);

surfaces = {
    'Z_NEG_300mm'
    'Z_NEG_150mm'
    'Z_ZERO_000mm'
    'Z_POS_150mm'
    'Z_POS_300mm'
    'CURVED200_MINUS_N'
};

expectedCfg = [
    20822
    27142
    26230
    18200
    19408
    650473
];

expectedReach = [
    14422
    17620
    15116
    9796
    10504
    39898
];

nSurfaces = numel(surfaces);

% Relative threshold levels
levels = (20:5:50)' / 100;
nLevels = numel(levels);

% Baseline threshold
baseTau = 0.30;
baseIdx = find(abs(levels - baseTau) < 1e-12);

assert(numel(baseIdx) == 1);

% Four screening criteria
criteria = {
    'ICN'
    'W'
    'A'
    'D'
};

nCriteria = 4;

% Six-surface normalization authority
Wmax = 8.56235473224922e-5;
Amax = 0.0107948076153145;
Dmax = 0.00629241406275165;

% Streaming configuration CSV
chunkSize = 25000;

%% 2. EXTRACT ORIGINAL ARCHIVE

tempDir = tempname;
mkdir(tempDir);

cleanupTemp = onCleanup(@() ...
    cleanupFolder(tempDir));

fprintf('\nExtracting archive...\n');
unzip(zipPath, tempDir);

outDir = fullfile(folder, ...
    'PANDA_REPRODUCIBILITY_PACKAGE', 'results');

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% 3. DETERMINE GLOBAL ICN MAXIMUM

fprintf('\nDetermining six-surface ICN maximum...\n');

ICNmax = -inf;
totalCfg = 0;

for k = 1:nSurfaces

    cfgPath = fullfile(tempDir, surfaces{k}, ...
        'PER_CONFIGURATION.csv');

    ds = tabularTextDatastore(cfgPath, ...
        'ReadSize', chunkSize);

    ds.SelectedVariableNames = { ...
        'ICN', 'metric_valid'};

    surfaceCount = 0;

    while hasdata(ds)

        T = read(ds);

        assert(all(T.metric_valid == 1), ...
            'Invalid configuration metric detected.');

        assert(all(isfinite(T.ICN)), ...
            'Nonfinite ICN value.');

        ICNmax = max(ICNmax, max(T.ICN));

        surfaceCount = surfaceCount + height(T);

    end

    assert(surfaceCount == expectedCfg(k), ...
        'Configuration count mismatch.');

    totalCfg = totalCfg + surfaceCount;

end

assert(totalCfg == 762275);

expectedICNmax = 0.122791686207514;

assert(abs(ICNmax - expectedICNmax) < 1e-12, ...
    'ICN maximum differs from published reference.');

fprintf('\n=== GLOBAL REFERENCES ===\n');
fprintf('Configurations: %d\n', totalCfg);
fprintf('ICN max: %.15g\n', ICNmax);
fprintf('W max: %.15g\n', Wmax);
fprintf('A max: %.15g\n', Amax);
fprintf('D max: %.15g\n', Dmax);

%% 4. PREALLOCATE RESULT TABLE DATA

% Joint sweep: 6 surfaces x 7 threshold levels
jointCells = cell(nSurfaces*nLevels, 16);
jointRow = 0;

% OAT: 6 surfaces x 2 models x 4 criteria x 7 levels
oatCells = cell(nSurfaces*2*nCriteria*nLevels, 8);
oatRow = 0;

% Leave-one-out: 6 surfaces x 2 models x 4 criteria
ablationCells = cell(nSurfaces*2*nCriteria, 8);
ablationRow = 0;

%% 5. PROCESS EACH SURFACE

for k = 1:nSurfaces

    surface = surfaces{k};

    fprintf('\n====================================\n');
    fprintf('Processing %s\n', surface);
    fprintf('====================================\n');

    cfgPath = fullfile(tempDir, surface, ...
        'PER_CONFIGURATION.csv');

    ledgerPath = fullfile(tempDir, surface, ...
        'FULL_TARGET_LEDGER_AND_METRICS.csv');

    %% 5.1 Load target ledger

    opts = detectImportOptions(ledgerPath);

    opts.SelectedVariableNames = { ...
        'target_index', ...
        'reachable', ...
        'retained_count', ...
        'area_weight'};

    L = readtable(ledgerPath, opts);

    nTargets = height(L);

    assert(nTargets == 40000);
    assert(numel(unique(L.target_index)) == 40000);

    reachable = L.reachable == 1;

    assert(nnz(reachable) == expectedReach(k));

    assert(all(reachable == (L.retained_count > 0)));

    weights = L.area_weight;

    assert(all(isfinite(weights)) && all(weights > 0));

    fullArea = sum(weights);
    reachableArea = sum(weights(reachable));

    %% 5.2 Initialize target masks

    % Joint sweep
    jointMask0 = false(nTargets, nLevels);
    jointMask1 = false(nTargets, nLevels);
    jointMaskCommon = false(nTargets, nLevels);

    % OAT: targets x criterion x threshold
    oatMask0 = false(nTargets, nCriteria, nLevels);
    oatMask1 = false(nTargets, nCriteria, nLevels);

    % Leave-one-out
    abMask0 = false(nTargets, nCriteria);
    abMask1 = false(nTargets, nCriteria);

    % Passing configuration counts
    jointCfg0 = zeros(nLevels,1);
    jointCfg1 = zeros(nLevels,1);
    jointCfgCommon = zeros(nLevels,1);

    oatCfg0 = zeros(nCriteria,nLevels);
    oatCfg1 = zeros(nCriteria,nLevels);

    abCfg0 = zeros(nCriteria,1);
    abCfg1 = zeros(nCriteria,1);

    %% 5.3 Load configuration datastore

    ds = tabularTextDatastore(cfgPath, ...
        'ReadSize', chunkSize);

    ds.SelectedVariableNames = { ...
        'target_index', ...
        'metric_valid', ...
        'ICN', ...
        'W_raw', ...
        'W_n', ...
        'A_R0', ...
        'A_R1', ...
        'A_n_R0', ...
        'A_n_R1', ...
        'D_vol_R0', ...
        'D_vol_R1', ...
        'D_n_R0', ...
        'D_n_R1'};

    configCount = 0;

    %% 5.4 Process configurations in chunks

    while hasdata(ds)

        T = read(ds);

        configCount = configCount + height(T);

        assert(all(T.metric_valid == 1), ...
            'Invalid screening metric.');

        rawAndNorm = [ ...
            T.ICN, T.W_raw, T.W_n, ...
            T.A_R0, T.A_R1, ...
            T.A_n_R0, T.A_n_R1, ...
            T.D_vol_R0, T.D_vol_R1, ...
            T.D_n_R0, T.D_n_R1];

        assert(all(isfinite(rawAndNorm), 'all'), ...
            'Nonfinite screening metric.');

        %% 5.5 Verify normalization authority

        tolNorm = 1e-8;

        assert(max(abs( ...
            T.W_n - T.W_raw/Wmax)) < tolNorm);

        assert(max(abs( ...
            T.A_n_R0 - T.A_R0/Amax)) < tolNorm);

        assert(max(abs( ...
            T.A_n_R1 - T.A_R1/Amax)) < tolNorm);

        assert(max(abs( ...
            T.D_n_R0 - T.D_vol_R0/Dmax)) < tolNorm);

        assert(max(abs( ...
            T.D_n_R1 - T.D_vol_R1/Dmax)) < tolNorm);

        %% 5.6 Match configuration records to target ledger

        [found, loc] = ismember( ...
            T.target_index, L.target_index);

        assert(all(found), ...
            'Unknown target identifier.');

        assert(all(reachable(loc)), ...
            'Configuration assigned to unreachable target.');

        %% 5.7 Construct screening matrices

        % Columns: ICN, W, A, D
        M0 = [ ...
            T.ICN, ...
            T.W_n, ...
            T.A_n_R0, ...
            T.D_n_R0];

        M1 = [ ...
            T.ICN, ...
            T.W_n, ...
            T.A_n_R1, ...
            T.D_n_R1];

        % Baseline thresholds
        baseThresholds = [ ...
            baseTau*ICNmax, ...
            baseTau, ...
            baseTau, ...
            baseTau];

        %% 5.8 Joint threshold sweep

        for j = 1:nLevels

            t = levels(j);

            thresholds = [ ...
                t*ICNmax, t, t, t];

            pass0 = all(M0 >= thresholds, 2);
            pass1 = all(M1 >= thresholds, 2);

            % Same-configuration intersection
            passCommon = pass0 & pass1;

            jointCfg0(j) = jointCfg0(j) + nnz(pass0);
            jointCfg1(j) = jointCfg1(j) + nnz(pass1);

            jointCfgCommon(j) = ...
                jointCfgCommon(j) + nnz(passCommon);

            jointMask0(loc(pass0),j) = true;
            jointMask1(loc(pass1),j) = true;

            jointMaskCommon(loc(passCommon),j) = true;

        end

        %% 5.9 One-at-a-time threshold variation

        for criterion = 1:nCriteria

            for j = 1:nLevels

                t = levels(j);

                thresholds = baseThresholds;

                if criterion == 1
                    thresholds(1) = t*ICNmax;
                else
                    thresholds(criterion) = t;
                end

                pass0 = all(M0 >= thresholds, 2);
                pass1 = all(M1 >= thresholds, 2);

                oatCfg0(criterion,j) = ...
                    oatCfg0(criterion,j) + nnz(pass0);

                oatCfg1(criterion,j) = ...
                    oatCfg1(criterion,j) + nnz(pass1);

                oatMask0(loc(pass0),criterion,j) = true;
                oatMask1(loc(pass1),criterion,j) = true;

            end

        end

        %% 5.10 Leave-one-criterion-out ablation

        for criterion = 1:nCriteria

            keep = setdiff(1:nCriteria, criterion);

            pass0 = all( ...
                M0(:,keep) >= baseThresholds(keep), 2);

            pass1 = all( ...
                M1(:,keep) >= baseThresholds(keep), 2);

            abCfg0(criterion) = ...
                abCfg0(criterion) + nnz(pass0);

            abCfg1(criterion) = ...
                abCfg1(criterion) + nnz(pass1);

            abMask0(loc(pass0),criterion) = true;
            abMask1(loc(pass1),criterion) = true;

        end

    end

    assert(configCount == expectedCfg(k), ...
        'Configuration count mismatch.');

    %% 5.11 Baseline area fractions

    baselineMask0 = jointMask0(:,baseIdx);
    baselineMask1 = jointMask1(:,baseIdx);

    baselineArea0 = ...
        100*sum(weights(baselineMask0))/reachableArea;

    baselineArea1 = ...
        100*sum(weights(baselineMask1))/reachableArea;

    %% 5.12 Export joint sweep rows

    for j = 1:nLevels

        m0 = jointMask0(:,j);
        m1 = jointMask1(:,j);
        mc = jointMaskCommon(:,j);

        jointRow = jointRow + 1;

        jointCells(jointRow,:) = { ...
            string(surface), ...
            100*levels(j), ...
            configCount, ...
            nnz(reachable), ...
            jointCfg0(j), ...
            jointCfg1(j), ...
            jointCfgCommon(j), ...
            nnz(m0), ...
            nnz(m1), ...
            nnz(mc), ...
            100*sum(weights(m0))/fullArea, ...
            100*sum(weights(m1))/fullArea, ...
            100*sum(weights(mc))/fullArea, ...
            100*sum(weights(m0))/reachableArea, ...
            100*sum(weights(m1))/reachableArea, ...
            100*sum(weights(mc))/reachableArea};

    end

    %% 5.13 Export OAT rows

    for criterion = 1:nCriteria

        for j = 1:nLevels

            for model = 1:2

                if model == 1
                    modelName = "R0";
                    mask = oatMask0(:,criterion,j);
                    nCfg = oatCfg0(criterion,j);
                else
                    modelName = "R1";
                    mask = oatMask1(:,criterion,j);
                    nCfg = oatCfg1(criterion,j);
                end

                oatRow = oatRow + 1;

                oatCells(oatRow,:) = { ...
                    string(surface), ...
                    modelName, ...
                    string(criteria{criterion}), ...
                    100*levels(j), ...
                    nCfg, ...
                    nnz(mask), ...
                    100*sum(weights(mask))/fullArea, ...
                    100*sum(weights(mask))/reachableArea};

            end

        end

    end

    %% 5.14 Export leave-one-out rows

    for criterion = 1:nCriteria

        for model = 1:2

            if model == 1
                modelName = "R0";
                mask = abMask0(:,criterion);
                nCfg = abCfg0(criterion);
                baseArea = baselineArea0;
            else
                modelName = "R1";
                mask = abMask1(:,criterion);
                nCfg = abCfg1(criterion);
                baseArea = baselineArea1;
            end

            abArea = ...
                100*sum(weights(mask))/reachableArea;

            % Percentage-point increase relative to 30% baseline
            gainPP = abArea - baseArea;

            assert(gainPP >= -1e-9, ...
                'Removing a criterion reduced qualification.');

            ablationRow = ablationRow + 1;

            ablationCells(ablationRow,:) = { ...
                string(surface), ...
                modelName, ...
                string(criteria{criterion}), ...
                nCfg, ...
                nnz(mask), ...
                baseArea, ...
                abArea, ...
                gainPP};

        end

    end

    %% 5.15 Print baseline checkpoint

    fprintf('30%% R0 targets:     %d\n', ...
        nnz(jointMask0(:,baseIdx)));

    fprintf('30%% R1 targets:     %d\n', ...
        nnz(jointMask1(:,baseIdx)));

    fprintf('30%% Common targets: %d\n', ...
        nnz(jointMaskCommon(:,baseIdx)));

    if k == nSurfaces

        fprintf('Spherical 30%% R1 full area: %.6f %%\n', ...
            100*sum(weights(jointMask1(:,baseIdx))) ...
            / fullArea);

    end

end

%% 6. CREATE OUTPUT TABLES

jointResults = cell2table(jointCells, ...
    'VariableNames', { ...
        'Surface', ...
        'Threshold_pct', ...
        'Configurations', ...
        'ReachableTargets', ...
        'R0_Configurations', ...
        'R1_Configurations', ...
        'Common_Configurations', ...
        'R0_Targets', ...
        'R1_Targets', ...
        'Common_Targets', ...
        'R0_FullArea_pct', ...
        'R1_FullArea_pct', ...
        'Common_FullArea_pct', ...
        'R0_ReachableArea_pct', ...
        'R1_ReachableArea_pct', ...
        'Common_ReachableArea_pct'});

oatResults = cell2table(oatCells, ...
    'VariableNames', { ...
        'Surface', ...
        'Model', ...
        'VariedCriterion', ...
        'Threshold_pct', ...
        'QualifiedConfigurations', ...
        'QualifiedTargets', ...
        'FullArea_pct', ...
        'ReachableArea_pct'});

ablationResults = cell2table(ablationCells, ...
    'VariableNames', { ...
        'Surface', ...
        'Model', ...
        'RemovedCriterion', ...
        'QualifiedConfigurations', ...
        'QualifiedTargets', ...
        'BaselineReachableArea_pct', ...
        'ThreeCriterionReachableArea_pct', ...
        'Gain_percentage_points'});

%% 7. SAVE OUTPUTS

jointFile = fullfile(outDir, ...
    'joint_threshold_sweep.csv');

oatFile = fullfile(outDir, ...
    'oat_threshold_sensitivity.csv');

ablationFile = fullfile(outDir, ...
    'leave_one_criterion_out.csv');

writetable(jointResults, jointFile);
writetable(oatResults, oatFile);
writetable(ablationResults, ablationFile);

%% 8. AUTOMATED 30% CHECKPOINTS

fprintf('\n====================================\n');
fprintf('30%% BASELINE REPRODUCTION CHECK\n');
fprintf('====================================\n');

baselineRows = ...
    abs(jointResults.Threshold_pct - 30) < 1e-9;

B = jointResults(baselineRows,:);

expectedR0 = [768; 831; 1; 0; 213; 11688];
expectedR1 = [5274; 6636; 718; 62; 2979; 38568];
expectedCommon = [768; 831; 1; 0; 213; 11623];

passCounts = ...
    isequal(B.R0_Targets, expectedR0) && ...
    isequal(B.R1_Targets, expectedR1) && ...
    isequal(B.Common_Targets, expectedCommon);

totalR1configs = sum(B.R1_Configurations);
totalR1targets = sum(B.R1_Targets);

passTotals = ...
    (totalR1configs == 322486) && ...
    (totalR1targets == 54237);

sphereFull = B.R1_FullArea_pct(end);
sphereReach = B.R1_ReachableArea_pct(end);
sphereCommon = B.Common_FullArea_pct(end);

% Published area percentages have 3 decimal places
areaTol = 0.00051;

passArea = ...
    abs(sphereFull - 97.521) < areaTol && ...
    abs(sphereReach - 97.760) < areaTol && ...
    abs(sphereCommon - 34.825) < areaTol;

fprintf('R1 configurations: %d / 322486\n', ...
    totalR1configs);

fprintf('R1 targets:        %d / 54237\n', ...
    totalR1targets);

fprintf('Sphere R1 full area: %.6f %%\n', sphereFull);
fprintf('Sphere R1 reachable: %.6f %%\n', sphereReach);
fprintf('Sphere common full: %.6f %%\n', sphereCommon);

%% 9. CONSISTENCY CHECKS

% Raising a common threshold cannot increase qualified area.
monotonicJoint = true;

for k = 1:nSurfaces

    rows = jointResults.Surface == string(surfaces{k});
    J = jointResults(rows,:);

    values = [ ...
        J.R0_ReachableArea_pct, ...
        J.R1_ReachableArea_pct, ...
        J.Common_ReachableArea_pct];

    if any(diff(values,1,1) > 1e-9, 'all')
        monotonicJoint = false;
    end

end

% At OAT level 30%, all four individually varied
% criteria must reproduce the same baseline area.
oatBaselinePass = true;

for k = 1:nSurfaces

    for model = ["R0", "R1"]

        rowsO = ...
            oatResults.Surface == string(surfaces{k}) & ...
            oatResults.Model == model & ...
            abs(oatResults.Threshold_pct - 30) < 1e-9;

        O = oatResults(rowsO,:);

        rowsJ = ...
            B.Surface == string(surfaces{k});

        if model == "R0"
            expectedArea = B.R0_ReachableArea_pct(rowsJ);
        else
            expectedArea = B.R1_ReachableArea_pct(rowsJ);
        end

        if height(O) ~= 4 || ...
           any(abs(O.ReachableArea_pct - expectedArea) > 1e-9)
            oatBaselinePass = false;
        end

    end

end

allPassed = ...
    passCounts && ...
    passTotals && ...
    passArea && ...
    monotonicJoint && ...
    oatBaselinePass;

fprintf('\n=== AUTOMATED TESTS ===\n');
fprintf('30%% target counts: %d\n', passCounts);
fprintf('30%% R1 totals: %d\n', passTotals);
fprintf('30%% area fractions: %d\n', passArea);
fprintf('Joint sweep monotonicity: %d\n', monotonicJoint);
fprintf('OAT 30%% baseline identity: %d\n', oatBaselinePass);

fprintf('\nOUTPUT FILES:\n');
fprintf('%s\n', jointFile);
fprintf('%s\n', oatFile);
fprintf('%s\n', ablationFile);

if allPassed

    fprintf('\n====================================\n');
    fprintf('PASS: THRESHOLD AUDIT COMPLETED\n');
    fprintf('====================================\n');

    fprintf(['30%% reference reproduced; ', ...
        'sensitivity and ablation files generated.\n']);

else

    fprintf('\n====================================\n');
    fprintf('FAIL: THRESHOLD AUDIT\n');
    fprintf('====================================\n');

    warning('At least one automated check failed.');

end

%% 10. CLEANUP

clear cleanupTemp;

fprintf('\nThreshold analysis completed.\n');

%% LOCAL FUNCTION

function cleanupFolder(folderPath)

    if exist(folderPath,'dir')
        try
            rmdir(folderPath,'s');
        catch ME
            warning('Cleanup failed: %s', ME.message);
        end
    end

end
