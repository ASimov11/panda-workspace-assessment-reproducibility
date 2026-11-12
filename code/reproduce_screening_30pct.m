
%% PANDA v2.10
% REPRODUCE 30% CONFIGURATION-CONSISTENT SCREENING
%
% Input:
%   PANDA_CONFIGURATION_AUDIT.zip
%
% Outputs:
%   screening_summary_30pct.csv
%   screening_masks_30pct.mat
%
% Requirements:
%   MATLAB with tabularTextDatastore, readtable, unzip.
%   No Robotics System Toolbox required.
%
% No IK, MEX, dynamics or new robot simulations.
%
% IMPORTANT:
%   Use D_n_R0 and D_n_R1.
%   DO NOT use D_n_R0_frozen_ref or D_n_R1_frozen_ref.

clearvars;
clc;

%% ================================================================
%  1. SELECT ORIGINAL ZIP ARCHIVE
%  ================================================================

[file, folder] = uigetfile('*.zip', ...
    'Select PANDA_CONFIGURATION_AUDIT ZIP');

if isequal(file, 0)
    error('No ZIP archive selected.');
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

% Screening threshold
tau = 0.30;

% Current six-surface normalization authority
Wmax_current = 8.56235473224922e-5;
Amax_current = 0.0107948076153145;
Dmax_current = 0.00629241406275165;

% Read configuration files in blocks
chunkSize = 25000;

%% ================================================================
%  2. EXTRACT ARCHIVE TO TEMPORARY DIRECTORY
%  ================================================================

tempDir = tempname;
mkdir(tempDir);

cleanupTemp = onCleanup(@() removeTempFolder(tempDir));

fprintf('\nExtracting original numerical archive...\n');

unzip(zipPath, tempDir);

% Save results next to the selected ZIP
outDir = fullfile(folder, ...
    'PANDA_REPRO_SCREENING_30pct');

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% ================================================================
%  3. FIRST PASS: OBSERVED ICN MAXIMUM
%  ================================================================
%
% ICN itself is not normalized by the observed maximum.
% The observed maximum is used ONLY for threshold selection.
%
% The current W/A/D columns already contain the correct
% six-surface normalization.

ICNmax = -inf;
nConfigCheck = zeros(nSurfaces, 1);

for k = 1:nSurfaces

    cfgPath = fullfile(tempDir, surfaces{k}, ...
        'PER_CONFIGURATION.csv');

    assert(isfile(cfgPath), ...
        'Missing configuration file: %s', cfgPath);

    ds = tabularTextDatastore(cfgPath, ...
        'ReadSize', chunkSize);

    ds.SelectedVariableNames = { ...
        'ICN', ...
        'metric_valid'};

    while hasdata(ds)

        T = read(ds);

        valid = ...
            (T.metric_valid == 1) & ...
            isfinite(T.ICN);

        if any(valid)
            ICNmax = max(ICNmax, max(T.ICN(valid)));
        end

        nConfigCheck(k) = ...
            nConfigCheck(k) + height(T);
    end

    assert(nConfigCheck(k) == expectedCfg(k), ...
        'Configuration count mismatch for %s', ...
        surfaces{k});

end

assert(isfinite(ICNmax) && ICNmax > 0, ...
    'Invalid observed ICN maximum.');

tauICN = tau * ICNmax;

fprintf('\n=== GLOBAL SCREENING REFERENCE ===\n');

fprintf('Observed ICN max: %.15g\n', ICNmax);
fprintf('Raw ICN threshold: %.15g\n', tauICN);
fprintf('W/A/D normalized threshold: %.2f\n', tau);

fprintf('\nCurrent six-surface maxima:\n');
fprintf('Wmax = %.15g\n', Wmax_current);
fprintf('Amax = %.15g\n', Amax_current);
fprintf('Dmax = %.15g\n', Dmax_current);

% Published ICN maximum from the previous audit
expectedICNmax = 0.122791686207514;

assert(abs(ICNmax - expectedICNmax) < 1e-12, ...
    'ICN reference differs from the expected archive.');

%% ================================================================
%  4. INITIALIZE SUMMARY
%  ================================================================

summary = table();

summary.Surface = string(surfaces);

summary.Configurations = zeros(nSurfaces, 1);
summary.ReachableTargets = zeros(nSurfaces, 1);

summary.R0_Configurations = zeros(nSurfaces, 1);
summary.R1_Configurations = zeros(nSurfaces, 1);
summary.Common_Configurations = zeros(nSurfaces, 1);

