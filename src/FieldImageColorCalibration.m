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
dngFilePath = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\raw\S1-02_after2.CR2";

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
meanLightness = mean(lightnessImg, 'all');
figure; 
imagesc(lightnessImg);
colormap('jet'); % Specify the color map here
colormap(func_dpcolor());
colorbar;
clim([0 1]);
cb = colorbar;
cb.Label.String = 'CIELAB Lightness (L*) / 100';
title(sprintf('Mean Lightness Value: %.2f', meanLightness));