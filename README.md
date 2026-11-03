# 文件占用助手

[简体中文](README.md) | [English](README_EN.md)

一个面向 Windows 的轻量工具，用于查找占用文件或文件夹的应用，并在确认释放后重试移动。

![文件占用助手图标](FileLockHelper.png)

## 功能

- 扫描选定的文件或文件夹，查看 Windows Restart Manager 能识别的占用应用和服务。
- 请求相关应用正常关闭，并重新检查占用状态。
- 选择目标文件夹后重试移动；如果目标位置已存在同名文件或文件夹，程序会停止，不覆盖现有内容。
- 将操作记录保存在本机，方便之后查看处理过程。

## 运行环境

- Windows 10 或 Windows 11
- Windows PowerShell 5.1
- 程序使用系统自带的 Windows Forms 和 Restart Manager API，无需安装 Python 包或额外服务。

## 开始使用

1. 下载本仓库并解压，或使用 Git 克隆到 Windows 电脑。
2. 双击 **打开文件占用助手.cmd** 启动程序。
3. 选择文件或文件夹，点击“查找占用”。
4. 如需关闭相关应用，请先保存其中的工作，再点击“请求正常释放”。
5. 需要移动文件时，点击“释放后重试移动”，然后选择目标文件夹。

更详细的操作步骤见[中文使用说明](使用说明.md)和[English user guide](USER_GUIDE_EN.md)。

## 隐私与操作说明

- 程序请求应用正常关闭，不会强制结束进程。
- 移动前会再次检查占用情况；目标位置存在同名项目时会停止，不会覆盖。
- 操作日志保存在 **%LOCALAPPDATA%\FileLockHelper\activity.log**。程序不会将文件路径或日志发送到网络。
- 部分驱动、系统组件或特殊共享方式可能无法通过 Restart Manager 识别。遇到这种情况，可以先关闭资源管理器预览窗格、同步软件或正在使用文件的应用，再重新扫描。

## 项目文件

- **FileLockHelper.ps1**：主程序和图形界面。
- **打开文件占用助手.cmd**：启动入口。
- **使用说明.md**：中文操作步骤。
- **USER_GUIDE_EN.md**：English user guide.
- **生成图标.ps1**、**FileLockHelper.ico**、**FileLockHelper.png**：图标生成脚本和图标文件。