summary.R0_Targets = zeros(nSurfaces, 1);
summary.R1_Targets = zeros(nSurfaces, 1);
summary.Common_Targets = zeros(nSurfaces, 1);

summary.R0_FullArea_pct = zeros(nSurfaces, 1);
summary.R1_FullArea_pct = zeros(nSurfaces, 1);
summary.Common_FullArea_pct = zeros(nSurfaces, 1);

summary.R0_ReachableArea_pct = zeros(nSurfaces, 1);
summary.R1_ReachableArea_pct = zeros(nSurfaces, 1);
summary.Common_ReachableArea_pct = zeros(nSurfaces, 1);

masks = struct([]);

%% ================================================================
%  5. SECOND PASS: CONFIGURATION-LEVEL SCREENING
%  ================================================================

for k = 1:nSurfaces

    surface = surfaces{k};

    fprintf('\nProcessing %s\n', surface);

    cfgPath = fullfile(tempDir, surface, ...
        'PER_CONFIGURATION.csv');

    ledgerPath = fullfile(tempDir, surface, ...
        'FULL_TARGET_LEDGER_AND_METRICS.csv');

    assert(isfile(ledgerPath), ...
        'Missing target ledger: %s', ledgerPath);

    %% ------------------------------------------------------------
    %  5.1 LOAD TARGET LEDGER
    %  ------------------------------------------------------------

    opts = detectImportOptions(ledgerPath);

    opts.SelectedVariableNames = { ...
        'target_index', ...
        'reachable', ...
        'retained_count', ...
        'area_weight'};

    L = readtable(ledgerPath, opts);

    assert(height(L) == 40000, ...
        'Incorrect target count for %s', surface);

    assert(numel(unique(L.target_index)) == 40000, ...
        'Duplicate target_index in %s', surface);

    reachable = (L.reachable == 1);

    assert(nnz(reachable) == expectedReach(k), ...
        'Reachability mismatch for %s', surface);

    assert(all(reachable == (L.retained_count > 0)), ...
        'Reachability/retained_count mismatch.');

    assert(all(isfinite(L.area_weight)) && ...
           all(L.area_weight > 0), ...
        'Invalid area weights.');

    fullArea = sum(L.area_weight);

    reachableArea = ...
        sum(L.area_weight(reachable));

    nTargets = height(L);

    %% ------------------------------------------------------------
    %  5.2 INITIALIZE TARGET-LEVEL MASKS
    %  ------------------------------------------------------------

    maskR0 = false(nTargets, 1);
    maskR1 = false(nTargets, 1);
    maskCommon = false(nTargets, 1);

    %% ------------------------------------------------------------
    %  5.3 OPEN CONFIGURATION DATASTORE
    %  ------------------------------------------------------------

    ds = tabularTextDatastore(cfgPath, ...
        'ReadSize', chunkSize);

    % CORRECT CURRENT NORMALIZATION COLUMNS
    %
    % D_n_R0 and D_n_R1 are the current six-surface values.
    % Do not select the older frozen_ref columns.

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

    countR0 = 0;
    countR1 = 0;
    countCommon = 0;

    %% ------------------------------------------------------------
    %  5.4 PROCESS CONFIGURATIONS IN CHUNKS
    %  ------------------------------------------------------------

    while hasdata(ds)

        T = read(ds);

        configCount = configCount + height(T);

        %% Validate metric population

        assert(all(T.metric_valid == 1), ...
            'Invalid metric record in %s', surface);

        metricData = [ ...
            T.ICN, ...
            T.W_raw, ...
            T.W_n, ...
            T.A_R0, ...
            T.A_R1, ...
            T.A_n_R0, ...
            T.A_n_R1, ...
            T.D_vol_R0, ...
            T.D_vol_R1, ...
            T.D_n_R0, ...
            T.D_n_R1];

        assert(all(isfinite(metricData), 'all'), ...
            'Nonfinite metric encountered in %s', surface);

        %% --------------------------------------------------------
        %  5.5 VERIFY CURRENT NORMALIZATION
        %  --------------------------------------------------------

        % These checks prevent use of obsolete normalizations.

        expectedWn = T.W_raw / Wmax_current;

        expectedAnR0 = T.A_R0 / Amax_current;
        expectedAnR1 = T.A_R1 / Amax_current;

        expectedDnR0 = T.D_vol_R0 / Dmax_current;
        expectedDnR1 = T.D_vol_R1 / Dmax_current;

        normTolerance = 1e-8;

        assert(max(abs(T.W_n - expectedWn)) ...
               < normTolerance, ...
            'W normalization mismatch in %s', surface);

        assert(max(abs(T.A_n_R0 - expectedAnR0)) ...
               < normTolerance, ...
            'R0 Asada normalization mismatch in %s', surface);

        assert(max(abs(T.A_n_R1 - expectedAnR1)) ...
               < normTolerance, ...
            'R1 Asada normalization mismatch in %s', surface);

        assert(max(abs(T.D_n_R0 - expectedDnR0)) ...
               < normTolerance, ...
            'R0 D normalization mismatch in %s', surface);

        assert(max(abs(T.D_n_R1 - expectedDnR1)) ...
               < normTolerance, ...
            'R1 D normalization mismatch in %s', surface);

        %% --------------------------------------------------------
        %  5.6 IDENTIFY TARGET ROWS
        %  --------------------------------------------------------

        [found, loc] = ismember( ...
            T.target_index, L.target_index);

        assert(all(found), ...
            'Unknown target_index in %s', surface);

        assert(all(reachable(loc)), ...
            'Configuration assigned to unreachable target.');

        %% --------------------------------------------------------
        %  5.7 FOUR-CRITERION SCREENING
        %  --------------------------------------------------------
        %
        % All criteria are applied to the SAME retained q.
        %
        % ICN threshold = 30% of observed raw ICN max.
        % W, A and D thresholds = 0.30 on normalized values.

        passKinematic = ...
            (T.ICN >= tauICN) & ...
            (T.W_n >= tau);

        passR0 = ...
            passKinematic & ...
            (T.A_n_R0 >= tau) & ...
            (T.D_n_R0 >= tau);

        passR1 = ...
            passKinematic & ...
            (T.A_n_R1 >= tau) & ...
            (T.D_n_R1 >= tau);

        % Intersection at the SAME configuration
        passCommon = passR0 & passR1;

        %% --------------------------------------------------------
        %  5.8 COUNT PASSING CONFIGURATIONS
        %  --------------------------------------------------------

        countR0 = countR0 + nnz(passR0);
        countR1 = countR1 + nnz(passR1);

        countCommon = ...
            countCommon + nnz(passCommon);

        %% --------------------------------------------------------
        %  5.9 AGGREGATE TO TARGET MASKS
        %  --------------------------------------------------------
        %
        % A target qualifies if at least one retained
        % configuration passes the corresponding screen.
        %
        % Common is NOT computed by intersecting target masks.

        maskR0(loc(passR0)) = true;

        maskR1(loc(passR1)) = true;

        maskCommon(loc(passCommon)) = true;

    end

    %% ------------------------------------------------------------
    %  5.10 POPULATION CHECKS
    %  ------------------------------------------------------------

    assert(configCount == expectedCfg(k), ...
        'Configuration count mismatch in %s', surface);

    assert(~any(maskR0 & ~reachable), ...
        'R0 qualifying target marked unreachable.');

    assert(~any(maskR1 & ~reachable), ...
        'R1 qualifying target marked unreachable.');

    assert(~any(maskCommon & ~reachable), ...
        'Common qualifying target marked unreachable.');

    assert(all(~maskCommon | (maskR0 & maskR1)), ...
        'Common mask inconsistent with model masks.');

    %% ------------------------------------------------------------
    %  5.11 WRITE SUMMARY
    %  ------------------------------------------------------------

    summary.Configurations(k) = configCount;

    summary.ReachableTargets(k) = nnz(reachable);

    summary.R0_Configurations(k) = countR0;
    summary.R1_Configurations(k) = countR1;

    summary.Common_Configurations(k) = ...
        countCommon;

    summary.R0_Targets(k) = nnz(maskR0);
    summary.R1_Targets(k) = nnz(maskR1);

    summary.Common_Targets(k) = ...
        nnz(maskCommon);

    %% Full-area coverage

    summary.R0_FullArea_pct(k) = ...
        100 * sum(L.area_weight(maskR0)) / fullArea;

    summary.R1_FullArea_pct(k) = ...
        100 * sum(L.area_weight(maskR1)) / fullArea;

    summary.Common_FullArea_pct(k) = ...
        100 * sum(L.area_weight(maskCommon)) / fullArea;

    %% Reachable-area coverage

    summary.R0_ReachableArea_pct(k) = ...
        100 * sum(L.area_weight(maskR0)) / reachableArea;

    summary.R1_ReachableArea_pct(k) = ...
        100 * sum(L.area_weight(maskR1)) / reachableArea;

    summary.Common_ReachableArea_pct(k) = ...
        100 * sum(L.area_weight(maskCommon)) / reachableArea;

    %% ------------------------------------------------------------
    %  5.12 SAVE TARGET MASKS IN MEMORY
    %  ------------------------------------------------------------

    masks(k).surface = surface;
    masks(k).target_index = L.target_index;

    masks(k).reachable = reachable;
    masks(k).area_weight = L.area_weight;

    masks(k).R0 = maskR0;
    masks(k).R1 = maskR1;
    masks(k).common = maskCommon;

    %% Print surface results

    fprintf('R0:     %8d configurations, %6d targets\n', ...
        countR0, nnz(maskR0));

    fprintf('R1:     %8d configurations, %6d targets\n', ...
        countR1, nnz(maskR1));

    fprintf('Common: %8d configurations, %6d targets\n', ...
        countCommon, nnz(maskCommon));

