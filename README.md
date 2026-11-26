# MATLAB 双目工业相机采集与立体标定 GUI 系统 (Stereo Calibration Suite)

基于 **MATLAB 官方工具箱** 构建的双目工业相机实时预览采集与标准棋盘格立体标定系统（兼容 **MATLAB R2017b** 及以上版本，针对京航 **JHUM1204B** 双目相机真机适配验证）。

## 核心功能模块

### 1. 双目工业相机实时预览与同步采集 (`StereoCaptureApp.m`)
- **即插即用双目控制**：基于 `Image Acquisition Toolbox (winvideo)` 自动枚举相机，支持热插拔刷新与一键互换左右相机。
- **分辨率与 ROI 裁剪**：支持硬件全档位分辨率（如 `2048×1500` 高帧率全视场、`4096×3000` 1200 万满幅）、`8位灰度 / RGB24` 切换及 4 字节对齐居中 ROI 裁剪，切换时自动保持已调好的曝光与增益。
- **双目配平与无警告翻转**：实时调节曝光（`1~10000`）、增益（`0~200`）、伽马、对比度；支持启动自动配平、「左→右配平」及单相机微调；支持京航硬件寄存器级水平/垂直翻转（`WB=11~14`）与连续流/软触发流（`WB=20~22`）。
- **调焦与对齐辅助**：实时叠加中心十字准星与水平对齐网格，实时计算 Tenengrad 清晰度对焦评分与过曝标红告警。
- **单人高效采图**：亚毫秒级双目同步帧抓取，支持防误触**空格键（`Space`）盲拍**、定时自动连拍、多级撤销栈、防覆盖保护、拍前棋盘格角点可视化预检，拍完点击 **「去标定>>」** 一键自动导入标定系统。

### 2. 双目立体标定与多维精度验证 (`StereoCalibApp.m`)
- **双模式数据加载**：支持「左右双文件夹」和「单文件夹左右拼接图（自动裁切）」，基于 `imageDatastore` 扫描、自然排序并自动校验全量图像分辨率一致性。
- **内置合成测试集**：一键生成 14 组带真实畸变和已知真值的双目棋盘格数据，零素材即可体验完整流程。
- **亚像素角点与误差矢量**：并排预览检测到的角点，支持叠加放大后的重投影误差矢量（`quiver`）定位局部畸变残留。
- **交互式筛选与重标**：左侧表格按 `max(左, 右)` 重投影误差展示，支持逐对勾选及按阈值一键剔除高误差图像对并重标。
- **多维度精度评估**：调用 MATLAB 官方工具箱输出重投影误差、官方校正单应 `H1/H2` 垂直极线误差、点到极线距离（`epipolarLine`）、**3D 物理尺度重建误差**（`triangulate` + `pdist`）、基线长度、欧拉角（`rotm2eul`）与 Rodrigues 向量（`rotationMatrixToVector`）。
- **极线校正检验与 3D 测距**：支持「左右并排 + 水平极线」与「红绿立体叠加」，校正图双目重检角点实测 `|dy|`；支持 `SemiGlobal / BlockMatching` 视差计算与鼠标点击任意像素实时 3D 测距。
- **参数导出与复用**：一键导出 `.mat`（含已初始化校正参数的官方 `stereoParams`）、`.json` 与中文 `.txt` 精度报告。

## 环境依赖

- MATLAB R2017b 及以上
- Image Acquisition Toolbox + `OS Generic Video Interface (winvideo)` 支持包（实拍采集需安装，并用 `DShowManager2` 注册相机）
- Computer Vision System Toolbox
- Image Processing Toolbox
- Robotics System Toolbox（用于 `rotm2eul` / `eul2rotm`）
- Statistics and Machine Learning Toolbox（用于 `pdist`）

> **编码说明**：为兼容中文 Windows 下 MATLAB R2017b 的默认字符集（防 GUI 中文乱码），`.m` 源码文件采用 **GBK (CP936)** 编码保存。

## 快速开始

在 MATLAB 中将工作目录切换至项目根目录：

```matlab
% 1. 启动双目工业相机实时预览与同步采集 GUI
cap = StereoCaptureApp();

% 2. 启动双目立体标定与精度验证 GUI（也可在采集界面点击「去标定>>」自动跳转导入）
app = StereoCalibApp();
```

## 项目结构

```text
├── StereoCaptureApp.m               # 双目工业相机实时预览、参数设置与同步采集 GUI (单文件独立运行)
├── StereoCalibApp.m                 # 双目立体标定与多维精度验证 GUI 主程序
└── +stereo/
    ├── loadImagePairs.m             # 图像扫描、自然排序、拼接图裁切与尺寸校验
    ├── runCalibration.m             # 基于官方工具箱的双目标定与多维度精度评估
    ├── exportParameters.m           # 导出 .mat / .json / 中文 .txt 报告
    └── generateSyntheticDataset.m   # 带已知真值的合成双目棋盘格数据生成器
```
