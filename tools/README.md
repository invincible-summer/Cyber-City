# 制作工具说明

> 本目录脚本只在**制作阶段**于本机运行；发布程序不调用它们。更新：2026-09-22（chapter1-3 构建可信性管线）。

`$GODOT` 指本地 Godot 4.7.2 可执行文件（示例：`"D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`）。**工具路径只作为可替换示例**，统一入口会从参数/环境变量读取。
注意：Windows PowerShell 5.1 读取无 BOM 的 UTF-8 中文脚本偶发乱码解析失败；出错时按下方"单步运行"逐条直调 Godot 即可（步骤等价）。

## 统一构建入口（chapter1-3 §36）

```powershell
$GODOT = "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
.\tools\build_chapter11.ps1 -GodotExe $GODOT -ProjectPath . -Stage all -MapId both -BuildId <sha-rc1> -ArtifactDir res://artifacts/chapter1_3
# 参数：BuildId 缺省=NEON_BUILD_ID→git short SHA→local 时间戳；ArtifactDir 只允许 res://artifacts 下
# 分阶段：
#   validate  引擎 4.7.2/注册表/画质配置/字体/BuildContract/导出预设/MapId 一致性
#   generate  纹理 → 招牌(固定字体) → ownership 指纹断言 → build_m01 → build_authored → build_interior
#   assemble  manifest v2 组装（can_reuse_bake 判定复用或预失效；不主动 bake）
#   bake      编辑器内真实烘焙（先落 manifest=running 再清数据；NEON_BAKE_EXIT 判定；报告入 ArtifactDir）
#   verify    verify_build v2 + 生命周期 + ch11/ch12/ch13 合同测试
#   export    独立入口必先完整 verify（不存在跳过门槛的路径）
```

`MapId=both` 顺序固定为"共享输入先稳定、street 先（含 ownership 断言）、interior 后"。

只改 UI 文案/书签/不参与烘焙的设置时**不需要**重跑 generate/bake——运行 `verify` 确认 `bake_input_hash` 未变即可（verify 完全只读）。

## 分层责任

| 层 | 来源 | 可否手工/工具精修 |
| --- | --- | --- |
| `maps/m01_afterglow/generated/` | `tools/build_m01.gd`（固定种子 730001） | 生成产物，**不得手工精修** |
| `maps/m01_afterglow/authored/` | `tools/build_authored.gd`（三新区域 + 精修附加件） | 本脚本即精修源；生成器不越界（ps1 ownership 断言保护） |
| `maps/*/map.tscn` | `tools/assemble_*.gd` 组合 + 环境/锚点/Ambient + manifest v2 | 组装产物 |
| `maps/*/build_manifest.json` | assemble/bake 状态机唯一写者（schema_version=2） | 制作数据，不存运行状态 |

同输入重建必产等价几何/布局。authored 层的唯一性保护已改为**生成器内 fail**（exclusion 精确重复即 exit 1）+ build_m01 前后 ownership 指纹断言；旧的 `authored_input_hash.baseline` 长期基线已删除（verify 不再写 res://）。

## BuildContract（tools/build_contract.gd，chapter1-3 §2）

纯制作辅助层（不生成场景、不决定状态机）：递归资源依赖闭包、`bake_input_hash`（依赖文件集 + LightmapGI 烘焙设置快照 + 按 environment_mode 的环境快照，数值 5 位小数规范化）、覆盖判定（expected/actual/missing，actual 允许超集）、`can_reuse_bake`、`write_json_recoverable`（tmp→校验→prev 备份→替换→失败恢复）、AABB 精确重复检查。bake 输入排除 `baked/**`、清单自身、`artifacts/docs/tests/**`、`*.uid`、运行脚本；源图片同路径 `.import` 一并入签名。

## 单步运行（等价于 Stage 内部步骤）

```powershell
# 1. 基础纹理（headless，固定种子 20260919）
& $GODOT --headless --path . --script res://tools/gen_textures.gd
& $GODOT --headless --path . --import

# 2. 中文招牌（窗口运行；固定字体 assets/fonts/source/NotoSansSC-Regular.otf，OFL 1.1）
& $GODOT --path . res://tools/run_gen_signs.tscn
& $GODOT --headless --path . --import

# 3a. 街区生成层 + 精修层（固定种子；build_m01 不得触碰 authored——ps1 里有指纹断言）
& $GODOT --headless --path . --script res://tools/build_m01.gd
& $GODOT --headless --path . --script res://tools/build_authored.gd
# 3b. 室内生成层
& $GODOT --headless --path . --script res://tools/build_interior.gd
& $GODOT --headless --path . --import

# 4. 组装最终地图（can_reuse_bake：输入未变则复用旧烘焙；变了先落 pending/stale 再清数据）
& $GODOT --headless --path . --script res://tools/assemble_m01.gd
& $GODOT --headless --path . --script res://tools/assemble_interior.gd
& $GODOT --headless --path . --import

# 5. LightmapGI 烘焙（编辑器插件；报告目录由 NEON_ARTIFACT_DIR 指定，缺省 res://artifacts/build）
$env:NEON_ARTIFACT_DIR = "res://artifacts/chapter1_3"
& $GODOT --path . --editor -- --auto-bake --scene res://maps/m01_afterglow/map.tscn
& $GODOT --path . --editor -- --auto-bake --scene res://maps/m01_repair_interior/map.tscn
& $GODOT --headless --path . --import

# 6. 验证（只读）
& $GODOT --headless --path . --script res://tools/verify_build.gd                # 全部生产地图
& $GODOT --headless --path . --script res://tools/verify_build.gd -- --map m01_afterglow
```

