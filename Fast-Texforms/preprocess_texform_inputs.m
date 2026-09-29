%% preprocess_texform_inputs.m
%
% Standardizes source photos to match the framing/proportions of a
% reference image (object isolated on a uniform background, occupying a
% moderate fraction of the frame, centered, with margin around it) --
% before they go into the texform-generation pipeline.
%
% WHY THIS MATTERS: the texform model's pooling windows grow with
% distance from the fixation point (image center). If an object fills
% almost the entire frame (a tight close-up), its most diagnostic
% features sit at very low eccentricity and get the smallest, least
% disruptive pooling windows -- so the synthesis barely alters them and
% the result stays recognizable. Matching your source images' framing
% to a reference that worked (object smaller relative to frame, with
% background space around it) gives the model room to disrupt the
% object's features as eccentricity increases outward from center.
%
% LIMITATION: this script detects the object by treating the image
% background as a roughly UNIFORM color and separating anything that
% differs from it. This works for clean product-photo-style or
% pre-segmented images (like a BOSS-style stimulus, or your hamster
% photo), but will fail on images with busy/textured/non-uniform
% backgrounds -- check each output visually before trusting it.

clear; clc; close all;

scriptFolder = fileparts(mfilename('fullpath'));

%% ---- USER SETTINGS: EDIT THESE ----

SOURCE_FOLDER = fullfile(scriptFolder, 'Raw images');        % your original, unprocessed photos
OUTPUT_FOLDER = fullfile(scriptFolder, 'source_images');      % standardized output (feed this
                                                                %   into batch_texform_generation.m
                                                                %   as its SOURCE_FOLDER)

CANVAS_SIZE           = [640 640];  % output canvas [rows cols] -- already a
                                     % multiple of 64, so it satisfies the
                                     % texform pipeline's pyramid constraint
TARGET_OBJECT_FRACTION = 0.55;      % object's longest side, as a fraction of
                                     % the canvas -- tune this to visually
                                     % match your reference image's proportions
FOREGROUND_THRESH      = 15;        % grey-level difference from background
                                     % needed to count a pixel as "object"
                                     % (0-255 scale) -- raise if too much
                                     % background gets included as object,
                                     % lower if parts of the object get missed
BACKGROUND_FILL        = 128;       % [] = auto-detect from each image's own
                                     % corners; or set a fixed value 0-255
                                     % (128 = mid-grey, roughly matching the
                                     % reference gemsbok image's background)

if exist(OUTPUT_FOLDER, 'dir') == 0
    mkdir(OUTPUT_FOLDER);
end

%% ---- Batch loop ----

sourceFiles = [dir(fullfile(SOURCE_FOLDER, '*.png')); ...
               dir(fullfile(SOURCE_FOLDER, '*.jpg')); ...
               dir(fullfile(SOURCE_FOLDER, '*.jpeg'))];

fprintf('Found %d raw photos in %s\n', numel(sourceFiles), SOURCE_FOLDER);

for k = 1:numel(sourceFiles)
    thisName = sourceFiles(k).name;
    [~, baseName, ~] = fileparts(thisName);
    fprintf('[%d/%d] Processing %s...\n', k, numel(sourceFiles), thisName);

    im = imread(fullfile(SOURCE_FOLDER, thisName));
    if size(im, 3) == 3
        im = rgb2gray(im);
    end
    im = double(im);

    try
        outIm = standardizeFraming(im, CANVAS_SIZE, TARGET_OBJECT_FRACTION, ...
            FOREGROUND_THRESH, BACKGROUND_FILL);
        outFile = fullfile(OUTPUT_FOLDER, [baseName '_prepped.png']);
        imwrite(uint8(outIm), outFile);
        fprintf('  Saved: %s\n', outFile);
    catch ME
        warning('  Failed on %s: %s\n  (likely a non-uniform background -- check this image manually)', ...
            thisName, ME.message);
    end
end

fprintf('\nDone. Check %s and visually inspect each result before running the texform batch.\n', ...
    OUTPUT_FOLDER);


%% ======================= LOCAL FUNCTIONS =======================

function outIm = standardizeFraming(im, canvasSize, targetFraction, threshVal, bgFillOverride)
    [rows, cols] = size(im);

    % --- Estimate background value from the four corners ---
    patch = 20;
    corners = [im(1:patch, 1:patch); im(1:patch, cols-patch+1:cols); ...
               im(rows-patch+1:rows, 1:patch); im(rows-patch+1:rows, cols-patch+1:cols)];
    bgValue = median(corners(:));

    % --- Build foreground mask: pixels that differ enough from background ---
    mask = abs(im - bgValue) > threshVal;
    mask = imfill(mask, 'holes');
    mask = bwareaopen(mask, 200);            % remove small speckle noise
    mask = imclose(mask, strel('disk', 5));   % close small gaps

    cc = bwconncomp(mask);
    if cc.NumObjects == 0
        error('No foreground object detected -- background may not be uniform enough, or FOREGROUND_THRESH needs adjusting.');
    end

    % Keep only the largest connected component (assumed to be the object)
    areas = cellfun(@numel, cc.PixelIdxList);
    [~, biggest] = max(areas);
    objMask = false(size(mask));
    objMask(cc.PixelIdxList{biggest}) = true;

    stats = regionprops(objMask, 'BoundingBox');
    bbox = round(stats.BoundingBox);  % [x y width height]

    % --- Determine background fill value (needed before substitution below) ---
    if isempty(bgFillOverride)
        fillValue = bgValue;
    else
        fillValue = bgFillOverride;
    end

    % --- Crop to the object's bounding box (from the greyscale image, not the mask) ---
    cropped = im(bbox(2):(bbox(2)+bbox(4)-1), bbox(1):(bbox(1)+bbox(3)-1));

    % Replace any background pixels still visible WITHIN this rectangular
    % crop (e.g. corners around an irregularly-shaped object) with the
    % same fill value used for the canvas, so there's no visible seam/box
    % between the object's silhouette and the surrounding grey.
    croppedMask = objMask(bbox(2):(bbox(2)+bbox(4)-1), bbox(1):(bbox(1)+bbox(3)-1));
    cropped(~croppedMask) = fillValue;

    % --- Resize so the object's longest side hits the target fraction of the canvas ---
    objLongSide = max(size(cropped));
    canvasLongSide = max(canvasSize);
    scaleFactor = (targetFraction * canvasLongSide) / objLongSide;
    resized = imresize(cropped, scaleFactor);

    if any(size(resized) > canvasSize)
        error('Resized object is larger than the canvas -- lower TARGET_OBJECT_FRACTION or increase CANVAS_SIZE.');
    end

    % --- Place the resized object centered on a uniform canvas ---
    outIm = ones(canvasSize) * fillValue;
    [rR, rC] = size(resized);
    rowStart = round((canvasSize(1) - rR) / 2) + 1;
    colStart = round((canvasSize(2) - rC) / 2) + 1;
    outIm(rowStart:(rowStart+rR-1), colStart:(colStart+rC-1)) = resized;
end
