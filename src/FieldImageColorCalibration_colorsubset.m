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
dngFilePath = "C:\Users\gdf435\Downloads\sites\sites\S1-02_after2.CR2";
% dngFilePath = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\S1-01_after.CR2";

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
% Try automatic detection first
try
    chart = colorChecker(img_for_calibration, "Downsample", false, "Sensitivity", 1);
    fprintf('Color checker automatically detected.\n');
catch
    fprintf('Automatic detection failed. Please manually select the four corner fiducials.\n');
    fprintf('Draw point ROIs on the plus-shaped (+) fiducials at each corner.\n');
    
    % Create figure for manual selection
    figManual = figure('Name', 'Manual Color Checker Registration');
    imshow(img_for_calibration);
    title('Select corners: 1) Black (top-left), 2) White (top-right), 3) Dark Skin (bottom-left), 4) Bluish Green (bottom-right)');
    
    % Draw point ROIs for each corner
    fprintf('1. Draw point on BLACK corner (top-left)...\n');
    blackPoint = drawpoint('Color', 'r', 'Label', 'Black');
    wait(blackPoint);
    
    fprintf('2. Draw point on WHITE corner (top-right)...\n');
    whitePoint = drawpoint('Color', 'r', 'Label', 'White');
    wait(whitePoint);
    
    fprintf('3. Draw point on DARK SKIN corner (bottom-left)...\n');
    darkSkinPoint = drawpoint('Color', 'r', 'Label', 'Dark Skin');
    wait(darkSkinPoint);
    
    fprintf('4. Draw point on BLUISH GREEN corner (bottom-right)...\n');
    bluishGreenPoint = drawpoint('Color', 'r', 'Label', 'Bluish Green');
    wait(bluishGreenPoint);
    
    % Collect corner points
    cornerPoints = [blackPoint.Position;
                    whitePoint.Position;
                    darkSkinPoint.Position;
                    bluishGreenPoint.Position];
    
    % Create color checker using registration points
    chart = colorChecker(img_for_calibration, "RegistrationPoints", cornerPoints);
    fprintf('Color checker registered using manual points.\n');
    
    close(figManual);
end
figure; displayChart(chart)

% measure color accuracy - use only grayscale patches (19-24)
[colorTable,~] = measureColor(chart);

% Filter to use only grayscale patches (indices 19-24)
fprintf('Using only grayscale patches (19-24) for calibration...\n');
grayPatchIndices = 13:24;
colorTable_gray = colorTable(grayPatchIndices, :);

% Extract measured RGB values
measuredRGB_gray = [colorTable_gray.Measured_R, ...
                    colorTable_gray.Measured_G, ...
                    colorTable_gray.Measured_B];

% Extract reference LAB values and convert to RGB
referenceLAB_gray = [colorTable_gray.Reference_L, ...
                     colorTable_gray.Reference_a, ...
                     colorTable_gray.Reference_b];
referenceRGB_gray = lab2rgb(referenceLAB_gray);

% Augment with ones for affine transformation (includes offset)
measuredRGB_gray_aug = [measuredRGB_gray, ones(size(measuredRGB_gray, 1), 1)];

% Solve for transformation matrix: referenceRGB = measuredRGB * ccm_gray
ccm = measuredRGB_gray_aug \ referenceRGB_gray;

% Display comparison
figure; displayColorPatch(colorTable_gray);
title('Grayscale Patches (19-24) - Measured vs Reference');

