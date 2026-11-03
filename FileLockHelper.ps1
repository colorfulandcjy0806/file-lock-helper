#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$rmSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class FileLockRestartManager
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RM_UNIQUE_PROCESS
    {
        public int dwProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }

    public enum RM_APP_TYPE
    {
        Unknown = 0, MainWindow = 1, OtherWindow = 2, Service = 3,
        Explorer = 4, Console = 5, Critical = 1000
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct RM_PROCESS_INFO
    {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
        public RM_APP_TYPE ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, StringBuilder strSessionKey);

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmRegisterResources(uint dwSessionHandle, uint nFiles,
        [MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPWStr)] string[] rgsFilenames,
        uint nApplications, IntPtr rgApplications, uint nServices, IntPtr rgsServiceNames);

    [DllImport("rstrtmgr.dll")]
    private static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded,
        ref uint pnProcInfo, IntPtr rgAffectedApps, out uint lpdwRebootReasons);

    [DllImport("rstrtmgr.dll")]
    private static extern int RmShutdown(uint dwSessionHandle, uint lActionFlags, IntPtr fnStatus);

    [DllImport("rstrtmgr.dll")]
    private static extern int RmEndSession(uint dwSessionHandle);

    private const int ERROR_MORE_DATA = 234;
    private const int MAX_PATHS_PER_CALL = 2048;

    private static uint StartSession()
    {
        uint session;
        var key = new StringBuilder(33);
        int rc = RmStartSession(out session, 0, key);
        if (rc != 0) throw new InvalidOperationException("Restart Manager 启动失败，错误码：" + rc);
        return session;
    }

    private static void Register(uint session, string[] paths)
    {
        for (int offset = 0; offset < paths.Length; offset += MAX_PATHS_PER_CALL)
        {
            int count = Math.Min(MAX_PATHS_PER_CALL, paths.Length - offset);
            var chunk = new string[count];
            Array.Copy(paths, offset, chunk, 0, count);
            int rc = RmRegisterResources(session, (uint)count, chunk, 0, IntPtr.Zero, 0, IntPtr.Zero);
            if (rc != 0) throw new InvalidOperationException("注册待检查路径失败，错误码：" + rc);
        }
    }

    public static RM_PROCESS_INFO[] GetProcesses(string[] paths)
    {
        uint session = StartSession();
        try
        {
            Register(session, paths);
            for (int attempt = 0; attempt < 4; attempt++)
            {
                uint needed;
                uint count = 0;
                uint rebootReasons;
                int rc = RmGetList(session, out needed, ref count, IntPtr.Zero, out rebootReasons);
                if (rc == 0 && needed == 0) return new RM_PROCESS_INFO[0];
                if (rc != ERROR_MORE_DATA && rc != 0)
                    throw new InvalidOperationException("读取占用进程失败，错误码：" + rc);

                count = needed;
                int size = Marshal.SizeOf(typeof(RM_PROCESS_INFO));
                IntPtr buffer = Marshal.AllocHGlobal(checked(size * (int)count));
                try
                {
                    rc = RmGetList(session, out needed, ref count, buffer, out rebootReasons);
                    if (rc == ERROR_MORE_DATA) continue;
                    if (rc != 0) throw new InvalidOperationException("读取占用进程失败，错误码：" + rc);
                    var result = new RM_PROCESS_INFO[count];
                    for (int i = 0; i < count; i++)
                        result[i] = (RM_PROCESS_INFO)Marshal.PtrToStructure(IntPtr.Add(buffer, i * size), typeof(RM_PROCESS_INFO));
                    return result;
                }
                finally { Marshal.FreeHGlobal(buffer); }
            }
            throw new InvalidOperationException("占用进程变化较快，请稍后重新扫描。");
        }
        finally { RmEndSession(session); }
    }

    public static int RequestGracefulShutdown(string[] paths)
    {
        uint session = StartSession();
        try
        {
            Register(session, paths);
            // Flags = 0: request normal shutdown; do not force-terminate processes.
            return RmShutdown(session, 0, IntPtr.Zero);
        }
        finally { RmEndSession(session); }
    }
}
'@

Add-Type -TypeDefinition $rmSource -Language CSharp

