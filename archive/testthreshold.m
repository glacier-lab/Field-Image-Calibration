%%
imfolder = "C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\calibrated_output";
imfiles = dir(fullfile(imfolder, "*_roi_data.mat"));

imfile = imfiles(2);
imdata = load(fullfile(imfolder, imfile.name));

%%
img = imdata.img_color_corrected;
img_lab = rgb2lab(img);
L = img_lab(:,:,1);
img_darkness = L / 100; % Normalize to [0, 1]
