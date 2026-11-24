function [leftDir, rightDir, groundTruth] = generateSyntheticDataset(outRoot, numPairs)
% GENERATESYNTHETICDATASET 生成带已知真值内参/外参/畸变的合成双目棋盘格测试数据集
%   调用 MATLAB Robotics System Toolbox eul2rotm 构造位姿，用于快速演练与回归验证

    if nargin < 1 || isempty(outRoot)
        outRoot = fullfile(pwd, 'demo_data');
    end
    if nargin < 2 || isempty(numPairs)
        numPairs = 14;
    end

    leftDir = fullfile(outRoot, 'left');
    rightDir = fullfile(outRoot, 'right');
    if ~exist(leftDir, 'dir'), mkdir(leftDir); end
    if ~exist(rightDir, 'dir'), mkdir(rightDir); end

    % 真值相机参数 (640x480, 基线 ~120.03 mm, 轻微会聚角)
    W = 640;
    H = 480;
    K1 = [720,   0, 324; ...
            0, 722, 238; ...
            0,   0,   1];
    D1 = [-0.12, 0.04, 0.0008, -0.0006]; % [k1, k2, p1, p2]

    K2 = [718,   0, 316; ...
            0, 720, 243; ...
            0,   0,   1];
    D2 = [-0.10, 0.03, -0.0005, 0.0007];

    % 右相机相对左相机外参: X_c2 = R * X_c1 + T
    R_gt = eul2rotm(deg2rad([-1.5, 0.8, 0.4]), 'ZYX');
    T_gt = [-120.0; 1.2; -2.5]; % mm

    % 棋盘格参数: 10 x 7 方格 (9 x 6 内角点), 方格 25 mm, 四周留 1 格白边
    rowsSq = 7;
    colsSq = 10;
    sqSize = 25.0; % mm

    % 利用 kron 向量化构造棋盘格纹理图 (每格 40 像素, 四周白边 40 像素)
    ppSq = 40;
    margin = 40;
    pattern = mod((0:rowsSq-1)' + (0:colsSq-1), 2) == 0;
    innerTex = kron(double(pattern), ones(ppSq));
    boardTexD = 245 * ones(rowsSq * ppSq + 2 * margin, colsSq * ppSq + 2 * margin);
    boardTexD((margin+1):(end-margin), (margin+1):(end-margin)) = 245 - 223 * innerTex;

    % 预设多样化位姿 (居中于左右双目公共视野 X ≈ +60 mm)
    rng(2026);
    poses = [ ...
         0,   0,   0,   600,   60,    0; ...
        18, -12,   5,   620,   45,  -15; ...
       -18,  10,  -6,   640,   75,   10; ...
        12,  16,  10,   580,   55,  -20; ...
       -15, -14,  -8,   650,   65,   18; ...
        22,   5,  -4,   610,   40,    8; ...
       -20,  -6,  12,   630,   80,  -12; ...
         5,  20,  -5,   590,   60,   15; ...
        -6, -20,   6,   640,   50,  -15; ...
        15,  12, -14,   580,   70,   -8; ...
       -14,  15,  14,   660,   55,   12; ...
        10, -18,   8,   620,   65,   15; ...
       -12, -10, -12,   600,   45,   -5; ...
         8,   8,   4,   680,   60,  -18; ...
       -16,  18,  -3,   590,   72,    5; ...
        20, -15,  10,   650,   52,  -10];

    numPairs = min(numPairs, size(poses, 1));
    [uGrid, vGrid] = meshgrid(1:W, 1:H);
    boardWmm = colsSq * sqSize;
    boardHmm = rowsSq * sqSize;

    for i = 1:numPairs
        R_b = eul2rotm(deg2rad([poses(i, 3), poses(i, 2), poses(i, 1)]), 'ZYX');
        T_b1 = [poses(i, 5); poses(i, 6); poses(i, 4)] + R_b * [-boardWmm/2; -boardHmm/2; 0];

        IL = renderBoardImage(uGrid, vGrid, K1, D1, R_b, T_b1, boardTexD, ppSq, sqSize, margin);
        IR = renderBoardImage(uGrid, vGrid, K2, D2, R_gt * R_b, R_gt * T_b1 + T_gt, boardTexD, ppSq, sqSize, margin);

        IL = uint8(min(max(IL + 1.5 * randn(H, W), 0), 255));
        IR = uint8(min(max(IR + 1.5 * randn(H, W), 0), 255));

        imwrite(IL, fullfile(leftDir,  sprintf('left_%02d.png', i)));
        imwrite(IR, fullfile(rightDir, sprintf('right_%02d.png', i)));
    end

    groundTruth = struct( ...
        'K1', K1, 'D1', D1, 'K2', K2, 'D2', D2, ...
        'R', R_gt, 'T', T_gt, 'baseline', norm(T_gt), ...
        'squareSize', sqSize, 'boardSize', [rowsSq, colsSq]);
end

function img = renderBoardImage(uGrid, vGrid, K, D, R, T, boardTexD, ppSq, sqSize, margin)
% 反向光线投射：像素 -> 迭代去畸变 -> 与标定板平面 Z_w=0 求交 -> 双线性采样
    [H, ~] = size(uGrid);
    xd = (uGrid - K(1, 3)) / K(1, 1);
    yd = (vGrid - K(2, 3)) / K(2, 2);

    x = xd;
    y = yd;
    k1 = D(1); k2 = D(2); p1 = D(3); p2 = D(4);
    for iter = 1:6
        r2 = x.^2 + y.^2;
        radial = 1 + k1 * r2 + k2 * (r2.^2);
        dx = 2 * p1 * x .* y + p2 * (r2 + 2 * x.^2);
        dy = p1 * (r2 + 2 * y.^2) + 2 * p2 * x .* y;
        x = (xd - dx) ./ radial;
        y = (yd - dy) ./ radial;
    end

    n = R(:, 3);
    s = (n' * T) ./ (n(1) * x + n(2) * y + n(3));
    Xc = s .* x - T(1);
    Yc = s .* y - T(2);
    Zc = s      - T(3);

    Xw = R(1, 1) * Xc + R(2, 1) * Yc + R(3, 1) * Zc;
    Yw = R(1, 2) * Xc + R(2, 2) * Yc + R(3, 2) * Zc;

    tx = Xw * (ppSq / sqSize) + margin + 0.5;
    ty = Yw * (ppSq / sqSize) + margin + 0.5;

    bg = 110 + 15 * (vGrid / H);
    sampled = interp2(boardTexD, tx, ty, 'linear', NaN);
    mask = ~isnan(sampled) & (s > 0);
    img = bg;
    img(mask) = sampled(mask);
end
