# File Lock Helper

[简体中文](README.md) | [English](README_EN.md)

A lightweight Windows utility for finding applications that are using a file or folder, then retrying a move after the item is released.

![File Lock Helper icon](FileLockHelper.png)

## Features

- Scan a selected file or folder and list the applications or services recognized by Windows Restart Manager.
- Ask the related applications to close normally, then check the lock status again.
- Retry moving the item to a selected folder after it is released. If an item with the same name already exists at the destination, the operation stops without overwriting it.
- Keep an activity log on the local computer for later review.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- The utility uses Windows Forms and the Restart Manager API included with Windows. No Python packages or additional services are required.

## Getting started

1. Download and extract this repository, or clone it to a Windows computer.
2. Double-click **打开文件占用助手.cmd** to launch the utility.
3. Select a file or folder and click “查找占用” (Find locks).
4. If a related application needs to close, save your work in that application first, then click “请求正常释放” (Request normal release).
5. To move the item, click “释放后重试移动” (Retry move after release) and choose a destination folder.

See the [English user guide](USER_GUIDE_EN.md) or the [Chinese user guide](使用说明.md) for step-by-step instructions.

## Privacy and behavior

- The utility asks applications to close normally. It does not forcibly terminate processes.
- It checks the lock status again before moving. It stops if an item with the same name exists at the destination and does not overwrite it.
- The activity log is stored locally at **%LOCALAPPDATA%\FileLockHelper\activity.log**. The utility does not send file paths or logs over the network.
- Some drivers, system components, or special sharing modes may not be reported by Restart Manager. If that happens, close Explorer's Preview pane, sync software, or the application using the item, then scan again.

## Project files

- **FileLockHelper.ps1**: main program and graphical interface.
- **打开文件占用助手.cmd**: Windows launch script.
- **使用说明.md**: Chinese user guide.
- **USER_GUIDE_EN.md**: English user guide.
- **生成图标.ps1**, **FileLockHelper.ico**, and **FileLockHelper.png**: icon generation script and icon assets.


## License

This project is released under the MIT License. See [LICENSE](LICENSE).
