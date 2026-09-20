# 构建入口：chapter1-1 制作/烘焙/验证/导出统一包装（chapter1-1 §9.1）。
# 用法示例：
#   .\tools\build_chapter11.ps1 -GodotExe 'D:\Godot\...\Godot_v4.7.2-stable_win64.exe' -ProjectPath . -Stage all -MapId m01_afterglow
# Godot 路径从 -GodotExe 参数或环境变量 NEON_GODOT 取得，不硬编码个人路径。
param(
    [string]$GodotExe = $env:NEON_GODOT,
    [string]$ProjectPath = ".",
    [ValidateSet("validate", "generate", "assemble", "bake", "verify", "export", "all")]
    [string]$Stage = "all",
    [ValidateSet("m01_afterglow")]
    [string]$MapId = "m01_afterglow"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    Write-Error "未提供 -GodotExe 且环境变量 NEON_GODOT 为空。用法：-GodotExe 'D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'"
}
if (-not (Test-Path $GodotExe)) {
    Write-Error "Godot 可执行文件不存在: $GodotExe"
}

$ProjectPath = (Resolve-Path $ProjectPath).Path
Set-Location $ProjectPath
$G = $GodotExe

function Invoke-Godot {
    param([string[]]$GodotArgs, [string]$Label)
    Write-Host "== $Label ==" -ForegroundColor Cyan
    & $G @GodotArgs 2>&1 | Tee-Object -Variable out
    if ($LASTEXITCODE -ne 0) {
        throw "$Label 失败（exit=$LASTEXITCODE）"
    }
}

function Step-Validate {
    # 校验引擎版本、字体、关键路径与规格结构
    Write-Host "== validate ==" -ForegroundColor Cyan
    & $G --version | Tee-Object -Variable ver
    $expected = "4.7.2"
    if (($ver -join "") -notmatch [regex]::Escape($expected)) {
        throw "引擎版本异常：$($ver -join ' ')（期望 $expected）"
    }
    if (-not (Test-Path "assets/fonts/source/NotoSansSC-Regular.otf")) { throw "固定字体缺失（FIX-10）" }
    if (-not (Test-Path "data/map_registry.json")) { throw "地图注册表缺失" }
    if (-not (Test-Path "data/quality/eco.json") -or -not (Test-Path "data/quality/balanced.json")) { throw "画质配置缺失" }
    if (-not (Test-Path "scripts/maps/map_manager.gd")) { throw "核心脚本缺失" }
    Write-Host "validate 通过"
}

function Step-Generate {
    # 生成可重建层（保留 authored）：纹理 → 招牌（固定字体） → 城市生成层 → 精修层
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/gen_textures.gd") "generate/textures"
    & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "导入失败" }
    # 招牌需要窗口环境栅格化（SubViewport + 字体渲染）
    Write-Host "== generate/signs ==" -ForegroundColor Cyan
    & $G --path $ProjectPath res://tools/run_gen_signs.tscn 2>&1 | Tee-Object -Variable sout
    if ($LASTEXITCODE -ne 0) { throw "招牌生成失败" }
    if (($sout -join "`n") -notmatch "SIGNS_DONE") { throw "招牌生成未完成（未见 SIGNS_DONE）" }
    & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/build_m01.gd") "generate/city"
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/build_authored.gd") "generate/authored"
    & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "导入失败" }
}

function Step-Assemble {
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/assemble_m01.gd") "assemble"
    & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "导入失败" }
}

function Step-Bake {
    # 真实图形编辑器中烘焙（addons/neon_bake 按钮）；NEON_BAKE_EXIT 判定结果
    Write-Host "== bake（编辑器内烘焙，最长 15 分钟） ==" -ForegroundColor Cyan
    & $G --path $ProjectPath --editor -- --auto-bake 2>&1 | Tee-Object -Variable bout
    $outText = $bout -join "`n"
    if ($outText -match "NEON_BAKE_EXIT=(\d)") {
        if ([int]$Matches[1] -ne 0) { throw "烘焙失败（NEON_BAKE_EXIT=$($Matches[1])），见 artifacts/chapter1_1/bake_report_*.json" }
    } else {
        throw "烘焙未给出结束标记（NEON_BAKE_EXIT 缺失）——编辑器可能仍打开，请检查"
    }
    & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
    Write-Host "bake 完成"
}

function Step-Verify {
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/verify_build.gd") "verify"
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tests/test_map_lifecycle.gd") "verify/lifecycle"
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tests/test_chapter11_contract.gd") "verify/contract"
}

function Step-Export {
    New-Item -ItemType Directory -Force -Path "build/windows" | Out-Null
    Write-Host "== export（Windows Release） ==" -ForegroundColor Cyan
    & $G --headless --path $ProjectPath --export-release "Windows Desktop" "build/windows/neon_haven.exe" 2>&1 | Tee-Object -Variable eout
    if ($LASTEXITCODE -ne 0) { throw "导出失败" }
    if (-not (Test-Path "build/windows/neon_haven.exe")) { throw "导出产物缺失" }
    Write-Host "导出完成：build/windows/neon_haven.exe (+ .pck)"
}

switch ($Stage) {
    "validate" { Step-Validate }
    "generate" { Step-Validate; Step-Generate }
    "assemble" { Step-Assemble }
    "bake"     { Step-Bake }
    "verify"   { Step-Verify }
    "export"   { Step-Export }
    "all"      {
        Step-Validate
        Step-Generate
        Step-Assemble
        Step-Bake
        Step-Verify
        Step-Export
    }
}
Write-Host "BUILD_CHAPTER11[$Stage] DONE" -ForegroundColor Green
