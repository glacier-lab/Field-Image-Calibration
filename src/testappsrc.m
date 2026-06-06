classdef FieldImageColorCalibration < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                   matlab.ui.Figure
        Label                      matlab.ui.control.Label
        Image5                     matlab.ui.control.Image
        Image4                     matlab.ui.control.Image
        Image3                     matlab.ui.control.Image
        Image2                     matlab.ui.control.Image
        Image                      matlab.ui.control.Image
        TabGroup                   matlab.ui.container.TabGroup
        RGBTab                     matlab.ui.container.Tab
        RGBAxes                    matlab.ui.control.UIAxes
        LightnessTab               matlab.ui.container.Tab
        LightnessAxes              matlab.ui.control.UIAxes
        Panel                      matlab.ui.container.Panel
        TextArea                   matlab.ui.control.TextArea
        RestAllButton              matlab.ui.control.Button
        SaveResultsButton          matlab.ui.control.Button
        CalculateStatisticsButton  matlab.ui.control.Button
        DrawROIButton              matlab.ui.control.Button
        DrawScaleBarButton         matlab.ui.control.Button
        CalibrateColorsButton      matlab.ui.control.Button
        SelectImageButton          matlab.ui.control.Button
    end

    
    properties (Access = private)
        dngFilePath               % Path to selected DNG file
        img_color_corrected       % Calibrated RGB image
        lightnessImg              % Lightness image
        roiPolygon                % ROI polygon object
        scaleLine                 % Scale line object
        mask                      % ROI mask
        roiData                   % ROI statistics
        scaleInfo                 % Scale calibration information
        roiDrawn                  % Flag for ROI completion
        scaleDrawn                % Flag for scale completion
    end
    
    methods (Access = private)
        
        function processScale(app)
            if isempty(app.scaleLine) || ~isvalid(app.scaleLine)
                return;
            end

            % Calculate pixel length
            linePos = app.scaleLine.Position;
            pixelLength = sqrt((linePos(2,1) - linePos(1,1))^2 + (linePos(2,2) - linePos(1,2))^2);

            % Ask user for real-world distance
            answer = inputdlg({'Enter the real-world distance (in cm):'}, ...
                'Scale Calibration', [1 50], {'10'});

            if ~isempty(answer)
                realDistance_cm = str2double(answer{1});
                pixelsPerCm = pixelLength / realDistance_cm;

                % Store scale information
                app.scaleInfo.linePosition = linePos;
                app.scaleInfo.pixelLength = pixelLength;
                app.scaleInfo.realDistance_cm = realDistance_cm;
                app.scaleInfo.pixelsPerCm = pixelsPerCm;
                app.scaleInfo.cmPerPixel = 1 / pixelsPerCm;

                app.scaleDrawn = true;

                statsText = sprintf(['✓ Scale Calibration Complete\n' ...
                    '========================\n' ...
                    'Line length: %.2f pixels\n' ...
                    'Real distance: %.2f cm\n' ...
                    'Scale: %.2f pixels/cm\n' ...
                    'cm per pixel: %.4f\n'], ...
                    pixelLength, realDistance_cm, pixelsPerCm, app.scaleInfo.cmPerPixel);
                % Draw scale bar on both RGB and Lightness images
                imgSize = size(app.img_color_corrected);
                scaleBarLength_cm = 10; % 10 cm scale bar
                scaleBarLength_px = scaleBarLength_cm * app.scaleInfo.pixelsPerCm;

                % Scale bar position (bottom-left with margins)
                margin = 200;
                scaleBarX = margin;
                scaleBarY = imgSize(1) - margin;

                % Draw scale bar
                hold(app.RGBAxes, "on");
                plot(app.RGBAxes, [scaleBarX, scaleBarX + scaleBarLength_px], [scaleBarY, scaleBarY], ...
                    'k-', 'LineWidth', 4);
                hold(app.LightnessAxes, "on");
                plot(app.LightnessAxes, [scaleBarX, scaleBarX + scaleBarLength_px], [scaleBarY, scaleBarY], ...
                    'k-', 'LineWidth', 4);

                % Add text label
                textOffset = 150;
                text(app.RGBAxes, scaleBarX + scaleBarLength_px + textOffset, scaleBarY, ...
                    sprintf('%d cm', scaleBarLength_cm), ...
                    'Color', 'white', 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
                    'BackgroundColor', [0 0 0 0.5], 'EdgeColor', 'white');
                text(app.LightnessAxes, scaleBarX + scaleBarLength_px + textOffset, scaleBarY, ...
                    sprintf('%d cm', scaleBarLength_cm), ...
                    'Color', 'white', 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
                    'BackgroundColor', [0 0 0 0.5], 'EdgeColor', 'white');
                hold(app.RGBAxes, "off");
                hold(app.LightnessAxes, "off");

                if app.roiDrawn
                    statsText = sprintf('%s\n✓ ROI drawn\n', statsText);
                    statsText = sprintf('%s\nReady to calculate statistics.', statsText);
                    app.CalculateStatisticsButton.Enable = 'on';
                else
                    statsText = sprintf('%s\nNow draw the ROI polygon.', statsText);
                end

                app.TextArea.Value = statsText;
            else
                app.TextArea.Value = 'Scale calibration cancelled.';
                app.scaleInfo = [];
                app.scaleDrawn = false;
                app.CalculateStatisticsButton.Enable = 'off';
            end
        end
        
        % Mark ROI drawing as complete
        function completeROIDrawing(app)
            if isempty(app.roiPolygon) || ~isvalid(app.roiPolygon)
                return;
            end
            
            app.roiDrawn = true;
            
            statsText = sprintf('✓ ROI Drawing Complete\n');
            
            if app.scaleDrawn
                statsText = sprintf('%s✓ Scale calibration complete\n', statsText);
                statsText = sprintf('%s\nReady to calculate statistics.', statsText);
                app.CalculateStatisticsButton.Enable = 'on';
            else
                statsText = sprintf('%s\nNow draw the scale bar.', statsText);
            end
            
            app.TextArea.Value = statsText;
        end
    end
    

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: SelectImageButton
        function SelectImageButtonPushed(app, event)
            [file, path] = uigetfile( ...
                {'*.CR2;*.CR3;*.NEF;*.ARW;*.DNG;*.RAF;*.ORF;*.RW2', ...
                 'Raw Image Files (*.CR2,*.CR3,*.NEF,*.ARW,*.DNG,*.RAF,*.ORF,*.RW2)'; ...
                 '*.*', 'All Files (*.*)'}, ...
                'Select a Raw Image File');
            
            if isequal(file, 0)
                return; % User canceled
            end
            
            app.dngFilePath = fullfile(path, file);
            app.CalibrateColorsButton.Enable = 'on';
            app.TextArea.Value = sprintf('Loading selected image: %s', file);
            imshow(raw2rgb(app.dngFilePath),'Parent', app.RGBAxes);
            
            % enable next step
            app.CalibrateColorsButton.Enable = 'on';
        end

        % Button pushed function: CalibrateColorsButton
        function CalibrateColorsButtonPushed(app, event)
            try
                app.TextArea.Value = 'Processing image...';
                drawnow;
                
                % Read and process DNG file
                rawImage = rawread(app.dngFilePath);
                rawInfo = rawinfo(app.dngFilePath);
                colorInfo = rawInfo.ColorInfo;
                
                % Black level correction
                blackLevel = colorInfo.BlackLevel;
                blackLevel = reshape(blackLevel, [1 1 numel(blackLevel)]);
                blackLevel = planar2raw(blackLevel);
                repeatDims = rawInfo.ImageSizeInfo.VisibleImageSize ./ size(blackLevel);
                blackLevel = repmat(blackLevel, repeatDims);
                imgCorrected = rawImage - blackLevel;
                imgCorrected = max(0, imgCorrected);
                imgCorrected = double(imgCorrected);
                maxValue = max(imgCorrected(:));
                imgCorrected = imgCorrected ./ maxValue;
                
                % White balance
                whiteBalance = colorInfo.CameraAsTakenWhiteBalance;
                gLoc = strfind(rawInfo.CFALayout, "G");
                gLoc = gLoc(1);
                whiteBalance = whiteBalance / whiteBalance(gLoc);
                whiteBalance = reshape(whiteBalance, [1 1 numel(whiteBalance)]);
                whiteBalance = planar2raw(whiteBalance);
                whiteBalance = repmat(whiteBalance, repeatDims);
                imgCorrected = imgCorrected .* whiteBalance;
                
                % Demosaic
                img = demosaic(im2uint16(imgCorrected), rawInfo.CFALayout);
                
                % Camera to sRGB transformation
                cam2srgbMat = colorInfo.CameraTosRGB;
                imTransform = imapplymatrix(cam2srgbMat, img, "uint16");
                srgbTransform = lin2rgb(imTransform);
                
                app.TextArea.Value = 'Detecting color checker...';
                drawnow;
                
                % Color checker calibration
                img_for_calibration = im2double(srgbTransform);
                
                % Try automatic detection first, then allow user confirmation
                autoDetected = false;
                try
                    chart = colorChecker(img_for_calibration, "Downsample", false, "Sensitivity", 1);
                    autoDetected = true;
                    app.TextArea.Value = 'Color checker automatically detected. Waiting for confirmation...';
                    drawnow;
                catch
                    app.TextArea.Value = 'Automatic detection failed. Manual selection required.';
                    drawnow;
                end

                if autoDetected
                    displayChart(chart,"Parent", app.RGBAxes);
                    answer = uiconfirm(app.UIFigure, ...
                        'Was the color checker successfully identified?', ...
                        'Color Checker Verification', ...
                        'Options', {'Yes', 'No - Pick manually'}, ...
                        'DefaultOption', 1);

                    if strcmp(answer, 'No - Pick manually')
                        autoDetected = false;
                    end
                end

                if ~autoDetected
                    app.TextArea.Value = 'Manual color checker selection in progress. Double click and select corners: 1) Black (top-left), 2) White (top-right), 3) Brown (bottom-left), 4) Bluish Green (bottom-right)';
                    drawnow;
                    % Get app window position [left bottom width height]
                    appPos = app.UIFigure.Position;

                    % Desired size for manual figure (80% of app size)
                    figW = round(0.8 * appPos(3));
                    figH = round(0.8 * appPos(4));

                    % Center the manual figure over the app
                    figLeft = appPos(1) + round((appPos(3) - figW)/2);
                    figBottom = appPos(2) + round((appPos(4) - figH)/2);

                    

                    % Manual color checker selection
                    figManual = uifigure('Name', 'Manual Color Checker Registration', ...
                        'WindowStyle', 'modal', ...
                        'Position', [figLeft, figBottom, figW, figH]);
                    ax = uiaxes(figManual, 'Position', [1 1 figW figH]);
                    imshow(img_for_calibration, 'Parent', ax);
                    % figManual = imshow(img_for_calibration, 'Parent', app.RGBAxes);

                    ax.Title.String = 'Double click and select corners: 1) Black (top-left), 2) White (top-right), 3) Brown (bottom-left), 4) Bluish Green (bottom-right)';
                    
                    uialert(figManual, 'Draw points on the four corner fiducials (+).', 'Manual Registration');
                    
                    blackPoint = drawpoint(ax, 'Color', 'r', 'Label', 'Black');
                    wait(blackPoint);
                    
                    whitePoint = drawpoint(ax, 'Color', 'r', 'Label', 'White');
                    wait(whitePoint);
                    
                    darkSkinPoint = drawpoint(ax, 'Color', 'r', 'Label', 'Brown');
                    wait(darkSkinPoint);
                    
                    bluishGreenPoint = drawpoint(ax, 'Color', 'r', 'Label', 'Bluish Green');
                    wait(bluishGreenPoint);
                    
                    cornerPoints = [blackPoint.Position;
                                    whitePoint.Position;
                                    darkSkinPoint.Position;
                                    bluishGreenPoint.Position];
                    
                    chart = colorChecker(img_for_calibration, "RegistrationPoints", cornerPoints);
                    displayChart(chart, 'Parent', app.RGBAxes);
                    close(figManual);
                    app.TextArea.Value = 'Color checker registered using manual points.';
                end
                
                [~, ccm] = measureColor(chart);
                app.img_color_corrected = imapplymatrix(ccm(1:3,:)', img_for_calibration, ccm(4,:));
                
                % Calculate lightness
                labImg = rgb2lab(app.img_color_corrected);
                app.lightnessImg = im2double(labImg(:,:,1)) / 100;
                app.lightnessImg = min(max(app.lightnessImg, 0), 1);
                
                % Display RGB image
                cla(app.RGBAxes);
                imshow(app.img_color_corrected, 'Parent', app.RGBAxes);
                % app.RGBAxes.Title.String = 'Color Calibrated RGB Image';
                % app.RGBAxes.Title.Visible = 'on';

                % Display lightness image
                cla(app.LightnessAxes);
                imagesc(app.LightnessAxes, app.lightnessImg);
                colormap(app.LightnessAxes, func_dpcolor());
                axis(app.LightnessAxes, 'off');
                cb = colorbar(app.LightnessAxes);
                cb.Label.String = 'CIELAB Lightness (L*) / 100';
                cb.Location = "southoutside";
                clim(app.LightnessAxes, [0 1]);
                
                % linkaxes([app.RGBAxes app.LightnessAxes]);
                
                % Enable drawing ROI and scale
                app.DrawROIButton.Enable = 'on';
                app.DrawScaleBarButton.Enable = 'on';
                
                % Reset flags
                app.roiDrawn = false;
                app.scaleDrawn = false;
                % app.CalculateStatisticsButton.Enable = 'off';
                
                app.TextArea.Value = 'Color calibration complete. Switch tabs to check the calibrated image and lightness values.';
                
            catch ME
                app.TextArea.Value = sprintf('Error: %s', ME.message);
                % % enable next step
            % app.DrawScaleBarButton.Enable = 'on';
            end
        end

        % Button pushed function: DrawScaleBarButton
        function DrawScaleBarButtonPushed(app, event)
            % Clear previous scale line if exists
            if ~isempty(app.scaleLine) && isvalid(app.scaleLine)
                delete(app.scaleLine);
            end

            app.scaleDrawn = false;

            % Switch to RGB tab
            app.TabGroup.SelectedTab = app.RGBTab;
            app.TextArea.Value = 'Clik and hold to draw a line of known distance. Double-click to finish.';

            % Draw line
            app.scaleLine = drawline(app.RGBAxes, 'Color', 'c', 'LineWidth', 2, 'Label', 'Scale Reference');

            % Wait for user to finish and prompt for distance
            wait(app.scaleLine);
            app.processScale();
            
        end

        % Button pushed function: DrawROIButton
        function DrawROIButtonPushed(app, event)
            % Clear previous ROI if exists
            if ~isempty(app.roiPolygon) && isvalid(app.roiPolygon)
                delete(app.roiPolygon);
            end

            app.roiDrawn = false;
            app.CalculateStatisticsButton.Enable = 'off';

            % Switch to RGB tab and draw polygon
            app.TabGroup.SelectedTab = app.RGBTab;
            app.TextArea.Value = 'Draw polygon ROI. Double-click to finish.';

            app.roiPolygon = drawpolygon(app.RGBAxes, 'Color', 'y', 'LineWidth', 2);

            % Wait for user to finish drawing
            wait(app.roiPolygon);
            app.completeROIDrawing();

            % enable the next step
            app.CalculateStatisticsButton.Enable = 'on';
        end

        % Button pushed function: CalculateStatisticsButton
        function CalculateStatisticsButtonPushed(app, event)
            if ~app.roiDrawn || ~app.scaleDrawn
                app.TextArea.Value = 'Error: Both ROI and scale bar must be drawn first.';
                return;
            end

            app.TextArea.Value = 'Calculating statistics...';
            drawnow;

            try
                % Get mask
                app.mask = createMask(app.roiPolygon);

                % Calculate statistics
                lightnessROI = app.lightnessImg .* app.mask;
                lightnessROI(~app.mask) = NaN;

                app.roiData.mask = app.mask;
                app.roiData.roiPosition = app.roiPolygon.Position;
                app.roiData.meanLightness = mean(lightnessROI(app.mask), 'omitnan');
                app.roiData.stdLightness = std(lightnessROI(app.mask), 'omitnan');
                app.roiData.minLightness = min(lightnessROI(app.mask));
                app.roiData.maxLightness = max(lightnessROI(app.mask));
                app.roiData.lightnessValues = lightnessROI(app.mask);
                app.roiData.numPixels = sum(app.mask(:));

                % Add scale information
                app.roiData.scaleInfo = app.scaleInfo;
                app.roiData.roiArea_cm2 = app.roiData.numPixels * app.scaleInfo.cmPerPixel^2;

                % Display lightness image
                cla(app.LightnessAxes);
                imagesc(app.LightnessAxes, lightnessROI, 'AlphaData', ~isnan(lightnessROI));
                colormap(app.LightnessAxes, func_dpcolor());
                axis(app.LightnessAxes, 'off');
                % cb = colorbar(app.LightnessAxes);
                % cb.Label.String = 'CIELAB Lightness (L*) / 100';
                clim(app.LightnessAxes, [0 1]);
                app.LightnessAxes.Title.String = sprintf('Lightness (Mean: %.4f)', app.roiData.meanLightness);
                app.LightnessAxes.Title.Visible = 'on';

                % Update statistics text
                statsText = sprintf(['=== ROI Lightness Statistics ===\n' ...
                    'Mean:   %.4f\n' ...
                    'Std:    %.4f\n' ...
                    'Pixels: %d\n' ...
                    '\n=== Scale Information ===\n' ...
                    'Pixels per cm: %.2f\n' ...
                    'cm per pixel:  %.4f\n' ...
                    'ROI area (cm²): %.2f\n' ...
                    '================================\n' ...
                    '\n✓ Statistics calculated successfully!'], ...
                    app.roiData.meanLightness, ...
                    app.roiData.stdLightness, ...
                    app.roiData.numPixels, ...
                    app.scaleInfo.pixelsPerCm, ...
                    app.scaleInfo.cmPerPixel, ...
                    app.roiData.roiArea_cm2);

                app.TextArea.Value = statsText;

                % Enable save button
                app.SaveResultsButton.Enable = 'on';

            catch ME
                app.TextArea.Value = sprintf('Error calculating statistics: %s', ME.message);
            end
        end

        % Button pushed function: SaveResultsButton
        function SaveResultsButtonPushed(app, event)
            app.TextArea.Value = sprintf('Saving results...');
            [filepath, name, ~] = fileparts(app.dngFilePath);
            outputDir = fullfile(filepath, 'calibrated_output');
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end

            % Create figure for export
            figExport = figure('Visible', 'off');
            t = tiledlayout(figExport, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

            % RGB with ROI
            ax1 = nexttile(t);
            imshow(app.img_color_corrected, 'Parent', ax1);
            hold(ax1, 'on');
            plot(ax1, [app.roiPolygon.Position(:,1); app.roiPolygon.Position(1,1)], ...
                [app.roiPolygon.Position(:,2); app.roiPolygon.Position(1,2)], ...
                'y-', 'LineWidth', 2);

            % Add scale bar if calibration was done
            if ~isempty(app.scaleInfo)
                imgSize = size(app.img_color_corrected);
                scaleBarLength_cm = 10; % 10 cm scale bar
                scaleBarLength_px = scaleBarLength_cm * app.scaleInfo.pixelsPerCm;

                % Scale bar position (bottom-left with margins)
                margin = 200;
                scaleBarX = margin;
                scaleBarY = imgSize(1) - margin;

                % Draw scale bar
                plot(ax1, [scaleBarX, scaleBarX + scaleBarLength_px], [scaleBarY, scaleBarY], ...
                    'k-', 'LineWidth', 4);

                % Add text label
                textOffset = 150;
                text(ax1, scaleBarX + scaleBarLength_px + textOffset, scaleBarY, ...
                    sprintf('%d cm', scaleBarLength_cm), ...
                    'Color', 'white', 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
                    'BackgroundColor', [0 0 0 0.5], 'EdgeColor', 'white');
            end

            hold(ax1, 'off');
            title(ax1, 'a) RGB Image with ROI');

            % Lightness
            ax2 = nexttile(t);
            lightnessROI = app.lightnessImg .* app.mask;
            lightnessROI(~app.mask) = NaN;
            imagesc(ax2, lightnessROI, 'AlphaData', ~isnan(lightnessROI));
            colormap(ax2, func_dpcolor());
            axis(ax2, 'off');
            cb = colorbar(ax2);
            cb.Label.String = 'CIELAB Lightness (L*) / 100';
            clim(ax2, [0 1]);
            title(ax2, sprintf('b) Lightness within ROI (Mean: %.4f)', app.roiData.meanLightness));

            % Add scale bar to lightness image if calibration was done
            if ~isempty(app.scaleInfo)
                hold(ax2, 'on');
                imgSize = size(app.img_color_corrected);
                scaleBarLength_cm = 10;
                scaleBarLength_px = scaleBarLength_cm * app.scaleInfo.pixelsPerCm;
                margin = 200;
                scaleBarX = margin;
                scaleBarY = imgSize(1) - margin;

                plot(ax2, [scaleBarX, scaleBarX + scaleBarLength_px], [scaleBarY, scaleBarY], ...
                    'k-', 'LineWidth', 4);

                textOffset = 150;
                text(ax2, scaleBarX + scaleBarLength_px + textOffset, scaleBarY, ...
                    sprintf('%d cm', scaleBarLength_cm), ...
                    'Color', 'white', 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
                    'BackgroundColor', [0 0 0 0.5], 'EdgeColor', 'white');
                hold(ax2, 'off');
            end

            fontsize(t, 16, 'points');
            axis(ax2, 'image');

            % Save figure
            pngFile = fullfile(outputDir, sprintf('%s_roi_lightness.png', name));
            pdfFile = fullfile(outputDir, sprintf('%s_roi_lightness.pdf', name));
            exportgraphics(figExport, pngFile, 'Resolution', 300);
            exportgraphics(figExport, pdfFile, 'Resolution', 300);
            close(figExport);

            % Save ROI data
            roiDataFile = fullfile(outputDir, sprintf('%s_roi_data.mat', name));
            roiData = app.roiData;
            img_color_corrected = app.img_color_corrected;
            save(roiDataFile, 'roiData', 'img_color_corrected');

            app.TextArea.Value = sprintf('Figure saved to:\n%s\n\nROI data saved to:\n%s', ...
                pngFile, roiDataFile);
        end

        % Button pushed function: RestAllButton
        function RestAllButtonPushed(app, event)
            % Confirm reset
            selection = uiconfirm(app.UIFigure, ...
                'This will clear all data and reset the application. Continue?', ...
                'Confirm Reset', ...
                'Options', {'Yes', 'No'}, ...
                'DefaultOption', 2, ...
                'Icon', 'warning');

            if strcmp(selection, 'No')
                return;
            end

            % Clear ROI polygon
            if ~isempty(app.roiPolygon) && isvalid(app.roiPolygon)
                delete(app.roiPolygon);
            end
            app.roiPolygon = [];

            % Clear scale line
            if ~isempty(app.scaleLine) && isvalid(app.scaleLine)
                delete(app.scaleLine);
            end
            app.scaleLine = [];

            % Clear all data properties
            app.dngFilePath = [];
            app.img_color_corrected = [];
            app.lightnessImg = [];
            app.mask = [];
            app.roiData = [];
            app.scaleInfo = [];
            app.roiDrawn = false;
            app.scaleDrawn = false;

            % Clear axes
            cla(app.RGBAxes);
            app.RGBAxes.Title.String = '';
            app.RGBAxes.XTick = [];
            app.RGBAxes.YTick = [];

            cla(app.LightnessAxes);
            app.LightnessAxes.Title.String = '';
            app.LightnessAxes.XTick = [];
            app.LightnessAxes.YTick = [];

            % Reset button states
            app.CalibrateColorsButton.Enable = 'off';
            app.DrawROIButton.Enable = 'off';
            app.DrawScaleBarButton.Enable = 'off';
            app.CalculateStatisticsButton.Enable = 'off';
            app.SaveResultsButton.Enable = 'off';

            % Reset statistics text
            app.TextArea.Value = 'Application reset. Select an image to begin...';

            % Switch to RGB tab
            app.TabGroup.SelectedTab = app.RGBTab;
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Get the file path for locating images
            pathToMLAPP = fileparts(mfilename('fullpath'));

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1196 669];
            app.UIFigure.Name = 'MATLAB App';

            % Create Panel
            app.Panel = uipanel(app.UIFigure);
            app.Panel.Position = [41 26 302 622];

            % Create SelectImageButton
            app.SelectImageButton = uibutton(app.Panel, 'push');
            app.SelectImageButton.ButtonPushedFcn = createCallbackFcn(app, @SelectImageButtonPushed, true);
            app.SelectImageButton.Position = [46 574 209 39];
            app.SelectImageButton.Text = 'Select Image';

            % Create CalibrateColorsButton
            app.CalibrateColorsButton = uibutton(app.Panel, 'push');
            app.CalibrateColorsButton.ButtonPushedFcn = createCallbackFcn(app, @CalibrateColorsButtonPushed, true);
            app.CalibrateColorsButton.Enable = 'off';
            app.CalibrateColorsButton.Position = [46 524 209 39];
            app.CalibrateColorsButton.Text = 'Calibrate Colors';

            % Create DrawScaleBarButton
            app.DrawScaleBarButton = uibutton(app.Panel, 'push');
            app.DrawScaleBarButton.ButtonPushedFcn = createCallbackFcn(app, @DrawScaleBarButtonPushed, true);
            app.DrawScaleBarButton.Enable = 'off';
            app.DrawScaleBarButton.Position = [46 474 209 39];
            app.DrawScaleBarButton.Text = 'Draw Scale Bar';

            % Create DrawROIButton
            app.DrawROIButton = uibutton(app.Panel, 'push');
            app.DrawROIButton.ButtonPushedFcn = createCallbackFcn(app, @DrawROIButtonPushed, true);
            app.DrawROIButton.Enable = 'off';
            app.DrawROIButton.Position = [46 424 209 39];
            app.DrawROIButton.Text = 'Draw ROI';

            % Create CalculateStatisticsButton
            app.CalculateStatisticsButton = uibutton(app.Panel, 'push');
            app.CalculateStatisticsButton.ButtonPushedFcn = createCallbackFcn(app, @CalculateStatisticsButtonPushed, true);
            app.CalculateStatisticsButton.Enable = 'off';
            app.CalculateStatisticsButton.Position = [46 374 209 39];
            app.CalculateStatisticsButton.Text = 'Calculate Statistics';

            % Create SaveResultsButton
            app.SaveResultsButton = uibutton(app.Panel, 'push');
            app.SaveResultsButton.ButtonPushedFcn = createCallbackFcn(app, @SaveResultsButtonPushed, true);
            app.SaveResultsButton.Enable = 'off';
            app.SaveResultsButton.Position = [46 324 209 39];
            app.SaveResultsButton.Text = 'Save Results';

            % Create RestAllButton
            app.RestAllButton = uibutton(app.Panel, 'push');
            app.RestAllButton.ButtonPushedFcn = createCallbackFcn(app, @RestAllButtonPushed, true);
            app.RestAllButton.BackgroundColor = [1 1 0];
            app.RestAllButton.Position = [46 274 209 39];
            app.RestAllButton.Text = 'Rest All';

            % Create TextArea
            app.TextArea = uitextarea(app.Panel);
            app.TextArea.Position = [16 22 271 240];
            app.TextArea.Value = {'Hi, this is an app to calibrate and postprocess field images. If you have any questions, please do not hesitate to contact me (Shunan Feng: shunan.feng@envs.au.dk).'};

            % Create TabGroup
            app.TabGroup = uitabgroup(app.UIFigure);
            app.TabGroup.Position = [428 119 736 529];

            % Create RGBTab
            app.RGBTab = uitab(app.TabGroup);
            app.RGBTab.Title = 'RGB';

            % Create RGBAxes
            app.RGBAxes = uiaxes(app.RGBTab);
            app.RGBAxes.XTick = [];
            app.RGBAxes.YTick = [];
            app.RGBAxes.Position = [1 1 703 505];

            % Create LightnessTab
            app.LightnessTab = uitab(app.TabGroup);
            app.LightnessTab.Title = 'Lightness';

            % Create LightnessAxes
            app.LightnessAxes = uiaxes(app.LightnessTab);
            app.LightnessAxes.XTick = [];
            app.LightnessAxes.YTick = [];
            app.LightnessAxes.Position = [1 1 703 505];

            % Create Image
            app.Image = uiimage(app.UIFigure);
            app.Image.Position = [544 32 150 68];
            app.Image.ImageSource = fullfile(pathToMLAPP, 'resources', 'aulogo_uk_var2_blue.png');

            % Create Image2
            app.Image2 = uiimage(app.UIFigure);
            app.Image2.Position = [884 32 99 72];
            app.Image2.ImageSource = fullfile(pathToMLAPP, 'resources', 'DP logo FINAL TRANSPARENT BACKGROUND.png');

            % Create Image3
            app.Image3 = uiimage(app.UIFigure);
            app.Image3.Position = [805 32 80 68];
            app.Image3.ImageSource = fullfile(pathToMLAPP, 'resources', 'SnowPI_logo_portrait_tagline_white_RGB.png');

            % Create Image4
            app.Image4 = uiimage(app.UIFigure);
            app.Image4.Position = [983 32 181 68];
            app.Image4.ImageSource = fullfile(pathToMLAPP, 'resources', 'LOGO_ERC-FLAG_EU-no text.png');

            % Create Image5
            app.Image5 = uiimage(app.UIFigure);
            app.Image5.Position = [694 32 112 74];
            app.Image5.ImageSource = fullfile(pathToMLAPP, 'resources', 'NNF_Logo_Vertical_Blue-1.png');

            % Create Label
            app.Label = uilabel(app.UIFigure);
            app.Label.Position = [866 -4 289 31];
            app.Label.Text = 'https://github.com/glacier-lab/Field-Image-Calibration';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = FieldImageColorCalibration

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end