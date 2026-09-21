# Keep Godot window foreground (local perf sampling aid, chapter1-2).
# Usage: powershell -File tools/focus_keep.ps1 [ProcName=Godot] [Seconds=200]
# Why: a GUI process started from an unattended session never holds stable
#      foreground focus, and benchmark_runner correctly aborts sampling on
#      focus loss; this loop keeps the measured window valid.
param(
    [string]$ProcName = "Godot_v4.7.2-stable_win64",
    [int]$Seconds = 200
)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Focus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    // Simulating an ALT keypress unlocks SetForegroundWindow rights on Windows.
    [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int size);
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public ushort vk, scan, flags, time, extra; }
    public static void NudgeAlt() {
        INPUT[] down = new INPUT[1];
        down[0].type = 1; down[0].vk = 0x12;  // VK_MENU keydown
        SendInput(1, down, Marshal.SizeOf(typeof(INPUT)));
        INPUT[] up = new INPUT[1];
        up[0].type = 1; up[0].vk = 0x12; up[0].flags = 2;  // KEYEVENTF_KEYUP
        SendInput(1, up, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
    $procs = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
    foreach ($p in $procs) {
        [Win32Focus]::NudgeAlt()
        [Win32Focus]::ShowWindow($p.MainWindowHandle, 9) | Out-Null  # SW_RESTORE
        [Win32Focus]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    }
    Start-Sleep -Milliseconds 700
}