end

%% ================================================================
%  6. SAVE REPRODUCTION RESULTS
%  ================================================================

csvOut = fullfile(outDir, ...
    'screening_summary_30pct.csv');

matOut = fullfile(outDir, ...
    'screening_masks_30pct.mat');

writetable(summary, csvOut);

save(matOut, ...
    'summary', ...
    'masks', ...
    'ICNmax', ...
    'tauICN', ...
    'tau', ...
    'Wmax_current', ...
    'Amax_current', ...
    'Dmax_current', ...
    '-v7.3');

fprintf('\n=== SCREENING SUMMARY ===\n');

disp(summary);

%% ================================================================
%  7. MANUSCRIPT REPRODUCTION CHECK
%  ================================================================

nR1cfg = sum(summary.R1_Configurations);

nR1targets = sum(summary.R1_Targets);

sphereR1cfg = summary.R1_Configurations(end);

sphereR1targets = summary.R1_Targets(end);

sphereFullPct = summary.R1_FullArea_pct(end);

sphereReachPct = summary.R1_ReachableArea_pct(end);

sphereCommonPct = ...
    summary.Common_FullArea_pct(end);

fprintf('\n=== MANUSCRIPT REPRODUCTION CHECK ===\n');

fprintf('R1 configurations: %d (expected 322486)\n', ...
    nR1cfg);

