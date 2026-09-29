%% equate_mondrian_texform.m
%
% Pipeline to equate a set of Mondrian noise masks and a set of texforms
% on mean luminance, RMS contrast, and spatial frequency (Fourier
% amplitude spectrum), following the logic of the SHINE toolbox
% (Willenbockel et al., 2010, Behavior Research Methods).
%
% --- ONE-TIME SETUP ---
% 1. Download the SHINE toolbox from:
%       http://www.mapageweb.umontreal.ca/gosselif/SHINE/
%    (this is the toolbox referenced in Willenbockel et al., 2010)
% 2. Unzip it somewhere on your computer, e.g. C:\Toolboxes\SHINE
%    or ~/Toolboxes/SHINE
% 3. Point SHINE_PATH below at that folder.
%
% This script uses SHINE's sfMatch() for spatial-frequency matching,
% since that function and its behavior are documented in the original
% paper. For mean luminance and RMS contrast, this script uses a small
% custom function (normLumContrast, defined at the bottom of this file)
% rather than guessing at SHINE's lumMatch() argument syntax -- if you'd
% rather use SHINE's own lumMatch, check its help text after adding the
% toolbox to your path (`help lumMatch`) and swap it in; the normalization
% math is the same either way.

clear; clc; close all;

%% ---- USER SETTINGS: EDIT THESE ----

SHINE_PATH      = '/Users/ejm6930/Documents/MATLAB';   % <-- path to unzipped SHINE toolbox
STIMULI_FOLDER  = 'All_Stim_Unequated';           % <-- single folder with BOTH Mondrian
                                            %     and texform .png files together
OUTPUT_FOLDER   = 'Equated';       % <-- where matched images will be saved

% Filenames must contain one of these substrings so the script can tell
% the two conditions apart (e.g. 'mondrian_01.png', 'texform_03.png').
% Edit these if your naming convention differs.
MONDRIAN_TAG = 'mondrian';
TEXFORM_TAG  = 'texform';

TARGET_MEAN_LUM = 0.5;    % target mean luminance (0-1 scale)
TARGET_RMS      = 0.15;   % target RMS contrast (0-1 scale)
IMG_SIZE        = [500 500];  % common size to resize all images to [rows cols]

%% ---- SETUP ----

addpath(genpath(SHINE_PATH));
if exist(OUTPUT_FOLDER, 'dir') == 0
    mkdir(OUTPUT_FOLDER);
end

%% ---- STEP 1: Load and prepare both image sets ----
% Both conditions live in one folder (STIMULI_FOLDER). Each file's
% condition is determined by checking whether its filename contains
% MONDRIAN_TAG or TEXFORM_TAG. Files matching neither tag are skipped,
% with a warning, so a stray/misnamed file doesn't silently get dropped
% into the wrong condition.

% Reads both .png and .jpg, since CFS-crafter exports Mondrian masks as
% JPEG with no way to change that, while texforms are saved as PNG.
allFiles = [dir(fullfile(STIMULI_FOLDER, '*.png')); ...
            dir(fullfile(STIMULI_FOLDER, '*.jpg')); ...
            dir(fullfile(STIMULI_FOLDER, '*.jpeg'))];
fprintf('Found %d image files in %s\n', numel(allFiles), STIMULI_FOLDER);

images    = {};
labels    = {};
filenames = {};

for i = 1:numel(allFiles)
    thisName = allFiles(i).name;

    if contains(thisName, MONDRIAN_TAG, 'IgnoreCase', true)
        thisLabel = 'mondrian';
    elseif contains(thisName, TEXFORM_TAG, 'IgnoreCase', true)
        thisLabel = 'texform';
    else
        warning('Skipping "%s": filename does not contain "%s" or "%s".', ...
            thisName, MONDRIAN_TAG, TEXFORM_TAG);
        continue
    end

    im = imread(fullfile(STIMULI_FOLDER, thisName));
    im = prepImage(im, IMG_SIZE);

    % Force the output filename to .png regardless of the source
    % extension, so JPEG-sourced Mondrian masks are re-saved losslessly
    % from here on rather than accumulating further compression.
    [~, baseName, ~] = fileparts(thisName);
    outName = [baseName '.png'];

    images{end+1}    = im;          %#ok<SAGROW>
    labels{end+1}    = thisLabel;   %#ok<SAGROW>
    filenames{end+1} = outName;     %#ok<SAGROW>
end

nTotal    = numel(images);
nMondrian = sum(strcmp(labels, 'mondrian'));
nTexform  = sum(strcmp(labels, 'texform'));
fprintf('Loaded %d Mondrian images and %d texform images.\n', nMondrian, nTexform);

%% ---- STEP 2: Measure baseline stats (before matching) ----

fprintf('\n--- BEFORE matching ---\n');
reportStats(images, labels);

%% ---- STEP 3: Match spatial frequency (amplitude spectrum) ----
% sfMatch equates the rotational average of the Fourier amplitude
% spectrum across ALL images passed to it, using (by default) the
% average spectrum of the whole set as the common target. Passing both
% conditions together means neither condition is treated as the fixed
% reference -- both are pulled toward a shared average spectrum.

