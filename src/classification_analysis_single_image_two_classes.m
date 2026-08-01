%% Two-class classification analysis for one selected MAT file
% Reads one classified MAT file and merges classes into:
% 1) ice (all non-cryoconite classes, including Unclassified)
% 2) cryoconite (dispersed cryoconite)
%
% Saves:
% - A single 4-panel figure (raw image, calibrated RGB, Lightness, 2-class map) to ../print

clear; clc;

%% User settings
inputFile = "C:\Users\au686295\Downloads\S1-02_before_roi_data.mat";
inputImageFile = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\S1-02_before.CR2";
scaleBarLength_cm = 10;

scriptDir = fileparts(mfilename('fullpath'));
outputFolder = fullfile(scriptDir, '..', 'print');

if ~isfile(inputFile)
    error("Input MAT file not found: %s", inputFile);
end
if ~isfile(inputImageFile)
    error("Input raw image file not found: %s", inputImageFile);
end
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

mergedClassNames = {'ice', 'cryoconite'};
mergedClassColors = [
    230, 222, 230;   % ice: #e6dee6
    230, 49, 49;     % cryoconite: #e63131
] / 255;

fprintf('Processing %s\n', inputFile);
S = load(inputFile);

if ~isfield(S, 'img_color_corrected') || ~isfield(S, 'classification_image')
    error('MAT file must contain img_color_corrected and classification_image.');
end

imgRGB = S.img_color_corrected;
if ndims(imgRGB) ~= 3 || size(imgRGB, 3) ~= 3
    error('img_color_corrected must be HxWx3.');
end
if ~isfloat(imgRGB)
    imgRGB = im2double(imgRGB);
end

rawImage = get_raw_image_from_file(inputImageFile, imgRGB);

[h, w, ~] = size(imgRGB);

roiMask = get_roi_mask_from_struct(S, h, w);
if ~any(roiMask, 'all')
    error('ROI mask has no valid pixels.');
end

classImage = double(S.classification_image);
if ndims(classImage) ~= 3 || size(classImage, 1) ~= h || size(classImage, 2) ~= w
    error('classification_image size mismatch.');
end

originalClassNames = get_original_class_names(S, size(classImage, 3));
mergedMap = build_two_class_map(classImage, originalClassNames, roiMask);

lightness = rgb2lab(imgRGB);
lightness = lightness(:, :, 1) / 100;
lightness = min(max(lightness, 0), 1);

roiBoundary = bwboundaries(roiMask);
[pixelArea_cm2, hasScaleInfo, pixelsPerCm] = get_pixel_area_cm2(S);

lightROI = lightness(roiMask);
overallMean = mean(lightROI, 'omitnan');
overallStd = std(lightROI, 0, 'omitnan');

nClasses = numel(mergedClassNames);
classCounts = zeros(1, nClasses);
classAreas = nan(1, nClasses);
classLMean = nan(1, nClasses);
classLStd = nan(1, nClasses);

for c = 1:nClasses
    cmask = roiMask & (mergedMap == c);
    classCounts(c) = nnz(cmask);

    if ~isnan(pixelArea_cm2)
        classAreas(c) = classCounts(c) * pixelArea_cm2;
    end

    cVals = lightness(cmask);
    if ~isempty(cVals)
        classLMean(c) = mean(cVals, 'omitnan');
        classLStd(c) = std(cVals, 0, 'omitnan');
    end
end

fprintf('\nTwo-class statistics for %s\n', baseName_from_path(inputFile));
fprintf('ROI pixels: %d\n', nnz(roiMask));
fprintf('ROI mean L*: %.6f\n', overallMean);
fprintf('ROI std  L*: %.6f\n', overallStd);

