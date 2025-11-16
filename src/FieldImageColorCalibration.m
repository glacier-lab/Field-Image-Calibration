% =========================================================================
% COLOR CALIBRATION SCRIPT FOR DNG IMAGES
% =========================================================================
% DESCRIPTION:
%   This script performs color calibration on DNG format images using a
%   Color Checker reference. It reads raw DNG images and applies color
%   correction based on color checker measurements to produce accurate
%   color reproduction.
%
% USAGE:
%   Run the script in MATLAB command window or editor. Ensure all
%   dependencies are in the MATLAB path and input DNG images are in the
%   expected directory.
%
%
% Shunan Feng (shunan.feng@envs.au.dk)
%
% =========================================================================

%% Configuration
% Path to DNG image
% dngFilePath = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\S1-02_after2.CR2";
dngFilePath = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\AM-S2-05.dng";

fprintf('Reading DNG image...\n');

% Read the DNG file
rawImage = rawread(dngFilePath);
rawInfo = rawinfo(dngFilePath);
colorInfo = rawInfo.ColorInfo;

%% Image Corrections
blackLevel = colorInfo.BlackLevel;
blackLevel = reshape(blackLevel,[1 1 numel(blackLevel)]);
blackLevel = planar2raw(blackLevel);
repeatDims = rawInfo.ImageSizeInfo.VisibleImageSize ./ size(blackLevel);
blackLevel = repmat(blackLevel,repeatDims);
imgCorrected = rawImage - blackLevel;

imgCorrected = max(0,imgCorrected);

imgCorrected = double(imgCorrected);
maxValue = max(imgCorrected(:));
imgCorrected = imgCorrected ./ maxValue;

whiteBalance = colorInfo.CameraAsTakenWhiteBalance;
gLoc = strfind(rawInfo.CFALayout,"G"); 
gLoc = gLoc(1);
whiteBalance = whiteBalance/whiteBalance(gLoc);

whiteBalance = reshape(whiteBalance,[1 1 numel(whiteBalance)]);
whiteBalance = planar2raw(whiteBalance);
whiteBalance = repmat(whiteBalance,repeatDims);
imgCorrected = imgCorrected .* whiteBalance;


%%
img = demosaic(im2uint16(imgCorrected), rawInfo.CFALayout); % Adjust pattern if needed
figure; imshow(img);
title("Demosaiced RGB Image in Linear Camera Space")


%% Convert from Camera Color Space to RGB Color Space
cam2srgbMat = colorInfo.CameraTosRGB;
imTransform = imapplymatrix(cam2srgbMat,img,"uint16");
srgbTransform = lin2rgb(imTransform);
figure; imshow(srgbTransform)
title("sRGB Image Using Transformation Matrix before color checker calibration")

%% Color Checker Calibration (on white-balanced sRGB image)
fprintf('\nPerforming color checker calibration...\n');

% Convert to double for calibration
img_for_calibration = im2double(srgbTransform);

% Detect color checker
chart = colorChecker(img_for_calibration);
figure; displayChart(chart)

% measure color accuracy
[colorTable,ccm] = measureColor(chart);
figure; displayColorPatch(colorTable);

% apply color correction
img_color_corrected = imapplymatrix(ccm(1:3,:)',img_for_calibration,ccm(4,:));

figure; imshow(img_color_corrected);
title("sRGB Image after color checker calibration");

% evaluation
chart_corrected = colorChecker(img_color_corrected);
colorTable_corrected = measureColor(chart_corrected);
figure; displayColorPatch(colorTable_corrected);

%% use CIELAB lightness for perceptual brightness comparison 
labImg = rgb2lab(img_color_corrected);
% Calculate the mean lightness value for perceptual brightness comparison
lightnessImg = im2double(labImg(:,:,1))/100;

%% Draw polygon ROI on RGB image
fprintf('\nDraw a polygon ROI on the RGB image...\n');
fprintf('Double-click to finish the polygon.\n');

% Create figure for ROI selection
figROI = figure('Name', 'Draw Polygon ROI');
imshow(img_color_corrected);
title('Draw Polygon ROI - Double-click to finish');

% Draw polygon
roi = drawpolygon('Color', 'y', 'LineWidth', 2);
wait(roi); % Wait for user to finish drawing

% Get the mask from the polygon
mask = createMask(roi);

% Calculate mean lightness only within ROI
lightnessROI = lightnessImg .* mask;
lightnessROI(~mask) = NaN; % Set outside ROI to NaN
meanLightness = mean(lightnessROI(mask), 'omitnan');
stdLightness = std(lightnessROI(mask), 'omitnan');
fprintf('Mean Lightness within ROI: %.4f ± %.4f\n', meanLightness, stdLightness);

%% Save RGB figure with ROI and display lightness image
% Create output directory if it doesn't exist
[filepath, name, ~] = fileparts(dngFilePath);
outputDir = fullfile(filepath, 'calibrated_output');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

% Create figure with two subplots
figComparison = figure('Name', 'RGB with ROI and Lightness');
t = tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
ax1 = nexttile;
% Left subplot: RGB image with ROI
imshow(img_color_corrected);
hold on;
% Redraw the polygon on this subplot
plot([roi.Position(:,1); roi.Position(1,1)], [roi.Position(:,2); roi.Position(1,2)], ...
    'y-', 'LineWidth', 2);
hold off;
title('a) RGB Image with ROI');

% Right subplot: Lightness image
ax2 = nexttile;
% show NaNs as white by making NaN pixels transparent over a white axes background
% set(ax2, 'Color', [1 1 1]); 
imagesc(ax2, lightnessROI, 'AlphaData', ~isnan(lightnessROI));
colormap(ax2, func_dpcolor());
axis(ax2, 'off');
colorbar;
clim([0 1]);
cb = colorbar;
cb.Label.String = 'CIELAB Lightness (L*) / 100';
title(sprintf('b) Lightness within ROI (Mean: %.4f)', meanLightness));
fontsize(t, 16, 'points');
axis image;

% Save the comparison figure
exportgraphics(figComparison,  fullfile(outputDir, sprintf('%s_roi_lightness.png', name)), 'Resolution', 300);
exportgraphics(figComparison,  fullfile(outputDir, sprintf('%s_roi_lightness.pdf', name)), 'Resolution', 300);
fprintf('Figure saved to: %s\n', fullfile(outputDir, sprintf('%s_roi_lightness.png', name)));

% Save ROI mask and statistics
roiData.mask = mask;
roiData.roiPosition = roi.Position;
roiData.meanLightness = meanLightness;
roiData.lightnessValues = lightnessROI(mask);
roiData.minLightness = min(lightnessROI(mask));
roiData.maxLightness = max(lightnessROI(mask));
roiData.stdLightness = std(lightnessROI(mask));

roiDataFilename = fullfile(outputDir, sprintf('%s_roi_data.mat', name));
save(roiDataFilename, 'roiData');
fprintf('ROI data saved to: %s\n', roiDataFilename);

% Display statistics
fprintf('\n=== ROI Lightness Statistics ===\n');
fprintf('Mean:   %.4f\n', roiData.meanLightness);
fprintf('Std:    %.4f\n', roiData.stdLightness);
fprintf('Min:    %.4f\n', roiData.minLightness);
fprintf('Max:    %.4f\n', roiData.maxLightness);
fprintf('Pixels: %d\n', sum(mask(:)));
fprintf('================================\n');