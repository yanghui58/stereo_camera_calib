classdef StereoCaptureApp < handle
% STEREOCAPTUREAPP 双目工业相机实时预览、参数设置与同步采集 GUI (JHUM1204B 适配版)
%   100% 基于 MATLAB 官方 Image Acquisition Toolbox (winvideo) 构建，独立单文件运行。
%
%   启动方式:
%       cap = StereoCaptureApp();
%
%   核心功能:
%       1. 自动枚举 winvideo 工业相机 (Cam0 / Cam1)，支持热插拔刷新与一键互换左右相机
%       2. 支持全部硬件预设分辨率切换、8位灰度/RGB24 切换及 4 字节对齐居中 ROI 裁剪
%       3. 实时调节曝光(1~10000)、增益(0~200)、伽马、对比度，以及无警告硬件水平/垂直翻转(WB=11~14)
%       4. 支持「双目同步调节」、「左->右一键配平」与「单相机独立微调」，支持连续流/软触发流(WB=20~22)
%       5. 实时叠加中心十字准星与水平极线对齐网格，实时监测 Tenengrad 对焦清晰度与过曝标红告警
%       6. 亚毫秒级双目同步帧抓取，支持空格键(Space)防误触盲拍、定时连拍、多级撤销、防覆盖保护
%       7. 支持拍前棋盘格角点可视化预检，采集完可一键自动载入 StereoCalibApp 进行双目标定

    properties (Access = public)
        VidLeft = []
        VidRight = []
        SrcLeft = []
        SrcRight = []
        DeviceList = struct('id', {}, 'name', {}, 'formats', {}, 'defaultFormat', {})
        IsPreviewing = false

        SaveRootDir = ''
        CaptureIndex = 1
        SavedHistory = struct('idx', {}, 'left', {}, 'right', {})
    end

    properties (Access = private)
        Fig
        FontName = 'Microsoft YaHei'

        % 1. 设备与格式控件
        PopCamLeft
        PopCamRight
        PopFormat
        PopColorSpace
        ChkCustomROI
        EdtRoiW
        EdtRoiH
        BtnStartStop

        % 2. 相机参数控件
        PopTuneTarget
        SldExposure
        EdtExposure
        SldGain
        EdtGain
        SldGamma
        EdtGamma
        SldContrast
        EdtContrast
        ChkFlipH
        ChkFlipV
        PopSnapMode

        % 3. 辅助对焦与网格控件
        ChkOverlay
        EdtGridStep
        ChkFocusMeter

        % 4. 采集存盘控件
        EdtSaveDir
        PopImgExt
        EdtPrefixL
        EdtPrefixR
        EdtNextIdx
        BtnSnap
        EdtInterval
        BtnAutoTimer

        % 右侧图像显示区
        AxLiveL
        AxLiveR
        LblMetricsL
        LblMetricsR
        AxSnapL
        AxSnapR
        LblSnapInfo
        LblStatus

        % 预览图形句柄、内部翻转状态与定时器
        HImgLiveL = []
        HImgLiveR = []
        FlipStateL = [false, false]  % [flipH, flipV]
        FlipStateR = [false, false]
        CachedParamsL = []
        CachedParamsR = []
        MeterTimer = []
        AutoSnapTimer = []
        IsUpdatingControls = false
    end

    methods (Access = public)
        function app = StereoCaptureApp()
            if isempty(which('videoinput'))
                errordlg('未检测到 Image Acquisition Toolbox。', '工具箱缺失');
                return;
            end
            hw = imaqhwinfo;
            if ~any(strcmp(hw.InstalledAdaptors, 'winvideo'))
                errordlg('未检测到 winvideo 硬件支持包 (OS Generic Video Interface)。', '适配器缺失');
                return;
            end

            projRoot = fileparts(mfilename('fullpath'));
            if isempty(projRoot), projRoot = pwd; end
            app.SaveRootDir = fullfile(projRoot, 'capture_data');

            app.buildUI();
            app.refreshDevices(false);
            app.syncNextCaptureIndex();
        end

        function delete(app)
            app.cleanupAll();
        end
    end

    methods (Access = private)
        % =================================================================
        % UI 构建
        % =================================================================
        function buildUI(app)
            bgMain   = [0.95 0.96 0.97];
            bgPanel  = [0.98 0.98 0.99];
            cPrimary = [0.13 0.45 0.78];
            cGreen   = [0.15 0.60 0.40];
            cOrange  = [0.85 0.45 0.12];

            app.Fig = figure( ...
                'Name', '双目工业相机实时预览与同步采集系统 (JHUM1204B - StereoCaptureApp)', ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'ToolBar', 'figure', ...
                'Color', bgMain, ...
                'Units', 'normalized', ...
                'Position', [0.03 0.05 0.94 0.88], ...
                'WindowKeyPressFcn', @(src, evt) app.onWindowKeyPress(src, evt), ...
                'CloseRequestFcn', @(~,~) app.onClose());

            % ==================== 左侧控制面板 ====================
            pnlLeft = uipanel('Parent', app.Fig, ...
                'Units', 'normalized', 'Position', [0.007 0.042 0.275 0.948], ...
                'BackgroundColor', bgPanel, 'BorderType', 'line', ...
                'HighlightColor', [0.82 0.85 0.88]);

            % --- 1. 设备连接与分辨率 ---
            p1 = uipanel('Parent', pnlLeft, 'Title', ' 1. 双目设备与分辨率 ', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.025 0.735 0.95 0.255]);

            uicontrol('Parent', p1, 'Style', 'text', 'String', '左相机:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.80 0.16 0.14]);
            app.PopCamLeft = uicontrol('Parent', p1, 'Style', 'popupmenu', 'String', {'未检测'}, ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.19 0.81 0.46 0.15], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onCameraSelectionChange()));

            uicontrol('Parent', p1, 'Style', 'pushbutton', 'String', '刷新', ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.67 0.80 0.14 0.16], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.refreshDevices(true)));
            uicontrol('Parent', p1, 'Style', 'pushbutton', 'String', '互换', ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.83 0.80 0.14 0.16], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onSwapCameras()));

            uicontrol('Parent', p1, 'Style', 'text', 'String', '右相机:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.61 0.16 0.14]);
            app.PopCamRight = uicontrol('Parent', p1, 'Style', 'popupmenu', 'String', {'未检测'}, ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.19 0.62 0.78 0.15], ...
                'Callback', @(src,~) app.withRefocus(src, @() []));

            uicontrol('Parent', p1, 'Style', 'text', 'String', '分辨率:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.42 0.16 0.14]);
            app.PopFormat = uicontrol('Parent', p1, 'Style', 'popupmenu', 'String', {'默认格式'}, ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.19 0.43 0.47 0.15], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onFormatChange()));
            app.PopColorSpace = uicontrol('Parent', p1, 'Style', 'popupmenu', ...
                'String', {'8位灰度', 'RGB24'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.68 0.43 0.29 0.15], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onFormatChange()));

            app.ChkCustomROI = uicontrol('Parent', p1, 'Style', 'checkbox', ...
                'String', '居中裁剪 ROI:', 'Value', 0, ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.03 0.23 0.36 0.15], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onFormatChange()));
            app.EdtRoiW = uicontrol('Parent', p1, 'Style', 'edit', 'String', '1280', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.40 0.23 0.22 0.15], ...
                'Callback', @(~,~) app.onRoiSizeEdited());
            uicontrol('Parent', p1, 'Style', 'text', 'String', 'x', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.63 0.22 0.06 0.14]);
            app.EdtRoiH = uicontrol('Parent', p1, 'Style', 'edit', 'String', '1024', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.70 0.23 0.22 0.15], ...
                'Callback', @(~,~) app.onRoiSizeEdited());

            app.BtnStartStop = uicontrol('Parent', p1, 'Style', 'pushbutton', ...
                'String', '开启双目实时预览', 'FontName', app.FontName, 'FontSize', 9.5, ...
                'FontWeight', 'bold', 'BackgroundColor', cGreen, 'ForegroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.03 0.03 0.94 0.17], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onTogglePreview()));

            % --- 2. 相机成像参数设置 ---
            p2 = uipanel('Parent', pnlLeft, 'Title', ' 2. 曝光 / 增益 / 翻转 / 触发 ', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.025 0.395 0.95 0.330]);

            uicontrol('Parent', p2, 'Style', 'text', 'String', '调节目标:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.85 0.20 0.11]);
            app.PopTuneTarget = uicontrol('Parent', p2, 'Style', 'popupmenu', ...
                'String', {'双目同步调节', '仅左相机', '仅右相机'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.23 0.86 0.50 0.12], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.syncSlidersFromHardware()));
            uicontrol('Parent', p2, 'Style', 'pushbutton', 'String', '左->右配平', ...
                'FontName', app.FontName, 'FontSize', 8, ...
                'Units', 'normalized', 'Position', [0.75 0.85 0.22 0.13], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.syncLeftToRight()));

            % 曝光 Brightness [1, 10000]
            [app.SldExposure, app.EdtExposure] = app.createSliderRow(p2, 0.69, ...
                '曝光(1-10000):', 1, 10000, 150, [0.001 0.05], @app.onExposureChanged);

            % 增益 Gain [0, 200]
            [app.SldGain, app.EdtGain] = app.createSliderRow(p2, 0.53, ...
                '增益(0-200):', 0, 200, 10, [0.005 0.05], @app.onGainChanged);

            % 伽马 Gamma [0, 200]
            [app.SldGamma, app.EdtGamma] = app.createSliderRow(p2, 0.37, ...
                '伽马(0-200):', 0, 200, 100, [0.005 0.05], @app.onGammaChanged);

            % 对比度 Contrast [0, 200]
            [app.SldContrast, app.EdtContrast] = app.createSliderRow(p2, 0.21, ...
                '对比度(0-200):', 0, 200, 100, [0.005 0.05], @app.onContrastChanged);

            app.ChkFlipH = uicontrol('Parent', p2, 'Style', 'checkbox', ...
                'String', '水平镜像', 'Value', 0, 'FontName', app.FontName, 'FontSize', 8.5, ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.04 0.24 0.13], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onFlipHChanged()));
            app.ChkFlipV = uicontrol('Parent', p2, 'Style', 'checkbox', ...
                'String', '垂直翻转', 'Value', 0, 'FontName', app.FontName, 'FontSize', 8.5, ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.28 0.04 0.24 0.13], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onFlipVChanged()));
            app.PopSnapMode = uicontrol('Parent', p2, 'Style', 'popupmenu', ...
                'String', {'连续流(WB20)', '触发流(WB21)'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 8, ...
                'Units', 'normalized', 'Position', [0.53 0.04 0.28 0.13], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onSnapModeChanged()));
            uicontrol('Parent', p2, 'Style', 'pushbutton', 'String', '单拍预览', ...
                'FontName', app.FontName, 'FontSize', 8, ...
                'Units', 'normalized', 'Position', [0.82 0.04 0.15 0.13], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onSoftTriggerPreviewOnce()));

            % --- 3. 对焦辅助与参考线 ---
            p3 = uipanel('Parent', pnlLeft, 'Title', ' 3. 调焦与双目对齐辅助 ', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.025 0.265 0.95 0.120]);

            app.ChkOverlay = uicontrol('Parent', p3, 'Style', 'checkbox', ...
                'String', '十字与水平对齐线  间距(px):', 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.03 0.54 0.62 0.36], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.drawPreviewOverlays()));
            app.EdtGridStep = uicontrol('Parent', p3, 'Style', 'edit', 'String', '150', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.66 0.54 0.15 0.36], ...
                'Callback', @(~,~) app.drawPreviewOverlays());
            uicontrol('Parent', p3, 'Style', 'pushbutton', 'String', '测棋盘', ...
                'FontName', app.FontName, 'FontSize', 8, ...
                'Units', 'normalized', 'Position', [0.83 0.53 0.14 0.38], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onCheckBoardNow()));

            app.ChkFocusMeter = uicontrol('Parent', p3, 'Style', 'checkbox', ...
                'String', '实时计算对焦清晰度评分、平均亮度与过曝告警', 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.03 0.10 0.94 0.36], ...
                'Callback', @(src,~) app.withRefocus(src, @() []));

            % --- 4. 图像采集与存盘 ---
            p4 = uipanel('Parent', pnlLeft, 'Title', ' 4. 双目同步采集存盘 (自动分 left / right) ', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.025 0.010 0.95 0.245]);

            uicontrol('Parent', p4, 'Style', 'text', 'String', '目录:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.78 0.12 0.15]);
            app.EdtSaveDir = uicontrol('Parent', p4, 'Style', 'edit', 'String', app.SaveRootDir, ...
                'FontName', app.FontName, 'FontSize', 8, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', [1 1 1], 'Units', 'normalized', 'Position', [0.15 0.78 0.57 0.17], ...
                'Callback', @(~,~) app.onSaveDirEdited());
            uicontrol('Parent', p4, 'Style', 'pushbutton', 'String', '浏览', ...
                'FontName', app.FontName, 'FontSize', 8, ...
                'Units', 'normalized', 'Position', [0.73 0.78 0.12 0.17], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onBrowseSaveDir()));
            uicontrol('Parent', p4, 'Style', 'pushbutton', 'String', '打开', ...
                'FontName', app.FontName, 'FontSize', 8, ...
                'Units', 'normalized', 'Position', [0.86 0.78 0.11 0.17], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onOpenSaveDir()));

            uicontrol('Parent', p4, 'Style', 'text', 'String', '格式:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.56 0.12 0.15]);
            app.PopImgExt = uicontrol('Parent', p4, 'Style', 'popupmenu', ...
                'String', {'.bmp', '.png', '.jpg'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.15 0.57 0.20 0.16], ...
                'Callback', @(src,~) app.withRefocus(src, @() []));

            uicontrol('Parent', p4, 'Style', 'text', 'String', '前缀:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.36 0.56 0.11 0.15]);
            app.EdtPrefixL = uicontrol('Parent', p4, 'Style', 'edit', 'String', 'left_', ...
                'FontName', app.FontName, 'FontSize', 8, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.47 0.57 0.13 0.16]);
            app.EdtPrefixR = uicontrol('Parent', p4, 'Style', 'edit', 'String', 'right_', ...
                'FontName', app.FontName, 'FontSize', 8, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.61 0.57 0.13 0.16]);

            uicontrol('Parent', p4, 'Style', 'text', 'String', '序号:', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.75 0.56 0.11 0.15]);
            app.EdtNextIdx = uicontrol('Parent', p4, 'Style', 'edit', 'String', '1', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.86 0.57 0.11 0.16]);

            app.BtnSnap = uicontrol('Parent', p4, 'Style', 'pushbutton', ...
                'String', '双目同步抓拍保存 (快捷键: 空格 Space)', ...
                'FontName', app.FontName, 'FontSize', 9.5, 'FontWeight', 'bold', ...
                'BackgroundColor', cPrimary, 'ForegroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.03 0.29 0.94 0.23], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onCapturePair(false)));

            uicontrol('Parent', p4, 'Style', 'text', 'String', '间隔(s):', ...
                'FontName', app.FontName, 'FontSize', 8, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.03 0.05 0.16 0.16]);
            app.EdtInterval = uicontrol('Parent', p4, 'Style', 'edit', 'String', '3.0', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.19 0.06 0.12 0.17]);
            app.BtnAutoTimer = uicontrol('Parent', p4, 'Style', 'pushbutton', ...
                'String', '定时连拍', 'FontName', app.FontName, 'FontSize', 8.5, ...
                'BackgroundColor', cOrange, 'ForegroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.33 0.05 0.21 0.19], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onToggleAutoTimer()));
            uicontrol('Parent', p4, 'Style', 'pushbutton', 'String', '撤销上对', ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.56 0.05 0.19 0.19], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onUndoLastPair()));
            uicontrol('Parent', p4, 'Style', 'pushbutton', 'String', '去标定>>', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'FontWeight', 'bold', ...
                'Units', 'normalized', 'Position', [0.77 0.05 0.20 0.19], ...
                'Callback', @(src,~) app.withRefocus(src, @() app.onLaunchCalibApp()));

            % ==================== 右侧预览与抓拍确认区 ====================
            pnlLive = uipanel('Parent', app.Fig, 'Title', ' 实时双目预览视图 ', ...
                'FontName', app.FontName, 'FontSize', 9.5, 'FontWeight', 'bold', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', ...
                'Position', [0.288 0.340 0.705 0.650]);

            app.LblMetricsL = uicontrol('Parent', pnlLive, 'Style', 'text', ...
                'String', '左相机：未开启预览', 'FontName', app.FontName, 'FontSize', 9, ...
                'ForegroundColor', [0.10 0.35 0.65], 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'left', 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.02 0.93 0.46 0.055]);
            app.LblMetricsR = uicontrol('Parent', pnlLive, 'Style', 'text', ...
                'String', '右相机：未开启预览', 'FontName', app.FontName, 'FontSize', 9, ...
                'ForegroundColor', [0.10 0.35 0.65], 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'left', 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.51 0.93 0.47 0.055]);

            app.AxLiveL = axes('Parent', pnlLive, 'Units', 'normalized', 'Position', [0.015 0.02 0.47 0.89]);
            axis(app.AxLiveL, 'off');
            title(app.AxLiveL, '左相机实时画面', 'FontName', app.FontName);

            app.AxLiveR = axes('Parent', pnlLive, 'Units', 'normalized', 'Position', [0.510 0.02 0.47 0.89]);
            axis(app.AxLiveR, 'off');
            title(app.AxLiveR, '右相机实时画面', 'FontName', app.FontName);

            % 下方：最近一次抓拍定格回看与棋盘格预检区
            pnlSnap = uipanel('Parent', app.Fig, 'Title', ' 最近一次抓拍存档 / 棋盘格角点预检视图 ', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', ...
                'Position', [0.288 0.042 0.705 0.290]);

            app.LblSnapInfo = uicontrol('Parent', pnlSnap, 'Style', 'text', ...
                'String', '尚未抓拍图像。开启预览后点击「双目同步抓拍保存」或按键盘空格键即可存盘。', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.02 0.86 0.96 0.12]);

            app.AxSnapL = axes('Parent', pnlSnap, 'Units', 'normalized', 'Position', [0.04 0.04 0.42 0.80]);
            axis(app.AxSnapL, 'off');
            app.AxSnapR = axes('Parent', pnlSnap, 'Units', 'normalized', 'Position', [0.54 0.04 0.42 0.80]);
            axis(app.AxSnapR, 'off');

            % 底部状态栏
            app.LblStatus = uicontrol('Parent', app.Fig, 'Style', 'text', ...
                'String', '  就绪', 'FontName', app.FontName, 'FontSize', 9, ...
                'HorizontalAlignment', 'left', 'BackgroundColor', [0.89 0.91 0.94], ...
                'Units', 'normalized', 'Position', [0.007 0.006 0.986 0.030]);
        end

        function [hSld, hEdt] = createSliderRow(app, parent, yPos, labelStr, minV, maxV, initV, stepVec, cbFcn)
            bg = get(parent, 'BackgroundColor');
            uicontrol('Parent', parent, 'Style', 'text', 'String', labelStr, ...
                'FontName', app.FontName, 'FontSize', 8, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bg, 'Units', 'normalized', 'Position', [0.03 yPos 0.30 0.12]);
            hSld = uicontrol('Parent', parent, 'Style', 'slider', ...
                'Min', minV, 'Max', maxV, 'Value', initV, 'SliderStep', stepVec, ...
                'Units', 'normalized', 'Position', [0.34 yPos 0.45 0.12], ...
                'Callback', @(src, ~) app.withRefocus(src, @() cbFcn(src)));
            hEdt = uicontrol('Parent', parent, 'Style', 'edit', 'String', num2str(initV), ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.81 yPos 0.16 0.13], ...
                'Callback', @(src, ~) cbFcn(src));
        end

        function withRefocus(app, srcCtrl, fnHandle)
        % 执行控件回调后释放按钮/滑块键盘焦点，防止按空格键抓拍时误触发上次点过的按钮
            fnHandle();
            if ~isempty(srcCtrl) && isvalid(srcCtrl) && ~isempty(app.Fig) && isvalid(app.Fig)
                try
                    prevState = get(srcCtrl, 'Enable');
                    if strcmpi(prevState, 'on')
                        set(srcCtrl, 'Enable', 'off');
                        drawnow limitrate;
                        set(srcCtrl, 'Enable', 'on');
                    end
                    figure(app.Fig);
                catch
                end
            end
        end

        % =================================================================
        % 设备枚举与启停预览
        % =================================================================
        function refreshDevices(app, doReset)
            if nargin < 2, doReset = false; end
            if app.IsPreviewing
                warndlg('请先停止当前预览后再刷新相机设备。', '提示');
                return;
            end
            if doReset
                imaqreset;
            end
            info = imaqhwinfo('winvideo');
            n = numel(info.DeviceInfo);
            if n == 0
                app.DeviceList = struct('id', {}, 'name', {}, 'formats', {}, 'defaultFormat', {});
                set(app.PopCamLeft,  'String', {'未检测到相机'}, 'Value', 1);
                set(app.PopCamRight, 'String', {'未检测到相机'}, 'Value', 1);
                app.setStatus('未检测到 winvideo 设备，请检查相机 USB 连接或运行 DShowManager2 注册。');
                return;
            end

            list = repmat(struct('id', 0, 'name', '', 'formats', {{}}, 'defaultFormat', ''), n, 1);
            labels = cell(n, 1);
            for i = 1:n
                di = info.DeviceInfo(i);
                list(i).id = di.DeviceID;
                list(i).name = di.DeviceName;
                list(i).formats = di.SupportedFormats;
                list(i).defaultFormat = di.DefaultFormat;
                labels{i} = sprintf('[ID:%d] %s', di.DeviceID, di.DeviceName);
            end
            app.DeviceList = list;

            set(app.PopCamLeft,  'String', labels, 'Value', 1);
            set(app.PopCamRight, 'String', labels, 'Value', min(2, n));
            app.populateFormats(1);
            app.setStatus(sprintf('检测到 %d 台 winvideo 工业相机。确认分辨率后点击「开启双目实时预览」。', n));
        end

        function populateFormats(app, devIdx)
            if isempty(app.DeviceList) || devIdx > numel(app.DeviceList), return; end
            fmts = app.DeviceList(devIdx).formats;
            if isempty(fmts)
                fmts = {app.DeviceList(devIdx).defaultFormat};
            end
            prefIdx = find(~cellfun(@isempty, strfind(fmts, '2048x1500')), 1);
            if isempty(prefIdx), prefIdx = 1; end
            set(app.PopFormat, 'String', fmts, 'Value', prefIdx);
        end

        function onCameraSelectionChange(app)
            idxL = get(app.PopCamLeft, 'Value');
            app.populateFormats(idxL);
        end

        function onSwapCameras(app)
            if isempty(app.DeviceList) || numel(app.DeviceList) < 2, return; end
            wasRunning = app.IsPreviewing;
            if wasRunning
                app.stopPreview();
            end
            vL = get(app.PopCamLeft, 'Value');
            vR = get(app.PopCamRight, 'Value');
            set(app.PopCamLeft,  'Value', vR);
            set(app.PopCamRight, 'Value', vL);
            tmpP = app.CachedParamsL;
            app.CachedParamsL = app.CachedParamsR;
            app.CachedParamsR = tmpP;
            if wasRunning
                app.startPreview();
            else
                app.setStatus('已互换左右相机序号。');
            end
        end

        function onRoiSizeEdited(app)
            rw = round(str2double(get(app.EdtRoiW, 'String')));
            rh = round(str2double(get(app.EdtRoiH, 'String')));
            if isnan(rw) || rw < 64, rw = 1280; end
            if isnan(rh) || rh < 64, rh = 1024; end
            rw = floor(rw / 4) * 4;
            rh = floor(rh / 4) * 4;
            set(app.EdtRoiW, 'String', num2str(rw));
            set(app.EdtRoiH, 'String', num2str(rh));
            if get(app.ChkCustomROI, 'Value') && app.IsPreviewing
                app.stopPreview();
                app.startPreview();
            end
        end

        function onFormatChange(app)
            if app.IsPreviewing
                app.stopPreview();
                app.startPreview();
            end
        end

        function onTogglePreview(app)
            if app.IsPreviewing
                app.stopPreview();
            else
                app.startPreview();
            end
        end

        function startPreview(app)
            if isempty(app.DeviceList)
                errordlg('未检测到可用相机，请先连接相机并点击「刷新」。', '无相机');
                return;
            end
            idxL = get(app.PopCamLeft, 'Value');
            idxR = get(app.PopCamRight, 'Value');
            if numel(app.DeviceList) >= 2 && idxL == idxR
                errordlg('左相机与右相机选择了同一个设备 ID，请选择两台不同的相机。', '设备冲突');
                return;
            end

            fmtList = get(app.PopFormat, 'String');
            fmtStr  = fmtList{get(app.PopFormat, 'Value')};
            isGray  = (get(app.PopColorSpace, 'Value') == 1);

            set(app.Fig, 'Pointer', 'watch');
            drawnow;
            try
                idL = app.DeviceList(idxL).id;
                app.VidLeft = videoinput('winvideo', idL, fmtStr);
                app.SrcLeft = getselectedsource(app.VidLeft);
                app.configureVideoInput(app.VidLeft, isGray);
                app.FlipStateL = [strcmpi(app.SrcLeft.HorizontalFlip, 'on'), ...
                                  strcmpi(app.SrcLeft.VerticalFlip, 'on')];

                if numel(app.DeviceList) >= 2
                    idR = app.DeviceList(idxR).id;
                    app.VidRight = videoinput('winvideo', idR, fmtStr);
                    app.SrcRight = getselectedsource(app.VidRight);
                    app.configureVideoInput(app.VidRight, isGray);
                    app.FlipStateR = [strcmpi(app.SrcRight.HorizontalFlip, 'on'), ...
                                      strcmpi(app.SrcRight.VerticalFlip, 'on')];
                end

                % 确保默认进入连续流模式 (WB=20)
                set(app.PopSnapMode, 'Value', 1);
                if isprop(app.SrcLeft, 'WhiteBalance'), app.SrcLeft.WhiteBalance = 20; end
                if ~isempty(app.SrcRight) && isprop(app.SrcRight, 'WhiteBalance')
                    app.SrcRight.WhiteBalance = 20;
                end

                % 初始化预览画布句柄并启动 MATLAB 官方底层预览流
                app.HImgLiveL = app.initPreviewAxes(app.AxLiveL, app.VidLeft, isGray);
                preview(app.VidLeft, app.HImgLiveL);

                if ~isempty(app.VidRight)
                    app.HImgLiveR = app.initPreviewAxes(app.AxLiveR, app.VidRight, isGray);
                    preview(app.VidRight, app.HImgLiveR);
                end

                app.IsPreviewing = true;
                set(app.BtnStartStop, 'String', '停止预览并释放相机', 'BackgroundColor', [0.78 0.22 0.20]);

                % 若之前已调过参数(如切换分辨率/ROI重启)，自动恢复用户调好的曝光/增益/翻转；
                % 首次启动若选中「双目同步调节」，则将左相机初始参数配平至右相机
                if ~isempty(app.CachedParamsL)
                    app.applyCachedParams(app.SrcLeft, app.CachedParamsL, true);
                    if ~isempty(app.SrcRight) && ~isempty(app.CachedParamsR)
                        app.applyCachedParams(app.SrcRight, app.CachedParamsR, false);
                    end
                    app.syncSlidersFromHardware();
                elseif get(app.PopTuneTarget, 'Value') == 1 && ~isempty(app.SrcRight)
                    app.syncLeftToRight();
                else
                    app.syncSlidersFromHardware();
                end
                app.drawPreviewOverlays();
                app.startMeterTimer();

                roiL = app.VidLeft.ROIPosition;
                app.setStatus(sprintf('实时预览运行中 | 格式: %s | 实际输出尺寸: %d x %d | 按【空格键】可快速同步抓拍。', ...
                    fmtStr, roiL(3), roiL(4)));
            catch ME
                app.stopPreview();
                errordlg(ME.message, '开启预览失败');
            end
            if isvalid(app.Fig), set(app.Fig, 'Pointer', 'arrow'); end
        end

        function configureVideoInput(app, vid, isGray)
            if isGray
                vid.ReturnedColorSpace = 'grayscale';
            else
                vid.ReturnedColorSpace = 'rgb';
            end
            if get(app.ChkCustomROI, 'Value')
                res = vid.VideoResolution; % [W, H]
                maxW = res(1);
                maxH = res(2);
                rw = round(str2double(get(app.EdtRoiW, 'String')));
                rh = round(str2double(get(app.EdtRoiH, 'String')));
                if ~isnan(rw) && ~isnan(rh) && rw >= 64 && rh >= 64
                    rw = min(floor(rw / 4) * 4, maxW);
                    rh = min(floor(rh / 4) * 4, maxH);
                    ox = floor((maxW - rw) / 4) * 2;
                    oy = floor((maxH - rh) / 4) * 2;
                    vid.ROIPosition = [ox, oy, rw, rh];
                    set(app.EdtRoiW, 'String', num2str(rw));
                    set(app.EdtRoiH, 'String', num2str(rh));
                end
            end
        end

        function hImg = initPreviewAxes(~, ax, vid, isGray)
            cla(ax, 'reset');
            roi = vid.ROIPosition; % [x, y, w, h]
            w = roi(3);
            h = roi(4);
            if isGray
                blank = zeros(h, w, 'uint8');
                hImg = image(blank, 'Parent', ax, 'CDataMapping', 'scaled');
                colormap(ax, gray(256));
                set(ax, 'CLim', [0 255]);
            else
                blank = zeros(h, w, 3, 'uint8');
                hImg = image(blank, 'Parent', ax);
            end
            axis(ax, 'image');
            axis(ax, 'off');
        end

        function stopPreview(app)
            app.stopAutoTimer();
            app.stopMeterTimer();

            % 缓存用户已调好的曝光/增益/翻转，切换分辨率或 ROI 重启时不丢失
            if ~isempty(app.SrcLeft) && isvalid(app.SrcLeft)
                app.CachedParamsL = app.readSrcParams(app.SrcLeft, app.FlipStateL);
            end
            if ~isempty(app.SrcRight) && isvalid(app.SrcRight)
                app.CachedParamsR = app.readSrcParams(app.SrcRight, app.FlipStateR);
            end

            % 关闭前恢复相机默认连续模式 (WB=20)，防止外部软件打开时停在触发态不出图
            if ~isempty(app.SrcLeft) && isvalid(app.SrcLeft) && isprop(app.SrcLeft, 'WhiteBalance')
                try app.SrcLeft.WhiteBalance = 20; catch, end
            end
            if ~isempty(app.SrcRight) && isvalid(app.SrcRight) && isprop(app.SrcRight, 'WhiteBalance')
                try app.SrcRight.WhiteBalance = 20; catch, end
            end

            if ~isempty(app.VidLeft) && isvalid(app.VidLeft)
                try closepreview(app.VidLeft); catch, end
                try stop(app.VidLeft); catch, end
                try delete(app.VidLeft); catch, end
            end
            if ~isempty(app.VidRight) && isvalid(app.VidRight)
                try closepreview(app.VidRight); catch, end
                try stop(app.VidRight); catch, end
                try delete(app.VidRight); catch, end
            end
            app.VidLeft = [];
            app.VidRight = [];
            app.SrcLeft = [];
            app.SrcRight = [];
            app.HImgLiveL = [];
            app.HImgLiveR = [];
            app.IsPreviewing = false;

            if ~isempty(app.BtnStartStop) && isvalid(app.BtnStartStop)
                set(app.BtnStartStop, 'String', '开启双目实时预览', 'BackgroundColor', [0.15 0.60 0.40]);
                set(app.LblMetricsL, 'String', '左相机：已停止', 'ForegroundColor', [0.10 0.35 0.65]);
                set(app.LblMetricsR, 'String', '右相机：已停止', 'ForegroundColor', [0.10 0.35 0.65]);
                app.setStatus('预览已停止，相机硬件句柄已安全释放。');
            end
        end

        % =================================================================
        % 硬件参数同步与调节
        % =================================================================
        function st = readSrcParams(~, src, flipVec)
            st = struct('Brightness', 150, 'Gain', 1, 'Gamma', 100, 'Contrast', 100, 'Flip', flipVec);
            try
                if isprop(src, 'Brightness'), st.Brightness = double(src.Brightness); end
                if isprop(src, 'Gain'),       st.Gain       = double(src.Gain);       end
                if isprop(src, 'Gamma'),      st.Gamma      = double(src.Gamma);      end
                if isprop(src, 'Contrast'),   st.Contrast   = double(src.Contrast);   end
            catch
            end
        end

        function applyCachedParams(app, src, st, isLeft)
            if isempty(src) || ~isvalid(src) || isempty(st), return; end
            try
                if isprop(src, 'Brightness'), src.Brightness = st.Brightness; end
                if isprop(src, 'Gain'),       src.Gain       = st.Gain;       end
                if isprop(src, 'Gamma'),      src.Gamma      = st.Gamma;      end
                if isprop(src, 'Contrast'),   src.Contrast   = st.Contrast;   end
                if isprop(src, 'WhiteBalance')
                    if st.Flip(1), src.WhiteBalance = 12; else, src.WhiteBalance = 11; end
                    if st.Flip(2), src.WhiteBalance = 14; else, src.WhiteBalance = 13; end
                end
                if isLeft
                    app.FlipStateL = st.Flip;
                else
                    app.FlipStateR = st.Flip;
                end
            catch
            end
        end

        function srcs = getTargetSources(app)
            srcs = {};
            if ~app.IsPreviewing, return; end
            mode = get(app.PopTuneTarget, 'Value');
            if (mode == 1 || mode == 2) && ~isempty(app.SrcLeft) && isvalid(app.SrcLeft)
                srcs{end+1} = app.SrcLeft;
            end
            if (mode == 1 || mode == 3) && ~isempty(app.SrcRight) && isvalid(app.SrcRight)
                srcs{end+1} = app.SrcRight;
            end
        end

        function syncLeftToRight(app)
            if ~app.IsPreviewing || isempty(app.SrcLeft) || isempty(app.SrcRight)
                return;
            end
            try
                if isprop(app.SrcLeft, 'Brightness')
                    app.SrcRight.Brightness = app.SrcLeft.Brightness;
                end
                if isprop(app.SrcLeft, 'Gain')
                    app.SrcRight.Gain = app.SrcLeft.Gain;
                end
                if isprop(app.SrcLeft, 'Gamma')
                    app.SrcRight.Gamma = app.SrcLeft.Gamma;
                end
                if isprop(app.SrcLeft, 'Contrast')
                    app.SrcRight.Contrast = app.SrcLeft.Contrast;
                end
                if isprop(app.SrcRight, 'WhiteBalance')
                    if app.FlipStateL(1), app.SrcRight.WhiteBalance = 12; else, app.SrcRight.WhiteBalance = 11; end
                    if app.FlipStateL(2), app.SrcRight.WhiteBalance = 14; else, app.SrcRight.WhiteBalance = 13; end
                    app.FlipStateR = app.FlipStateL;
                end
                app.syncSlidersFromHardware();
                app.setStatus('已将左相机的曝光、增益、伽马、对比度及翻转状态完整同步至右相机。');
            catch
            end
        end

        function syncSlidersFromHardware(app)
            if ~app.IsPreviewing, return; end
            mode = get(app.PopTuneTarget, 'Value');
            refSrc = app.SrcLeft;
            refFlip = app.FlipStateL;
            if mode == 3 && ~isempty(app.SrcRight)
                refSrc = app.SrcRight;
                refFlip = app.FlipStateR;
            end
            if isempty(refSrc) || ~isvalid(refSrc), return; end

            app.IsUpdatingControls = true;
            try
                if isprop(refSrc, 'Brightness')
                    v = double(refSrc.Brightness);
                    set(app.SldExposure, 'Value', min(max(v, 1), 10000));
                    set(app.EdtExposure, 'String', num2str(v));
                end
                if isprop(refSrc, 'Gain')
                    v = double(refSrc.Gain);
                    set(app.SldGain, 'Value', min(max(v, 0), 200));
                    set(app.EdtGain, 'String', num2str(v));
                end
                if isprop(refSrc, 'Gamma')
                    v = double(refSrc.Gamma);
                    set(app.SldGamma, 'Value', min(max(v, 0), 200));
                    set(app.EdtGamma, 'String', num2str(v));
                end
                if isprop(refSrc, 'Contrast')
                    v = double(refSrc.Contrast);
                    set(app.SldContrast, 'Value', min(max(v, 0), 200));
                    set(app.EdtContrast, 'String', num2str(v));
                end
                set(app.ChkFlipH, 'Value', logical(refFlip(1)));
                set(app.ChkFlipV, 'Value', logical(refFlip(2)));
            catch
            end
            app.IsUpdatingControls = false;
        end

        function val = readAndSyncSliderEdit(app, srcCtrl, hSld, hEdt, minV, maxV)
            if srcCtrl == hSld
                val = round(get(hSld, 'Value'));
            else
                val = round(str2double(get(hEdt, 'String')));
                if isnan(val), val = round(get(hSld, 'Value')); end
            end
            val = min(max(val, minV), maxV);
            app.IsUpdatingControls = true;
            set(hSld, 'Value', val);
            set(hEdt, 'String', num2str(val));
            app.IsUpdatingControls = false;
        end

        function onExposureChanged(app, srcCtrl)
            if app.IsUpdatingControls, return; end
            val = app.readAndSyncSliderEdit(srcCtrl, app.SldExposure, app.EdtExposure, 1, 10000);
            srcs = app.getTargetSources();
            for i = 1:numel(srcs)
                if isprop(srcs{i}, 'Brightness'), srcs{i}.Brightness = val; end
            end
        end

        function onGainChanged(app, srcCtrl)
            if app.IsUpdatingControls, return; end
            val = app.readAndSyncSliderEdit(srcCtrl, app.SldGain, app.EdtGain, 0, 200);
            srcs = app.getTargetSources();
            for i = 1:numel(srcs)
                if isprop(srcs{i}, 'Gain'), srcs{i}.Gain = val; end
            end
        end

        function onGammaChanged(app, srcCtrl)
            if app.IsUpdatingControls, return; end
            val = app.readAndSyncSliderEdit(srcCtrl, app.SldGamma, app.EdtGamma, 0, 200);
            srcs = app.getTargetSources();
            for i = 1:numel(srcs)
                if isprop(srcs{i}, 'Gamma'), srcs{i}.Gamma = val; end
            end
        end

        function onContrastChanged(app, srcCtrl)
            if app.IsUpdatingControls, return; end
            val = app.readAndSyncSliderEdit(srcCtrl, app.SldContrast, app.EdtContrast, 0, 200);
            srcs = app.getTargetSources();
            for i = 1:numel(srcs)
                if isprop(srcs{i}, 'Contrast'), srcs{i}.Contrast = val; end
            end
        end

        function onFlipHChanged(app)
        % 使用京航官方 WhiteBalance=12(水平镜像) / 11(水平不镜像)，预览流下零驱动警告且不干扰垂直状态
            if app.IsUpdatingControls || ~app.IsPreviewing, return; end
            flag = logical(get(app.ChkFlipH, 'Value'));
            wbCmd = 11; if flag, wbCmd = 12; end
            mode = get(app.PopTuneTarget, 'Value');
            if (mode == 1 || mode == 2) && ~isempty(app.SrcLeft) && isprop(app.SrcLeft, 'WhiteBalance')
                app.SrcLeft.WhiteBalance = wbCmd;
                app.FlipStateL(1) = flag;
            end
            if (mode == 1 || mode == 3) && ~isempty(app.SrcRight) && isprop(app.SrcRight, 'WhiteBalance')
                app.SrcRight.WhiteBalance = wbCmd;
                app.FlipStateR(1) = flag;
            end
        end

        function onFlipVChanged(app)
        % 使用京航官方 WhiteBalance=14(垂直镜像) / 13(垂直不镜像)，预览流下零驱动警告且不干扰水平状态
            if app.IsUpdatingControls || ~app.IsPreviewing, return; end
            flag = logical(get(app.ChkFlipV, 'Value'));
            wbCmd = 13; if flag, wbCmd = 14; end
            mode = get(app.PopTuneTarget, 'Value');
            if (mode == 1 || mode == 2) && ~isempty(app.SrcLeft) && isprop(app.SrcLeft, 'WhiteBalance')
                app.SrcLeft.WhiteBalance = wbCmd;
                app.FlipStateL(2) = flag;
            end
            if (mode == 1 || mode == 3) && ~isempty(app.SrcRight) && isprop(app.SrcRight, 'WhiteBalance')
                app.SrcRight.WhiteBalance = wbCmd;
                app.FlipStateR(2) = flag;
            end
        end

        function onSnapModeChanged(app)
            if ~app.IsPreviewing, return; end
            wbCmd = 20; % 20 = 连续模式, 21 = 触发模式 (见京航 AN019 手册)
            if get(app.PopSnapMode, 'Value') == 2
                wbCmd = 21;
            end
            if ~isempty(app.SrcLeft) && isprop(app.SrcLeft, 'WhiteBalance')
                app.SrcLeft.WhiteBalance = wbCmd;
            end
            if ~isempty(app.SrcRight) && isprop(app.SrcRight, 'WhiteBalance')
                app.SrcRight.WhiteBalance = wbCmd;
            end
            if wbCmd == 21
                app.setStatus('已切至【触发流模式 (WB=21)】：画面暂停自由刷新，点击「单拍预览」或「抓拍保存」触发同步曝光。');
            else
                app.setStatus('已切回【连续流模式 (WB=20)】：双目自由实时刷新。');
            end
        end

        function onSoftTriggerPreviewOnce(app)
            if ~app.IsPreviewing, return; end
            if get(app.PopSnapMode, 'Value') ~= 2
                app.setStatus('当前已是连续流模式，画面正在实时刷新；仅触发流(WB=21)下需手动单拍刷新。');
                return;
            end
            app.fireSimultaneousSoftTrigger();
            app.updateLiveMetrics();
            app.setStatus('已发送双目同步软触发脉冲 (WB=22) 并刷新画面。');
        end

        function fireSimultaneousSoftTrigger(app)
        % 紧邻向左右相机写入 WB=0 -> WB=22 同步曝光，并按当前曝光时间等待帧传输至预览缓冲
            expUnits = 150;
            if ~isempty(app.SrcLeft) && isprop(app.SrcLeft, 'Brightness')
                expUnits = max(expUnits, double(app.SrcLeft.Brightness));
            end
            if ~isempty(app.SrcRight) && isprop(app.SrcRight, 'Brightness')
                expUnits = max(expUnits, double(app.SrcRight.Brightness));
            end
            if ~isempty(app.SrcLeft) && isprop(app.SrcLeft, 'WhiteBalance')
                app.SrcLeft.WhiteBalance = 0;
            end
            if ~isempty(app.SrcRight) && isprop(app.SrcRight, 'WhiteBalance')
                app.SrcRight.WhiteBalance = 0;
            end
            if ~isempty(app.SrcLeft) && isprop(app.SrcLeft, 'WhiteBalance')
                app.SrcLeft.WhiteBalance = 22;
            end
            if ~isempty(app.SrcRight) && isprop(app.SrcRight, 'WhiteBalance')
                app.SrcRight.WhiteBalance = 22;
            end
            waitSec = min(2.0, max(0.12, expUnits * 1e-4 + 0.08));
            pause(waitSec);
            drawnow;
        end

        % =================================================================
        % 叠加对齐网格与实时清晰度对焦评估
        % =================================================================
        function drawPreviewOverlays(app)
            app.clearOverlayGroup(app.AxLiveL);
            app.clearOverlayGroup(app.AxLiveR);
            if ~app.IsPreviewing || ~get(app.ChkOverlay, 'Value'), return; end

            step = round(str2double(get(app.EdtGridStep, 'String')));
            if isnan(step) || step < 20, step = 150; end
            set(app.EdtGridStep, 'String', num2str(step));

            app.drawGridOnAxes(app.AxLiveL, app.VidLeft, step);
            if ~isempty(app.VidRight)
                app.drawGridOnAxes(app.AxLiveR, app.VidRight, step);
            end
        end

        function clearOverlayGroup(~, ax)
            if ~isempty(ax) && isvalid(ax)
                delete(findobj(ax, 'Tag', 'AlignOverlay'));
            end
        end

        function drawGridOnAxes(~, ax, vid, step)
            roi = vid.ROIPosition;
            W = roi(3);
            H = roi(4);
            hold(ax, 'on');
            for y = step:step:(H - 1)
                plot(ax, [1, W], [y, y], 'g:', 'LineWidth', 0.8, ...
                    'Tag', 'AlignOverlay', 'HitTest', 'off', 'PickableParts', 'none');
            end
            cx = W / 2;
            cy = H / 2;
            plot(ax, [1, W], [cy, cy], 'y-', 'LineWidth', 1.1, ...
                'Tag', 'AlignOverlay', 'HitTest', 'off', 'PickableParts', 'none');
            plot(ax, [cx, cx], [1, H], 'y-', 'LineWidth', 1.1, ...
                'Tag', 'AlignOverlay', 'HitTest', 'off', 'PickableParts', 'none');
            hold(ax, 'off');
        end

        function startMeterTimer(app)
            app.stopMeterTimer();
            app.MeterTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.45, ...
                'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) app.updateLiveMetrics());
            start(app.MeterTimer);
        end

        function stopMeterTimer(app)
            if ~isempty(app.MeterTimer) && isvalid(app.MeterTimer)
                try stop(app.MeterTimer); catch, end
                try delete(app.MeterTimer); catch, end
            end
            app.MeterTimer = [];
        end

        function updateLiveMetrics(app)
            if ~app.IsPreviewing || ~isvalid(app.Fig) || ~get(app.ChkFocusMeter, 'Value')
                return;
            end
            try
                if ~isempty(app.HImgLiveL) && isvalid(app.HImgLiveL)
                    imgL = get(app.HImgLiveL, 'CData');
                    [strL, overL] = app.calcFrameStats(imgL);
                    cL = [0.10 0.35 0.65]; if overL > 1.0, cL = [0.82 0.12 0.12]; end
                    set(app.LblMetricsL, 'String', ['左相机 | ' strL], 'ForegroundColor', cL);
                end
                if ~isempty(app.HImgLiveR) && isvalid(app.HImgLiveR)
                    imgR = get(app.HImgLiveR, 'CData');
                    [strR, overR] = app.calcFrameStats(imgR);
                    cR = [0.10 0.35 0.65]; if overR > 1.0, cR = [0.82 0.12 0.12]; end
                    set(app.LblMetricsR, 'String', ['右相机 | ' strR], 'ForegroundColor', cR);
                end
            catch
            end
        end

        function [s, overPct] = calcFrameStats(~, img)
            overPct = 0;
            if isempty(img)
                s = '等待帧数据...';
                return;
            end
            if size(img, 3) == 3
                g = img(:, :, 2);
            else
                g = img;
            end
            [H, W] = size(g);
            r1 = max(1, round(H * 0.15)); r2 = min(H, round(H * 0.85));
            c1 = max(1, round(W * 0.15)); c2 = min(W, round(W * 0.85));
            sub = double(g(r1:2:r2, c1:2:c2));
            if max(sub(:)) == 0
                s = '等待首帧曝光...';
                return;
            end
            gx = diff(sub, 1, 2);
            gy = diff(sub, 1, 1);
            nMinR = min(size(gx, 1), size(gy, 1));
            nMinC = min(size(gx, 2), size(gy, 2));
            sharp = mean(mean(hypot(gx(1:nMinR, 1:nMinC), gy(1:nMinR, 1:nMinC))));
            meanVal = mean(sub(:));
            overPct = 100 * mean(sub(:) >= 252);
            if overPct > 1.0
                s = sprintf('清晰度: %.1f | 均值: %.1f | 过曝告警: %.1f%%', sharp, meanVal, overPct);
            else
                s = sprintf('清晰度: %.1f (拧焦冲高) | 均值: %.1f | 过曝: %.2f%%', sharp, meanVal, overPct);
            end
        end

        % =================================================================
        % 棋盘格可视化预检 & 亚毫秒级双目同步抓拍存盘
        % =================================================================
        function onCheckBoardNow(app)
            if ~app.IsPreviewing
                warndlg('请先开启相机预览。', '提示');
                return;
            end
            if isempty(which('detectCheckerboardPoints'))
                warndlg('未检测到 Computer Vision System Toolbox，无法预检棋盘格。', '提示');
                return;
            end
            app.setStatus('正在抓帧并检测双目棋盘格角点...');
            try
                [IL, IR] = app.grabCurrentPair();
                cla(app.AxSnapL); imshow(IL, 'Parent', app.AxSnapL); hold(app.AxSnapL, 'on');
                if ~isempty(IR)
                    cla(app.AxSnapR); imshow(IR, 'Parent', app.AxSnapR); hold(app.AxSnapR, 'on');
                    [pts, bSz] = detectCheckerboardPoints(IL, IR);
                    ok = ~isempty(pts) && size(pts, 4) == 2;
                    if ok
                        pL = pts(:, :, 1, 1); pR = pts(:, :, 1, 2);
                        plot(app.AxSnapL, pL(:,1), pL(:,2), 'g+', 'MarkerSize', 5);
                        plot(app.AxSnapL, pL(1,1), pL(1,2), 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);
                        plot(app.AxSnapR, pR(:,1), pR(:,2), 'g+', 'MarkerSize', 5);
                        plot(app.AxSnapR, pR(1,1), pR(1,2), 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);
                    end
                    hold(app.AxSnapR, 'off');
                else
                    [pts, bSz] = detectCheckerboardPoints(IL);
                    ok = ~isempty(pts);
                    if ok
                        plot(app.AxSnapL, pts(:,1), pts(:,2), 'g+', 'MarkerSize', 5);
                        plot(app.AxSnapL, pts(1,1), pts(1,2), 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);
                    end
                end
                hold(app.AxSnapL, 'off');

                if ok
                    msg = sprintf('预检通过：双目完整检出棋盘格 (%dx%d 方格，内角点 %dx%d)，角点已标在下视图！', ...
                        bSz(1), bSz(2), bSz(1)-1, bSz(2)-1);
                    title(app.AxSnapL, '预检左图 (检出通过)', 'FontName', app.FontName, 'FontSize', 8.5);
                    if ~isempty(IR)
                        title(app.AxSnapR, '预检右图 (检出通过)', 'FontName', app.FontName, 'FontSize', 8.5);
                    end
                    set(app.LblSnapInfo, 'String', msg);
                    app.setStatus(msg);
                else
                    msg = '预检未通过：未在左右画面同时检出完整棋盘格，请调整倾角、视野或减小曝光消除反光。';
                    title(app.AxSnapL, '预检左图 (未同时检出)', 'FontName', app.FontName, 'FontSize', 8.5);
                    if ~isempty(IR)
                        title(app.AxSnapR, '预检右图 (未同时检出)', 'FontName', app.FontName, 'FontSize', 8.5);
                    end
                    set(app.LblSnapInfo, 'String', msg);
                    app.setStatus(msg);
                end
            catch ME
                errordlg(ME.message, '检测异常');
            end
        end

        function [IL, IR] = grabCurrentPair(app)
        % 统一双目同步取帧：
        %   - 触发模式(WB=21): 紧邻向左右相机发 WB=22 同步软触发，等待曝光传输完成后直接读取预览缓冲
        %   - 连续模式(WB=20): 直接同步读取 C++ 预览线程实时更新的全分辨率无损帧缓冲 (<1ms，零左右串行延迟)
            if get(app.PopSnapMode, 'Value') == 2
                app.fireSimultaneousSoftTrigger();
            else
                drawnow;
            end

            IL = [];
            if ~isempty(app.HImgLiveL) && isvalid(app.HImgLiveL)
                IL = get(app.HImgLiveL, 'CData');
            end
            if isempty(IL) || max(IL(:)) == 0
                IL = getsnapshot(app.VidLeft);
            end

            IR = [];
            if ~isempty(app.VidRight)
                if ~isempty(app.HImgLiveR) && isvalid(app.HImgLiveR)
                    IR = get(app.HImgLiveR, 'CData');
                end
                if isempty(IR) || max(IR(:)) == 0
                    IR = getsnapshot(app.VidRight);
                end
            end
        end

        function onCapturePair(app, fromAutoTimer)
            if nargin < 2, fromAutoTimer = false; end
            if ~app.IsPreviewing
                warndlg('请先点击「开启双目实时预览」后再执行抓拍。', '未开启预览');
                return;
            end
            rootDir = strtrim(get(app.EdtSaveDir, 'String'));
            if isempty(rootDir)
                errordlg('保存目录不能为空。', '路径错误');
                return;
            end
            app.SaveRootDir = rootDir;
            leftDir  = fullfile(rootDir, 'left');
            rightDir = fullfile(rootDir, 'right');
            if ~exist(leftDir, 'dir'),  mkdir(leftDir);  end
            if ~exist(rightDir, 'dir'), mkdir(rightDir); end

            exts = get(app.PopImgExt, 'String');
            ext  = exts{get(app.PopImgExt, 'Value')};
            preL = strtrim(get(app.EdtPrefixL, 'String'));
            preR = strtrim(get(app.EdtPrefixR, 'String'));
            idx  = round(str2double(get(app.EdtNextIdx, 'String')));
            if isnan(idx) || idx < 1, idx = 1; end

            fL = fullfile(leftDir,  sprintf('%s%02d%s', preL, idx, ext));
            fR = fullfile(rightDir, sprintf('%s%02d%s', preR, idx, ext));

            % 防误覆盖保护 (手动抓拍且目标序号文件已存在时询问)
            if ~fromAutoTimer && (exist(fL, 'file') == 2 || (~isempty(app.VidRight) && exist(fR, 'file') == 2))
                choice = questdlg(sprintf('序号 #%02d 的图像文件已存在，是否覆盖？', idx), ...
                    '文件已存在', '跳至末尾新序号', '覆盖当前序号', '取消', '跳至末尾新序号');
                if isempty(choice) || strcmp(choice, '取消')
                    return;
                elseif strcmp(choice, '跳至末尾新序号')
                    app.syncNextCaptureIndex();
                    idx = app.CaptureIndex;
                    fL = fullfile(leftDir,  sprintf('%s%02d%s', preL, idx, ext));
                    fR = fullfile(rightDir, sprintf('%s%02d%s', preR, idx, ext));
                end
            end

            t0 = tic;
            try
                [IL, IR] = app.grabCurrentPair();
                imwrite(IL, fL);
                if ~isempty(IR)
                    imwrite(IR, fR);
                else
                    fR = '';
                end

                % 压入多级撤销历史栈
                rec = struct('idx', idx, 'left', fL, 'right', fR);
                app.SavedHistory(end + 1) = rec;

                % 更新下方定格缩略图确认
                cla(app.AxSnapL); imshow(IL, 'Parent', app.AxSnapL);
                title(app.AxSnapL, sprintf('已存左图 #%02d (%dx%d)', idx, size(IL,2), size(IL,1)), ...
                    'FontName', app.FontName, 'FontSize', 8.5);
                if ~isempty(IR)
                    cla(app.AxSnapR); imshow(IR, 'Parent', app.AxSnapR);
                    title(app.AxSnapR, sprintf('已存右图 #%02d (%dx%d)', idx, size(IR,2), size(IR,1)), ...
                        'FontName', app.FontName, 'FontSize', 8.5);
                end

                dtMs = toc(t0) * 1000;
                set(app.LblSnapInfo, 'String', sprintf('已保存第 #%02d 对 (耗时 %.1f ms, 可撤销栈 %d 对):  %s', ...
                    idx, dtMs, numel(app.SavedHistory), fL));
                app.setStatus(sprintf('抓拍成功 [#%02d] -> %s', idx, rootDir));
                beep;

                app.CaptureIndex = idx + 1;
                set(app.EdtNextIdx, 'String', num2str(app.CaptureIndex));
            catch ME
                errordlg(ME.message, '抓拍保存失败');
            end
        end

        function onWindowKeyPress(app, ~, evt)
        % 窗口级全局空格键抓拍 (仅当焦点在 edit 文本输入框打字时放行)
            if strcmp(evt.Key, 'space') && app.IsPreviewing
                curObj = get(app.Fig, 'CurrentObject');
                if ~isempty(curObj) && isvalid(curObj) && isprop(curObj, 'Style') ...
                        && strcmpi(get(curObj, 'Style'), 'edit')
                    return;
                end
                app.onCapturePair(false);
            end
        end

        function onToggleAutoTimer(app)
            if ~isempty(app.AutoSnapTimer) && isvalid(app.AutoSnapTimer)
                app.stopAutoTimer();
                app.setStatus('已停止定时自动连拍。');
                return;
            end
            if ~app.IsPreviewing
                warndlg('请先开启双目实时预览。', '提示');
                return;
            end
            sec = str2double(get(app.EdtInterval, 'String'));
            if isnan(sec) || sec < 0.5
                errordlg('连拍间隔请设为 >= 0.5 秒的数值。', '参数错误');
                return;
            end
            app.AutoSnapTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', sec, ...
                'StartDelay', sec, ...
                'TimerFcn', @(~,~) app.onCapturePair(true));
            start(app.AutoSnapTimer);
            set(app.BtnAutoTimer, 'String', '停止连拍', 'BackgroundColor', [0.78 0.22 0.20]);
            app.setStatus(sprintf('定时自动连拍已开启：每隔 %.1f 秒自动抓拍保存一对图像...', sec));
        end

        function stopAutoTimer(app)
            if ~isempty(app.AutoSnapTimer) && isvalid(app.AutoSnapTimer)
                try stop(app.AutoSnapTimer); catch, end
                try delete(app.AutoSnapTimer); catch, end
            end
            app.AutoSnapTimer = [];
            if ~isempty(app.BtnAutoTimer) && isvalid(app.BtnAutoTimer)
                set(app.BtnAutoTimer, 'String', '定时连拍', 'BackgroundColor', [0.85 0.45 0.12]);
            end
        end

        function onUndoLastPair(app)
            if isempty(app.SavedHistory)
                warndlg('当前会话没有可撤销的抓拍记录。', '提示');
                return;
            end
            rec = app.SavedHistory(end);
            app.SavedHistory(end) = [];

            if ~isempty(rec.left) && exist(rec.left, 'file') == 2
                delete(rec.left);
            end
            if ~isempty(rec.right) && exist(rec.right, 'file') == 2
                delete(rec.right);
            end
            app.CaptureIndex = rec.idx;
            set(app.EdtNextIdx, 'String', num2str(rec.idx));

            % 若栈内仍有上一对，回显上一对缩略图；否则清空
            if ~isempty(app.SavedHistory) && exist(app.SavedHistory(end).left, 'file') == 2
                prev = app.SavedHistory(end);
                cla(app.AxSnapL); imshow(imread(prev.left), 'Parent', app.AxSnapL);
                title(app.AxSnapL, sprintf('已存左图 #%02d', prev.idx), 'FontName', app.FontName, 'FontSize', 8.5);
                if ~isempty(prev.right) && exist(prev.right, 'file') == 2
                    cla(app.AxSnapR); imshow(imread(prev.right), 'Parent', app.AxSnapR);
                    title(app.AxSnapR, sprintf('已存右图 #%02d', prev.idx), 'FontName', app.FontName, 'FontSize', 8.5);
                end
            else
                cla(app.AxSnapL); axis(app.AxSnapL, 'off');
                cla(app.AxSnapR); axis(app.AxSnapR, 'off');
            end
            set(app.LblSnapInfo, 'String', sprintf('已撤销并删除 #%02d 对，剩余可撤销 %d 对，下次序号回退至 #%02d。', ...
                rec.idx, numel(app.SavedHistory), rec.idx));
            app.setStatus(sprintf('已删除第 #%02d 对图像，下次抓拍序号为 #%02d。', rec.idx, rec.idx));
        end

        % =================================================================
        % 目录管理与一键联动 StereoCalibApp
        % =================================================================
        function onSaveDirEdited(app)
            app.SaveRootDir = strtrim(get(app.EdtSaveDir, 'String'));
            app.SavedHistory = struct('idx', {}, 'left', {}, 'right', {});
            app.syncNextCaptureIndex();
        end

        function onBrowseSaveDir(app)
            d = uigetdir(app.SaveRootDir, '选择双目采集保存根目录');
            if isequal(d, 0), return; end
            app.SaveRootDir = d;
            app.SavedHistory = struct('idx', {}, 'left', {}, 'right', {});
            set(app.EdtSaveDir, 'String', d);
            app.syncNextCaptureIndex();
        end

        function onOpenSaveDir(app)
            d = strtrim(get(app.EdtSaveDir, 'String'));
            if ~exist(d, 'dir'), mkdir(d); end
            if ispc
                winopen(d);
            end
        end

        function syncNextCaptureIndex(app)
            leftDir = fullfile(app.SaveRootDir, 'left');
            maxNum = 0;
            if exist(leftDir, 'dir')
                files = dir(leftDir);
                for i = 1:numel(files)
                    if files(i).isdir, continue; end
                    tok = regexp(files(i).name, '(\d+)', 'tokens');
                    if ~isempty(tok)
                        v = str2double(tok{end}{1});
                        if ~isnan(v) && v > maxNum, maxNum = v; end
                    end
                end
            end
            app.CaptureIndex = maxNum + 1;
            if ~isempty(app.EdtNextIdx) && isvalid(app.EdtNextIdx)
                set(app.EdtNextIdx, 'String', num2str(app.CaptureIndex));
            end
        end

        function onLaunchCalibApp(app)
            if isempty(which('StereoCalibApp'))
                warndlg('未在当前路径下找到 StereoCalibApp.m。', '提示');
                return;
            end
            leftDir  = fullfile(app.SaveRootDir, 'left');
            rightDir = fullfile(app.SaveRootDir, 'right');
            calibApp = StereoCalibApp();
            if exist(leftDir, 'dir') && exist(rightDir, 'dir')
                try
                    calibApp.loadStereoFolders(leftDir, rightDir);
                    app.setStatus(sprintf('已启动 StereoCalibApp 并自动导入采集图像目录: %s', app.SaveRootDir));
                catch
                    app.setStatus('已启动 StereoCalibApp (当前采集目录尚无成对图像，可采集后再导入)。');
                end
            end
        end

        % =================================================================
        % 清理与状态栏
        % =================================================================
        function setStatus(app, msg)
            if ~isempty(app.LblStatus) && isvalid(app.LblStatus)
                set(app.LblStatus, 'String', ['  ' msg]);
                drawnow limitrate;
            end
        end

        function cleanupAll(app)
            app.stopPreview();
        end

        function onClose(app)
            app.cleanupAll();
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end
    end
end
