# 构建入口：chapter1-1/1-2 制作/烘焙/验证/导出统一包装（chapter1-3 §36 深化）。
# 用法示例：
#   .\tools\build_chapter11.ps1 -GodotExe 'D:\Godot\...\Godot_v4.7.2-stable_win64.exe' -ProjectPath . -Stage all -MapId both -BuildId <sha-rc1> -ArtifactDir res://artifacts/chapter1_3
# Godot 路径从 -GodotExe 参数或环境变量 NEON_GODOT 取得，不硬编码个人路径。
# chapter1-3：MapId=both 顺序固定为"共享输入先稳定、street 先、interior 后"；
# build_m01 前后做 authored ownership 指纹断言（生成器不得越界写精修层）；
# Stage=export 独立入口必须先跑完整 verify；bake 报告目录由 -ArtifactDir 注入 NEON_ARTIFACT_DIR。
param(
    [string]$GodotExe = $env:NEON_GODOT,
    [string]$ProjectPath = ".",
    [ValidateSet("validate", "generate", "assemble", "bake", "verify", "export", "all")]
    [string]$Stage = "all",
    [ValidateSet("m01_afterglow", "m01_repair_interior", "both")]
    [string]$MapId = "m01_afterglow",
    [string]$BuildId = "",
    [string]$ArtifactDir = "res://artifacts/build"
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

if ([string]::IsNullOrWhiteSpace($BuildId)) {
    if (-not [string]::IsNullOrWhiteSpace($env:NEON_BUILD_ID)) { $BuildId = $env:NEON_BUILD_ID }
    elseif (Test-Path ".git") {
        $sha = git rev-parse --short HEAD 2>$null
        if ($sha) { $BuildId = "$sha-local" } else { $BuildId = "local-" + (Get-Date -Format "yyyyMMddTHHmmss") }
    } else { $BuildId = "local-" + (Get-Date -Format "yyyyMMddTHHmmss") }
}
$env:NEON_BUILD_ID = $BuildId
if ($ArtifactDir -notmatch '^res://artifacts(/|$)') {
    Write-Error "ArtifactDir 只允许 res://artifacts 下（收到 $ArtifactDir）"
}
Write-Host "BuildId = $BuildId  ArtifactDir = $ArtifactDir" -ForegroundColor DarkCyan

function Invoke-Godot {
    param([string[]]$GodotArgs, [string]$Label)
    Write-Host "== $Label ==" -ForegroundColor Cyan
    & $G @GodotArgs 2>&1 | Tee-Object -Variable out
    if ($LASTEXITCODE -ne 0) {
        throw "$Label 失败（exit=$LASTEXITCODE）"
    }
}

function Get-OwnershipFingerprint {
    # C13-04：authored 所有权指纹。build_m01 前后必须一致（生成器不得越界写精修层）。
    $paths = @()
    if (Test-Path "maps/m01_afterglow/authored") { $paths += Get-ChildItem "maps/m01_afterglow/authored" -Recurse -File }
    if (Test-Path "maps/m01_afterglow/meshes") {
        $paths += Get-ChildItem "maps/m01_afterglow/meshes" -Recurse -File | Where-Object { $_.Name -like "authored_*" }
    }
    $acc = ""
    foreach ($p in ($paths | Sort-Object FullName)) {
        $hash = (Get-FileHash -LiteralPath $p.FullName -Algorithm SHA256).Hash
        $rel = Resolve-Path -LiteralPath $p.FullName -Relative
        $rel = $rel -replace '\\', '/'
        $tscn = $rel -match '\.(tscn|tres)$'
        if ($tscn) {
            $text = [IO.File]::ReadAllText($p.FullName) -replace 'unique_id=\d+', ''
            $bytes = [Text.Encoding]::UTF8.GetBytes($text)
            $sha = [Security.Cryptography.SHA256]::Create()
            $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', ''
        }
        $acc += "$rel`:$hash;"
    }
    $md5 = [Security.Cryptography.MD5]::Create()
    return [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($acc))) -replace '-', ''
}

function Step-Validate {
    # §36 validate：引擎版本、注册表、画质配置、字体、BuildContract、导出预设、MapId 一致
    Write-Host "== validate ==" -ForegroundColor Cyan
    & $G --version | Tee-Object -Variable ver
    $expected = "4.7.2"
    if (($ver -join "") -notmatch [regex]::Escape($expected)) {
        throw "引擎版本异常：$($ver -join ' ')（期望 $expected）"
    }
    if (-not (Test-Path "assets/fonts/source/NotoSansSC-Regular.otf")) { throw "固定字体缺失（FIX-10）" }
    if (-not (Test-Path "data/map_registry.json")) { throw "地图注册表缺失" }
    if (-not (Test-Path "data/quality/eco.json") -or -not (Test-Path "data/quality/balanced.json")) { throw "画质配置缺失" }
    foreach ($q in @("data/quality/eco.json", "data/quality/balanced.json")) {
        try { Get-Content $q -Raw | ConvertFrom-Json | Out-Null } catch { throw "画质配置不可解析：$q" }
    }
    try { $reg = Get-Content "data/map_registry.json" -Raw | ConvertFrom-Json } catch { throw "注册表不可解析" }
    if (-not $reg.maps -or $reg.maps.Count -lt 1) { throw "注册表 maps 为空" }
    $regIds = @($reg.maps | ForEach-Object { $_.map_id })
    if ($MapId -ne "both" -and $regIds -notcontains $MapId) { throw "MapId=$MapId 不在注册表内（$($regIds -join ',')）" }
    if (-not (Test-Path "tools/build_contract.gd")) { throw "BuildContract 助手缺失" }
    if (-not (Test-Path "tools/verify_build.gd")) { throw "verify_build 缺失" }
    if (-not (Test-Path "export_presets.cfg")) { throw "导出预设缺失" }
    & $G --headless --path $ProjectPath --check-only --script res://tools/build_contract.gd 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "BuildContract 不可加载" }
    foreach ($m in $reg.maps) {
        $defPath = $m.definition_path -replace '^res://', ''
        if (-not (Test-Path $defPath)) { throw "注册表指向的定义缺失：$defPath" }
    }
    Write-Host "validate 通过"
}

