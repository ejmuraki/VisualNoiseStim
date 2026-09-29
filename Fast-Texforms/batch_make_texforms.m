%% batch_make_texforms.m
%
% For each image in source_images:
%   1) run make_texform on it
%   2) move the iter_*.png files it produced into iter_files/image name
%   3) copy the final iteration (iter_50.png) into texforms output and
%   rename
%
% make_texform.m must be in the same folder as this script

clear; clc; close all;

scriptFolder = fileparts(mfilename('fullpath')); 

%% --- USER SETTING ---

SOURCE_FOLDER = fullfile(scriptFolder, 'source_images');
OUTPUT_FOLDER = fullfile(scriptFolder, 'texforms_output');
ITER_FOLDER = fullfile(scriptFolder, 'iter_files');

ITER_SEARCH_DIR = scriptFolder;

FINAL_ITER = 50;

%% ---- SETUP ----

addpath(scriptFolder);

if ~exist(OUTPUT_FOLDER, 'dir'), mkdir(OUTPUT_FOLDER); end
if ~exist(ITER_FOLDER, 'dir'), mkdir(ITER_FOLDER); end

files = dir(fullfile(SOURCE_FOLDER, '*.png'));
fprintf('Founde %d images in %s\n', numel(files), SOURCE_FOLDER');

%% ---- LOOP ----

for k = 1:numel(files)
    imageName = files(k).name;
    [~, name] = fileparts(imageName);
    cleanName = regexprep(name, '^[\d.]+_', '');
    fprintf('\n[%d/%d] %s\n', k, numel(files), imageName);

    thisIterDir = fullfile(ITER_FOLDER, cleanName);
    if ~exist(thisIterDir, 'dir'), mkdir(thisIterDir); end
    
    % Only files written after this moment count as iterations
    tStart = now - 2/86400;

    try
        % The returned result is also saved, as a cross-check against
        % iter_50
        make_texform(fullfile(SOURCE_FOLDER, imageName), ...
                    fullfile(thisIterDir, 'returned_result.png'));

    catch ME
        fprintf(2, ' FAILED: %s\n', ME.message);
        close all;
        continue
    end
    
    close all; % make_texform opens a plotWindows figure each time

    % Move this image's iteration files into its own folder
    d = dir(fullfile(ITER_SEARCH_DIR, '*iter_*.png'));
    d = d([d.datenum] >= tStart);
    for j = 1:numel(d)
        movefile(fullfile(d(j).folder, d(j).name), thisIterDir);
    end
    fprintf(' moved %d iteration files to %s\n', numel(d), thisIterDir);

    % Copy final iteration to the output folder
    f = dir(fullfile(thisIterDir, sprintf('*_iter_%d.png', FINAL_ITER)));
    if ~isempty(f)
        copyfile(fullfile(f(1).folder, f(1).name), fullfile(OUTPUT_FOLDER, [cleanName '_texform.png']));
        fprintf(' saved %s_texform.png\n', cleanName);
    else
        warning('*iter_%d.png not found for %s. Check ITER_SEARCH_DIR.', FINAL_ITER, cleanName);
    end
end

fprintf('\nDone.\n');