for c = 1:nClasses
    if isnan(classAreas(c))
        areaText = 'NaN';
    else
        areaText = sprintf('%.6f', classAreas(c));
    end
    fprintf('%s: pixels=%d, area_cm2=%s, mean_L*=%.6f, std_L*=%.6f, frac=%.6f\n', ...
        mergedClassNames{c}, classCounts(c), areaText, classLMean(c), classLStd(c), classCounts(c) / nnz(roiMask));
end

fig = figure('Color', 'w', 'Position', [80 80 1500 1100]);
t = tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax1 = nexttile(t, 1);
imshow(rawImage, 'Parent', ax1);
axis(ax1, 'off');
title(ax1, 'a) Raw image (black-level and white-balance corrected)');

ax2 = nexttile(t, 2);
imshow(imgRGB, 'Parent', ax2);
hold(ax2, 'on');
draw_roi_boundaries(ax2, roiBoundary, 'y', 2);
hold(ax2, 'off');
title(ax2, 'b) Calibrated RGB with ROI boundary');

ax3 = nexttile(t, 3);
imagesc(ax3, lightness);
axis(ax3, 'image');
axis(ax3, 'off');
if exist('func_dpcolor', 'file') == 2
    colormap(ax3, func_dpcolor());
else
    colormap(ax3, parula(256));
end
clim(ax3, [0 1]);
cb = colorbar(ax3);
cb.Location = 'southoutside';
cb.Label.String = 'CIELAB Lightness (L*) / 100';
hold(ax3, 'on');
draw_roi_boundaries(ax3, roiBoundary, 'w', 2);
hold(ax3, 'off');
title(ax3, sprintf('c) Lightness (ROI mean=%.4f, std=%.4f)', overallMean, overallStd));

ax4 = nexttile(t, 4);
mergedMapMasked = mergedMap;
mergedMapMasked(~roiMask) = NaN;
imagesc(ax4, mergedMapMasked, 'AlphaData', ~isnan(mergedMapMasked));
axis(ax4, 'image');
axis(ax4, 'off');
colormap(ax4, mergedClassColors);
clim(ax4, [1 nClasses]);
title(ax4, 'd) Classification');

if hasScaleInfo
    draw_scale_bar(ax4, h, pixelsPerCm, scaleBarLength_cm);
end

legendHandles = gobjects(1, nClasses);
for c = 1:nClasses
    legendHandles(c) = patch(ax4, nan, nan, mergedClassColors(c, :), ...
        'EdgeColor', 'k', 'DisplayName', mergedClassNames{c});
end
legend(ax4, legendHandles, mergedClassNames, ...
    'Location', 'southoutside', ...
    'NumColumns', nClasses, ...
    'Box', 'off');

[~, baseName, ~] = fileparts(inputFile);
pngPath = fullfile(outputFolder, sprintf('%s_two_class_analysis.png', baseName));
pdfPath = fullfile(outputFolder, sprintf('%s_two_class_analysis.pdf', baseName));
fontsize(t, 20, "points");
exportgraphics(fig, pngPath, 'Resolution', 300);
exportgraphics(fig, pdfPath, 'Resolution', 300);
% close(fig);


fprintf('Saved figure to:\n%s\n%s\n', pngPath, pdfPath);


function roiMask = get_roi_mask_from_struct(S, h, w)
roiMask = true(h, w);

if isfield(S, 'roiData')
    roiData = S.roiData;

    if isstruct(roiData)
        if isfield(roiData, 'mask') && isequal(size(roiData.mask), [h w])
            roiMask = logical(roiData.mask);
            return;
        end

        if isfield(roiData, 'lightnessValues') && isequal(size(roiData.lightnessValues), [h w])
            roiMask = ~isnan(roiData.lightnessValues);
            return;
        end
    end
end
end


function rawImage = get_raw_image_from_file(inputImageFile, fallbackImage)
% Read input image directly from source file for panel a).
% If possible, apply black-level subtraction and white-balance correction
% before demosaic so the image is not too dark.
rawImage = [];

