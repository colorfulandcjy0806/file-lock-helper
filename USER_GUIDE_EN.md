# File Lock Helper User Guide

## Launch

Double-click **打开文件占用助手.cmd** to start the utility. The desktop shortcut created on the development computer is local-only and is not included in this repository.

## Find what is using a file

1. Click “选择文件” (Choose file) or “选择文件夹” (Choose folder), then select the item that could not be moved.
2. Click “查找占用” (Find locks) to see the applications or services Windows can identify.
3. Review the list and save any work in the applications that need to close.

## Release the lock and retry the move

1. Click “请求正常释放” (Request normal release). The utility asks the related applications to close normally; it does not force-terminate them.
2. If you also need to move the item, click “释放后重试移动” (Retry move after release).
3. Choose the destination folder. The utility checks the lock status again before moving the item.
4. If an item with the same name already exists in the destination, the move stops and the existing item is left untouched.

## Activity log

The activity log is stored locally at:

**%LOCALAPPDATA%\FileLockHelper\activity.log**

## Notes

The utility uses Windows Restart Manager to find processes associated with the selected item. Some drivers, system components, or special sharing modes may not appear in the results. If the item remains in use, close Explorer's Preview pane, sync software, or the application accessing it, then scan again. An application may also reopen the item after it has been released.
