function [leftFiles, rightFiles, info] = loadImagePairs(mode, path1, path2)
% LOADIMAGEPAIRS 使用 MATLAB 官方 imageDatastore 扫描并配对双目图像文件
%   mode  - 'separate' (双文件夹) 或 'sidebyside' (单文件夹左右拼接图)
%   path1 - 左图文件夹 (separate) 或 拼接图文件夹 (sidebyside)
%   path2 - 右图文件夹 (仅 separate 模式需要)

    info = struct('mode', mode, 'count', 0, 'imageSize', [], 'message', '');

    if strcmpi(mode, 'separate')
        leftFiles = scanImageDir(path1);
        rightFiles = scanImageDir(path2);

        nL = numel(leftFiles);
        nR = numel(rightFiles);
        if nL ~= nR
            nMin = min(nL, nR);
            warning('StereoCalib:CountMismatch', ...
                '左图(%d)与右图(%d)数量不一致，已按前 %d 对配对。', nL, nR, nMin);
            leftFiles = leftFiles(1:nMin);
            rightFiles = rightFiles(1:nMin);
            msgPrefix = sprintf('警告：左右图数量不一致(%d vs %d)，已截断为 %d 对。', nL, nR, nMin);
        else
            msgPrefix = sprintf('成功加载 %d 对双目图像。', nL);
        end

        % 校验所有左右图像分辨率一致
        imSize = validatePairSizes(leftFiles, rightFiles);
        info.count = numel(leftFiles);
        info.imageSize = imSize;
        info.message = sprintf('%s 分辨率: %d x %d (W x H)。', msgPrefix, imSize(2), imSize(1));

    elseif strcmpi(mode, 'sidebyside')
        rawFiles = scanImageDir(path1);
        cacheRoot = fullfile(path1, '_split_cache');
        leftDir = fullfile(cacheRoot, 'left');
        rightDir = fullfile(cacheRoot, 'right');
        if ~exist(leftDir, 'dir'), mkdir(leftDir); end
        if ~exist(rightDir, 'dir'), mkdir(rightDir); end

        n = numel(rawFiles);
        leftFiles = cell(n, 1);
        rightFiles = cell(n, 1);
        for i = 1:n
            I = imread(rawFiles{i});
            [~, W, ~] = size(I);
            if W < 4
                error('StereoCalib:InvalidImage', '拼接图宽度过小: %s', rawFiles{i});
            end
            halfW = floor(W / 2);
            [~, baseName, ~] = fileparts(rawFiles{i});
            % 加序号前缀避免同主名不同后缀文件覆盖
            lPath = fullfile(leftDir,  sprintf('%04d_%s_L.png', i, baseName));
            rPath = fullfile(rightDir, sprintf('%04d_%s_R.png', i, baseName));
            imwrite(I(:, 1:halfW, :), lPath);
            imwrite(I(:, (W - halfW + 1):W, :), rPath);
            leftFiles{i} = lPath;
            rightFiles{i} = rPath;
        end
        imSize = validatePairSizes(leftFiles, rightFiles);
        info.count = n;
        info.imageSize = imSize;
        info.message = sprintf('已裁切并加载 %d 对拼接图 (%dx%d，缓存于 _split_cache)。', ...
            n, imSize(2), imSize(1));
    else
        error('StereoCalib:InvalidMode', '不支持的加载模式: %s', mode);
    end
end

function files = scanImageDir(folderPath)
    if ~exist(folderPath, 'dir')
        error('StereoCalib:DirNotFound', '目录不存在: %s', folderPath);
    end
    try
        imds = imageDatastore(folderPath, 'IncludeSubfolders', false);
        files = imds.Files;
    catch
        error('StereoCalib:EmptyDir', '目录中未找到 MATLAB 支持的图像文件: %s', folderPath);
    end
    if isempty(files)
        error('StereoCalib:EmptyDir', '目录中未找到支持的图像文件: %s', folderPath);
    end
    files = naturalSortPaths(files);
end

function imSize = validatePairSizes(leftFiles, rightFiles)
% 使用 imfinfo 快速检查全部左右图尺寸是否一致（无需逐张解码像素）
    refInfo = imfinfo(leftFiles{1});
    imSize = [refInfo.Height, refInfo.Width];
    for i = 1:numel(leftFiles)
        li = imfinfo(leftFiles{i});
        ri = imfinfo(rightFiles{i});
        if li.Height ~= imSize(1) || li.Width ~= imSize(2) || ...
           ri.Height ~= imSize(1) || ri.Width ~= imSize(2)
            error('StereoCalib:SizeMismatch', ...
                '第 %d 对图像尺寸与第 1 对 (%dx%d) 不一致: 左(%dx%d), 右(%dx%d)。', ...
                i, imSize(2), imSize(1), li.Width, li.Height, ri.Width, ri.Height);
        end
    end
end

function sorted = naturalSortPaths(fullPaths)
% 对文件名中的数字做自然排序 (如 img2 排在 img10 之前)
    if numel(fullPaths) <= 1
        sorted = fullPaths;
        return;
    end
    keys = cell(size(fullPaths));
    for i = 1:numel(fullPaths)
        [~, name, ext] = fileparts(fullPaths{i});
        keys{i} = regexprep(lower([name ext]), '(\d+)', '${sprintf(''%010d'', str2double($1))}');
    end
    [~, idx] = sort(keys);
    sorted = fullPaths(idx);
end