$script:LogDirectory = Join-Path $env:LOCALAPPDATA 'FileLockHelper'
$script:LogPath = Join-Path $script:LogDirectory 'activity.log'
$script:MaxResources = 20000
$script:LastProcesses = @()

if (-not (Test-Path -LiteralPath $script:LogDirectory)) {
    New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null
}

function New-UiLabel([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [float]$FontSize = 10, [bool]$Bold = $false, [System.Drawing.Color]$Color = [System.Drawing.Color]::FromArgb(47, 59, 76)) {
    $control = New-Object System.Windows.Forms.Label
    $control.Text = $Text
    $control.Location = New-Object System.Drawing.Point($X, $Y)
    $control.Size = New-Object System.Drawing.Size($Width, $Height)
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $control.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $FontSize, $style)
    $control.ForeColor = $Color
    $control.AutoEllipsis = $true
    return $control
}

function New-UiButton([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Style = 'light') {
    $control = New-Object System.Windows.Forms.Button
    $control.Text = $Text
    $control.Location = New-Object System.Drawing.Point($X, $Y)
    $control.Size = New-Object System.Drawing.Size($Width, $Height)
    $control.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $control.FlatAppearance.BorderSize = 1
    $control.Cursor = [System.Windows.Forms.Cursors]::Hand
    $control.UseVisualStyleBackColor = $false
    if ($Style -eq 'primary') {
        $control.BackColor = [System.Drawing.Color]::FromArgb(32, 111, 209)
        $control.ForeColor = [System.Drawing.Color]::White
        $control.FlatAppearance.BorderSize = 0
        $control.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(26, 96, 187)
        $control.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(22, 82, 164)
    } elseif ($Style -eq 'success') {
        $control.BackColor = [System.Drawing.Color]::FromArgb(15, 143, 126)
        $control.ForeColor = [System.Drawing.Color]::White
        $control.FlatAppearance.BorderSize = 0
        $control.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(11, 125, 112)
        $control.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(9, 108, 98)
    } else {
        $control.BackColor = [System.Drawing.Color]::White
        $control.ForeColor = [System.Drawing.Color]::FromArgb(47, 64, 83)
        $control.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(218, 226, 236)
        $control.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(241, 246, 251)
        $control.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(229, 237, 247)
    }
    return $control
}

function New-UiCard([int]$X, [int]$Y, [int]$Width, [int]$Height) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($X, $Y)
    $card.Size = New-Object System.Drawing.Size($Width, $Height)
    $card.BackColor = [System.Drawing.Color]::White
    $paintHandler = {
        param($sender, $eventArgs)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(226, 232, 240))
        $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
        $pen.Dispose()
    }
    $card.Add_Paint($paintHandler.GetNewClosure())
    return $card
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '文件占用助手'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(1040, 760)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 247, 251)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$script:IconPath = Join-Path $PSScriptRoot 'FileLockHelper.ico'
$script:ImagePath = Join-Path $PSScriptRoot 'FileLockHelper.png'
if (Test-Path -LiteralPath $script:IconPath) {
    $form.Icon = New-Object System.Drawing.Icon($script:IconPath)
}

# Header
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(1040, 108)
$header.BackColor = [System.Drawing.Color]::FromArgb(20, 48, 79)
$form.Controls.Add($header)

$headerIcon = New-Object System.Windows.Forms.PictureBox
$headerIcon.Location = New-Object System.Drawing.Point(26, 20)
$headerIcon.Size = New-Object System.Drawing.Size(68, 68)
$headerIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
if (Test-Path -LiteralPath $script:ImagePath) { $headerIcon.Image = [System.Drawing.Image]::FromFile($script:ImagePath) }
$header.Controls.Add($headerIcon)

$headerTitle = New-UiLabel '文件占用助手' 112 24 520 34 21 $true ([System.Drawing.Color]::White)
$headerTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 20, [System.Drawing.FontStyle]::Bold)
$header.Controls.Add($headerTitle)
$headerSubtitle = New-UiLabel '定位占用进程，安全释放后继续移动' 114 63 650 24 10 $false ([System.Drawing.Color]::FromArgb(190, 211, 231))
$header.Controls.Add($headerSubtitle)
$headerTag = New-UiLabel '轻量 · 安全 · 中文界面' 805 42 205 24 9.5 $false ([System.Drawing.Color]::FromArgb(190, 211, 231))
$header.Controls.Add($headerTag)

