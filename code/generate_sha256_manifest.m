
function generate_sha256_manifest()
% PANDA v2.10 - SHA-256 provenance generator
% Windows implementation using certutil.
%
% Outputs:
%   SOURCE_ARCHIVE_SHA256.txt
%   ARCHIVE_MEMBERS_SHA256.txt
%   SHA256SUMS.txt
%
% Original source data are read-only.

clc;

%% 1. Resolve package root

codeDir = fileparts(mfilename('fullpath'));
root = fileparts(codeDir);

assert(isfolder(fullfile(root,'code')));
assert(isfolder(fullfile(root,'results')));

fprintf('\n=== PANDA SHA-256 GENERATOR ===\n');
fprintf('Package: %s\n',root);

%% 2. Select original numerical ZIP

[file,folder] = uigetfile('*.zip', ...
    'Select original PANDA_CONFIGURATION_AUDIT ZIP');

assert(~isequal(file,0), ...
    'No source ZIP selected.');

zipPath = fullfile(folder,file);

%% 3. Hash original ZIP

fprintf('\nHashing original ZIP...\n');

zipHash = sha256certutil(zipPath);

writeManifest(fullfile(root, ...
    'SOURCE_ARCHIVE_SHA256.txt'), ...
    {sprintf('%s  %s',zipHash,file)});

fprintf('ZIP SHA-256: %s\n',zipHash);

%% 4. Extract and hash all 19 archive members

tempDir = tempname;
mkdir(tempDir);

cleanupObj = onCleanup(@() ...
    cleanupTemporary(tempDir));

fprintf('\nExtracting archive...\n');

unzip(zipPath,tempDir);

items = dir(fullfile(tempDir,'**','*'));
items = items(~[items.isdir]);

assert(numel(items)==19, ...
    'Expected 19 archived files.');

relativeNames = cell(19,1);
absoluteNames = cell(19,1);

for k=1:19

    absoluteNames{k} = fullfile( ...
        items(k).folder,items(k).name);

    relativeNames{k} = ...
        absoluteNames{k}(numel(tempDir)+2:end);

    relativeNames{k} = strrep( ...
        relativeNames{k},filesep,'/');
end

[relativeNames,order] = sort(relativeNames);
absoluteNames = absoluteNames(order);

memberLines = cell(19,1);

fprintf('\n=== ARCHIVE MEMBER HASHES ===\n');

for k=1:19

    h = sha256certutil(absoluteNames{k});

    memberLines{k} = sprintf('%s  %s', ...
        h,relativeNames{k});

    fprintf('%2d/19  %s\n',k,relativeNames{k});
end

writeManifest(fullfile(root, ...
    'ARCHIVE_MEMBERS_SHA256.txt'),memberLines);

%% 5. Collect code and results

relativeFiles = cell(0,1);

subfolders = {'code','results'};

for f=1:numel(subfolders)

    items = dir(fullfile(root, ...
        subfolders{f},'**','*'));

    items = items(~[items.isdir]);

    for k=1:numel(items)

        p = fullfile(items(k).folder,items(k).name);

        rel = p(numel(root)+2:end);
        rel = strrep(rel,filesep,'/');

        relativeFiles{end+1,1} = rel; %#ok<AGROW>
    end
end

%% 6. Include documentation if present

docs = { ...
    'README.md'
    'DATA_DICTIONARY.md'
    'CITATION.cff'
};

for k=1:numel(docs)

    if isfile(fullfile(root,docs{k}))
        relativeFiles{end+1,1} = docs{k}; %#ok<AGROW>
    else
        fprintf('NOT YET PRESENT: %s\n',docs{k});
    end
end

relativeFiles = sort(unique(relativeFiles));

assert(~isempty(relativeFiles), ...
    'No package files found.');

%% 7. Hash package files

packageLines = cell(numel(relativeFiles),1);

fprintf('\n=== PACKAGE HASHES ===\n');

for k=1:numel(relativeFiles)

    rel = relativeFiles{k};

    absolutePath = fullfile(root, ...
        strrep(rel,'/',filesep));

    h = sha256certutil(absolutePath);

    packageLines{k} = sprintf('%s  %s',h,rel);

    fprintf('%3d/%3d  %s\n', ...
        k,numel(relativeFiles),rel);
end

writeManifest(fullfile(root, ...
    'SHA256SUMS.txt'),packageLines);

%% 8. Final summary

fprintf('\n====================================\n');
fprintf('PROVENANCE MANIFEST\n');
fprintf('====================================\n');

fprintf('Original ZIP SHA-256: %s\n',zipHash);
fprintf('Archive members hashed: %d\n', ...
    numel(memberLines));
fprintf('Package files hashed: %d\n', ...
    numel(packageLines));

fprintf('\nPASS: SHA-256 MANIFEST GENERATED\n');

clear cleanupObj;

end

%% LOCAL FUNCTIONS

function hash = sha256certutil(filePath)

    assert(isfile(filePath), ...
        'File not found: %s',filePath);

    assert(~contains(filePath,'"'), ...
        'Unsupported quotation mark in path.');

    command = sprintf( ...
        'certutil -hashfile "%s" SHA256',filePath);

    [status,output] = system(command);

    assert(status==0, ...
        'certutil failed: %s',output);

    % Find a full line containing exactly 64 hex digits.
    token = regexp(output, ...
        '(?m)^\s*([0-9a-fA-F]{64})\s*$', ...
        'tokens','once');

    assert(~isempty(token), ...
        'Could not read SHA-256 digest: %s',output);

    hash = lower(token{1});
end

function writeManifest(filePath,lines)

    fid = fopen(filePath,'wt');

    assert(fid>0, ...
        'Cannot create manifest: %s',filePath);

    cleanupObj = onCleanup(@()fclose(fid));

    for k=1:numel(lines)
        fprintf(fid,'%s\n',lines{k});
    end
end

function cleanupTemporary(folderPath)

    if isfolder(folderPath)
        try
            rmdir(folderPath,'s');
        catch ME
            warning('Temporary cleanup failed: %s', ...
                ME.message);
        end
    end
end