function Get-MapIds {
    if ($MapId -eq "both") { return @("m01_afterglow", "m01_repair_interior") }
    return @($MapId)
}

function Step-Generate {
    # §36 generate：共享输入先稳定；street 先（含 ownership 断言）、interior 后。
    foreach ($mid in Get-MapIds) {
        if ($mid -eq "m01_repair_interior") {
            # 单独 interior：Validate 已确认其依赖的共享 materials/textures/signs 全部存在
            Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/build_interior.gd") "generate/interior"
            & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "导入失败" }
        }
    }
    if ((Get-MapIds) -contains "m01_afterglow") {
        Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/gen_textures.gd") "generate/textures"
        & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "导入失败" }
        # 招牌需要窗口环境栅格化（SubViewport + 字体渲染）
        Write-Host "== generate/signs ==" -ForegroundColor Cyan
        & $G --path $ProjectPath res://tools/run_gen_signs.tscn 2>&1 | Tee-Object -Variable sout
        if ($LASTEXITCODE -ne 0) { throw "招牌生成失败" }
        if (($sout -join "`n") -notmatch "SIGNS_DONE") { throw "招牌生成未完成（未见 SIGNS_DONE）" }
        & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "导入失败" }
        # C13-04：build_m01 前后 authored ownership 指纹必须一致
        $pre = Get-OwnershipFingerprint
        Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/build_m01.gd") "generate/city"
        $post = Get-OwnershipFingerprint
        if ($pre -ne $post) { throw "authored 所有权指纹变化：build_m01 越界修改 authored（C13-04）" }
        Write-Host "ownership 断言通过（authored 未被 build_m01 触碰）"
        Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/build_authored.gd") "generate/authored"
        & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "导入失败" }
    }
}

function Step-Assemble {
    foreach ($mid in Get-MapIds) {
        $script = "res://tools/assemble_m01.gd"
        if ($mid -eq "m01_repair_interior") { $script = "res://tools/assemble_interior.gd" }
        Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", $script) "assemble/$mid"
    }
    & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "导入失败" }
}

function Step-Bake {
    # 真实图形编辑器中烘焙（addons/neon_bake 按钮）；NEON_BAKE_EXIT 判定结果
    $env:NEON_ARTIFACT_DIR = $ArtifactDir
    foreach ($mid in Get-MapIds) {
        Write-Host "== bake $mid（编辑器内烘焙，最长 15 分钟） ==" -ForegroundColor Cyan
        & $G --path $ProjectPath --editor -- --auto-bake --scene "res://maps/$mid/map.tscn" 2>&1 | Tee-Object -Variable bout
        $outText = $bout -join "`n"
        if ($outText -match "NEON_BAKE_EXIT=(\d)") {
            if ([int]$Matches[1] -ne 0) { throw "烘焙失败（NEON_BAKE_EXIT=$($Matches[1])），见 $ArtifactDir/bake_report_*.json" }
        } else {
            throw "烘焙未给出结束标记（NEON_BAKE_EXIT 缺失）——编辑器可能仍打开，请检查"
        }
    }
    & $G --headless --path $ProjectPath --import 2>&1 | Out-Null
    Write-Host "bake 完成"
}

function Step-Verify {
    foreach ($mid in Get-MapIds) {
        Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tools/verify_build.gd", "--", "--map", $mid) "verify/$mid"
    }
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tests/test_map_lifecycle.gd") "verify/lifecycle"
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tests/test_chapter11_contract.gd") "verify/contract"
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tests/test_chapter12_contract.gd") "verify/contract12"
    Invoke-Godot @("--headless", "--path", $ProjectPath, "--script", "res://tests/test_chapter13_contract.gd") "verify/contract13"
}

function Step-Export {
    New-Item -ItemType Directory -Force -Path "build/windows" | Out-Null
    Write-Host "== export（Windows Release） ==" -ForegroundColor Cyan
    & $G --headless --path $ProjectPath --export-release "Windows Desktop" "build/windows/neon_haven.exe" 2>&1 | Tee-Object -Variable eout
    if ($LASTEXITCODE -ne 0) { throw "导出失败" }
    if (-not (Test-Path "build/windows/neon_haven.exe")) { throw "导出产物缺失" }
    Write-Host "导出完成：build/windows/neon_haven.exe (+ .pck)"
}

$verifiedThisRun = $false
switch ($Stage) {
    "validate" { Step-Validate }
    "generate" { Step-Validate; Step-Generate }
    "assemble" { Step-Assemble }
    "bake"     { Step-Bake }
    "verify"   { Step-Verify; $verifiedThisRun = $true }
    "export"   {
        # 独立 export 必须先过完整 verify（§36）：不允许跳过门槛直接导出
        Step-Verify
        Step-Export
    }
    "all"      {
        Step-Validate
        Step-Generate
        Step-Assemble
        Step-Bake
        Step-Verify
        $verifiedThisRun = $true
        Step-Export
    }
}
Write-Host "BUILD_CHAPTER11[$Stage] DONE (BuildId=$BuildId)" -ForegroundColor Green
