# 上传和运行说明

建议仓库名：mpc-robot-calibration

Description:
Industrial robot calibration with measurement configuration selection and multi-planar constraints, implemented in MATLAB.

## 上传 GitHub

解压外层 ZIP，打开 mpc-robot-calibration 文件夹，把里面的文件和子文件夹一起拖到 GitHub 上传页面，保持文件夹结构。不要只上传 ZIP。Public；README、gitignore、license 创建时不额外添加。本包已提供 README 和 .gitignore。

## 数据核查

原始 Excel 有效样本分别为 800/800/803。预选工作簿每个平面100行，300行已逐行匹配，均与同名原始平面一致，没有标签错配。保留原始文件及逐行匹配证据。论文描述每个平面800行，额外3行保留不改。

## 本地运行

在 MATLAB 中把当前目录设为项目根目录，运行：

run('matlab/calibration/mainMultiplaner.m')

默认使用提供的预选数据，每平面80条训练、20条测试。可选运行 mainObservabilityIndex 和 mainO60 分析观测性、重新选位姿。重新生成的文件写入 data/selected；要使用它，将标定脚本 dataFile 中的 provided_selection 改为 selected。

MATLAB 目标版本 R2020a+，当前环境没有 MATLAB，未执行标定，不能把论文结果说成已复现。README 图表分别是论文表格数据与标称运动学数据展示。输出文件写入 outputs。最终 RMSE/MAX/MEAN 是拉线残差，单位米，不是直接的六维位姿精度。

已移除临时锁文件、制图编辑源文件和37.6MB产品手册，保留论文、补充材料、实验表、原始数据和代码。
