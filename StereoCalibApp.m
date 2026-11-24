classdef StereoCalibApp < handle
% STEREOCALIBAPP MATLAB 双目立体标定与精度验证 GUI 系统 (标准棋盘格)
%   兼容 MATLAB R2017b 及以上版本，核心算法全程复用 MATLAB 官方工具箱:
%     - Computer Vision System Toolbox: detectCheckerboardPoints, generateCheckerboardPoints,
%       estimateCameraParameters, showReprojectionErrors, showExtrinsics,
%       rectifyStereoImages, stereoAnaglyph, undistortPoints, epipolarLine,
%       triangulate, disparity, reconstructScene, rotationMatrixToVector
%     - Image Processing Toolbox: imshow, rgb2gray, projective2d, transformPointsForward
%     - Robotics System Toolbox: rotm2eul, eul2rotm
%     - Statistics Toolbox: pdist
%
%   启动方式:
%       app = StereoCalibApp();

    properties (Access = public)
        % 图像文件与检测状态
        LeftFiles = {}
        RightFiles = {}
        ImageSize = []               % [H, W]
        BoardSize = []               % [rows, cols]
        AllImagePoints = []          % M x 2 x N_valid x 2
        DetectedMask = []            % N x 1 logical
        DetectedToOrigIdx = []       % N_valid x 1 映射到原始文件索引
        OrigToDetectedIdx = []       % N x 1 原始索引 -> AllImagePoints 第三维索引 (0表示未检出)
        PairEnabled = []             % N x 1 logical (用户是否启用该对)
        PairErrorMax = []            % N x 1 double (最近一次标定该对 max(左,右) 平均误差)
        CalibOrigIdx = []            % K x 1 最近一次标定实际使用的原始图像对序号
        SelectedPairIdx = 1

        % 标定结果与缓存
        CalibResult = []             % stereo.runCalibration 返回结构体
        RectifiedLeft = []
        RectifiedRight = []
        LastDisparity = []
        LastPoints3D = []
    end

    properties (Access = private)
        Fig
        FontName = 'Microsoft YaHei'

        % 左侧控件
        EdtSquareSize
        PopUnits
        PopRadial
        ChkTangential
        ChkSkew
        EdtErrThresh
        TblPairs
        LblStatus

        % 右侧 Tab 与组件
        TabGroup
        % Tab 1: 角点预览
        AxLeft
        AxRight
        ChkShowQuiver
        EdtQuiverScale
        LblPairInfo

        % Tab 2: 标定参数报告
        TxtParams

        % Tab 3: 误差与 3D 位姿
        AxErrBar
        AxExtrinsics
        PopExtView

        % Tab 4: 极线校正
        AxRect
        PopRectView
        PopRectMode
        EdtLineStep
        LblEpipolarInfo

        % Tab 5: 视差与 3D 测距
        AxDispLeft
        AxDispMap
        PopDispMethod
        EdtDispMin
        EdtDispMax
        EdtBlockSize
        LblMeasureInfo
    end

    methods (Access = public)
        function app = StereoCalibApp()
            if isempty(which('detectCheckerboardPoints')) || isempty(which('estimateCameraParameters'))
                errordlg('未检测到 Computer Vision System Toolbox，无法运行双目标定。', '依赖缺失');
                return;
            end
            app.buildUI();
            app.setStatus('就绪：请加载左右图像文件夹，或点击「生成测试数据」快速体验。');
        end
    end

    methods (Access = private)
        function buildUI(app)
            bgMain   = [0.95 0.96 0.97];
            bgPanel  = [0.98 0.98 0.99];
            cPrimary = [0.13 0.45 0.78];
            cAccent  = [0.16 0.62 0.43];
            cWarn    = [0.85 0.45 0.12];

            app.Fig = figure( ...
                'Name', '双目立体标定系统 (MATLAB Stereo Calibration Suite)', ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'ToolBar', 'figure', ...
                'Color', bgMain, ...
                'Units', 'normalized', ...
                'Position', [0.05 0.06 0.90 0.86], ...
                'CloseRequestFcn', @(~,~) delete(app.Fig));

            % ==================== 左侧控制面板 ====================
            pnlLeft = uipanel('Parent', app.Fig, ...
                'Units', 'normalized', 'Position', [0.008 0.045 0.275 0.945], ...
                'BackgroundColor', bgPanel, 'BorderType', 'line', ...
                'HighlightColor', [0.82 0.85 0.88]);

            % --- 1. 数据加载区 ---
            pnlData = uipanel('Parent', pnlLeft, 'Title', ' 1. 图像数据加载 ', ...
                'FontName', app.FontName, 'FontSize', 9.5, 'FontWeight', 'bold', ...
                'Units', 'normalized', 'Position', [0.03 0.82 0.94 0.165], ...
                'BackgroundColor', bgPanel);

            uicontrol('Parent', pnlData, 'Style', 'pushbutton', ...
                'String', '加载左右文件夹', 'FontName', app.FontName, 'FontSize', 9, ...
                'Units', 'normalized', 'Position', [0.03 0.54 0.45 0.36], ...
                'BackgroundColor', cPrimary, 'ForegroundColor', [1 1 1], 'FontWeight', 'bold', ...
                'Callback', @(~,~) app.onLoadSeparate());

            uicontrol('Parent', pnlData, 'Style', 'pushbutton', ...
                'String', '加载左右拼接图', 'FontName', app.FontName, 'FontSize', 9, ...
                'Units', 'normalized', 'Position', [0.52 0.54 0.45 0.36], ...
                'Callback', @(~,~) app.onLoadSideBySide());

            uicontrol('Parent', pnlData, 'Style', 'pushbutton', ...
                'String', '生成测试数据 (Demo)', 'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.03 0.10 0.45 0.34], ...
                'Callback', @(~,~) app.onGenerateDemo());

            uicontrol('Parent', pnlData, 'Style', 'pushbutton', ...
                'String', '导入已有 .mat 参数', 'FontName', app.FontName, 'FontSize', 8.5, ...
                'Units', 'normalized', 'Position', [0.52 0.10 0.45 0.34], ...
                'Callback', @(~,~) app.onLoadMatParams());

            % --- 2. 标定板与模型配置 ---
            pnlCfg = uipanel('Parent', pnlLeft, 'Title', ' 2. 标定板与镜头模型 ', ...
                'FontName', app.FontName, 'FontSize', 9.5, 'FontWeight', 'bold', ...
                'Units', 'normalized', 'Position', [0.03 0.59 0.94 0.22], ...
                'BackgroundColor', bgPanel);

            uicontrol('Parent', pnlCfg, 'Style', 'text', 'String', '方格边长:', ...
                'FontName', app.FontName, 'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.04 0.74 0.28 0.18]);
            app.EdtSquareSize = uicontrol('Parent', pnlCfg, 'Style', 'edit', 'String', '25', ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.34 0.74 0.30 0.20]);
            app.PopUnits = uicontrol('Parent', pnlCfg, 'Style', 'popupmenu', ...
                'String', {'mm', 'cm', 'm'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 9, ...
                'Units', 'normalized', 'Position', [0.68 0.74 0.28 0.20]);

            uicontrol('Parent', pnlCfg, 'Style', 'text', 'String', '径向畸变:', ...
                'FontName', app.FontName, 'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.04 0.48 0.28 0.18]);
            app.PopRadial = uicontrol('Parent', pnlCfg, 'Style', 'popupmenu', ...
                'String', {'2 阶 (k1, k2)', '3 阶 (k1, k2, k3)'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 9, ...
                'Units', 'normalized', 'Position', [0.34 0.48 0.62 0.20]);

            app.ChkTangential = uicontrol('Parent', pnlCfg, 'Style', 'checkbox', ...
                'String', '估计切向畸变 (p1, p2)', 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.04 0.24 0.90 0.18]);

            app.ChkSkew = uicontrol('Parent', pnlCfg, 'Style', 'checkbox', ...
                'String', '估计像素倾斜因子 (Skew)', 'Value', 0, ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', bgPanel, ...
                'Units', 'normalized', 'Position', [0.04 0.04 0.90 0.18]);

            % --- 3. 图像对列表 ---
            pnlList = uipanel('Parent', pnlLeft, 'Title', ' 3. 图像对列表 (点击预览 / 勾选启用) ', ...
                'FontName', app.FontName, 'FontSize', 9.5, 'FontWeight', 'bold', ...
                'Units', 'normalized', 'Position', [0.03 0.22 0.94 0.36], ...
                'BackgroundColor', bgPanel);

            app.TblPairs = uitable('Parent', pnlList, ...
                'Units', 'normalized', 'Position', [0.02 0.03 0.96 0.94], ...
                'ColumnName', {'启用', '左图', '状态', 'max误差(px)'}, ...
                'ColumnFormat', {'logical', 'char', 'char', 'numeric'}, ...
                'ColumnEditable', [true, false, false, false], ...
                'ColumnWidth', {38, 120, 56, 72}, ...
                'FontName', app.FontName, 'FontSize', 8.5, ...
                'CellSelectionCallback', @(src, evt) app.onTableSelect(src, evt), ...
                'CellEditCallback', @(src, evt) app.onTableEdit(src, evt));

            % --- 4. 执行与导出区 ---
            pnlAct = uipanel('Parent', pnlLeft, 'Title', ' 4. 标定执行与导出 ', ...
                'FontName', app.FontName, 'FontSize', 9.5, 'FontWeight', 'bold', ...
                'Units', 'normalized', 'Position', [0.03 0.015 0.94 0.195], ...
                'BackgroundColor', bgPanel);

            uicontrol('Parent', pnlAct, 'Style', 'pushbutton', ...
                'String', '① 检测棋盘格角点', 'FontName', app.FontName, 'FontSize', 9, ...
                'Units', 'normalized', 'Position', [0.03 0.68 0.45 0.25], ...
                'Callback', @(~,~) app.onDetectCorners());

            uicontrol('Parent', pnlAct, 'Style', 'pushbutton', ...
                'String', '② 执行双目标定', 'FontName', app.FontName, 'FontSize', 9, ...
                'BackgroundColor', cAccent, 'ForegroundColor', [1 1 1], 'FontWeight', 'bold', ...
                'Units', 'normalized', 'Position', [0.52 0.68 0.45 0.25], ...
                'Callback', @(~,~) app.onRunCalibration());

            uicontrol('Parent', pnlAct, 'Style', 'text', 'String', '误差阈值(px):', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'HorizontalAlignment', 'left', ...
                'BackgroundColor', bgPanel, 'Units', 'normalized', 'Position', [0.03 0.37 0.30 0.20]);
            app.EdtErrThresh = uicontrol('Parent', pnlAct, 'Style', 'edit', 'String', '0.5', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.33 0.38 0.16 0.22]);
            uicontrol('Parent', pnlAct, 'Style', 'pushbutton', ...
                'String', '剔除高误差对并重标', 'FontName', app.FontName, 'FontSize', 8.5, ...
                'BackgroundColor', cWarn, 'ForegroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.52 0.37 0.45 0.24], ...
                'Callback', @(~,~) app.onPruneAndRecalib());

            uicontrol('Parent', pnlAct, 'Style', 'pushbutton', ...
                'String', '③ 导出标定结果 (.mat / .json / .txt 报告)', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', cPrimary, 'ForegroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.03 0.06 0.94 0.25], ...
                'Callback', @(~,~) app.onExportParams());

            % ==================== 右侧多标签可视化区 ====================
            app.TabGroup = uitabgroup('Parent', app.Fig, ...
                'Units', 'normalized', 'Position', [0.290 0.045 0.702 0.945]);

            % --- Tab 1: 图像与角点预览 ---
            tab1 = uitab('Parent', app.TabGroup, 'Title', ' 图像与角点预览 ');
            app.LblPairInfo = uicontrol('Parent', tab1, 'Style', 'text', ...
                'String', '当前图像对：未加载', 'FontName', app.FontName, 'FontSize', 9.5, ...
                'HorizontalAlignment', 'left', 'Units', 'normalized', ...
                'Position', [0.02 0.935 0.52 0.045]);
            app.ChkShowQuiver = uicontrol('Parent', tab1, 'Style', 'checkbox', ...
                'String', '叠加重投影误差矢量  放大倍率:', 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.55 0.94 0.28 0.04], 'Callback', @(~,~) app.updatePreviewTab());
            app.EdtQuiverScale = uicontrol('Parent', tab1, 'Style', 'edit', 'String', '25', ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.84 0.94 0.06 0.04], ...
                'Callback', @(~,~) app.updatePreviewTab());
            uicontrol('Parent', tab1, 'Style', 'pushbutton', 'String', '刷新', ...
                'FontName', app.FontName, 'FontSize', 8.5, 'Units', 'normalized', ...
                'Position', [0.91 0.94 0.07 0.04], 'Callback', @(~,~) app.updatePreviewTab());

            app.AxLeft = axes('Parent', tab1, 'Units', 'normalized', 'Position', [0.02 0.04 0.47 0.87]);
            title(app.AxLeft, '左相机视图', 'FontName', app.FontName);
            axis(app.AxLeft, 'off');

            app.AxRight = axes('Parent', tab1, 'Units', 'normalized', 'Position', [0.51 0.04 0.47 0.87]);
            title(app.AxRight, '右相机视图', 'FontName', app.FontName);
            axis(app.AxRight, 'off');

            % --- Tab 2: 标定结果与参数矩阵 ---
            tab2 = uitab('Parent', app.TabGroup, 'Title', ' 标定参数与精度报告 ');
            app.TxtParams = uicontrol('Parent', tab2, 'Style', 'edit', 'Max', 2, 'Min', 0, ...
                'HorizontalAlignment', 'left', 'FontName', 'Consolas', 'FontSize', 10, ...
                'BackgroundColor', [1 1 1], 'Enable', 'on', ...
                'String', {'尚未执行双目标定。完成标定后，此处将显示完整内参、畸变、外参及 3D 尺度精度评估。'}, ...
                'Units', 'normalized', 'Position', [0.02 0.03 0.96 0.94]);

            % --- Tab 3: 误差分析与 3D 位姿 ---
            tab3 = uitab('Parent', app.TabGroup, 'Title', ' 误差分布与 3D 位姿 ');
            app.AxErrBar = axes('Parent', tab3, 'Units', 'normalized', 'Position', [0.07 0.56 0.89 0.39]);
            title(app.AxErrBar, '各图像对平均重投影误差', 'FontName', app.FontName);

            uicontrol('Parent', tab3, 'Style', 'text', 'String', '3D 位姿视角:', ...
                'FontName', app.FontName, 'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'Units', 'normalized', 'Position', [0.02 0.47 0.12 0.04]);
            app.PopExtView = uicontrol('Parent', tab3, 'Style', 'popupmenu', ...
                'String', {'相机中心视角 (CameraCentric)', '标定板中心视角 (PatternCentric)'}, ...
                'Value', 1, 'FontName', app.FontName, 'FontSize', 9, ...
                'Units', 'normalized', 'Position', [0.14 0.475 0.28 0.04], ...
                'Callback', @(~,~) app.updateExtrinsicsPlot());

            app.AxExtrinsics = axes('Parent', tab3, 'Units', 'normalized', 'Position', [0.07 0.05 0.89 0.40]);
            title(app.AxExtrinsics, '双目外参 3D 空间分布 (工具栏可开启 3D 旋转)', 'FontName', app.FontName);

            % --- Tab 4: 极线校正检验 ---
            tab4 = uitab('Parent', app.TabGroup, 'Title', ' 极线校正检验 ');
            uicontrol('Parent', tab4, 'Style', 'text', 'String', '显示方式:', ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.02 0.935 0.09 0.04]);
            app.PopRectMode = uicontrol('Parent', tab4, 'Style', 'popupmenu', ...
                'String', {'左右并排 + 水平极线', '红绿立体叠加 (Anaglyph)'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.11 0.94 0.22 0.04]);

            uicontrol('Parent', tab4, 'Style', 'text', 'String', '输出视野:', ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.34 0.935 0.09 0.04]);
            app.PopRectView = uicontrol('Parent', tab4, 'Style', 'popupmenu', ...
                'String', {'valid (无黑边)', 'full (保留全图)'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.43 0.94 0.16 0.04]);

            uicontrol('Parent', tab4, 'Style', 'text', 'String', '极线间距(px):', ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.60 0.935 0.11 0.04]);
            app.EdtLineStep = uicontrol('Parent', tab4, 'Style', 'edit', 'String', '40', ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.71 0.94 0.07 0.04]);

            uicontrol('Parent', tab4, 'Style', 'pushbutton', 'String', '执行极线校正', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', cPrimary, 'ForegroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.80 0.935 0.18 0.045], ...
                'Callback', @(~,~) app.onRunRectify());

            app.LblEpipolarInfo = uicontrol('Parent', tab4, 'Style', 'text', ...
                'String', '提示：在左侧列表选择任意图像对，点击「执行极线校正」检验同名点水平对齐精度。', ...
                'FontName', app.FontName, 'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'Units', 'normalized', 'Position', [0.02 0.885 0.96 0.04]);

            app.AxRect = axes('Parent', tab4, 'Units', 'normalized', 'Position', [0.02 0.03 0.96 0.84]);
            axis(app.AxRect, 'off');

            % --- Tab 5: 视差图与 3D 测距验证 ---
            tab5 = uitab('Parent', app.TabGroup, 'Title', ' 视差与 3D 测距验证 ');
            uicontrol('Parent', tab5, 'Style', 'text', 'String', '匹配算法:', ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.02 0.935 0.09 0.04]);
            app.PopDispMethod = uicontrol('Parent', tab5, 'Style', 'popupmenu', ...
                'String', {'SemiGlobal', 'BlockMatching'}, 'Value', 1, ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.11 0.94 0.15 0.04]);

            uicontrol('Parent', tab5, 'Style', 'text', 'String', '视差范围:', ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.27 0.935 0.09 0.04]);
            app.EdtDispMin = uicontrol('Parent', tab5, 'Style', 'edit', 'String', '0', ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.36 0.94 0.06 0.04]);
            uicontrol('Parent', tab5, 'Style', 'text', 'String', '~', ...
                'FontName', app.FontName, 'FontSize', 10, 'Units', 'normalized', ...
                'Position', [0.42 0.935 0.02 0.04]);
            app.EdtDispMax = uicontrol('Parent', tab5, 'Style', 'edit', 'String', '192', ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.44 0.94 0.07 0.04]);

            uicontrol('Parent', tab5, 'Style', 'text', 'String', '窗口(奇数):', ...
                'FontName', app.FontName, 'FontSize', 9, 'Units', 'normalized', ...
                'Position', [0.53 0.935 0.10 0.04]);
            app.EdtBlockSize = uicontrol('Parent', tab5, 'Style', 'edit', 'String', '15', ...
                'FontName', app.FontName, 'FontSize', 9, 'BackgroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.63 0.94 0.06 0.04]);

            uicontrol('Parent', tab5, 'Style', 'pushbutton', 'String', '计算视差与 3D 场景', ...
                'FontName', app.FontName, 'FontSize', 9, 'FontWeight', 'bold', ...
                'BackgroundColor', cAccent, 'ForegroundColor', [1 1 1], ...
                'Units', 'normalized', 'Position', [0.71 0.935 0.27 0.045], ...
                'Callback', @(~,~) app.onComputeDisparity());

            app.LblMeasureInfo = uicontrol('Parent', tab5, 'Style', 'text', ...
                'String', '计算完成后，直接用鼠标点击下方任意图像像素，即可实时查询该点的三维坐标 (X, Y, Z) 与深度距离。', ...
                'FontName', app.FontName, 'FontSize', 9, 'HorizontalAlignment', 'left', ...
                'ForegroundColor', [0.10 0.35 0.65], 'FontWeight', 'bold', ...
                'Units', 'normalized', 'Position', [0.02 0.885 0.96 0.04]);

            app.AxDispLeft = axes('Parent', tab5, 'Units', 'normalized', 'Position', [0.02 0.04 0.45 0.82]);
            title(app.AxDispLeft, '校正后左图 (点击测距)', 'FontName', app.FontName);
            axis(app.AxDispLeft, 'off');

            app.AxDispMap = axes('Parent', tab5, 'Units', 'normalized', 'Position', [0.50 0.04 0.45 0.82]);
            title(app.AxDispMap, '视差图 (px)', 'FontName', app.FontName);
            axis(app.AxDispMap, 'off');

            % ==================== 底部状态栏 ====================
            app.LblStatus = uicontrol('Parent', app.Fig, 'Style', 'text', ...
                'String', '就绪', 'FontName', app.FontName, 'FontSize', 9, ...
                'HorizontalAlignment', 'left', 'BackgroundColor', [0.89 0.91 0.94], ...
                'Units', 'normalized', 'Position', [0.008 0.008 0.984 0.030]);
        end

        % =================================================================
        % 数据加载回调
        % =================================================================
        function onLoadSeparate(app)
            leftDir = uigetdir(pwd, '选择【左相机】图像文件夹');
            if isequal(leftDir, 0), return; end
            rightDir = uigetdir(fileparts(leftDir), '选择【右相机】图像文件夹');
            if isequal(rightDir, 0), return; end

            try
                [lFiles, rFiles, info] = stereo.loadImagePairs('separate', leftDir, rightDir);
                app.initDataset(lFiles, rFiles, info.imageSize, info.message);
            catch ME
                errordlg(ME.message, '加载失败');
            end
        end

        function onLoadSideBySide(app)
            dirPath = uigetdir(pwd, '选择【左右拼接图】文件夹');
            if isequal(dirPath, 0), return; end

            cleanup = app.setBusy('正在自动裁切左右拼接图...'); %#ok<NASGU>
            try
                [lFiles, rFiles, info] = stereo.loadImagePairs('sidebyside', dirPath);
                app.initDataset(lFiles, rFiles, info.imageSize, info.message);
            catch ME
                errordlg(ME.message, '加载失败');
            end
        end

        function onGenerateDemo(app)
            outRoot = fullfile(fileparts(mfilename('fullpath')), 'demo_data');
            cleanup = app.setBusy('正在渲染 14 组带真实畸变的合成双目棋盘格测试数据...'); %#ok<NASGU>
            try
                [leftDir, rightDir, gt] = stereo.generateSyntheticDataset(outRoot, 14);
                [lFiles, rFiles, info] = stereo.loadImagePairs('separate', leftDir, rightDir);
                set(app.EdtSquareSize, 'String', num2str(gt.squareSize));
                set(app.PopUnits, 'Value', 1);
                msg = sprintf('已生成 %d 组合成测试数据 (真值基线 %.2f mm, f≈720 px)，请点击「① 检测棋盘格角点」。', ...
                    numel(lFiles), gt.baseline);
                app.initDataset(lFiles, rFiles, info.imageSize, msg);
            catch ME
                errordlg(ME.message, '生成测试数据失败');
            end
        end

        function onLoadMatParams(app)
            [f, p] = uigetfile('*.mat', '选择已有双目标定结果 (.mat)');
            if isequal(f, 0), return; end
            try
                S = load(fullfile(p, f));
                if ~isfield(S, 'stereoParams') || ~isa(S.stereoParams, 'stereoParameters')
                    errordlg('该 .mat 文件中不包含有效的 MATLAB stereoParameters 对象 (变量名 stereoParams)。', '格式错误');
                    return;
                end

                ps = [];
                if isfield(S, 'paramsStruct')
                    ps = S.paramsStruct;
                elseif isfield(S, 'cvParams')
                    ps = S.cvParams;
                end
                mt = [];
                if isfield(S, 'metrics')
                    mt = S.metrics;
                end
                ee = [];
                if isfield(S, 'estimationErrors')
                    ee = S.estimationErrors;
                end

                app.CalibResult = struct( ...
                    'stereoParams', S.stereoParams, ...
                    'estimationErrors', ee, ...
                    'pairsUsed', [], ...
                    'paramsStruct', ps, ...
                    'metrics', mt);

                if ~isempty(ps) && ~isempty(mt)
                    app.updateParamsTab();
                else
                    sp = S.stereoParams;
                    set(app.TxtParams, 'String', { ...
                        '已导入外部 MATLAB stereoParams 对象。', ...
                        sprintf('总体平均重投影误差: %.4f px (左: %.4f px, 右: %.4f px)', ...
                            sp.MeanReprojectionError, ...
                            sp.CameraParameters1.MeanReprojectionError, ...
                            sp.CameraParameters2.MeanReprojectionError), ...
                        sprintf('双目基线长度: %.4f %s', norm(sp.TranslationOfCamera2), sp.WorldUnits), ...
                        sprintf('参与标定模式数: %d', sp.NumPatterns), ...
                        '', ...
                        '可直接查看「误差分布与 3D 位姿」，或加载测试图像进行极线校正与 3D 测距。'});
                end
                app.updateAnalysisTab();

                % 清空与旧图像对的逐帧误差映射，防止误差矢量错位
                app.CalibOrigIdx = [];
                app.LastDisparity = [];
                app.LastPoints3D = [];
                if ~isempty(app.LeftFiles)
                    app.PairErrorMax = nan(numel(app.LeftFiles), 1);
                    app.refreshPairTable();
                    app.updatePreviewTab();
                end
                app.setStatus(sprintf('已导入标定参数文件: %s', fullfile(p, f)));
            catch ME
                errordlg(ME.message, '导入失败');
            end
        end

        function initDataset(app, lFiles, rFiles, imSize, statusMsg)
            n = numel(lFiles);
            app.LeftFiles = lFiles;
            app.RightFiles = rFiles;
            app.ImageSize = imSize;
            app.DetectedMask = false(n, 1);
            app.DetectedToOrigIdx = [];
            app.OrigToDetectedIdx = zeros(n, 1);
            app.AllImagePoints = [];
            app.BoardSize = [];
            app.PairEnabled = true(n, 1);
            app.PairErrorMax = nan(n, 1);
            app.CalibOrigIdx = [];
            app.RectifiedLeft = [];
            app.RectifiedRight = [];
            app.LastDisparity = [];
            app.LastPoints3D = [];
            app.SelectedPairIdx = 1;

            app.refreshPairTable();
            app.updatePreviewTab();
            app.setStatus(statusMsg);
        end

        % =================================================================
        % 角点检测与标定核心回调
        % =================================================================
        function onDetectCorners(app)
            if isempty(app.LeftFiles)
                warndlg('请先加载双目图像对。', '提示');
                return;
            end
            cleanup = app.setBusy('正在调用 detectCheckerboardPoints 检测亚像素角点...'); %#ok<NASGU>
            t0 = tic;
            try
                [imgPts, bSize, pairsUsed] = detectCheckerboardPoints(app.LeftFiles, app.RightFiles);
                if isempty(imgPts) || sum(pairsUsed) < 3
                    errordlg('成功检测到完整棋盘格的图像对不足 3 组，请检查图像清晰度或棋盘格完整性。', '检测失败');
                    return;
                end

                app.AllImagePoints = imgPts;
                app.BoardSize = bSize;
                app.DetectedMask = logical(pairsUsed(:));
                app.DetectedToOrigIdx = find(app.DetectedMask);
                app.OrigToDetectedIdx = zeros(numel(app.LeftFiles), 1);
                app.OrigToDetectedIdx(app.DetectedToOrigIdx) = 1:numel(app.DetectedToOrigIdx);
                app.PairEnabled = app.DetectedMask;
                app.PairErrorMax = nan(numel(app.LeftFiles), 1);
                app.CalibOrigIdx = [];

                app.refreshPairTable();
                app.updatePreviewTab();
                app.setStatus(sprintf('角点检测完成 (%.2f s)：棋盘格 %dx%d 方格 (内角点 %dx%d)，成功 %d / %d 对。', ...
                    toc(t0), bSize(1), bSize(2), bSize(1)-1, bSize(2)-1, sum(pairsUsed), numel(pairsUsed)));
            catch ME
                errordlg(ME.message, '角点检测异常');
            end
        end

        function onRunCalibration(app)
            if isempty(app.AllImagePoints)
                warndlg('请先执行「① 检测棋盘格角点」。', '提示');
                return;
            end
            sqSize = str2double(get(app.EdtSquareSize, 'String'));
            if isnan(sqSize) || sqSize <= 0
                errordlg('请输入有效的正数方格边长。', '参数错误');
                return;
            end

            activeOrigIdx = find(app.PairEnabled & app.DetectedMask);
            if numel(activeOrigIdx) < 3
                errordlg('至少需要勾选 3 组有效图像对才能执行双目标定。', '样本不足');
                return;
            end

            detIdx = app.OrigToDetectedIdx(activeOrigIdx);
            subPts = app.AllImagePoints(:, :, detIdx, :);

            unitList = get(app.PopUnits, 'String');
            worldUnits = unitList{get(app.PopUnits, 'Value')};
            numRadial = 2;
            if get(app.PopRadial, 'Value') == 2
                numRadial = 3;
            end
            opts = struct( ...
                'numRadial', numRadial, ...
                'estimateTangential', logical(get(app.ChkTangential, 'Value')), ...
                'estimateSkew', logical(get(app.ChkSkew, 'Value')));

            cleanup = app.setBusy('正在调用 MATLAB 官方工具箱执行双目标定与 3D 尺度评估...'); %#ok<NASGU>
            t0 = tic;
            try
                res = stereo.runCalibration(subPts, app.BoardSize, sqSize, worldUnits, app.ImageSize, opts);

                usedOrig = activeOrigIdx(res.pairsUsed);
                usedOrig = usedOrig(:);
                droppedOrig = setdiff(activeOrigIdx(:), usedOrig);
                res.metrics.usedPairIndices = usedOrig;

                app.CalibResult = res;
                app.CalibOrigIdx = usedOrig;
                app.PairErrorMax = nan(numel(app.LeftFiles), 1);
                app.PairErrorMax(usedOrig) = res.metrics.perPairErrMax;
                if ~isempty(droppedOrig)
                    app.PairEnabled(droppedOrig) = false;
                end

                app.refreshPairTable();
                app.updatePreviewTab();
                app.updateParamsTab();
                app.updateAnalysisTab();

                m = res.metrics;
                msg = sprintf('标定完成 (%.2f s) | 有效对: %d | 重投影: %.4f px | 极线 RMS: %.4f px | 3D 尺度误差: %.3f %s (%.3f%%) | 基线: %.3f %s', ...
                    toc(t0), m.numPairs, m.meanReprojError, m.epipolarRmsPx, ...
                    m.scaleErrMean, m.worldUnits, m.scaleErrRelPct, m.baseline, m.worldUnits);
                if ~isempty(droppedOrig)
                    msg = [msg, sprintf(' | 自动丢弃退化对: %s', mat2str(droppedOrig'))];
                end
                app.setStatus(msg);
            catch ME
                errordlg(ME.message, '标定失败');
            end
        end

        function onPruneAndRecalib(app)
            if isempty(app.CalibResult) || isempty(app.CalibOrigIdx)
                warndlg('请先基于当前数据集执行一次双目标定。', '提示');
                return;
            end
            thresh = str2double(get(app.EdtErrThresh, 'String'));
            if isnan(thresh) || thresh <= 0
                errordlg('请输入有效的正数误差阈值 (px)。', '参数错误');
                return;
            end

            badMask = app.PairEnabled & (app.PairErrorMax > thresh);
            nBad = sum(badMask);
            if nBad == 0
                msgbox(sprintf('当前所有启用图像对的 max(左,右) 误差均 <= %.3f px，无需剔除。', thresh), '提示');
                return;
            end
            remain = sum(app.PairEnabled & app.DetectedMask) - nBad;
            if remain < 3
                errordlg(sprintf('按阈值 %.3f px 剔除 %d 对后仅剩 %d 对（少于 3 对），请调大阈值。', ...
                    thresh, nBad, remain), '无法剔除');
                return;
            end

            app.PairEnabled(badMask) = false;
            app.refreshPairTable();
            app.onRunCalibration();
        end

        function onExportParams(app)
            if isempty(app.CalibResult) || isempty(app.CalibResult.paramsStruct)
                warndlg('当前没有可导出的完整标定结果，请先执行双目标定。', '提示');
                return;
            end
            outDir = uigetdir(pwd, '选择标定结果导出目录');
            if isequal(outDir, 0), return; end

            try
                files = stereo.exportParameters(outDir, app.CalibResult, 'stereo_calib');
                msg = sprintf('已成功导出 3 份文件至:\n%s\n\n- stereo_calib.mat (含 MATLAB 原生 stereoParams)\n- stereo_calib.json\n- stereo_calib_report.txt', outDir);
                msgbox(msg, '导出成功');
                app.setStatus(sprintf('标定参数已导出 (%d 个文件): %s', numel(files), outDir));
            catch ME
                errordlg(ME.message, '导出失败');
            end
        end

        % =================================================================
        % 表格与可视化更新
        % =================================================================
        function refreshPairTable(app)
            n = numel(app.LeftFiles);
            data = cell(n, 4);
            for i = 1:n
                [~, name, ext] = fileparts(app.LeftFiles{i});
                data{i, 1} = logical(app.PairEnabled(i));
                data{i, 2} = [name ext];
                if isempty(app.AllImagePoints)
                    data{i, 3} = '待检测';
                elseif app.DetectedMask(i)
                    data{i, 3} = '成功';
                else
                    data{i, 3} = '未检出';
                end
                if isnan(app.PairErrorMax(i))
                    data{i, 4} = [];
                else
                    data{i, 4} = round(app.PairErrorMax(i) * 1000) / 1000;
                end
            end
            set(app.TblPairs, 'Data', data);
        end

        function onTableSelect(app, ~, evt)
            if isempty(evt.Indices), return; end
            row = evt.Indices(1, 1);
            if row >= 1 && row <= numel(app.LeftFiles)
                app.SelectedPairIdx = row;
                app.updatePreviewTab();
            end
        end

        function onTableEdit(app, ~, evt)
            row = evt.Indices(1);
            col = evt.Indices(2);
            if col == 1
                if ~isempty(app.AllImagePoints) && ~app.DetectedMask(row)
                    data = get(app.TblPairs, 'Data');
                    data{row, 1} = false;
                    set(app.TblPairs, 'Data', data);
                    app.PairEnabled(row) = false;
                    return;
                end
                app.PairEnabled(row) = logical(evt.NewData);
            end
        end

        function updatePreviewTab(app)
            if isempty(app.LeftFiles), return; end
            idx = min(max(app.SelectedPairIdx, 1), numel(app.LeftFiles));
            IL = imread(app.LeftFiles{idx});
            IR = imread(app.RightFiles{idx});

            cla(app.AxLeft);  imshow(IL, 'Parent', app.AxLeft);  hold(app.AxLeft, 'on');
            cla(app.AxRight); imshow(IR, 'Parent', app.AxRight); hold(app.AxRight, 'on');

            [~, lName, lExt] = fileparts(app.LeftFiles{idx});
            [~, rName, rExt] = fileparts(app.RightFiles{idx});
            errStr = '未标定';
            if ~isnan(app.PairErrorMax(idx))
                errStr = sprintf('max(左,右)误差: %.4f px', app.PairErrorMax(idx));
            end
            set(app.LblPairInfo, 'String', sprintf('图像对 #%d/%d: %s | %s  (%s)', ...
                idx, numel(app.LeftFiles), [lName lExt], [rName rExt], errStr));

            if ~isempty(app.AllImagePoints) && app.DetectedMask(idx)
                dIdx = app.OrigToDetectedIdx(idx);
                ptsL = app.AllImagePoints(:, :, dIdx, 1);
                ptsR = app.AllImagePoints(:, :, dIdx, 2);

                plot(app.AxLeft, ptsL(:,1), ptsL(:,2), 'g+', 'MarkerSize', 6, 'LineWidth', 1.1);
                plot(app.AxLeft, ptsL(1,1), ptsL(1,2), 'ro', 'MarkerSize', 9, 'LineWidth', 1.8);
                plot(app.AxRight, ptsR(:,1), ptsR(:,2), 'g+', 'MarkerSize', 6, 'LineWidth', 1.1);
                plot(app.AxRight, ptsR(1,1), ptsR(1,2), 'ro', 'MarkerSize', 9, 'LineWidth', 1.8);

                % 按标定时持久化的 CalibOrigIdx 索引精确叠加误差放大矢量
                if get(app.ChkShowQuiver, 'Value') && ~isempty(app.CalibResult) && ~isempty(app.CalibOrigIdx)
                    calibPos = find(app.CalibOrigIdx == idx, 1);
                    errL = app.CalibResult.stereoParams.CameraParameters1.ReprojectionErrors;
                    errR = app.CalibResult.stereoParams.CameraParameters2.ReprojectionErrors;
                    if ~isempty(calibPos) && calibPos <= size(errL, 3) && size(errL, 1) == size(ptsL, 1)
                        scale = str2double(get(app.EdtQuiverScale, 'String'));
                        if isnan(scale) || scale <= 0, scale = 25; end
                        eL = errL(:, :, calibPos);
                        eR = errR(:, :, calibPos);
                        quiver(app.AxLeft, ptsL(:,1), ptsL(:,2), eL(:,1)*scale, eL(:,2)*scale, 0, ...
                            'Color', [1 0.2 0.2], 'LineWidth', 1.2);
                        quiver(app.AxRight, ptsR(:,1), ptsR(:,2), eR(:,1)*scale, eR(:,2)*scale, 0, ...
                            'Color', [1 0.2 0.2], 'LineWidth', 1.2);
                    end
                end
            end

            title(app.AxLeft, sprintf('左相机 (#%d)', idx), 'FontName', app.FontName);
            title(app.AxRight, sprintf('右相机 (#%d)', idx), 'FontName', app.FontName);
            hold(app.AxLeft, 'off');
            hold(app.AxRight, 'off');
        end

        function updateParamsTab(app)
            if isempty(app.CalibResult) || isempty(app.CalibResult.paramsStruct), return; end
            p = app.CalibResult.paramsStruct;
            m = app.CalibResult.metrics;

            lines = { ...
                '========================================================================', ...
                '                MATLAB 双目立体标定核心参数与多维度精度评估', ...
                '========================================================================', ...
                sprintf('图像分辨率           : %d x %d (W x H)', p.imageWidth, p.imageHeight), ...
                sprintf('棋盘格规格           : %d x %d 方格 (内角点 %d x %d), 边长 %.3f %s', ...
                    m.boardSize(1), m.boardSize(2), m.boardSize(1)-1, m.boardSize(2)-1, m.squareSize, m.worldUnits), ...
                sprintf('参与标定图像对数     : %d 对', m.numPairs), ...
                '------------------------------------------------------------------------', ...
                sprintf('总体平均重投影误差   : %.4f px  (左: %.4f px | 右: %.4f px)', ...
                    m.meanReprojError, m.leftMeanReprojError, m.rightMeanReprojError), ...
                sprintf('官方校正极线垂直误差 : Mean = %.4f px | RMS = %.4f px | Max = %.4f px', ...
                    m.epipolarMeanPx, m.epipolarRmsPx, m.epipolarMaxPx), ...
                sprintf('官方极线点到线距离   : Mean = %.4f px (epipolarLine)', m.epiLineDistMeanPx), ...
                sprintf('3D 物理尺度重建误差  : Mean = %.4f %s (%.4f%%) | Max = %.4f %s (triangulate)', ...
                    m.scaleErrMean, m.worldUnits, m.scaleErrRelPct, m.scaleErrMax, m.worldUnits), ...
                sprintf('双目基线长度 B       : %.4f %s', m.baseline, m.worldUnits), ...
                sprintf('相对欧拉角 ZYX (deg) : Yaw = %.4f°, Pitch = %.4f°, Roll = %.4f°', ...
                    m.eulerZYXDeg(1), m.eulerZYXDeg(2), m.eulerZYXDeg(3)), ...
                sprintf('Rodrigues 向量 (deg) : [%.4f, %.4f, %.4f]', ...
                    m.rvecDeg(1), m.rvecDeg(2), m.rvecDeg(3)), ...
                '------------------------------------------------------------------------', ...
                '[注] 以下 K/R/T 按教科书标准列向量写法展示 (X_cam2 = R * X_cam1 + T，主点 MATLAB 1-based)', ...
                '     导出 .mat 文件内完整保存官方 stereoParams 对象，可直接传给 MATLAB 视觉工具箱函数', ...
                '', ...
                '左相机内参矩阵 K1:', ...
                app.fmtMat(p.K1), ...
                sprintf('左相机畸变 D1 [k1, k2, p1, p2, k3]:  [%.6f, %.6f, %.6f, %.6f, %.6f]', p.D1), ...
                '', ...
                '右相机内参矩阵 K2:', ...
                app.fmtMat(p.K2), ...
                sprintf('右相机畸变 D2 [k1, k2, p1, p2, k3]:  [%.6f, %.6f, %.6f, %.6f, %.6f]', p.D2), ...
                '', ...
                '相对旋转矩阵 R (Left -> Right):', ...
                app.fmtMat(p.R), ...
                sprintf('相对平移向量 T (%s):  [%.6f,  %.6f,  %.6f]^T', m.worldUnits, p.T(1), p.T(2), p.T(3)), ...
                '', ...
                '本质矩阵 E (stereoParams.EssentialMatrix):', ...
                app.fmtMat(p.E), ...
                '基础矩阵 F (stereoParams.FundamentalMatrix):', ...
                app.fmtMat(p.F)};

            if isfield(p, 'Q') && ~isempty(p.Q)
                lines = [lines, {'官方立体校正重投影矩阵 Q (RectificationParams.Q):', app.fmtMat(p.Q)}];
            end

            flatLines = {};
            for i = 1:numel(lines)
                parts = strsplit(lines{i}, sprintf('\n'));
                flatLines = [flatLines, parts]; %#ok<AGROW>
            end
            set(app.TxtParams, 'String', flatLines);
        end

        function updateAnalysisTab(app)
            if isempty(app.CalibResult), return; end
            sp = app.CalibResult.stereoParams;

            cla(app.AxErrBar, 'reset');
            if ~isempty(app.CalibResult.metrics)
                m = app.CalibResult.metrics;
                n = numel(m.perPairErrLeft);
                if isfield(m, 'usedPairIndices') && numel(m.usedPairIndices) == n
                    xIdx = m.usedPairIndices(:)';
                else
                    xIdx = 1:n;
                end
                bar(app.AxErrBar, 1:n, [m.perPairErrLeft, m.perPairErrRight], 'grouped');
                set(app.AxErrBar, 'XTick', 1:n, 'XTickLabel', arrayfun(@num2str, xIdx, 'UniformOutput', false));
                hold(app.AxErrBar, 'on');
                yMean = m.meanReprojError;
                plot(app.AxErrBar, [0.5, n + 0.5], [yMean, yMean], '--r', 'LineWidth', 1.4);
                thresh = str2double(get(app.EdtErrThresh, 'String'));
                if ~isnan(thresh) && thresh > 0
                    plot(app.AxErrBar, [0.5, n + 0.5], [thresh, thresh], ':k', 'LineWidth', 1.2);
                    legend(app.AxErrBar, {'左相机', '右相机', sprintf('均值 %.3f px', yMean), ...
                        sprintf('剔除阈值 %.3f px (任一相机超出即剔除)', thresh)}, 'Location', 'northeast', 'FontName', app.FontName);
                else
                    legend(app.AxErrBar, {'左相机', '右相机', sprintf('均值 %.3f px', yMean)}, ...
                        'Location', 'northeast', 'FontName', app.FontName);
                end
                xlabel(app.AxErrBar, '图像对原始序号 (与左侧列表行号一致)', 'FontName', app.FontName);
                ylabel(app.AxErrBar, '平均重投影误差 (px)', 'FontName', app.FontName);
                title(app.AxErrBar, sprintf('重投影误差分布 (总体均值 = %.4f px)', yMean), 'FontName', app.FontName);
                grid(app.AxErrBar, 'on');
                hold(app.AxErrBar, 'off');
            else
                showReprojectionErrors(sp, 'Parent', app.AxErrBar);
            end

            app.updateExtrinsicsPlot();
        end

        function updateExtrinsicsPlot(app)
            if isempty(app.CalibResult), return; end
            sp = app.CalibResult.stereoParams;
            cla(app.AxExtrinsics, 'reset');
            if get(app.PopExtView, 'Value') == 1
                viewMode = 'CameraCentric';
            else
                viewMode = 'PatternCentric';
            end
            showExtrinsics(sp, viewMode, 'Parent', app.AxExtrinsics);
            title(app.AxExtrinsics, ['双目 3D 空间位姿 - ' viewMode ' (工具栏可开启 3D 旋转)'], ...
                'FontName', app.FontName);
            grid(app.AxExtrinsics, 'on');
        end

        % =================================================================
        % Tab 4: 极线校正检验
        % =================================================================
        function onRunRectify(app)
            if isempty(app.CalibResult)
                warndlg('请先执行双目标定或导入 .mat 标定参数。', '提示');
                return;
            end
            if isempty(app.LeftFiles)
                warndlg('请先加载双目图像对。', '提示');
                return;
            end

            cleanup = app.setBusy('正在调用 rectifyStereoImages 执行立体极线校正...'); %#ok<NASGU>
            try
                idx = min(max(app.SelectedPairIdx, 1), numel(app.LeftFiles));
                IL = imread(app.LeftFiles{idx});
                IR = imread(app.RightFiles{idx});
                if ~app.checkImageSize(IL), return; end

                if get(app.PopRectView, 'Value') == 1
                    ov = 'valid';
                else
                    ov = 'full';
                end
                [J1, J2] = rectifyStereoImages(IL, IR, app.CalibResult.stereoParams, 'OutputView', ov);
                app.RectifiedLeft = J1;
                app.RectifiedRight = J2;

                cla(app.AxRect, 'reset');
                if get(app.PopRectMode, 'Value') == 1
                    combined = [J1, J2];
                    imshow(combined, 'Parent', app.AxRect);
                    hold(app.AxRect, 'on');
                    step = str2double(get(app.EdtLineStep, 'String'));
                    if isnan(step) || step < 10, step = 40; end
                    [H, W2, ~] = size(combined);
                    for y = step:step:(H - 1)
                        plot(app.AxRect, [1, W2], [y, y], 'g-', 'LineWidth', 0.8);
                    end
                    plot(app.AxRect, [size(J1,2), size(J1,2)], [1, H], 'y--', 'LineWidth', 1.2);
                    hold(app.AxRect, 'off');
                    title(app.AxRect, sprintf('极线校正并排图 (#%d, OutputView=%s)', idx, ov), 'FontName', app.FontName);
                else
                    anaglyph = stereoAnaglyph(J1, J2);
                    imshow(anaglyph, 'Parent', app.AxRect);
                    title(app.AxRect, sprintf('红绿立体叠加图 (#%d, 水平偏移即为视差)', idx), 'FontName', app.FontName);
                end

                % 使用官方双目重载 detectCheckerboardPoints(J1, J2)，保证左右角点顺序严格对应不翻转
                pairStr = '本对校正图未检出完整棋盘格，无法实测';
                [cPair, bPair] = detectCheckerboardPoints(J1, J2);
                if ~isempty(cPair) && ~isempty(bPair) && size(cPair, 4) == 2
                    c1 = cPair(:, :, 1, 1);
                    c2 = cPair(:, :, 1, 2);
                    dy = abs(c1(:, 2) - c2(:, 2));
                    pairStr = sprintf('本对实测 |dy|: Mean = %.4f px, Max = %.4f px', mean(dy), max(dy));
                    if get(app.PopRectMode, 'Value') == 1
                        hold(app.AxRect, 'on');
                        plot(app.AxRect, c1(:, 1), c1(:, 2), 'r+', 'MarkerSize', 5);
                        plot(app.AxRect, c2(:, 1) + size(J1, 2), c2(:, 2), 'r+', 'MarkerSize', 5);
                        hold(app.AxRect, 'off');
                    end
                end

                if ~isempty(app.CalibResult.metrics)
                    m = app.CalibResult.metrics;
                    set(app.LblEpipolarInfo, 'String', sprintf( ...
                        '校正 %dx%d | %s | 全数据集 RMS = %.4f px, Max = %.4f px', ...
                        size(J1,2), size(J1,1), pairStr, m.epipolarRmsPx, m.epipolarMaxPx));
                else
                    set(app.LblEpipolarInfo, 'String', sprintf('校正 %dx%d | %s', size(J1,2), size(J1,1), pairStr));
                end
                app.setStatus(sprintf('图像对 #%d 极线校正完成。', idx));
            catch ME
                errordlg(ME.message, '极线校正失败');
            end
        end

        % =================================================================
        % Tab 5: 视差计算与 3D 点击测距
        % =================================================================
        function onComputeDisparity(app)
            if isempty(app.CalibResult)
                warndlg('请先执行双目标定或导入 .mat 标定参数。', '提示');
                return;
            end
            if isempty(app.LeftFiles)
                warndlg('请先加载双目图像对。', '提示');
                return;
            end

            cleanup = app.setBusy('正在调用 disparity 与 reconstructScene 计算视差和 3D 场景...'); %#ok<NASGU>
            t0 = tic;
            try
                idx = min(max(app.SelectedPairIdx, 1), numel(app.LeftFiles));
                IL = imread(app.LeftFiles{idx});
                IR = imread(app.RightFiles{idx});
                if ~app.checkImageSize(IL), return; end

                [J1, J2] = rectifyStereoImages(IL, IR, app.CalibResult.stereoParams, 'OutputView', 'valid');
                app.RectifiedLeft = J1;
                app.RectifiedRight = J2;

                if size(J1, 3) == 3, g1 = rgb2gray(J1); else, g1 = J1; end
                if size(J2, 3) == 3, g2 = rgb2gray(J2); else, g2 = J2; end
                [H, W] = size(g1);

                % 严格按 MATLAB disparity 约束校验并自动对齐参数
                dMin = round(str2double(get(app.EdtDispMin, 'String')));
                dMax = round(str2double(get(app.EdtDispMax, 'String')));
                bs   = round(str2double(get(app.EdtBlockSize, 'String')));
                if isnan(dMin), dMin = 0; end
                maxAllowedSpan = max(16, floor((W - 1) / 16) * 16);
                dMin = max(-maxAllowedSpan + 16, min(dMin, maxAllowedSpan - 16));
                if isnan(dMax) || dMax <= dMin, dMax = dMin + 64; end
                span = max(16, min(maxAllowedSpan, ceil((dMax - dMin) / 16) * 16));
                dMax = dMin + span;
                set(app.EdtDispMin, 'String', num2str(dMin));
                set(app.EdtDispMax, 'String', num2str(dMax));

                maxBs = min(255, floor((min(H, W) - 1) / 2) * 2 - 1);
                if isnan(bs) || bs < 5, bs = 15; end
                bs = min(bs, maxBs);
                if mod(bs, 2) == 0, bs = max(5, bs - 1); end
                set(app.EdtBlockSize, 'String', num2str(bs));

                methods = get(app.PopDispMethod, 'String');
                methodName = methods{get(app.PopDispMethod, 'Value')};

                dispMap = disparity(g1, g2, ...
                    'Method', methodName, ...
                    'DisparityRange', [dMin, dMax], ...
                    'BlockSize', bs);
                pts3D = reconstructScene(dispMap, app.CalibResult.stereoParams);

                app.LastDisparity = dispMap;
                app.LastPoints3D = pts3D;

                cla(app.AxDispLeft, 'reset');
                hImg1 = imshow(J1, 'Parent', app.AxDispLeft);
                title(app.AxDispLeft, sprintf('校正左图 (#%d) - 点击任意位置测距', idx), 'FontName', app.FontName);
                set(hImg1, 'ButtonDownFcn', @(src, evt) app.onMeasureClick(src, evt));

                cla(app.AxDispMap, 'reset');
                hImg2 = imshow(dispMap, [dMin, dMax], 'Parent', app.AxDispMap);
                colormap(app.AxDispMap, parula(256));
                colorbar(app.AxDispMap);
                title(app.AxDispMap, sprintf('视差图 [%d, %d] (%s)', dMin, dMax, methodName), 'FontName', app.FontName);
                set(hImg2, 'ButtonDownFcn', @(src, evt) app.onMeasureClick(src, evt));

                app.setStatus(sprintf('视差与三维重建完成 (%.2f s)，点击图像任意点即可查看 3D 坐标与距离。', toc(t0)));
            catch ME
                errordlg(ME.message, '视差计算失败');
            end
        end

        function onMeasureClick(app, src, ~)
            if isempty(app.LastPoints3D), return; end
            ax = get(src, 'Parent');
            pt = get(ax, 'CurrentPoint');
            u = round(pt(1, 1));
            v = round(pt(1, 2));
            [H, W, ~] = size(app.LastPoints3D);
            if u < 1 || u > W || v < 1 || v > H, return; end

            dVal = double(app.LastDisparity(v, u));
            X = double(app.LastPoints3D(v, u, 1));
            Y = double(app.LastPoints3D(v, u, 2));
            Z = double(app.LastPoints3D(v, u, 3));
            uStr = app.CalibResult.stereoParams.WorldUnits;

            if ~isfinite(dVal) || dVal < -1e5 || ~isfinite(Z) || Z <= 0
                set(app.LblMeasureInfo, 'String', sprintf( ...
                    '像素 (%d, %d) 视差无效，请点击纹理较丰富或非遮挡区域。', u, v));
            else
                dist = norm([X, Y, Z]);
                set(app.LblMeasureInfo, 'String', sprintf( ...
                    '像素 (%d, %d) | 视差 d = %.2f px | 3D 坐标: X = %.2f, Y = %.2f, Z = %.2f %s | 欧氏距离 = %.2f %s', ...
                    u, v, dVal, X, Y, Z, uStr, dist, uStr));
            end

            for targetAx = [app.AxDispLeft, app.AxDispMap]
                delete(findobj(targetAx, 'Tag', 'MeasureCross'));
                hold(targetAx, 'on');
                plot(targetAx, u, v, 'r+', 'MarkerSize', 12, 'LineWidth', 1.8, 'Tag', 'MeasureCross', ...
                    'HitTest', 'off', 'PickableParts', 'none');
                hold(targetAx, 'off');
            end
        end

        % =================================================================
        % 工具方法
        % =================================================================
        function ok = checkImageSize(app, I)
            ok = true;
            cp = app.CalibResult.stereoParams.CameraParameters1;
            if isprop(cp, 'ImageSize') && ~isempty(cp.ImageSize)
                calibSz = double(cp.ImageSize(1:2));
                curSz = [size(I, 1), size(I, 2)];
                if ~isequal(calibSz(:)', curSz)
                    errordlg(sprintf('当前图像尺寸 %dx%d (WxH) 与标定参数 %dx%d 不一致。', ...
                        curSz(2), curSz(1), calibSz(2), calibSz(1)), '尺寸不匹配');
                    ok = false;
                end
            end
        end

        function setStatus(app, msg)
            if isvalid(app.LblStatus)
                set(app.LblStatus, 'String', ['  ' msg]);
                drawnow limitrate;
            end
        end

        function cleanup = setBusy(app, msg)
            app.setStatus(msg);
            set(app.Fig, 'Pointer', 'watch');
            drawnow;
            cleanup = onCleanup(@() app.clearBusy());
        end

        function clearBusy(app)
            if isvalid(app.Fig)
                set(app.Fig, 'Pointer', 'arrow');
            end
        end

        function s = fmtMat(~, M)
            lines = cell(size(M, 1), 1);
            for r = 1:size(M, 1)
                rowStr = '  ';
                for c = 1:size(M, 2)
                    rowStr = [rowStr, sprintf('%13.6f', M(r, c))]; %#ok<AGROW>
                end
                lines{r} = rowStr;
            end
            s = strjoin(lines, sprintf('\n'));
        end
    end
end