# Path card
$pathCard = New-UiCard 24 126 992 126
$form.Controls.Add($pathCard)
$pathCard.Controls.Add((New-UiLabel '检查对象' 24 14 180 24 11 $true))
$pathCard.Controls.Add((New-UiLabel '支持单个文件或整个文件夹' 700 16 264 22 9 $false ([System.Drawing.Color]::FromArgb(125, 139, 157))))
$targetBox = New-Object System.Windows.Forms.TextBox
$targetBox.Location = New-Object System.Drawing.Point(24, 50)
$targetBox.Size = New-Object System.Drawing.Size(654, 35)
$targetBox.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$targetBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$targetBox.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 254)
$pathCard.Controls.Add($targetBox)
$browseFile = New-UiButton '选择文件' 692 49 126 37 'light'
$pathCard.Controls.Add($browseFile)
$browseFolder = New-UiButton '选择文件夹' 832 49 136 37 'light'
$pathCard.Controls.Add($browseFolder)
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 8000
$toolTip.InitialDelay = 500
$toolTip.ReshowDelay = 150
$toolTip.SetToolTip($browseFile, '选择一个当前无法移动的文件')
$toolTip.SetToolTip($browseFolder, '选择一个当前无法移动的文件夹')

# Actions card
$actionCard = New-UiCard 24 266 992 86
$form.Controls.Add($actionCard)
$scanButton = New-UiButton '查找占用' 24 20 160 46 'primary'
$actionCard.Controls.Add($scanButton)
$releaseButton = New-UiButton '请求正常释放' 198 20 178 46 'light'
$actionCard.Controls.Add($releaseButton)
$moveButton = New-UiButton '释放后重试移动' 390 20 210 46 'success'
$actionCard.Controls.Add($moveButton)
$toolTip.SetToolTip($scanButton, '列出 Windows 能识别的占用进程')
$toolTip.SetToolTip($releaseButton, '先保存工作，再请求相关应用正常关闭')
$toolTip.SetToolTip($moveButton, '扫描占用，必要时请求释放，然后移动到选定文件夹')
$status = New-UiLabel '准备就绪　选择目标后点击“查找占用”' 620 26 348 34 9.5 $false ([System.Drawing.Color]::FromArgb(94, 111, 132))
$status.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$actionCard.Controls.Add($status)

# Process card
$processCard = New-UiCard 24 366 992 224
$form.Controls.Add($processCard)
$processTitle = New-UiLabel '占用进程' 24 14 180 26 11 $true
$processCard.Controls.Add($processTitle)
$processHint = New-UiLabel '仅显示 Windows 能识别的相关应用' 190 17 500 22 9 $false ([System.Drawing.Color]::FromArgb(125, 139, 157))
$processCard.Controls.Add($processHint)
$countBadge = New-Object System.Windows.Forms.Label
$countBadge.Text = '0 个进程'
$countBadge.Location = New-Object System.Drawing.Point(852, 12)
$countBadge.Size = New-Object System.Drawing.Size(116, 27)
$countBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$countBadge.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$countBadge.ForeColor = [System.Drawing.Color]::FromArgb(32, 111, 209)
$countBadge.BackColor = [System.Drawing.Color]::FromArgb(235, 244, 255)
$processCard.Controls.Add($countBadge)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(24, 49)
$list.Size = New-Object System.Drawing.Size(944, 153)
$list.View = [System.Windows.Forms.View]::Details
$list.FullRowSelect = $true
$list.GridLines = $false
$list.HideSelection = $false
$list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$list.BackColor = [System.Drawing.Color]::FromArgb(252, 253, 255)
$list.ForeColor = [System.Drawing.Color]::FromArgb(47, 59, 76)
$list.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$list.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
[void]$list.Columns.Add('应用或服务', 410)
[void]$list.Columns.Add('进程 ID', 105)
[void]$list.Columns.Add('会话', 100)
[void]$list.Columns.Add('类型', 190)
[void]$list.Columns.Add('可重启', 100)
$processCard.Controls.Add($list)
$emptyHint = New-UiLabel '选择目标后点击“查找占用”，检测结果会显示在这里' 230 110 620 24 9 $false ([System.Drawing.Color]::FromArgb(147, 160, 177))
$emptyHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$processCard.Controls.Add($emptyHint)

