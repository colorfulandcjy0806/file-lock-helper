# 🔥 File Lock Helper User Guide

File in use? Select it, scan for locks, and follow the prompts. After the lock is released, retry the move from the utility.

## 🚀 Launch

Double-click **打开文件占用助手.cmd** to start. No installation is needed.

## ⚡ Find and move an item

1. Click “选择文件” (Choose file) or “选择文件夹” (Choose folder), then select the item that could not be moved.
2. Click “查找占用” (Find locks) to see the applications or services Windows can identify.
3. If a related application needs to close, save your work first, then click “请求正常释放” (Request normal release).
4. To move the item, click “释放后重试移动” (Retry move after release) and choose a destination. The utility checks the lock status again before moving.
5. If an item with the same name already exists in the destination, the move stops without overwriting it.

## 📒 Activity log

The log stays on your computer at:

%LOCALAPPDATA%\FileLockHelper\activity.log

## 💡 Tip

A small number of system components, drivers, or sync tasks may not appear in the results. If that happens, close Explorer's Preview pane or the related application and scan again.