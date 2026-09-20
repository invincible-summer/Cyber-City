# Windows 进程级采样工具（chapter1-1 §8.5 / FIX-06）。
# 以 1 Hz 采集目标游戏进程的 WorkingSet64 / PrivateMemorySize64 / 累计 CPU 时间。
# 只针对给定 PID（+可选启动时间校验，防止 PID 复用污染）；不采样编辑器或整个 Godot 进程组。
# 用法：
#   .\tools\sample_process.ps1 -GameProcessId 1234 -RunId 'v11_eco_01' -OutputDirectory '.\artifacts\chapter1_1\performance'
# 可选：-ProcessStartTime (Get-Process -Id 1234).StartTime   用于 PID 复用校验
param(
    [Parameter(Mandatory = $true)][int]$GameProcessId,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [datetime]$ProcessStartTime = [datetime]::MinValue
)

$ErrorActionPreference = "Stop"
$MiB = 1024 * 1024

if ($GameProcessId -le 0) { throw "GameProcessId 非法" }

function Get-Target {
    try {
        $p = Get-Process -Id $GameProcessId -ErrorAction Stop
    } catch {
        return $null
    }
    # PID 复用防护：启动时间不匹配即视为原进程已退出
    if ($ProcessStartTime -ne [datetime]::MinValue -and $p.StartTime -ne $ProcessStartTime) {
        return $null
    }
    return $p
}

$first = Get-Target
if ($null -eq $first) { throw "进程 $GameProcessId 不存在或启动时间不匹配" }
if ($null -eq $ProcessStartTime -or $ProcessStartTime -eq [datetime]::MinValue) {
    $ProcessStartTime = $first.StartTime
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$csvPath = Join-Path $OutputDirectory "$RunId`_process.csv"
$summaryPath = Join-Path $OutputDirectory "$RunId`_process_summary.json"
"timestamp_utc,elapsed_s,working_set_mib,private_bytes_mib,cpu_time_total_s,cpu_percent" | Out-File -FilePath $csvPath -Encoding utf8

Write-Host "采样进程 PID=$GameProcessId（$($first.ProcessName)）-> $csvPath"
$startTime = Get-Date
$startCpu = $first.TotalProcessorTime.TotalSeconds
$peakWs = 0.0; $peakPriv = 0.0; $lastCpuPct = 0.0
$prevCpuSec = $startCpu; $prevWall = $startTime
$logical = [Environment]::ProcessorCount

while ($true) {
    Start-Sleep -Seconds 1
    $p = Get-Target
    if ($null -eq $p) { break }   # 进程退出即停止
    $now = Get-Date
    $cpuSec = $p.TotalProcessorTime.TotalSeconds
    $wallSec = ($now - $startTime).TotalSeconds
    # CPU 占整机比例 = CPU 时间增量 / 墙钟增量 / 逻辑处理器数 × 100
    $cpuPct = 0.0
    if (($now - $prevWall).TotalSeconds -gt 0) {
        $cpuPct = [math]::Round((($cpuSec - $prevCpuSec) / ($now - $prevWall).TotalSeconds) / $logical * 100, 1)
    }
    $ws = [math]::Round($p.WorkingSet64 / $MiB, 1)
    $priv = [math]::Round($p.PrivateMemorySize64 / $MiB, 1)
    "$($now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')),$([math]::Round($wallSec,1)),$ws,$priv,$([math]::Round($cpuSec,2)),$cpuPct" |
        Out-File -FilePath $csvPath -Append -Encoding utf8
    if ($ws -gt $peakWs) { $peakWs = $ws }
    if ($priv -gt $peakPriv) { $peakPriv = $priv }
    $lastCpuPct = $cpuPct
    $prevCpuSec = $cpuSec; $prevWall = $now
}

$summary = [ordered]@{
    schema_version = 1
    run_id = $RunId
    game_process_id = $GameProcessId
    process_start_utc = $ProcessStartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    sampled_seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    peak_working_set_mib = $peakWs
    peak_private_bytes_mib = $peakPriv
    cpu_total_seconds = [math]::Round($prevCpuSec - $startCpu, 2)
    cpu_percent_last = $lastCpuPct
    cpu_percent_formula = "CPU时间增量/墙钟增量/逻辑处理器数($logical)*100"
    note = "WorkingSet64/PrivateMemorySize64 来自 Get-Process；不与引擎内存估计混用"
}
$summary | ConvertTo-Json | Out-File -FilePath $summaryPath -Encoding utf8
Write-Host "采样结束：peak WS=$peakWs MiB, peak Private=$peakPriv MiB -> $summaryPath"
