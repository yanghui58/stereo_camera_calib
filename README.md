# MATLAB 双目立体标定 GUI 系统 (Stereo Calibration Suite)

基于 **MATLAB 官方视觉工具箱** 构建的标准棋盘格双目立体标定与精度验证 GUI 程序（兼容 **MATLAB R2017b** 及以上版本）。

## 功能特性

- **双模式数据加载**：支持「左右双文件夹」和「单文件夹左右拼接图（自动裁切）」，基于 `imageDatastore` 扫描、自然排序并自动校验全量图像分辨率一致性。
- **内置合成测试集**：一键生成 14 组带真实畸变和已知真值的双目棋盘格数据，零素材即可体验完整流程。
- **亚像素角点与误差矢量**：并排预览检测到的角点，支持叠加放大后的重投影误差矢量（`quiver`）定位局部畸变残留。
- **交互式筛选与重标**：左侧表格按 `max(左, 右)` 重投影误差展示，支持逐对勾选及按阈值一键剔除高误差图像对并重标。
- **多维度精度评估**：全部调用 MATLAB 官方工具箱输出重投影误差、官方校正单应 `H1/H2` 垂直极线误差、点到极线距离（`epipolarLine`）、**3D 物理尺度重建误差**（`triangulate` + `pdist`）、基线长度、欧拉角（`rotm2eul`）与 Rodrigues 向量（`rotationMatrixToVector`）。
- **极线校正检验**：支持「左右并排 + 水平极线」与「红绿立体叠加（`stereoAnaglyph`）」，并在校正后图像上用双目 `detectCheckerboardPoints(J1, J2)` 实测 `|dy|`。
- **视差与 3D 点击测距**：支持 `SemiGlobal` / `BlockMatching`（自动边界钳位与 16 倍数对齐），鼠标点击任意像素实时显示 `(X, Y, Z)` 坐标与欧氏距离。
- **参数导出与复用**：一键导出 `.mat`（含已初始化校正参数的官方 `stereoParams`）、`.json` 与中文 `.txt` 精度报告；支持直接导入已有 `.mat`（含官方 `stereoCameraCalibrator` 导出结果）。

## 环境依赖

- MATLAB R2017b 及以上
- Computer Vision System Toolbox
- Image Processing Toolbox
- Robotics System Toolbox（用于 `rotm2eul` / `eul2rotm`）
- Statistics and Machine Learning Toolbox（用于 `pdist`）

> **编码说明**：为兼容中文 Windows 下 MATLAB R2017b 的默认字符集（防 GUI 中文乱码），`.m` 源码文件采用 **GBK (CP936)** 编码保存。

## 快速开始

在 MATLAB 中将工作目录切换至项目根目录，运行：

```matlab
app = StereoCalibApp();
```

## 项目结构

```text
├── StereoCalibApp.m                 # GUI 主程序入口
└── +stereo/
    ├── loadImagePairs.m             # 图像扫描、自然排序、拼接图裁切与尺寸校验
    ├── runCalibration.m             # 基于官方工具箱的双目标定与多维度精度评估
    ├── exportParameters.m           # 导出 .mat / .json / 中文 .txt 报告
    └── generateSyntheticDataset.m   # 带已知真值的合成双目棋盘格数据生成器
```