# Activity card
$activityCard = New-UiCard 24 604 992 134
$form.Controls.Add($activityCard)
$logLabel = New-UiLabel '操作记录' 24 12 180 24 10.5 $true
$activityCard.Controls.Add($logLabel)
$logHint = New-UiLabel '记录仅保存在本机' 780 13 188 22 9 $false ([System.Drawing.Color]::FromArgb(125, 139, 157))
$logHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$activityCard.Controls.Add($logHint)
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(24, 41)
$logBox.Size = New-Object System.Drawing.Size(944, 61)
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$logBox.BackColor = [System.Drawing.Color]::FromArgb(250, 252, 254)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(91, 106, 126)
$logBox.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$activityCard.Controls.Add($logBox)
$logPathLabel = New-UiLabel "日志：$script:LogPath" 24 108 944 18 8.5 $false ([System.Drawing.Color]::FromArgb(139, 151, 167))
$activityCard.Controls.Add($logPathLabel)

function Write-Activity([string]$Message) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $logBox.AppendText($line + [Environment]::NewLine)
    try { [System.IO.File]::AppendAllText($script:LogPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8) } catch { }
}

function Set-Status([string]$Message, [string]$Kind = 'info') {
    $status.Text = $Message
    switch ($Kind) {
        'success' { $status.ForeColor = [System.Drawing.Color]::FromArgb(31, 127, 99) }
        'warning' { $status.ForeColor = [System.Drawing.Color]::FromArgb(172, 103, 22) }
        'error'   { $status.ForeColor = [System.Drawing.Color]::FromArgb(177, 55, 62) }
        default   { $status.ForeColor = [System.Drawing.Color]::FromArgb(94, 111, 132) }
    }
}

function Get-TargetPath {
    $raw = $targetBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { throw '请先选择文件或文件夹。' }
    if (-not (Test-Path -LiteralPath $raw)) { throw '目标路径不存在，请确认路径后重试。' }
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $raw).Path)
}

function Get-Resources([string]$Path) {
    $paths = New-Object 'System.Collections.Generic.List[string]'
    $paths.Add($Path)
    $isDirectory = [System.IO.Directory]::Exists($Path)
    $truncated = $false
    $skippedDirectories = 0
    if ($isDirectory) {
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($Path)
        while ($pending.Count -gt 0 -and -not $truncated) {
            $current = $pending.Pop()
            try { $entries = [System.IO.Directory]::EnumerateFileSystemEntries($current) }
            catch { $skippedDirectories++; continue }
            foreach ($entry in $entries) {
                $paths.Add($entry)
                if ($paths.Count -ge $script:MaxResources) { $truncated = $true; break }
                try {
                    $item = Get-Item -LiteralPath $entry -Force -ErrorAction Stop
                    if ($item.PSIsContainer -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) {
                        $pending.Push($entry)
                    }
                } catch { }
            }
        }
    }
    if ($truncated) {
        Write-Activity "目录内容超过 $script:MaxResources 项，扫描了前 $script:MaxResources 项。大型目录建议直接选择具体文件。"
    }
    if ($skippedDirectories -gt 0) {
        Write-Activity "有 $skippedDirectories 个子文件夹无法读取；占用扫描可能不完整。"
    }
    return ,$paths.ToArray()
}