fprintf('R1 targets:        %d (expected 54237)\n', ...
    nR1targets);

fprintf('Spherical R1 configurations: %d (expected 302155)\n', ...
    sphereR1cfg);

fprintf('Spherical R1 targets:        %d (expected 38568)\n', ...
    sphereR1targets);

fprintf('Spherical R1 full area: %.6f %% (expected 97.521%%)\n', ...
    sphereFullPct);

fprintf('Spherical R1 reachable area: %.6f %% (expected 97.760%%)\n', ...
    sphereReachPct);

fprintf('Spherical common full area: %.6f %% (expected 34.825%%)\n', ...
    sphereCommonPct);

%% Compare exact counts

passCounts = ...
    (nR1cfg == 322486) && ...
    (nR1targets == 54237) && ...
    (sphereR1cfg == 302155) && ...
    (sphereR1targets == 38568);

% Published percentages have three decimal places.
% Allow rounding tolerance slightly above 0.0005.
areaTol = 0.00051;

passArea = ...
    (abs(sphereFullPct - 97.521) < areaTol) && ...
    (abs(sphereReachPct - 97.760) < areaTol) && ...
    (abs(sphereCommonPct - 34.825) < areaTol);

fprintf('\nOUTPUT CSV: %s\n', csvOut);
fprintf('OUTPUT MAT: %s\n', matOut);

if passCounts && passArea

    fprintf('\n');
    fprintf('========================================\n');
    fprintf('PASS: 30%% SCREENING REPRODUCED\n');
    fprintf('========================================\n');

else

    fprintf('\n');
    fprintf('========================================\n');
    fprintf('FAIL: MANUSCRIPT CHECKPOINT MISMATCH\n');
    fprintf('========================================\n');

    warning(['At least one published screening result ', ...
        'was not reproduced. Do not publish as verified.']);

end

%% ================================================================
%  8. CLEAN UP TEMPORARY EXTRACTION
%  ================================================================

clear cleanupTemp;

fprintf('\nReproduction script completed.\n');

%% ================================================================
%  LOCAL FUNCTION
%  ================================================================

function removeTempFolder(folderPath)

    if exist(folderPath, 'dir')
        try
            rmdir(folderPath, 's');
        catch ME
            warning('Could not remove temporary folder: %s', ...
                ME.message);
        end
    end

end
