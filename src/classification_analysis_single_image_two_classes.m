%% Two-class classification analysis for one selected MAT file
% Reads one classified MAT file and merges classes into:
% 1) ice (all non-cryoconite classes, including Unclassified)
% 2) cryoconite (dispersed cryoconite)
%
% Saves:
% - A single 3-panel figure (RGB, Lightness, 2-class map) to ../print

clear; clc;

%% User settings
inputFile = "E:\iCalibrateImages\data\BGO_calibrated_output\classfied_images_SF_75conf\S1-02_before_roi_data.mat";
scaleBarLength_cm = 10;

scriptDir = fileparts(mfilename('fullpath'));
outputFolder = fullfile(scriptDir, '..', 'print');

if ~isfile(inputFile)
    error("Input MAT file not found: %s", inputFile);
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

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1500 560]);
t = tiledlayout(fig, 1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

ax1 = nexttile(t, 1);
imshow(imgRGB, 'Parent', ax1);
hold(ax1, 'on');
draw_roi_boundaries(ax1, roiBoundary, 'y', 2);
hold(ax1, 'off');
title(ax1, 'a) RGB with ROI boundary');

ax2 = nexttile(t, 2);
imagesc(ax2, lightness);
axis(ax2, 'image');
axis(ax2, 'off');
if exist('func_dpcolor', 'file') == 2
    colormap(ax2, func_dpcolor());
else
    colormap(ax2, parula(256));
end
clim(ax2, [0 1]);
cb = colorbar(ax2);
cb.Location = 'southoutside';
cb.Label.String = 'CIELAB Lightness (L*) / 100';
hold(ax2, 'on');
draw_roi_boundaries(ax2, roiBoundary, 'w', 2);
hold(ax2, 'off');
title(ax2, sprintf('b) Lightness (ROI mean=%.4f, std=%.4f)', overallMean, overallStd));

ax3 = nexttile(t, 3);
mergedMapMasked = mergedMap;
mergedMapMasked(~roiMask) = NaN;
imagesc(ax3, mergedMapMasked, 'AlphaData', ~isnan(mergedMapMasked));
axis(ax3, 'image');
axis(ax3, 'off');
colormap(ax3, mergedClassColors);
clim(ax3, [1 nClasses]);
title(ax3, 'c) Classification');

if hasScaleInfo
    draw_scale_bar(ax3, h, pixelsPerCm, scaleBarLength_cm);
end

legendHandles = gobjects(1, nClasses);
for c = 1:nClasses
    legendHandles(c) = patch(ax3, nan, nan, mergedClassColors(c, :), ...
        'EdgeColor', 'k', 'DisplayName', mergedClassNames{c});
end
legend(ax3, legendHandles, mergedClassNames, ...
    'Location', 'southoutside', ...
    'NumColumns', nClasses, ...
    'Box', 'off');

[~, baseName, ~] = fileparts(inputFile);
pngPath = fullfile(outputFolder, sprintf('%s_two_class_analysis.png', baseName));
pdfPath = fullfile(outputFolder, sprintf('%s_two_class_analysis.pdf', baseName));
exportgraphics(fig, pngPath, 'Resolution', 300);
exportgraphics(fig, pdfPath, 'Resolution', 300);
close(fig);

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