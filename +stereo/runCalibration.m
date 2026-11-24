function result = runCalibration(imagePoints, boardSize, squareSize, worldUnits, imageSize, opts)
% RUNCALIBRATION 基于 MATLAB 官方工具箱执行双目立体标定与精度量化评估
%   全程调用 MATLAB 官方工具箱函数，不重复实现底层数学求解器:
%     - generateCheckerboardPoints / estimateCameraParameters (Computer Vision Toolbox)
%     - rectifyStereoImages / undistortPoints / epipolarLine / triangulate (Computer Vision Toolbox)
%     - rotationMatrixToVector (Computer Vision Toolbox) / rotm2eul (Robotics System Toolbox)
%     - projective2d / transformPointsForward (Image Processing Toolbox)
%     - pdist (Statistics and Machine Learning Toolbox)

    if nargin < 6 || isempty(opts)
        opts = struct('numRadial', 2, 'estimateTangential', true, 'estimateSkew', false);
    end

    worldPoints = generateCheckerboardPoints(boardSize, squareSize);

    [stereoParams, pairsUsed, estimationErrors] = estimateCameraParameters( ...
        imagePoints, worldPoints, ...
        'EstimateSkew', logical(opts.estimateSkew), ...
        'EstimateTangentialDistortion', logical(opts.estimateTangential), ...
        'NumRadialDistortionCoefficients', opts.numRadial, ...
        'WorldUnits', worldUnits, ...
        'ImageSize', imageSize);
    pairsUsed = logical(pairsUsed(:));

    % 用官方 rectifyStereoImages 初始化 stereoParams 内置 RectificationParams (H1, H2, Q)
    dummyImg = zeros(imageSize(1), imageSize(2), 'uint8');
    rectifyStereoImages(dummyImg, dummyImg, stereoParams, 'OutputView', 'valid');
    spStruct = toStruct(stereoParams);
    rectParams = spStruct.RectificationParams;

    % 提取每对图像的重投影误差 (像素)
    err1 = stereoParams.CameraParameters1.ReprojectionErrors; % M x 2 x N_used
    err2 = stereoParams.CameraParameters2.ReprojectionErrors;
    numPairs = size(err1, 3);
    perPairErrLeft = zeros(numPairs, 1);
    perPairErrRight = zeros(numPairs, 1);
    for i = 1:numPairs
        perPairErrLeft(i) = mean(hypot(err1(:, 1, i), err1(:, 2, i)));
        perPairErrRight(i) = mean(hypot(err2(:, 1, i), err2(:, 2, i)));
    end
    perPairErrMean = 0.5 * (perPairErrLeft + perPairErrRight);
    perPairErrMax  = max(perPairErrLeft, perPairErrRight);

    % 使用官方工具箱计算旋转向量、欧拉角、极线精度与 3D 物理尺度精度
    % MATLAB stereoParams 为行向量约定 (X2 = X1 * R_mat + t_mat)，
    % 其列向量等价旋转矩阵为 R_col = R_mat'
    R_col = stereoParams.RotationOfCamera2';
    T_col = stereoParams.TranslationOfCamera2(:);
    rvecRad = rotationMatrixToVector(stereoParams.RotationOfCamera2);
    if ~isempty(which('rotm2eul'))
        eulDeg = rad2deg(rotm2eul(R_col, 'ZYX'));
    else
        eulDeg = rad2deg([atan2(R_col(2,1), R_col(1,1)), asin(max(min(-R_col(3,1),1),-1)), atan2(R_col(3,2), R_col(3,3))]);
    end
    baseline = norm(T_col);

    % 利用官方校正单应 H1/H2、epipolarLine 与 triangulate 评估全数据集真实几何精度
    usedPts = imagePoints(:, :, pairsUsed, :);
    tform1 = projective2d(rectParams.H1);
    tform2 = projective2d(rectParams.H2);
    gtPairDist = pdist(worldPoints);

    rectDyAll = [];
    epiDistAll = [];
    scaleErrAll = [];
    for i = 1:size(usedPts, 3)
        u1 = undistortPoints(usedPts(:, :, i, 1), stereoParams.CameraParameters1);
        u2 = undistortPoints(usedPts(:, :, i, 2), stereoParams.CameraParameters2);

        % 1) 官方极线校正后的垂直对齐残差 |y_L - y_R|
        r1 = transformPointsForward(tform1, u1);
        r2 = transformPointsForward(tform2, u2);
        rectDyAll = [rectDyAll; abs(r1(:, 2) - r2(:, 2))]; %#ok<AGROW>

        % 2) 官方 epipolarLine 点到极线距离
        epiLines = epipolarLine(stereoParams.FundamentalMatrix, u1);
        dEpi = abs(sum(epiLines .* [u2, ones(size(u2, 1), 1)], 2)) ./ hypot(epiLines(:, 1), epiLines(:, 2));
        epiDistAll = [epiDistAll; dEpi]; %#ok<AGROW>

        % 3) 官方 triangulate 三角化 3D 点与棋盘格物理真值距离对比 (检验防过拟合)
        pts3D = triangulate(u1, u2, stereoParams);
        estPairDist = pdist(pts3D);
        scaleErrAll = [scaleErrAll, abs(estPairDist - gtPairDist)]; %#ok<AGROW>
    end

    % 整理便于阅读与 JSON 导出的结构化参数 (标准列向量表示: X_c2 = R * X_c1 + T)
    K1 = stereoParams.CameraParameters1.IntrinsicMatrix';
    K2 = stereoParams.CameraParameters2.IntrinsicMatrix';
    D1 = packDistortion(stereoParams.CameraParameters1);
    D2 = packDistortion(stereoParams.CameraParameters2);

    paramsStruct = struct( ...
        'imageWidth', imageSize(2), ...
        'imageHeight', imageSize(1), ...
        'K1', K1, 'D1', D1, ...
        'K2', K2, 'D2', D2, ...
        'R', R_col, 'T', T_col, ...
        'E', stereoParams.EssentialMatrix, ...
        'F', stereoParams.FundamentalMatrix, ...
        'H1', rectParams.H1, ...
        'H2', rectParams.H2, ...
        'Q', rectParams.Q);

    metrics = struct( ...
        'meanReprojError', stereoParams.MeanReprojectionError, ...
        'leftMeanReprojError', stereoParams.CameraParameters1.MeanReprojectionError, ...
        'rightMeanReprojError', stereoParams.CameraParameters2.MeanReprojectionError, ...
        'perPairErrLeft', perPairErrLeft, ...
        'perPairErrRight', perPairErrRight, ...
        'perPairErrMean', perPairErrMean, ...
        'perPairErrMax', perPairErrMax, ...
        'baseline', baseline, ...
        'worldUnits', worldUnits, ...
        'rvecDeg', rad2deg(rvecRad(:)'), ...
        'eulerZYXDeg', eulDeg, ...
        'epipolarMeanPx', mean(rectDyAll), ...
        'epipolarRmsPx', sqrt(mean(rectDyAll.^2)), ...
        'epipolarMaxPx', max(rectDyAll), ...
        'epiLineDistMeanPx', mean(epiDistAll), ...
        'scaleErrMean', mean(scaleErrAll), ...
        'scaleErrMax', max(scaleErrAll), ...
        'scaleErrRelPct', 100 * mean(scaleErrAll) / mean(gtPairDist), ...
        'numPairs', numPairs, ...
        'boardSize', boardSize, ...
        'squareSize', squareSize, ...
        'usedPairIndices', []);

    result = struct( ...
        'stereoParams', stereoParams, ...
        'estimationErrors', estimationErrors, ...
        'pairsUsed', pairsUsed, ...
        'paramsStruct', paramsStruct, ...
        'metrics', metrics);
end

function D = packDistortion(camParams)
% 打包畸变系数 [k1, k2, p1, p2, k3]
    rad = camParams.RadialDistortion;
    tanD = camParams.TangentialDistortion;
    k3 = 0;
    if numel(rad) >= 3
        k3 = rad(3);
    end
    D = [rad(1), rad(2), tanD(1), tanD(2), k3];
end
