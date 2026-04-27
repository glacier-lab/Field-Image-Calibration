%% Interactive pixel classifier training from calibrated MAT files
% This script loads calibrated MAT files one-by-one, lets the user click
% training pixels for each class, and trains a multi-class classifier.

close all;
clc;

%% User settings
imFolder = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\calibrated_output";
modelOutputFile = fullfile(imFolder, "pixelClassifierModel.mat");

% Prefer ROI output MAT files if available
matFiles = dir(fullfile(imFolder, "*_roi_data.mat"));
if isempty(matFiles)
    matFiles = dir(fullfile(imFolder, "*.mat"));
end

if isempty(matFiles)
    error("No MAT files found in folder: %s", imFolder);
end

%% Ask class setup
nClassAnswer = inputdlg({"How many classes?"}, "Classifier Setup", [1 40], {"2"});
if isempty(nClassAnswer)
    error("Cancelled by user.");
end

numClasses = str2double(nClassAnswer{1});
if isnan(numClasses) || numClasses < 2 || mod(numClasses,1) ~= 0
    error("Number of classes must be an integer >= 2.");
end

defaultClassNames = strjoin(compose("Class%d", 1:numClasses), ",");
classAnswer = inputdlg({"Class names (comma separated):"}, "Classifier Setup", [1 70], {char(defaultClassNames)});
if isempty(classAnswer)
    error("Cancelled by user.");
end

classNames = strtrim(string(split(classAnswer{1}, ",")));
classNames(classNames == "") = [];
if numel(classNames) ~= numClasses
    error("Expected %d class names, got %d.", numClasses, numel(classNames));
end

% Classifier setup
classifierOptions = {'SVM', 'RandomForest'};
[classifierIdx, classifierOk] = listdlg('PromptString', 'Choose classifier type:', ...
    'SelectionMode', 'single', 'ListString', classifierOptions, 'InitialValue', 1, 'ListSize', [180 80]);
if ~classifierOk
    error("Cancelled by user.");
end
classifierType = string(classifierOptions{classifierIdx});

modelAnswer = inputdlg({"Random seed (integer):", "Unclassified confidence threshold [0-1]:", "RandomForest: number of trees"}, ...
    "Model Setup", [1 50], {"42", "0.60", "200"});
if isempty(modelAnswer)
    error("Cancelled by user.");
end

seedValue = str2double(modelAnswer{1});
if isnan(seedValue) || mod(seedValue,1) ~= 0
    error("Seed must be an integer.");
end

unclassifiedThreshold = str2double(modelAnswer{2});
if isnan(unclassifiedThreshold) || unclassifiedThreshold < 0 || unclassifiedThreshold > 1
    error("Unclassified confidence threshold must be in [0, 1].");
end

numTrees = str2double(modelAnswer{3});
if isnan(numTrees) || numTrees < 1 || mod(numTrees,1) ~= 0
    error("Number of trees must be an integer >= 1.");
end

%% Collect clicked samples
X = zeros(0,3); % RGB features
Y = categorical();

metaFile = strings(0,1);
metaClass = strings(0,1);
metaX = zeros(0,1);
metaY = zeros(0,1);

classColors = lines(numClasses);

for i = 1:numel(matFiles)
    dataPath = fullfile(imFolder, matFiles(i).name);
    data = load(dataPath);

    if ~isfield(data, "img_color_corrected")
        fprintf("Skipping %s (missing img_color_corrected).\n", matFiles(i).name);
        continue;
    end

    imgRGB = im2double(data.img_color_corrected);
    if ndims(imgRGB) ~= 3 || size(imgRGB,3) ~= 3
        fprintf("Skipping %s (img_color_corrected is not an RGB image).\n", matFiles(i).name);
        continue;
    end

    [h, w, ~] = size(imgRGB);
    redCh = imgRGB(:,:,1);
    greenCh = imgRGB(:,:,2);
    blueCh = imgRGB(:,:,3);

    fig = figure("Name", sprintf("Training file %d/%d: %s", i, numel(matFiles), matFiles(i).name));
    imshow(imgRGB);
    hold on;

    for c = 1:numClasses
        className = classNames(c);
        title(sprintf("%s\nClass %s: click training pixels, then press Enter", matFiles(i).name, className));
        fprintf("File %d/%d (%s): select pixels for class '%s', then press Enter.\n", i, numel(matFiles), matFiles(i).name, className);

        [xClick, yClick] = getpts(fig);
        if isempty(xClick)
            fprintf("  No samples selected for class '%s' in this image.\n", className);
            continue;
        end

        xClick = round(xClick);
        yClick = round(yClick);

        valid = xClick >= 1 & xClick <= w & yClick >= 1 & yClick <= h;
        xClick = xClick(valid);
        yClick = yClick(valid);

        if isempty(xClick)
            fprintf("  All clicked points were outside image bounds for class '%s'.\n", className);
            continue;
        end

        plot(xClick, yClick, "o", "Color", classColors(c,:), "MarkerSize", 6, "LineWidth", 1.5);

        linIdx = sub2ind([h, w], yClick, xClick);
        Xnew = [redCh(linIdx), greenCh(linIdx), blueCh(linIdx)];

        yNew = categorical(repmat(className, numel(linIdx), 1), classNames);

        X = [X; Xnew];
        Y = [Y; yNew];

        metaFile = [metaFile; repmat(string(matFiles(i).name), numel(linIdx), 1)];
        metaClass = [metaClass; repmat(className, numel(linIdx), 1)];
        metaX = [metaX; xClick];
        metaY = [metaY; yClick];

        fprintf("  Added %d samples for class '%s'.\n", numel(linIdx), className);
    end

    hold off;
    close(fig);
