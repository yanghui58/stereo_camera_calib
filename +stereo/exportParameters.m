function filesWritten = exportParameters(outDir, calibResult, prefix)
% EXPORTPARAMETERS 导出 MATLAB 原生 .mat、JSON 与中文标定精度报告 (.txt)
%   outDir      - 目标输出目录
%   calibResult - stereo.runCalibration 返回的结果结构体
%   prefix      - 文件名前缀 (默认 'stereo_calib')

    if nargin < 3 || isempty(prefix)
        prefix = 'stereo_calib';
    end
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    stereoParams = calibResult.stereoParams; %#ok<NASGU>
    estimationErrors = calibResult.estimationErrors; %#ok<NASGU>
    paramsStruct = calibResult.paramsStruct;
    metrics = calibResult.metrics;

    % 1. MATLAB 原生 .mat (含已初始化校正参数的 stereoParams，可直接用于官方函数)
    matFile = fullfile(outDir, [prefix '.mat']);
    save(matFile, 'stereoParams', 'estimationErrors', 'paramsStruct', 'metrics');

    % 2. JSON (.json) - MATLAB 原生 jsonencode
    jsonFile = fullfile(outDir, [prefix '.json']);
    jsonData = struct('metrics', metrics, 'parameters', paramsStruct);
    fid = fopen(jsonFile, 'w', 'n', 'UTF-8');
    if fid == -1
        error('StereoCalib:WriteError', '无法写入 JSON 文件: %s', jsonFile);
    end
    fprintf(fid, '%s\n', jsonencode(jsonData));
    fclose(fid);

    % 3. 可读中文标定报告 (.txt)
    txtFile = fullfile(outDir, [prefix '_report.txt']);
    writeTextReport(txtFile, calibResult);

    filesWritten = {matFile; jsonFile; txtFile};
end

function writeTextReport(filePath, calibResult)
    fid = fopen(filePath, 'w', 'n', 'UTF-8');
    if fid == -1
        error('StereoCalib:WriteError', '无法写入文本报告: %s', filePath);
    end
    cleaner = onCleanup(@() fclose(fid));

    p = calibResult.paramsStruct;
    m = calibResult.metrics;

    fprintf(fid, '============================================================\n');
    fprintf(fid, '              MATLAB 双目立体标定精度与参数报告\n');
    fprintf(fid, '============================================================\n');
    fprintf(fid, '生成时间       : %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, '图像分辨率     : %d x %d (W x H)\n', p.imageWidth, p.imageHeight);
    fprintf(fid, '棋盘格尺寸     : %d x %d 方格 (内角点 %d x %d), 边长 %.3f %s\n', ...
        m.boardSize(1), m.boardSize(2), m.boardSize(1)-1, m.boardSize(2)-1, m.squareSize, m.worldUnits);
    fprintf(fid, '有效图像对数   : %d\n', m.numPairs);
    if isfield(m, 'usedPairIndices') && ~isempty(m.usedPairIndices)
        fprintf(fid, '参与标定序号   : %s\n', mat2str(m.usedPairIndices(:)'));
    end
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, '[精度指标 (基于 MATLAB 官方工具箱实测)]\n');
    fprintf(fid, '  总体平均重投影误差    : %.4f px (左: %.4f px | 右: %.4f px)\n', ...
        m.meanReprojError, m.leftMeanReprojError, m.rightMeanReprojError);
    fprintf(fid, '  校正后极线垂直误差    : Mean = %.4f px | RMS = %.4f px | Max = %.4f px\n', ...
        m.epipolarMeanPx, m.epipolarRmsPx, m.epipolarMaxPx);
    fprintf(fid, '  极线点到线距离 (Mean) : %.4f px\n', m.epiLineDistMeanPx);
    fprintf(fid, '  3D 物理尺度重建误差   : Mean = %.4f %s (%.4f%%) | Max = %.4f %s\n', ...
        m.scaleErrMean, m.worldUnits, m.scaleErrRelPct, m.scaleErrMax, m.worldUnits);
    fprintf(fid, '  双目基线长度 B        : %.4f %s\n', m.baseline, m.worldUnits);
    fprintf(fid, '  相对欧拉角 ZYX (deg)  : Yaw = %.4f, Pitch = %.4f, Roll = %.4f\n', ...
        m.eulerZYXDeg(1), m.eulerZYXDeg(2), m.eulerZYXDeg(3));
    fprintf(fid, '  Rodrigues 向量 (deg)  : [%.4f, %.4f, %.4f]\n', ...
        m.rvecDeg(1), m.rvecDeg(2), m.rvecDeg(3));
    fprintf(fid, '------------------------------------------------------------\n');
    fprintf(fid, '[相机参数 (K/R/T 采用标准列向量写法: X_c2 = R * X_c1 + T，主点为 MATLAB 1-based)]\n');
    fprintf(fid, '[注: stereo_calib.mat 中保存完整的 MATLAB 原生 stereoParams 对象]\n\n');
    printMat(fid, '左相机内参 K1', p.K1);
    printMat(fid, '左相机畸变 D1 [k1, k2, p1, p2, k3]', p.D1);
    printMat(fid, '右相机内参 K2', p.K2);
    printMat(fid, '右相机畸变 D2 [k1, k2, p1, p2, k3]', p.D2);
    printMat(fid, '相对旋转矩阵 R (Left -> Right)', p.R);
    printMat(fid, '相对平移向量 T (Left -> Right)', p.T);
    printMat(fid, '本质矩阵 E (MATLAB stereoParams.EssentialMatrix)', p.E);
    printMat(fid, '基础矩阵 F (MATLAB stereoParams.FundamentalMatrix)', p.F);
    printMat(fid, '官方立体校正重投影矩阵 Q (RectificationParams.Q)', p.Q);
end

function printMat(fid, titleStr, M)
    fprintf(fid, '%s:\n', titleStr);
    for r = 1:size(M, 1)
        fprintf(fid, '  ');
        for c = 1:size(M, 2)
            fprintf(fid, '%14.6f', M(r, c));
        end
        fprintf(fid, '\n');
    end
    fprintf(fid, '\n');
end