任何几何/灯光/材质/纹理改动后**必须重跑 3→6**（输入签名变化会让 assemble 判 stale，旧 bake 不再被 verify 接受）。

## LightmapGI 自动烘焙（addons/neon_bake）

关键实现细节（排障记录，勿"简化"掉）：

1. **`bake()` 需要保存路径**：插件先落 `manifest=running`，再创建并保存空 `LightmapGIData`（`maps/<map>/baked/map_lightmap.res`），fresh-load 重绑确认 user_count=0 后才触发按钮。
2. **网格必须带 `lightmap_size_hint`**：`gen_lib.gd` 的 `commit()` 负责设置，调用处按网格体量传 2048/512/64；commit 的保存错误记录在 `last_save_error`，上层必需输出未检查即 exit 1。
3. 烘焙要求表面同时具备 UV2 与法线，收集范围为 LightmapGI 子树内 `gi_mode == GI_MODE_STATIC` 且可见的网格。
4. 完成判定：`LightmapGIData.get_user_count() > 0` 且连续 2 秒稳定；随后 missing=0 才算过（actual 允许是 expected 超集，如 Backdrop 历史 user）、`EditorInterface.save_scene()` 检查返回 Error、磁盘 fresh-load 终检、manifest=succeeded、报告写 ArtifactDir。
5. 清单 hash 与当前输入不一致会直接失败并要求重新 assemble（防旧 bake 冒充新输入）。

## 自动化截图 / 性能（运行主程序）

```powershell
# 锚点 × 两档截图（user://captures/，PNG+JSON 元数据；任一目标失败即非零退出，不静默跳图）
& $GODOT --path . -- --shoot --map m01_afterglow --quality both       # 7 锚点 × 2 档 = 14 张
& $GODOT --path . -- --shoot --map m01_repair_interior --quality both # 4 锚点 × 2 档 = 8 张
& $GODOT --path . -- --shoot --graybox          # 灰盒对照
# 注：不再生成 "_diag" 图（诊断层属 capture_ui，截图时会被隐藏；render_stats JSON 是诊断权威）

# 基准（路线必须与 --map 匹配；输出 user://benchmarks/<run_id>/ + summary.csv）
& $GODOT --path . -- --perf --map m01_afterglow --route expanded_v11 --quality both --runs 3 --warmup 15
& $GODOT --path . -- --perf --map m01_repair_interior --route interior_v13 --quality both --runs 3
& $GODOT --path . -- --perf --map m01_afterglow --route expanded_v11 --quality eco --runs 1 --occlusion off
& $GODOT --path . -- --perf --map m01_afterglow --route legacy_v1 --mode headroom --duration 5  # 余量冒烟
```

基准期间**保持窗口前台**；失焦/最小化会把本轮标记无效并中止。报告记录的是**测量期冻结快照**（不是恢复后的环境）。进程级采样另开终端：

```powershell
.\tools\sample_process.ps1 -GameProcessId <游戏PID> -RunId 'v13_eco_01' -OutputDirectory '.\artifacts\chapter1_3\performance'
```

## 测试

```powershell
& $GODOT --headless --path . --script res://tests/test_map_lifecycle.gd        # A→B→A×10 + 泄漏指标
& $GODOT --headless --path . --script res://tests/test_chapter11_contract.gd   # ch11 合同
& $GODOT --headless --path . --script res://tests/test_chapter12_contract.gd   # ch12 合同（walk/门户）
& $GODOT --headless --path . --script res://tests/test_chapter13_contract.gd   # ch13 合同（83 项检查）
```

## 脚本可重复性

所有生成脚本使用固定随机种子（纹理 20260919、几何 730001、背景 99001）；招牌使用项目内固定字体文件（哈希与许可见 `docs/asset_sources.md`）。同一输入必然产出相同资产；`bake_input_hash` no-op 稳定（tscn/tres 的随机 unique_id 在哈希前剥离）。

## 辅助

- `tools/analyze_shots.gd`：对 `artifacts/**/*.png` 输出亮度/暖色/天空/地面统计（辅助检查；目检由可看图 Agent 执行）。
- `tools/serve_artifacts.ps1`：本地静态服务器（可选，人工浏览器查看截图用）。
- `tools/build_bake_probe.gd`：最小烘焙 API/UV2 诊断（保留，非生产平行路径）。
