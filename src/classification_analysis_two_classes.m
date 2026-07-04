%% Two-class classification analysis from MAT outputs
% Reads classified MAT files and merges classes into:
% 1) ice (all non-cryoconite classes, including Unclassified)
% 2) cryoconite (dispersed cryoconite)
%
% Saves:
% - Per-image 3-panel figure (RGB, Lightness, 2-class map)
% - Combined CSV with ROI and 2-class statistics

clear; clc;

%% User settings
inputFolder = "E:\iCalibrateImages\data\BGO_calibrated_output\classfied_images_SF_75conf";
outputFolder = "E:\iCalibrateImages\data\BGO_calibrated_output\classification_analysis_output_two_classes_75conf";
scaleBarLength_cm = 10;

if ~isfolder(inputFolder)
    error("Input folder not found: %s", inputFolder);
end
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

matFiles = dir(fullfile(inputFolder, "*.mat"));
if isempty(matFiles)
    error("No MAT files found in: %s", inputFolder);
end

rows = struct([]);

% Class definition for final merged map.
mergedClassNames = {'ice', 'cryoconite'};
mergedClassColors = [
    230, 222, 230;   % ice: #e6dee6
    230, 49, 49;     % cryoconite: #e63131
] / 255;

for i = 1:numel(matFiles)
    matName = matFiles(i).name;
    matPath = fullfile(matFiles(i).folder, matName);

    fprintf('[%d/%d] %s\n', i, numel(matFiles), matName);

    S = load(matPath);

    if ~isfield(S, 'img_color_corrected') || ~isfield(S, 'classification_image')
        warning('Skipping %s (missing img_color_corrected or classification_image)', matName);
        continue;
    end

    imgRGB = S.img_color_corrected;
    if ndims(imgRGB) ~= 3 || size(imgRGB, 3) ~= 3
        warning('Skipping %s (img_color_corrected is not HxWx3)', matName);
        continue;
    end
    if ~isfloat(imgRGB)
        imgRGB = im2double(imgRGB);
    end

    [h, w, ~] = size(imgRGB);

    roiMask = get_roi_mask_from_struct(S, h, w);
    if ~any(roiMask, 'all')
        warning('Skipping %s (ROI mask has no valid pixels)', matName);
        continue;
    end

    classImage = double(S.classification_image);
    if ndims(classImage) ~= 3 || size(classImage, 1) ~= h || size(classImage, 2) ~= w
        warning('Skipping %s (classification_image size mismatch)', matName);
        continue;
    end

    originalClassNames = get_original_class_names(S, size(classImage, 3));
    mergedMap = build_two_class_map(classImage, originalClassNames, roiMask);

    lightness = rgb2lab(imgRGB);
    lightness = lightness(:, :, 1) / 100;
    lightness = min(max(lightness, 0), 1);

    roiBoundary = bwboundaries(roiMask);
    [pixelArea_cm2, hasScaleInfo, pixelsPerCm] = get_pixel_area_cm2(S);

    % Statistics
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

    % Plot: RGB, Lightness, 2-class map
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
    title(ax3, 'c) Two-class map (outside ROI masked)');

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

    [~, baseName, ~] = fileparts(matName);
    pngPath = fullfile(outputFolder, sprintf('%s_two_class_analysis.png', baseName));
    pdfPath = fullfile(outputFolder, sprintf('%s_two_class_analysis.pdf', baseName));
    exportgraphics(fig, pngPath, 'Resolution', 300);
    exportgraphics(fig, pdfPath, 'Resolution', 300);
    close(fig);

    % CSV row
    row = struct();
    row.image_name = string(matName);
    row.lightness_roi_mean = overallMean;
    row.lightness_roi_std = overallStd;
    
    row.class_ice_pixels = classCounts(1);
    row.class_ice_cm2 = classAreas(1);
    row.class_ice_lightness_mean = classLMean(1);
    row.class_ice_lightness_std = classLStd(1);
    
    row.class_cryoconite_pixels = classCounts(2);
    row.class_cryoconite_cm2 = classAreas(2);
    row.class_cryoconite_lightness_mean = classLMean(2);
    row.class_cryoconite_lightness_std = classLStd(2);
    
    % Fractions of ROI (handle zero ROI pixels)
    total_roi_pixels = nnz(roiMask);
    if total_roi_pixels > 0
        row.cc_frac = classCounts(2) / total_roi_pixels;
        row.ice_frac = classCounts(1) / total_roi_pixels;
    else
        row.cc_frac = NaN;
        row.ice_frac = NaN;
    end

    if isempty(rows)
        rows = row;
    else
        rows(end + 1) = row; %#ok<SAGROW>
    end
end

if isempty(rows)
    warning('No valid files processed. CSV not written.');
else
    statsTable = struct2table(rows);
    csvPath = fullfile(outputFolder, 'classification_statistics_two_classes.csv');
    writetable(statsTable, csvPath);
    fprintf('\nSaved CSV:\n%s\n', csvPath);
    fprintf('Saved figures to:\n%s\n', outputFolder);
end


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

% Normalize naming variants.
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
pred(unclassifiedBand >= 0.5) = nUser + 1;  % mark unclassified as extra class index

cryoClassIdx = false(1, nBands);
for i = 1:min(nBands, numel(classNames))
    k = strtrim(classNames{i});
    if ~isempty(regexpi(k, '^cryoconite$', 'once'))
        cryoClassIdx(i) = true;
    end
end

mergedMap = ones(size(pred));  % default -> ice
for idx = find(cryoClassIdx)
    mergedMap(pred == idx) = 2; % cryoconite
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