fprintf('\nRunning sfMatch on combined image set...\n');
images = sfMatch(images);   % check `help sfMatch` if you want to pass
                             % specific target spectrum arguments instead
                             % of the default group-average behavior

% sfMatch's output isn't guaranteed to be a 0-1 double array (SHINE
% functions commonly work in the conventional 0-255 image range) -- so
% normalize every image back to double, 0-1 range here, regardless of
% what class/scale it came back as, before doing any further math on it.
for i = 1:nTotal
    im = double(images{i});
    if max(im(:)) > 1.5   % heuristic: looks like a 0-255 range image
        im = im / 255;
    end
    images{i} = im;
end

%% ---- STEP 4: Match mean luminance and RMS contrast ----
% Applied after spatial frequency matching, since sfMatch's filtering
% can slightly perturb luminance/contrast -- so these are locked to
% their exact target values last.

fprintf('Matching mean luminance (target = %.2f) and RMS contrast (target = %.2f)...\n', ...
    TARGET_MEAN_LUM, TARGET_RMS);

for i = 1:nTotal
    images{i} = normLumContrast(images{i}, TARGET_MEAN_LUM, TARGET_RMS);
end

%% ---- STEP 5: Verify the final images ----

fprintf('\n--- AFTER matching ---\n');
reportStats(images, labels);

%% ---- STEP 6: Save equated images and a diagnostic spectrum plot ----

for i = 1:nTotal
    outPath = fullfile(OUTPUT_FOLDER, filenames{i});
    imwrite(images{i}, outPath);
end
fprintf('\nSaved %d equated images to %s\n', nTotal, OUTPUT_FOLDER);

plotSpectra(images, labels, OUTPUT_FOLDER);
fprintf('Saved diagnostic amplitude-spectrum plot to %s/spectrum_check.png\n', OUTPUT_FOLDER);


%% ======================= LOCAL FUNCTIONS =======================

function im = prepImage(im, targetSize)
    % Convert to greyscale double in [0,1] and resize to a common size.
    if size(im, 3) == 3
        im = rgb2gray(im);
    end
    im = im2double(im);
    im = imresize(im, targetSize);
end

function imOut = normLumContrast(im, targetMean, targetRMS)
    % Rescale an image so its mean equals targetMean and its RMS
    % contrast (standard deviation of pixel values, for a 0-1 image)
    % equals targetRMS. This implements the same normalization SHINE's
    % lumMatch is doing internally, written explicitly here so the exact
    % operation is transparent and verifiable rather than assumed from
    % an unconfirmed function signature.
    currentStd = std(im(:));
    if currentStd == 0
        % avoid divide-by-zero for a blank image
        imOut = ones(size(im)) * targetMean;
        return
    end
    imOut = (im - mean(im(:))) / currentStd * targetRMS + targetMean;
    imOut = min(max(imOut, 0), 1);  % clip to valid [0,1] range
end

function reportStats(images, labels)
    condNames = unique(labels);
    for c = 1:numel(condNames)
        idx = strcmp(labels, condNames{c});
        means = cellfun(@(im) mean(im(:)), images(idx));
        stds  = cellfun(@(im) std(im(:)),  images(idx));
        fprintf('%-10s  mean lum = %.4f (SD %.4f)   RMS contrast = %.4f (SD %.4f)   n = %d\n', ...
            condNames{c}, mean(means), std(means), mean(stds), std(stds), sum(idx));
    end
end

function plotSpectra(images, labels, outputFolder)
    % Compute and plot the radially-averaged amplitude spectrum for each
    % condition, so you (and your collaborators) can visually confirm
    % the two conditions' spectra now overlap.
    condNames = unique(labels);
    figure('Visible', 'off');
    hold on;
    colors = lines(numel(condNames));
    for c = 1:numel(condNames)
        idx = find(strcmp(labels, condNames{c}));
        allSpectra = [];
        for k = 1:numel(idx)
            im = images{idx(k)};
            F = fftshift(fft2(im));
            magSpec = abs(F);
            radAvg = radialAverage(magSpec);
            allSpectra = [allSpectra; radAvg]; %#ok<AGROW>
        end
        meanSpec = mean(allSpectra, 1);
        plot(meanSpec, 'Color', colors(c,:), 'LineWidth', 1.5, ...
            'DisplayName', condNames{c});
    end
    set(gca, 'XScale', 'log', 'YScale', 'log');
    xlabel('Spatial frequency (cycles/image, radial)');
    ylabel('Mean amplitude');
    title('Radially-averaged amplitude spectrum by condition');
    legend show;
    saveas(gcf, fullfile(outputFolder, 'spectrum_check.png'));
    close(gcf);
end

function radAvg = radialAverage(magSpec)
    % Radially average a 2D magnitude spectrum into a 1D profile.
    [rows, cols] = size(magSpec);
    cy = ceil(rows/2); cx = ceil(cols/2);
    [X, Y] = meshgrid(1:cols, 1:rows);
    R = round(sqrt((X-cx).^2 + (Y-cy).^2));
    maxR = min(cx, cy) - 1;
    radAvg = zeros(1, maxR);
    for r = 1:maxR
        mask = (R == r);
        radAvg(r) = mean(magSpec(mask));
    end
end
