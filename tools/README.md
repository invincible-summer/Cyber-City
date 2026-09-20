# 制作工具说明

> 本目录脚本只在**制作阶段**于本机运行；发布程序不调用它们。更新：2026-09-20（chapter1-1 分层管线）。

`$GODOT` 指本地 Godot 4.7.2 可执行文件（示例：`"D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`）。**工具路径只作为可替换示例**，统一入口会从参数/环境变量读取。

## 统一构建入口（chapter1-1 §9.1）

```powershell
$GODOT = "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
.\tools\build_chapter11.ps1 -GodotExe $GODOT -ProjectPath . -Stage all -MapId m01_afterglow
# 分阶段：
#   validate  引擎/字体/路径校验
#   generate  纹理 → 招牌(固定字体) → generated/ 生成层 + authored/ 精修层
#   assemble  组合 map.tscn + MapDefinition v2 + build_manifest.json
#   bake      编辑器内真实烘焙（neon_bake 插件；NEON_BAKE_EXIT 判定）
#   verify    指纹/烘焙覆盖/场景/定义 + 生命周期 + 合同测试
#   export    Windows Release 导出
```

只改 UI 文案/书签/不参与烘焙的设置时**不需要**重跑 generate/bake——运行 `verify` 确认指纹未变即可。

## 分层责任（chapter1-1 §6.1）

| 层 | 来源 | 可否手工/工具精修 |
| --- | --- | --- |
| `maps/m01_afterglow/generated/` | `tools/build_m01.gd`（固定种子 730001） | 生成产物，**不得手工精修** |
| `maps/m01_afterglow/authored/` | `tools/build_authored.gd`（三新区域 + 精修附加件） | 本脚本即精修源；生成器不覆盖 |
| `maps/m01_afterglow/map.tscn` | `tools/assemble_m01.gd` 组合两层 + 环境/六锚点/Ambient | 组装产物 |
| `maps/m01_afterglow/build_manifest.json` | assemble 写输入指纹；烘焙插件回写 bake_status | 制作数据，不存运行状态 |

同输入重建必产等价几何/布局；authored 指纹在 `authored/authored_input_hash.baseline` 对照（T12）。

## 单步运行（等价于 Stage 内部步骤）

```powershell
# 1. 基础纹理（headless，固定种子 20260919）
& $GODOT --headless --path . --script res://tools/gen_textures.gd
& $GODOT --headless --path . --import

# 2. 中文招牌（窗口运行；固定字体 assets/fonts/source/NotoSansSC-Regular.otf，OFL 1.1）
& $GODOT --path . res://tools/run_gen_signs.tscn
& $GODOT --headless --path . --import

# 3. 城市生成层 + 精修层（固定种子）
& $GODOT --headless --path . --script res://tools/build_m01.gd
& $GODOT --headless --path . --script res://tools/build_authored.gd
& $GODOT --headless --path . --import

# 4. 组装最终地图（map.tscn + 定义 v2 + 清单）
& $GODOT --headless --path . --script res://tools/assemble_m01.gd
& $GODOT --headless --path . --import

# 5. LightmapGI 烘焙（编辑器插件自动触发；4.7.2 无脚本可调 bake()）
& $GODOT --path . --editor -- --auto-bake
& $GODOT --headless --path . --import

# 6. 验证
& $GODOT --headless --path . --script res://tools/verify_build.gd
```

任何几何/灯光改动后**必须重跑 3→6**（光照是烘焙的；清单指纹会把旧 EXR 判为 stale）。

## LightmapGI 自动烘焙（addons/neon_bake）

关键实现细节（排障记录，勿"简化"掉）：

1. **`bake()` 需要保存路径**：插件先创建并保存空 `LightmapGIData`（`maps/m01_afterglow/baked/map_lightmap.res`）再触发按钮。
2. **网格必须带 `lightmap_size_hint`**：`gen_lib.gd` 的 `commit()` 负责设置，调用处按网格体量传 2048/512/64。
3. 烘焙要求表面同时具备 UV2 与法线，收集范围为 LightmapGI 子树内 `gi_mode == GI_MODE_STATIC` 且可见的网格。
4. 完成判定：`LightmapGIData.get_user_count() > 0` 且连续 2 秒稳定；随后核对 user 路径 vs 场景网格、回写 `build_manifest.json`、写 `artifacts/chapter1_1/bake_report_*.json`。

## 自动化截图 / 性能（运行主程序）

```powershell
# 六机位 × 两档截图 + 每档诊断图（user://captures/，PNG+JSON 元数据）
& $GODOT --path . -- --shoot
& $GODOT --path . -- --shoot --graybox          # 灰盒对照
& $GODOT --path . -- --shoot --quality eco      # 只拍经济档

# 基准（BenchmarkRunner 合同；输出 user://benchmarks/<run_id>/ + summary.csv）
& $GODOT --path . -- --perf                                        # legacy_v1 ×3 × 两档
& $GODOT --path . -- --perf --route expanded_v11                   # 1.1 全覆盖路线
& $GODOT --path . -- --perf --route expanded_v11 --quality eco --runs 1 --occlusion off
& $GODOT --path . -- --perf --route legacy_v1 --mode headroom --warmup 5   # 余量诊断（≤60s）
```

基准运行期间**保持窗口前台**；失焦/最小化会把本轮标记无效并中止（不混入有效结果）。进程级采样另开终端：

```powershell
.\tools\sample_process.ps1 -GameProcessId <游戏PID> -RunId 'v11_eco_01' -OutputDirectory '.\artifacts\chapter1_1\performance'
```

游戏进程 PID 可在启动后从任务管理器或 `Get-Process neon_haven` 取得（以启动时间匹配防复用）。

## 测试

```powershell
& $GODOT --headless --path . --script res://tests/test_map_lifecycle.gd      # A→B→A×10 + 泄漏指标
& $GODOT --headless --path . --script res://tests/test_chapter11_contract.gd # 合同测试
```

## 脚本可重复性

所有生成脚本使用固定随机种子（纹理 20260919、几何 730001、背景 99001）；招牌使用项目内固定字体文件（哈希与许可见 `docs/asset_sources.md`）。同一输入必然产出相同资产。

## 辅助

- `tools/analyze_shots.gd`：对 `artifacts/**/*.png` 输出亮度/暖色/天空/地面统计（辅助检查；目检由可看图 Agent 执行）。
- `tools/serve_artifacts.ps1`：本地静态服务器（可选，人工浏览器查看截图用）。