try
    % For camera raw files, apply correction pipeline, demosaic,
    % then convert from camera space to sRGB.
    if exist('rawread', 'file') == 2 && exist('rawinfo', 'file') == 2
        rawMosaic = rawread(inputImageFile);
        rawMeta = rawinfo(inputImageFile);
        if isnumeric(rawMosaic) && isfield(rawMeta, 'CFALayout') && isfield(rawMeta, 'ColorInfo')
            colorInfo = rawMeta.ColorInfo;

            blackLevel = colorInfo.BlackLevel;
            blackLevel = reshape(blackLevel, [1 1 numel(blackLevel)]);
            blackLevel = planar2raw(blackLevel);

            repeatDims = rawMeta.ImageSizeInfo.VisibleImageSize ./ size(blackLevel);
            blackLevel = repmat(blackLevel, repeatDims);

            imgCorrected = rawMosaic - blackLevel;
            imgCorrected = max(0, imgCorrected);

            imgCorrected = double(imgCorrected);
            maxValue = max(imgCorrected(:));
            if maxValue > 0
                imgCorrected = imgCorrected ./ maxValue;
            end

            whiteBalance = colorInfo.CameraAsTakenWhiteBalance;
            gLoc = strfind(rawMeta.CFALayout, "G");
            gLoc = gLoc(1);
            whiteBalance = whiteBalance / whiteBalance(gLoc);

            whiteBalance = reshape(whiteBalance, [1 1 numel(whiteBalance)]);
            whiteBalance = planar2raw(whiteBalance);
            whiteBalance = repmat(whiteBalance, repeatDims);
            imgCorrected = imgCorrected .* whiteBalance;

            imgLinear = demosaic(im2uint16(imgCorrected), rawMeta.CFALayout);

            if isfield(colorInfo, 'CameraTosRGB')
                cam2srgbMat = colorInfo.CameraTosRGB;
                imTransform = imapplymatrix(cam2srgbMat, imgLinear, "uint16");
                rawImage = lin2rgb(imTransform);
            else
                rawImage = imgLinear;
            end
        end
    end
catch
    rawImage = [];
end

if isempty(rawImage)
    try
        rawImage = imread(inputImageFile);
    catch
        warning('Could not read inputImageFile directly. Using img_color_corrected in panel a).');
        rawImage = fallbackImage;
    end
end

if ndims(rawImage) ~= 3 || size(rawImage, 3) ~= 3
    warning('Input image is not RGB. Using img_color_corrected in panel a).');
    rawImage = fallbackImage;
end
end


function baseName = baseName_from_path(inputPath)
[~, baseName, ~] = fileparts(inputPath);
end


function classNames = get_original_class_names(S, nBands)
if isfield(S, 'classification_band_names')
    classNamesRaw = S.classification_band_names;

    if isstring(classNamesRaw)
        classNames = cellstr(classNamesRaw(:));
    elseif iscell(classNamesRaw)
        classNames = cellfun(@(x) string(x), classNamesRaw, 'UniformOutput', false);
        classNames = cellfun(@char, classNames, 'UniformOutput', false);
    else
        classNames = cellstr(string(classNamesRaw(:)));
    end

    classNames = reshape(classNames, 1, []);

    if numel(classNames) ~= nBands
        classNames = make_default_class_names(nBands);
    end
else
    classNames = make_default_class_names(nBands);
end

for i = 1:numel(classNames)
    k = strtrim(classNames{i});
    if ~isempty(regexpi(k, '^disp_cco$', 'once')) || ~isempty(regexpi(k, '^dispersed cryoconites$', 'once'))
        classNames{i} = 'cryoconite';
    end
    if ~isempty(regexpi(k, '^dispersed cryoconite$', 'once'))
        classNames{i} = 'cryoconite';
    end
end
end


function classNames = make_default_class_names(nBands)
classNames = cell(1, nBands);
for k = 1:(nBands - 1)
    classNames{k} = sprintf('Class_%d', k);
