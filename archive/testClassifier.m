%% Test trained pixel classifier on calibrated MAT image
close all;
clc;

imFolder = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\calibrated_output";

% 1) Load trained model
[modelFileName, modelFilePath] = uigetfile(fullfile(imFolder, '*.mat'), 'Select trained model MAT file');
if isequal(modelFileName, 0)
	error('No model file selected.');
end

modelData = load(fullfile(modelFilePath, modelFileName));
if ~isfield(modelData, 'pixelModel')
	error('Selected MAT file does not contain ''pixelModel''.');
end
pixelModel = modelData.pixelModel;

if isfield(modelData, 'settings') && isfield(modelData.settings, 'unclassifiedThreshold')
	confThreshold = modelData.settings.unclassifiedThreshold;
else
	confThreshold = 0.60;
end

if isfield(modelData, 'trainingData') && isfield(modelData.trainingData, 'classNames')
	knownClassNames = string(modelData.trainingData.classNames);
else
	knownClassNames = string(categories(predict(pixelModel, [0 0 0])));
end

% 2) Load one calibrated image MAT file
[imageFileName, imageFilePath] = uigetfile(fullfile(imFolder, '*_roi_data.mat'), 'Select calibrated ROI MAT file');
if isequal(imageFileName, 0)
	error('No calibrated image MAT selected.');
end

imageData = load(fullfile(imageFilePath, imageFileName));
if ~isfield(imageData, 'img_color_corrected')
	error('Selected image MAT file does not contain ''img_color_corrected''.');
end

imgRGB = im2double(imageData.img_color_corrected);
[h, w, ~] = size(imgRGB);

% 3) Build RGB feature matrix and predict class for each pixel
X = [reshape(imgRGB(:,:,1), [], 1), reshape(imgRGB(:,:,2), [], 1), reshape(imgRGB(:,:,3), [], 1)];
[predLabelsRaw, score] = predict(pixelModel, X);

% Convert model scores to confidence and assign low-confidence pixels to
% an additional n+1 class named "Unclassified".
if isnumeric(score) && ~isempty(score)
	score = double(score);
	scoreShift = score - max(score, [], 2);
	scoreExp = exp(scoreShift);
	scoreProb = scoreExp ./ sum(scoreExp, 2);
	maxConfidence = max(scoreProb, [], 2);
else
	maxConfidence = ones(size(X,1), 1);
end

predStr = string(predLabelsRaw);
unclassifiedName = "Unclassified";
predStr(maxConfidence < confThreshold) = unclassifiedName;

allClassNames = [knownClassNames(:); unclassifiedName];
allClassNames = unique(allClassNames, 'stable');
predLabels = categorical(predStr, allClassNames);
predMap = reshape(predLabels, h, w);

% 4) Use ROI support if available in MAT file
if isfield(imageData, 'roiData') && isfield(imageData.roiData, 'lightnessValues')
	roiMask = ~isnan(imageData.roiData.lightnessValues);
else
	roiMask = true(h, w);
end

classNames = categories(predMap);
numClasses = numel(classNames);
classColors = lines(numClasses);
unclassifiedIdx = find(classNames == unclassifiedName, 1);
if ~isempty(unclassifiedIdx)
	classColors(unclassifiedIdx, :) = [0.6 0.6 0.6];
end

labelIdx = grp2idx(predMap);
labelPlot = double(labelIdx);
labelPlot(~roiMask) = NaN;

% 5) Display results
figure('Name', 'Classifier Test Results');
t = tiledlayout(1,2,'Padding','compact','TileSpacing','compact');

nexttile;
imshow(imgRGB);
title(sprintf('Input RGB (%s)', imageFileName), 'Interpreter', 'none');

nexttile;
imagesc(labelPlot);
axis image off;
colormap([0 0 0; classColors]);
cb = colorbar;
cb.Ticks = 1:numClasses;
cb.TickLabels = classNames;
title('Predicted Class Map');

fontsize(t, 14, 'points');

% 6) Print class fractions within ROI
fprintf('\n=== Predicted Class Fractions (within ROI) ===\n');
totalRoiPixels = sum(roiMask(:));
for k = 1:numClasses
	nPixels = sum(predMap(roiMask) == classNames{k});
	pct = 100 * nPixels / totalRoiPixels;
	fprintf('%s: %d pixels (%.2f%%)\n', classNames{k}, nPixels, pct);
end
fprintf('Unclassified threshold: %.2f\n', confThreshold);
fprintf('============================================\n');