end

if isempty(X)
    error("No training samples were collected.");
end

% Ensure labels use the configured class order
Y = categorical(Y, classNames);

sampleCounts = countcats(Y);
disp(table(classNames(:), sampleCounts(:), 'VariableNames', {'Class', 'NumSamples'}));

if any(sampleCounts == 0)
    missingClasses = classNames(sampleCounts == 0);
    error("Missing training samples for class(es): %s", strjoin(cellstr(missingClasses), ', '));
end

%% Balance training samples across classes
rng(seedValue, 'twister');
minCount = min(sampleCounts);
balancedIdx = zeros(0,1);

for c = 1:numClasses
    classIdx = find(Y == classNames(c));
    if numel(classIdx) > minCount
        classIdx = classIdx(randperm(numel(classIdx), minCount));
    end
    balancedIdx = [balancedIdx; classIdx(:)];
end

balancedIdx = sort(balancedIdx);

XBalanced = X(balancedIdx, :);
YBalanced = Y(balancedIdx);

balancedMetaFile = metaFile(balancedIdx);
balancedMetaClass = metaClass(balancedIdx);
balancedMetaX = metaX(balancedIdx);
balancedMetaY = metaY(balancedIdx);

balancedCounts = countcats(categorical(YBalanced, classNames));

fprintf("\nBalancing classes to %d samples per class for training.\n", minCount);
disp(table(classNames(:), sampleCounts(:), balancedCounts(:), 'VariableNames', {'Class', 'RawSamples', 'BalancedSamples'}));

%% Train classifier model
if classifierType == "SVM"
    svmTemplate = templateSVM("KernelFunction", "rbf", "Standardize", true);
    pixelModel = fitcecoc(XBalanced, YBalanced, "Learners", svmTemplate, "Coding", "onevsall");
    modelType = "fitcecoc-templateSVM-rbf";
else
    treeTemplate = templateTree();
    pixelModel = fitcensemble(XBalanced, YBalanced, ...
        'Method', 'Bag', 'Learners', treeTemplate, 'NumLearningCycles', numTrees);
    modelType = "fitcensemble-bag-randomforest";
end

if minCount >= 2
    kfoldUsed = min(5, minCount);
    cvModel = crossval(pixelModel, "KFold", kfoldUsed);
    cvLoss = kfoldLoss(cvModel);
else
    cvLoss = NaN;
    kfoldUsed = 0;
end

%% Save training outputs
sampleMeta = table(metaFile, metaClass, metaX, metaY, ...
    'VariableNames', {'FileName', 'ClassName', 'X', 'Y'});

sampleMetaBalanced = table(balancedMetaFile, balancedMetaClass, balancedMetaX, balancedMetaY, ...
    'VariableNames', {'FileName', 'ClassName', 'X', 'Y'});

trainingData = struct;
trainingData.featuresRGB = X;
trainingData.labels = Y;
trainingData.featuresRGBBalanced = XBalanced;
trainingData.labelsBalanced = YBalanced;
trainingData.classNames = classNames;
trainingData.sampleCounts = sampleCounts;
trainingData.sampleCountsBalanced = balancedCounts;
trainingData.sampleMeta = sampleMeta;
trainingData.sampleMetaBalanced = sampleMetaBalanced;
trainingData.balancedIndices = balancedIdx;

settings = struct;
settings.imFolder = imFolder;
settings.numClasses = numClasses;
settings.classNames = classNames;
settings.classifierType = classifierType;
settings.modelType = modelType;
settings.classBalancing = "random downsampling to smallest class";
settings.seedValue = seedValue;
settings.unclassifiedThreshold = unclassifiedThreshold;
settings.numTrees = numTrees;
settings.kfoldUsed = kfoldUsed;
settings.cvLoss = cvLoss;

save(modelOutputFile, "pixelModel", "trainingData", "settings");

fprintf("\nTraining complete.\n");
fprintf("Model saved to: %s\n", modelOutputFile);
if ~isnan(cvLoss)
    fprintf("Cross-validated loss (%d-fold): %.4f\n", kfoldUsed, cvLoss);
else
    fprintf("Cross-validation skipped (insufficient samples per class).\n");
end