end
classNames{nBands} = 'Unclassified';
end


function mergedMap = build_two_class_map(classImage, classNames, roiMask)
% mergedMap labels:
% 1 = ice
% 2 = cryoconite

nBands = size(classImage, 3);
nUser = nBands - 1;

prob = classImage(:, :, 1:nUser);
unclassifiedBand = classImage(:, :, end);

[~, pred] = max(prob, [], 3);
pred = double(pred);
pred(unclassifiedBand >= 0.5) = nUser + 1;

cryoClassIdx = false(1, nBands);
for i = 1:min(nBands, numel(classNames))
    k = strtrim(classNames{i});
    if ~isempty(regexpi(k, '^cryoconite$', 'once'))
        cryoClassIdx(i) = true;
    end
end

mergedMap = ones(size(pred));
for idx = find(cryoClassIdx)
    mergedMap(pred == idx) = 2;
end

mergedMap(~roiMask) = NaN;
end


function draw_roi_boundaries(ax, boundaries, colorSpec, lineWidth)
for b = 1:numel(boundaries)
    xy = boundaries{b};
    plot(ax, xy(:, 2), xy(:, 1), 'Color', colorSpec, 'LineWidth', lineWidth);
end
end


function [pixelArea_cm2, hasScaleInfo, pixelsPerCm] = get_pixel_area_cm2(S)
pixelArea_cm2 = NaN;
hasScaleInfo = false;
pixelsPerCm = NaN;

if ~isfield(S, 'roiData') || ~isstruct(S.roiData)
    return;
end

roiData = S.roiData;
if ~isfield(roiData, 'scaleInfo') || ~isstruct(roiData.scaleInfo)
    return;
end

scaleInfo = roiData.scaleInfo;
if isfield(scaleInfo, 'cmPerPixel') && ~isempty(scaleInfo.cmPerPixel) && isfinite(scaleInfo.cmPerPixel)
    pixelArea_cm2 = (double(scaleInfo.cmPerPixel))^2;
    hasScaleInfo = true;
    if isfield(scaleInfo, 'pixelsPerCm') && ~isempty(scaleInfo.pixelsPerCm)
        pixelsPerCm = double(scaleInfo.pixelsPerCm);
    else
        pixelsPerCm = 1 / double(scaleInfo.cmPerPixel);
    end
elseif isfield(scaleInfo, 'pixelsPerCm') && ~isempty(scaleInfo.pixelsPerCm) && isfinite(scaleInfo.pixelsPerCm)
    pixelsPerCm = double(scaleInfo.pixelsPerCm);
    pixelArea_cm2 = (1 / pixelsPerCm)^2;
    hasScaleInfo = true;
end
end


function draw_scale_bar(ax, imageHeight, pixelsPerCm, scaleBarLength_cm)
if ~isfinite(pixelsPerCm) || pixelsPerCm <= 0
    return;
end

scaleBarLength_px = scaleBarLength_cm * pixelsPerCm;
margin = 200;
scaleBarX = margin;
scaleBarY = imageHeight - margin;

hold(ax, 'on');
plot(ax, [scaleBarX, scaleBarX + scaleBarLength_px], [scaleBarY, scaleBarY], ...
    'k-', 'LineWidth', 4);
text(ax, scaleBarX + scaleBarLength_px + 150, scaleBarY, sprintf('%d cm', scaleBarLength_cm), ...
    'Color', 'w', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', [0.1 0.1 0.1], 'EdgeColor', 'w');
hold(ax, 'off');
end

%Two-class statistics for S1-02_before_roi_data
% ROI pixels: 1290480
% ROI mean L*: 0.652563
% ROI std  L*: 0.090681
% ice: pixels=1272260, area_cm2=767.798180, mean_L*=0.655477, std_L*=0.086523, frac=0.985881
% cryoconite: pixels=18220, area_cm2=10.995616, mean_L*=0.449074, std_L*=0.132925, frac=0.014119