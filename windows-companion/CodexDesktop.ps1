# The Windows Codex package may run ChatGPT.exe. Match the package identity,
# not just the display name, and never treat a headless CLI as the GUI.
function Test-CodexDesktopIdentity([string]$name, [string]$path, [string]$appId) {
    return ($appId -like 'OpenAI.Codex_*!*' -or
        $path -match '[\\/]OpenAI\.Codex_[^\\/]+[\\/]' -or
        ($name -ieq 'Codex' -and $path -notmatch '[\\/]OpenAI[\\/]Codex[\\/]bin[\\/]'))
}
function Get-PetCloseDecision([int]$missingPolls, [bool]$isCodexRunning, [int]$threshold = 2) {
    if ($isCodexRunning) { return [pscustomobject]@{ Close = $false; MissingPolls = 0 } }
    $next = $missingPolls + 1
    return [pscustomobject]@{ Close = $next -ge $threshold; MissingPolls = $next }
}
function Get-CodexApplicationId([int]$processId) {
    if (-not ('YanXiaoBei.ApplicationIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace YanXiaoBei {
    public static class ApplicationIdentity {
        [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int id);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
        static extern int GetApplicationUserModelId(IntPtr process, ref uint size, StringBuilder id);
        public static string Read(int id) {
            IntPtr handle = OpenProcess(0x1000, false, id);
            if (handle == IntPtr.Zero) return "";
            try {
                uint size = 512;
                var result = new StringBuilder((int)size);
                return GetApplicationUserModelId(handle, ref size, result) == 0 ? result.ToString() : "";
            } finally { CloseHandle(handle); }
        }
    }
}
'@
    }
    return [YanXiaoBei.ApplicationIdentity]::Read($processId)
}
function Get-CodexDesktopProcesses([switch]$IncludeHidden) {
    $sessionId = (Get-Process -Id $PID).SessionId
    foreach ($candidate in @(Get-Process -Name Codex,ChatGPT -ErrorAction SilentlyContinue)) {
        try {
            if ($candidate.SessionId -ne $sessionId) { continue }
            if (-not $IncludeHidden -and $candidate.MainWindowHandle -eq [IntPtr]::Zero) { continue }
            $path = [string]$candidate.Path
            $appId = if ($candidate.ProcessName -ieq 'ChatGPT') { Get-CodexApplicationId $candidate.Id } else { '' }
            if (Test-CodexDesktopIdentity $candidate.ProcessName $path $appId) { $candidate }
        } catch { }
    }
}

function Initialize-CodexWindowApi {
    if ('YanXiaoBei.WindowActivation' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace YanXiaoBei {
    public static class WindowActivation {
        delegate bool EnumCallback(IntPtr hwnd, IntPtr state);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback, IntPtr state);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint command);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder name, int count);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowTextLength(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int command);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);

        public static bool IsMainWindow(IntPtr hwnd, int[] processIds) {
            if (!IsWindow(hwnd) || GetWindow(hwnd, 4) != IntPtr.Zero || (GetWindowLong(hwnd, -20) & 0x80) != 0) return false;
            uint pid; GetWindowThreadProcessId(hwnd, out pid);
            if (Array.IndexOf(processIds, (int)pid) < 0) return false;
            var name = new StringBuilder(256);
            GetClassName(hwnd, name, name.Capacity);
            // Exclude Electron message windows, menus and unnamed helper windows.
            return name.ToString() == "Chrome_WidgetWin_1" && GetWindowTextLength(hwnd) > 0;
        }
        public static IntPtr Find(int[] processIds, IntPtr preferred) {
            if (IsMainWindow(preferred, processIds)) return preferred;
            IntPtr result = IntPtr.Zero;
            EnumWindows(delegate(IntPtr hwnd, IntPtr state) {
                if (!IsMainWindow(hwnd, processIds)) return true;
                result = hwnd;
                return false;
            }, IntPtr.Zero);
            return result;
        }
        public static bool Restore(IntPtr hwnd) {
            if (!IsWindow(hwnd)) return false;
            if (IsIconic(hwnd)) ShowWindow(hwnd, 9); // restore only minimized windows
            else if (!IsWindowVisible(hwnd)) ShowWindow(hwnd, 5); // keep maximized/normal placement
            // No URL, command-line route, keystroke, or navigation message is sent.
            return SetForegroundWindow(hwnd);
        }
    }
}
'@
}
function Remember-CodexForegroundWindow {
    try {
        Initialize-CodexWindowApi
        $foreground = [YanXiaoBei.WindowActivation]::GetForegroundWindow()
        if ($foreground -eq $script:lastObservedForeground) { return }
        $script:lastObservedForeground = $foreground
        $processIds = [int[]]@(Get-CodexDesktopProcesses -IncludeHidden | ForEach-Object Id)
        if ([YanXiaoBei.WindowActivation]::IsMainWindow($foreground, $processIds)) {
            $script:lastCodexWindowHandle = $foreground
        }
    } catch {}
}
function Get-CodexRestoreTarget {
    Initialize-CodexWindowApi
    $processes = @(Get-CodexDesktopProcesses -IncludeHidden)
    $preferred = if ($null -ne $script:lastCodexWindowHandle) { $script:lastCodexWindowHandle } else { [IntPtr]::Zero }
    $handle = [YanXiaoBei.WindowActivation]::Find([int[]]@($processes | ForEach-Object Id), $preferred)
    return [pscustomobject]@{ Handle = $handle; IsRunning = $processes.Count -gt 0 }
}
function Restore-CodexWindow([IntPtr]$handle) {
    Initialize-CodexWindowApi
    return [YanXiaoBei.WindowActivation]::Restore($handle)
}
function Start-CodexDesktopApplication {
    # Only cold launch, with no URI or task arguments. Discover the installed app
    # instead of assuming its changing display name or package version.
    $app = Get-StartApps | Where-Object { $_.AppID -like 'OpenAI.Codex_*!*' } | Select-Object -First 1
    if ($null -eq $app) { throw '未找到 Codex 的启动入口，请从任务栏打开 Codex。' }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = 'explorer.exe'
    $info.Arguments = 'shell:AppsFolder\' + $app.AppID
    $info.UseShellExecute = $true
    $null = [Diagnostics.Process]::Start($info)
}
function Show-CodexDesktop {
    $target = Get-CodexRestoreTarget
    if ($target.Handle -ne [IntPtr]::Zero) {
        if (-not (Restore-CodexWindow $target.Handle)) {
            throw '找到了原窗口，但 Windows 未允许切到前台。请点击任务栏中的 Codex；桌宠没有切换页面。'
        }
        return
    }
    if ($target.IsRunning) { throw 'Codex 仍在运行，但没有找到可恢复的主窗口。请从任务栏打开；桌宠没有新建聊天或切换任务。' }
    Start-CodexDesktopApplication
}
