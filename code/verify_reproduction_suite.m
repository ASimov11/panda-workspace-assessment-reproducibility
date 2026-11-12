
function verify_reproduction_suite()
% PANDA v2.10: regression checks for saved postprocessing outputs.
% Does not rerun IK, dynamics, screening or other analyses.
%
% Expected root:
% PANDA_REPRODUCIBILITY_PACKAGE/
%   results/*.csv

clc;

root = uigetdir(pwd,'Select PANDA_REPRODUCIBILITY_PACKAGE');
if isequal(root,0)
    error('No package selected.');
end
r = fullfile(root,'results');
assert(isfolder(r),'Results folder missing.');

sf = fullfile(r,'screening_summary_30pct.csv');
if ~isfile(sf)
    [f,p] = uigetfile('*.csv', ...
        'Select screening_summary_30pct.csv');
    if isequal(f,0), error('Screening summary required.'); end
    sf = fullfile(p,f);
end

S = readtable(sf);
P = readtable(fullfile(r,'paired_loading_sphere_30pct.csv'));
M = readtable(fullfile(r,'pose_matched_summary_30pct.csv'));
J = readtable(fullfile(r,'joint_threshold_sweep.csv'));
O = readtable(fullfile(r,'oat_threshold_sensitivity.csv'));
A = readtable(fullfile(r,'leave_one_criterion_out.csv'));

names = strings(0,1);
passed = false(0,1);

% Population and 30% screening
addTest('Six surfaces',height(S)==6);
addTest('Configuration population', ...
    sum(S.Configurations)==762275);
addTest('Reachable target population', ...
    sum(S.ReachableTargets)==107356);

expR0 = [768;831;1;0;213;11688];
expR1 = [5274;6636;718;62;2979;38568];
expCommon = [768;831;1;0;213;11623];

addTest('R0 target counts',isequal(S.R0_Targets,expR0));
addTest('R1 target counts',isequal(S.R1_Targets,expR1));
addTest('Common target counts', ...
    isequal(S.Common_Targets,expCommon));

addTest('R1 configuration total', ...
    sum(S.R1_Configurations)==322486);
addTest('R1 selected-target total', ...
    sum(S.R1_Targets)==54237);
addTest('Sphere R1 selected configurations', ...
    S.R1_Configurations(end)==302155);

addTest('Sphere R1 full-area percentage', ...
    abs(S.R1_FullArea_pct(end)-97.521)<0.00051);
addTest('Sphere R1 reachable-area percentage', ...
    abs(S.R1_ReachableArea_pct(end)-97.760)<0.00051);
addTest('Sphere common full-area percentage', ...
    abs(S.Common_FullArea_pct(end)-34.825)<0.00051);

% Paired loading
addTest('Paired loading configurations', ...
    P.SelectedConfigurations(1)==302155);
addTest('Paired loading targets', ...
    P.SelectedTargets(1)==38568);
addTest('Paired inertia percent', ...
    abs(P.InertiaChange_pct(1)-14.213)<0.00051);
addTest('Paired mobility percent', ...
    abs(P.MobilityChange_pct(1)+29.837)<0.00051);

% Target-roll matching
addTest('Eligible targets',M.EligibleTargets(1)==1317);
addTest('Mixed target-roll groups', ...
    M.MixedTargetRollGroups(1)==1326);
addTest('Pose inertia contrast', ...
    abs(M.PoseMatchedInertia_kg(1)+4.120129)<5e-6);
addTest('Target-only inertia contrast', ...
    abs(M.TargetOnlyInertia_kg(1)-0.535486)<5e-6);
addTest('Pose mobility contrast', ...
    abs(M.PoseMatchedMobility_invkg(1)-0.0529554)<5e-7);
addTest('Target-only mobility contrast', ...
    abs(M.TargetOnlyMobility_invkg(1)+0.00296119)<5e-7);

% Sensitivity output shapes
addTest('Joint sweep row count',height(J)==42);
addTest('OAT row count',height(O)==336);
addTest('Ablation row count',height(A)==48);
addTest('Nonnegative ablation gains', ...
    all(A.Gain_percentage_points>=-1e-9));

% Spherical R1 OAT values: rows ICN/W/A/D, columns 20/30/40/50
criterion = ["ICN","W","A","D"];
levels = [20,30,40,50];
expected = [
  99.119 97.760 64.950 11.595
  98.379 97.760 97.368 93.822
  98.041 97.760 94.794 35.488
  98.077 97.760 93.582 60.381
];

for c=1:4
    for t=1:4
        row = string(O.Surface)=="CURVED200_MINUS_N" & ...
            string(O.Model)=="R1" & ...
            string(O.VariedCriterion)==criterion(c) & ...
            abs(O.Threshold_pct-levels(t))<1e-9;
        ok = nnz(row)==1;
        if ok
            ok = abs(O.ReachableArea_pct(row)- ...
                expected(c,t))<0.00051;
        end
        addTest(sprintf('OAT R1 %s %d%%', ...
            char(criterion(c)),levels(t)),ok);
    end
end

% Empty common screening at 40/50 on sphere
for threshold=[40 50]
    row = string(J.Surface)=="CURVED200_MINUS_N" & ...
        abs(J.Threshold_pct-threshold)<1e-9;
    ok = nnz(row)==1;
    if ok
        ok = J.Common_Configurations(row)==0 && ...
             J.Common_Targets(row)==0;
    end
    addTest(sprintf('Common sphere %d%%',threshold),ok);
end

% OAT at 30% must recover four-criterion baseline
oatOK = true;
for k=1:height(S)
    for model=["R0","R1"]
        row = string(O.Surface)==string(S.Surface(k)) & ...
            string(O.Model)==model & ...
            abs(O.Threshold_pct-30)<1e-9;
        oatOK = oatOK && nnz(row)==4;
        if nnz(row)==4
            if model=="R0"
                reference=S.R0_ReachableArea_pct(k);
            else
                reference=S.R1_ReachableArea_pct(k);
            end
            oatOK = oatOK && ...
                all(abs(O.ReachableArea_pct(row)-reference)<1e-9);
        end
    end
end
addTest('OAT 30% baseline identity',oatOK);

% Monotonic joint sweep
monoOK = true;
for k=1:height(S)
    row = string(J.Surface)==string(S.Surface(k));
    X = sortrows(J(row,:),'Threshold_pct');
    if height(X)~=7
        monoOK=false;
        continue;
    end
    y = [X.R0_ReachableArea_pct, ...
         X.R1_ReachableArea_pct, ...
         X.Common_ReachableArea_pct];
    monoOK = monoOK && all(diff(y,1,1)<=1e-9,'all');
end
addTest('Joint sweep monotonicity',monoOK);

% Export results
report = table(names,passed, ...
    'VariableNames',{'Test','Pass'});
outFile = fullfile(r,'verification_report.csv');
writetable(report,outFile);

fprintf('\n=== FINAL REGRESSION RESULT ===\n');
fprintf('Tests: %d | PASS: %d | FAIL: %d\n', ...
    numel(passed),nnz(passed),nnz(~passed));
fprintf('Report: %s\n',outFile);

if all(passed)
    fprintf('PASS: ALL REGRESSION CHECKPOINTS\n');
else
    disp(report(~report.Pass,:));
    error('FAIL: REGRESSION SUITE');
end

    function addTest(name,condition)
        names(end+1,1)=string(name);
        passed(end+1,1)= ...
            isscalar(condition) && logical(condition);
        if passed(end)
            status='PASS';
        else
            status='FAIL';
        end
        fprintf('%-42s %s\n',char(string(name)),status);
    end
end
