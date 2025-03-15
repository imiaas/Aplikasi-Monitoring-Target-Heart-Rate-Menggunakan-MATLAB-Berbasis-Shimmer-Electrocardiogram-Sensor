classdef THR < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = private)
        UIFigure                        matlab.ui.Figure
        MONITORINGTARGETHEARTRATEPanel  matlab.ui.container.Panel
        Panel                           matlab.ui.container.Panel
        Button                          matlab.ui.control.Button
        GenderDropDown                  matlab.ui.control.DropDown
        GenderDropDownLabel             matlab.ui.control.Label
        UsiaEditField                   matlab.ui.control.NumericEditField
        UsiaEditFieldLabel              matlab.ui.control.Label
        NamaEditField                   matlab.ui.control.EditField
        NamaEditFieldLabel              matlab.ui.control.Label
        Panel_2                         matlab.ui.container.Panel
        THRLabel                        matlab.ui.control.Label
        Lamp                            matlab.ui.control.Lamp
        LampLabel                       matlab.ui.control.Label
        BPMLabel                        matlab.ui.control.Label
        UIAxes                          matlab.ui.control.UIAxes
        StopButton                      matlab.ui.control.StateButton
        StartButton                     matlab.ui.control.StateButton                  

        shimmer       % ShimmerHandleClass object
        Fs = 512      % Sampling rate
        T             % Sampling period
        buffer_size   % Buffer size for ECG data
        ecg_data_buffer  % Buffer for ECG data
        RHR                  double
        iterationCounter     double
        lastValidBPM         double
        
    end

    methods (Access = private)
                % StartButton callback
        function StartButtonValueChanged(app, event)
            if app.StartButton.Value
                startECGProcessing(app);
            end
        end

        % StopButton callback
        function StopButtonValueChanged(app, event)
            if ~app.StartButton.Value
                stopECGProcessing(app);
            end
        end

        % Function to start ECG processing
        function startECGProcessing(app)
            clc;
            comPort = '5';  
            app.shimmer = ShimmerHandleClass(comPort); 

            % Try to connect to the Shimmer device
            connected = app.shimmer.connect(); 
            if connected
                disp('Shimmer connected'); 
                app.shimmer.setsamplingrate(app.Fs); 
                app.shimmer.start(); 
                disp('Shimmer started'); 
                
                app.iterationCounter = 0;
                app.RHR = NaN;
                app.lastValidBPM = NaN;
                
                while app.StartButton.Value
                    
                    [data, ~] = app.shimmer.getdata('c'); 
                    pause(10); 
                    [numRow, numCol] = size(data); 

                    if (numRow > 0 && numCol > 0) 
                        signalData = data(:,4); 
                        tp = data(:,1); 
                        app.ecg_data_buffer = [app.ecg_data_buffer(numRow+1:end); signalData];
                        bp_ecg = bandpassFilter(app, app.ecg_data_buffer);  
                        derivative_ecg = derivative(app, bp_ecg, app.T);
                        squared_ecg = derivative_ecg .^ 2;
                        mwi_ecg = movingWindowIntegration(app, squared_ecg);
                        threshold = 0.6 * max(mwi_ecg); 
                        min_peak_distance = round(0.2 * app.Fs);
                        if min_peak_distance >= length(mwi_ecg)
                            min_peak_distance = length(mwi_ecg) - 1;
                        end
                        [peaks, peak_indices] = findpeaks(mwi_ecg, 'MinPeakHeight', threshold, 'MinPeakDistance', min_peak_distance);
                        num_peaks = length(peak_indices);
                        if num_peaks > 1
                            rr_intervals = diff(peak_indices) / app.Fs; 
                            avg_rr_interval = mean(rr_intervals); 
                            BPM = 60 / avg_rr_interval; 
                        else
                            BPM = NaN; 
                        end

                        if ~isnan(BPM)
                            app.lastValidBPM = BPM;
                        end
                        % Increment counter iterasi
                        app.iterationCounter = app.iterationCounter + 1;
                        
    
                        % Simpan hasil BPM pada iterasi ke-3 ke variabel tetap RHR
                        if app.iterationCounter == 2
                            if ~isnan(BPM)
                                app.RHR = BPM;
                            elseif ~isnan(app.lastValidBPM)
                                app.RHR = app.lastValidBPM;
                            end
                        end

                        age = app.UsiaEditField.Value; 
                        gender = app.GenderDropDown.Value;
                        RHR = app.RHR;

                        % Calculate MHR and THR
                        MHR = app.calculateMHR(age, gender);
                        HRR = MHR - RHR; % Perhitungan HRR berdasarkan MHR yang sudah ditentukan
                        i_max = 0.70;
                        THR = round((HRR * i_max) + RHR);
                        BPMn = round(BPM);

                        % Update BPM and THR labels
                        
                        app.BPMLabel.Text = ['BPM: ', num2str(BPMn)];
                        app.THRLabel.Text = ['THR: ', num2str(THR)];

                        % Update lamp and label based on BPM and THR
                        if BPMn < THR
                            app.Lamp.Color = [0.5 0.5 0.5]; 
                            app.LampLabel.Text = 'THR BELUM TERCAPAI, LANJUTKAN!';
                        elseif BPMn >= THR
                            app.Lamp.Color = [0 1 0]; 
                            app.LampLabel.Text = 'THR SUDAH TERCAPAI, BERHENTI!';
                        else
                            app.Lamp.Color = [1 0 0]; 
                            app.LampLabel.Text = 'Not Enough Data';
                        end


                        plot(app.UIAxes,((1:length(mwi_ecg))/512), mwi_ecg, 'b');
                        hold(app.UIAxes, 'on');
                        plot(app.UIAxes, peak_indices/512, mwi_ecg(peak_indices), 'ro');
                        hold(app.UIAxes, 'off');
                        % plot(app.UIAxes, ((1:length(bp_ecg))/app.Fs), bp_ecg, 'b');
                        title(app.UIAxes, 'ECG Signal');
                        xlabel(app.UIAxes, 'Time');
                        ylabel(app.UIAxes, 'Amplitude');

                        drawnow; 
                        
                        
                    end 

                end 

                app.shimmer.stop(); 
                app.shimmer.disconnect(); 
                disp('Shimmer disconnected'); 
            else
                disp('Failed to connect to Shimmer device');
            end 
        end

        % Function to stop ECG processing
        function stopECGProcessing(app)
            app.StartButton.Value = false;
        end

        % Function for bandpass filtering (combination of lowpass and highpass)
        function bp_ecg = bandpassFilter(app, ecg_data)
            lp_ecg = zeros(size(ecg_data));
            for n = 13:length(ecg_data)
                lp_ecg(n) = 2*lp_ecg(n-1) - lp_ecg(n-2) + ecg_data(n) - 2*ecg_data(n-6) + ecg_data(n-12);
            end
            bp_ecg = zeros(size(lp_ecg));
            for n = 33:length(lp_ecg)
                bp_ecg(n) = bp_ecg(n-1) - (1/32)*lp_ecg(n) + lp_ecg(n-16) - lp_ecg(n-17) + (1/32)*lp_ecg(n-32);
            end
        end

        % Function for derivative
        function derivative_ecg = derivative(app, bp_ecg, T)
            derivative_ecg = zeros(size(bp_ecg));
            for n = 3:length(bp_ecg)-2
                derivative_ecg(n) = (1/(8*T)) * (-bp_ecg(n-2) - 2*bp_ecg(n-1) + 2*bp_ecg(n+1) + bp_ecg(n+2));
            end
        end

        % Function for moving window integration
        function mwi_ecg = movingWindowIntegration(app, squared_ecg)
            window_size = round(0.150 * app.Fs); 
            mwi_ecg = zeros(size(squared_ecg));
            for n = window_size:length(squared_ecg)
                mwi_ecg(n) = (1/window_size) * sum(squared_ecg(n-window_size+1:n));
            end
        end

         % Function to calculate MHR based on gender and age
        function MHR = calculateMHR(~, age, gender)
            if strcmpi(gender, 'Wanita')
                MHR = 206 - (0.88 * age);
            elseif strcmpi(gender, 'Pria')
                MHR = 206.9 - (0.67 * age);
            end
        end
     end
   

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)
            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Color = [0.7412 0.6824 0.6824];
            app.UIFigure.Position = [100 100 891 488];
            app.UIFigure.Name = 'THR App';

            % Create Panel_2
            app.Panel_2 = uipanel(app.UIFigure);
            app.Panel_2.BackgroundColor = [0.8902 0.8706 0.8745];
            app.Panel_2.Position = [328 28 543 403];

            % Create UIAxes
            app.UIAxes = uiaxes(app.Panel_2);
            title(app.UIAxes, 'Sinyal ECG')
            xlabel(app.UIAxes, 'Waktu (s)')
            ylabel(app.UIAxes, 'Amplitudo')
            app.UIAxes.Position = [39 33 461 232];

            % Create BPMLabel
            app.BPMLabel = uilabel(app.Panel_2);
            app.BPMLabel.FontSize = 18;
            app.BPMLabel.FontWeight = 'bold';
            app.BPMLabel.Position = [39 344 400 42]; 
            app.BPMLabel.Text = 'BPM: ';

            % Create Lamp
            app.Lamp = uilamp(app.Panel_2);
            app.Lamp.Position = [39 290 33 33];
            app.Lamp.Color = [0.8 0.8 0.8];

            % Create LampLabel
            app.LampLabel = uilabel(app.Panel_2);
            app.LampLabel.Position = [80 290 600 33]; % Atur posisi label di samping lampu
            app.LampLabel.Text = " "; % Tetapkan teks sesuai kondisi detak jantung
            app.LampLabel.FontWeight = 'bold'; % Atur teks menjadi tebal
            app.LampLabel.FontSize = 18;

            % Create THRLabel
            app.THRLabel = uilabel(app.Panel_2);
            app.THRLabel.FontSize = 18;
            app.THRLabel.FontWeight = 'bold';
            app.THRLabel.Position = [328 344 400 42];
            app.THRLabel.Text = 'THR: ';

            % Create Panel
            app.Panel = uipanel(app.UIFigure);
            app.Panel.BackgroundColor = [0.902 0.902 0.902];
            app.Panel.Position = [23 143 277 288];

            % Create NamaEditFieldLabel
            app.NamaEditFieldLabel = uilabel(app.Panel);
            app.NamaEditFieldLabel.HorizontalAlignment = 'right';
            app.NamaEditFieldLabel.FontSize = 16;
            app.NamaEditFieldLabel.Position = [40 216 48 22];
            app.NamaEditFieldLabel.Text = 'Nama';

            % Create NamaEditField
            app.NamaEditField = uieditfield(app.Panel, 'text');
            app.NamaEditField.FontSize = 16;
            app.NamaEditField.Position = [103 208 122 30];
            app.NamaEditField.Value = "";

            % Create UsiaEditFieldLabel
            app.UsiaEditFieldLabel = uilabel(app.Panel);
            app.UsiaEditFieldLabel.HorizontalAlignment = 'right';
            app.UsiaEditFieldLabel.FontSize = 16;
            app.UsiaEditFieldLabel.Position = [51 159 37 22];
            app.UsiaEditFieldLabel.Text = 'Usia';

            % Create UsiaEditField
            app.UsiaEditField = uieditfield(app.Panel, 'numeric');
            app.UsiaEditField.FontSize = 16;
            app.UsiaEditField.Position = [103 154 122 27];
            app.UsiaEditField.Value = 0;

            % Create GenderDropDownLabel
            app.GenderDropDownLabel = uilabel(app.Panel);
            app.GenderDropDownLabel.HorizontalAlignment = 'right';
            app.GenderDropDownLabel.FontSize = 16;
            app.GenderDropDownLabel.Position = [32 105 58 22];
            app.GenderDropDownLabel.Text = 'Gender';

            % Create GenderDropDown
            app.GenderDropDown = uidropdown(app.Panel);
            app.GenderDropDown.Items = {'Wanita', 'Pria'};
            app.GenderDropDown.FontSize = 16;
            app.GenderDropDown.Position = [105 100 120 27];
            app.GenderDropDown.Value = 'Wanita';

            % Create StartButton
            app.StartButton = uibutton(app.Panel, 'state');
            app.StartButton.BackgroundColor = [0.6235 0.9294 0.5765];
            app.StartButton.FontSize = 18;
            app.StartButton.FontWeight = 'bold';
            app.StartButton.Position = [99 39 60 39];
            app.StartButton.Text = 'Start';
            app.StartButton.ValueChangedFcn = @(src,event) StartButtonValueChanged(app, event);

            % Create StopButton
            app.StopButton = uibutton(app.Panel, 'state');
            app.StopButton.BackgroundColor = [0.9804 0.7529 0.6549];
            app.StopButton.FontSize = 18;
            app.StopButton.FontWeight = 'bold';
            app.StopButton.Position = [170 39 59 39];
            app.StopButton.Text = 'Stop';
            app.StopButton.ValueChangedFcn = @(src,event) StartButtonValueChanged(app, event);

            % Create MONITORINGTARGETHEARTRATEPanel
            app.MONITORINGTARGETHEARTRATEPanel = uipanel(app.UIFigure);
            app.MONITORINGTARGETHEARTRATEPanel.TitlePosition = 'centertop';
            app.MONITORINGTARGETHEARTRATEPanel.Title = 'MONITORING TARGET HEART RATE';
            app.MONITORINGTARGETHEARTRATEPanel.BackgroundColor = [0.9412 0.902 0.9098];
            app.MONITORINGTARGETHEARTRATEPanel.FontWeight = 'bold';
            app.MONITORINGTARGETHEARTRATEPanel.FontSize = 20;
            app.MONITORINGTARGETHEARTRATEPanel.Position = [23 441 848 30];

            app.T = 1 / app.Fs;
            app.buffer_size = 3 * app.Fs;
            app.ecg_data_buffer = zeros(app.buffer_size, 1);

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = THR

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
            
            % Disconnect and delete Shimmer object if it exists
            if ~isempty(app.shimmer)
                app.shimmer.stop;
                app.shimmer.disconnect;
                delete(app.shimmer);
            end
        end
    end    
end
        

    