function Show-Processes($Processes) {
    $list.Items.Clear()
    $countBadge.Text = "$($Processes.Count) 个进程"
    $emptyHint.Visible = ($Processes.Count -eq 0)
    if ($Processes.Count -gt 0) {
        $countBadge.ForeColor = [System.Drawing.Color]::FromArgb(172, 103, 22)
        $countBadge.BackColor = [System.Drawing.Color]::FromArgb(255, 246, 224)
    } else {
        $countBadge.ForeColor = [System.Drawing.Color]::FromArgb(32, 111, 209)
        $countBadge.BackColor = [System.Drawing.Color]::FromArgb(235, 244, 255)
    }
    foreach ($p in $Processes) {
        $name = $p.strAppName
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $p.strServiceShortName }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = '未知应用' }
        if (-not [string]::IsNullOrWhiteSpace($p.strServiceShortName) -and $p.strServiceShortName -ne $name) {
            $name += ' (' + $p.strServiceShortName + ')'
        }
        $type = [string]$p.ApplicationType
        $item = New-Object System.Windows.Forms.ListViewItem($name)
        [void]$item.SubItems.Add([string]$p.Process.dwProcessId)
        [void]$item.SubItems.Add([string]$p.TSSessionId)
        [void]$item.SubItems.Add($type)
        [void]$item.SubItems.Add([string]$p.bRestartable)
        [void]$list.Items.Add($item)
    }
}

function Scan-Target([switch]$Quiet) {
    $path = Get-TargetPath
    $resources = Get-Resources $path
    $script:LastProcesses = [FileLockRestartManager]::GetProcesses([string[]]$resources)
    Show-Processes $script:LastProcesses
    if ($script:LastProcesses.Count -eq 0) {
        $emptyHint.Text = '未发现可识别的占用进程'
        Set-Status '未发现可识别的占用进程' 'success'
        if (-not $Quiet) { Write-Activity "扫描完成，未查到可识别的占用进程：$path" }
    } else {
        Set-Status "发现 $($script:LastProcesses.Count) 个相关进程，请核对列表" 'warning'
        if (-not $Quiet) { Write-Activity "扫描完成，查到 $($script:LastProcesses.Count) 个相关进程：$path" }
    }
    return @{ Path = $path; Resources = $resources; Processes = $script:LastProcesses }
}

function Invoke-Move([string]$SourcePath, [string]$DestinationFolder) {
    if (-not [System.IO.Directory]::Exists($DestinationFolder)) { throw '目标位置必须是已存在的文件夹。' }
    $sourceName = [System.IO.Path]::GetFileName($SourcePath.TrimEnd([char[]]@('\', '/')))
    if ([string]::IsNullOrWhiteSpace($sourceName)) { throw '不能移动磁盘根目录。' }
    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $DestinationFolder $sourceName))
    if ($destinationPath.TrimEnd('\') -ieq $SourcePath.TrimEnd('\')) { throw '目标位置与源位置相同。' }
    if ([System.IO.Directory]::Exists($SourcePath) -and $destinationPath.StartsWith($SourcePath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw '不能把文件夹移动到它自己的子文件夹中。'
    }
    if (Test-Path -LiteralPath $destinationPath) { throw "目标位置已存在同名项目，未覆盖：$destinationPath" }
    Move-Item -LiteralPath $SourcePath -Destination $DestinationFolder -ErrorAction Stop
    return $destinationPath
}

$browseFile.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    $dialog.Title = '选择要检查的文件'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $targetBox.Text = $dialog.FileName; Set-Status '已选择文件，点击“查找占用”' 'info' }
})

$browseFolder.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = '选择要检查的文件夹'
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $targetBox.Text = $dialog.SelectedPath; Set-Status '已选择文件夹，点击“查找占用”' 'info' }
})

$targetBox.Add_TextChanged({
    if ([string]::IsNullOrWhiteSpace($targetBox.Text)) {
        Set-Status '准备就绪　选择目标后点击“查找占用”' 'info'
    } else {
        Set-Status '目标已填写，点击“查找占用”查看相关进程' 'info'
    }
})

$scanButton.Add_Click({
    try { [void](Scan-Target); }
    catch { Set-Status '扫描失败，请检查路径' 'error'; Write-Activity ('扫描失败：' + $_.Exception.Message); [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '扫描失败', 'OK', 'Warning') | Out-Null }
})