% apply color correction
img_color_corrected = imapplymatrix(ccm(1:3,:)',img_for_calibration,ccm(4,:));

figure; imshow(img_color_corrected);
title("sRGB Image after grayscale-only calibration");


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

% close(figROI);

%% Draw line for scale calibration
fprintf('\nDraw a line for scale calibration...\n');
fprintf('Draw a line of known distance on the image.\n');

% Create figure for scale calibration
figScale = figure('Name', 'Draw Scale Reference Line');
imshow(img_color_corrected);
title('Draw a line of known distance - Double-click to finish');

% Draw line
scaleLine = drawline('Color', 'c', 'LineWidth', 2, 'Label', 'Scale Reference');
wait(scaleLine); % Wait for user to finish drawing

% Calculate pixel length
linePos = scaleLine.Position;
pixelLength = sqrt((linePos(2,1) - linePos(1,1))^2 + (linePos(2,2) - linePos(1,2))^2);

% Ask user for real-world distance
prompt = {'Enter the real-world distance (in cm):'};
dlgtitle = 'Scale Calibration';
dims = [1 50];
definput = {'10'};
answer = inputdlg(prompt, dlgtitle, dims, definput);

if ~isempty(answer)
    realDistance_cm = str2double(answer{1});
    pixelsPerCm = pixelLength / realDistance_cm;
    
    fprintf('Scale calibration:\n');
    fprintf('  Line length: %.2f pixels\n', pixelLength);
    fprintf('  Real distance: %.2f cm\n', realDistance_cm);
    fprintf('  Scale: %.2f pixels/cm\n', pixelsPerCm);
    
    % Store scale information
    scaleInfo.linePosition = linePos;
    scaleInfo.pixelLength = pixelLength;
    scaleInfo.realDistance_cm = realDistance_cm;
    scaleInfo.pixelsPerCm = pixelsPerCm;
    scaleInfo.cmPerPixel = 1 / pixelsPerCm;
else
    fprintf('Scale calibration cancelled. No scale bar will be added.\n');
    scaleInfo = [];
    pixelsPerCm = NaN;
end

% close(figScale);

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

% Add scale bar if calibration was done
if ~isempty(scaleInfo)
    % Position scale bar in bottom-left corner
    imgSize = size(img_color_corrected);
    scaleBarLength_cm = 10; % 10 cm scale bar
    scaleBarLength_px = scaleBarLength_cm * pixelsPerCm;
    
    % Scale bar position (with margins)
    margin = 200; % pixels from edge
    scaleBarX = margin;
    scaleBarY = imgSize(1) - margin;
    
    % Draw scale bar
    plot([scaleBarX, scaleBarX + scaleBarLength_px], [scaleBarY, scaleBarY], ...
        'k-', 'LineWidth', 4);
    
    % Add text label to the right of the scale bar
    textOffset = 150; % pixels to the right of the bar
    textX = scaleBarX + scaleBarLength_px + textOffset;
    textY = scaleBarY;
    text(textX, textY, sprintf('%d cm', scaleBarLength_cm), ...
        'Color', 'white', 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
        'BackgroundColor', [0 0 0 0.5], 'EdgeColor', 'white');
end

hold off;
title('a) RGB Image with ROI');

% Right subplot: Lightness image
ax2 = nexttile;
imagesc(ax2, lightnessROI, 'AlphaData', ~isnan(lightnessROI));
colormap(ax2, func_dpcolor());
axis(ax2, 'off');
colorbar;
clim([0 1]);
cb = colorbar;
cb.Label.String = 'CIELAB Lightness (L*) / 100';
title(sprintf('b) Lightness within ROI (Mean: %.4f)', meanLightness));

% Add scale bar to lightness image if calibration was done
if ~isempty(scaleInfo)
    hold on;
    % Draw scale bar at same position
    plot([scaleBarX, scaleBarX + scaleBarLength_px], [scaleBarY, scaleBarY], ...
        'k-', 'LineWidth', 4);
    
    % Add text label to the right of the scale bar
    % reuse existing textOffset if present, otherwise set a default
    if ~exist('textOffset','var')
        textOffset = 150; % pixels to the right of the bar
    end
    textX = scaleBarX + scaleBarLength_px + textOffset;
    textY = scaleBarY;
    text(textX, textY, sprintf('%d cm', scaleBarLength_cm), ...
        'Color', 'white', 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
        'BackgroundColor', [0 0 0 0.5], 'EdgeColor', 'white');
    hold off;
end

fontsize(t, 16, 'points');
axis(ax2, 'image');

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
roiData.scaleInfo = scaleInfo; % Add scale information

roiDataFilename = fullfile(outputDir, sprintf('%s_roi_data.mat', name));
save(roiDataFilename, 'roiData');
fprintf('ROI data saved to: %s\n', roiDataFilename);

% Display statistics
fprintf('\n=== ROI Lightness Statistics ===\n');
fprintf('Mean:   %.4f\n', roiData.meanLightness);
fprintf('Std:    %.4f\n', roiData.stdLightness);
fprintf('Pixels: %d\n', sum(mask(:)));
if ~isempty(scaleInfo)
    fprintf('\n=== Scale Information ===\n');
    fprintf('Pixels per cm: %.2f\n', scaleInfo.pixelsPerCm);
    fprintf('cm per pixel:  %.4f\n', scaleInfo.cmPerPixel);
    fprintf('ROI area (cm²): %.2f\n', sum(mask(:)) * scaleInfo.cmPerPixel^2);
end
fprintf('================================\n');