$releaseButton.Add_Click({
    try {
        $result = Scan-Target -Quiet
        if ($result.Processes.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('没有查到可请求关闭的占用进程。', '文件占用助手', 'OK', 'Information') | Out-Null
            return
        }
        $names = @($result.Processes | ForEach-Object { if ($_.strAppName) { $_.strAppName } else { $_.strServiceShortName } } | Select-Object -Unique)
        $prompt = "Windows 将请求以下应用或服务正常关闭，以便释放目标路径。请先保存相关应用中的工作。程序不会强制结束进程。`r`n`r`n" + ($names -join "`r`n") + "`r`n`r`n是否继续？"
        $answer = [System.Windows.Forms.MessageBox]::Show($prompt, '确认请求正常关闭', 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $code = [FileLockRestartManager]::RequestGracefulShutdown([string[]]$result.Resources)
        Write-Activity "已向 Restart Manager 请求正常释放路径：$($result.Path)；返回码 $code。"
        Set-Status '已请求应用正常释放，正在复查…' 'info'
        $form.Refresh()
        Start-Sleep -Milliseconds 1200
        $after = Scan-Target -Quiet
        if ($after.Processes.Count -eq 0) {
            Set-Status '已释放，可以重试移动' 'success'
            Write-Activity "复查完成，未查到相关占用进程：$($result.Path)"
            [System.Windows.Forms.MessageBox]::Show('复查时未查到相关占用进程。现在可以重试移动。', '处理完成', 'OK', 'Information') | Out-Null
        } else {
            Set-Status '仍有进程占用，请保存并手动关闭应用' 'warning'
            Write-Activity "复查后仍有 $($after.Processes.Count) 个相关进程：$($result.Path)"
            [System.Windows.Forms.MessageBox]::Show('仍检测到相关进程。请先保存工作，再手动关闭列表中的应用，然后重新扫描。', '仍被占用', 'OK', 'Warning') | Out-Null
        }
    } catch {
        Set-Status '释放请求失败' 'error'
        Write-Activity ('释放请求失败：' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '释放失败', 'OK', 'Error') | Out-Null
    }
})

$moveButton.Add_Click({
    try {
        $source = Get-TargetPath
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = '选择移动后的存放文件夹'
        $dialog.ShowNewFolderButton = $true
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $destination = [System.IO.Path]::GetFullPath($dialog.SelectedPath)

        $result = Scan-Target -Quiet
        if ($result.Processes.Count -gt 0) {
            $names = @($result.Processes | ForEach-Object { if ($_.strAppName) { $_.strAppName } else { $_.strServiceShortName } } | Select-Object -Unique)
            $prompt = "检测到以下应用或服务正在使用目标路径：`r`n`r`n" + ($names -join "`r`n") + "`r`n`r`n请先保存相关工作。是否请求它们正常关闭，然后重试移动？"
            $answer = [System.Windows.Forms.MessageBox]::Show($prompt, '确认处理占用并移动', 'YesNo', 'Warning')
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $code = [FileLockRestartManager]::RequestGracefulShutdown([string[]]$result.Resources)
            Write-Activity "移动前请求应用正常释放；返回码 $code；路径：$source"
            Set-Status '正在复查占用情况…' 'info'
            $form.Refresh()
            Start-Sleep -Milliseconds 1200
            $after = Scan-Target -Quiet
            if ($after.Processes.Count -gt 0) {
                Set-Status '仍有进程占用，已取消移动' 'warning'
                Write-Activity "占用仍存在，取消移动：$source"
                [System.Windows.Forms.MessageBox]::Show('目标仍被占用，已取消移动。请保存工作并关闭列表中的应用后，再重新尝试。', '仍被占用', 'OK', 'Warning') | Out-Null
                return
            }
        }
        $movedTo = Invoke-Move $source $destination
        $targetBox.Clear()
        Show-Processes @()
        $emptyHint.Text = '移动完成，可继续选择其他文件或文件夹'
        Set-Status '移动完成' 'success'
        Write-Activity "移动成功：$source -> $movedTo"
        [System.Windows.Forms.MessageBox]::Show("移动完成：`r`n$movedTo", '移动完成', 'OK', 'Information') | Out-Null
    } catch {
        Set-Status '移动未完成，请查看提示' 'error'
        Write-Activity ('移动失败：' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message + "`r`n`r`n如果仍提示文件正在使用，请关闭相关应用后重新扫描。", '移动失败', 'OK', 'Warning') | Out-Null
    }
})

Write-Activity '工具已启动。默认只扫描和请求应用正常关闭，不会强制结束进程。'
[void]$form.ShowDialog()
