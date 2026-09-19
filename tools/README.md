# 制作工具说明

> 本目录脚本只在**制作阶段**于本机运行；发布程序不调用它们。更新：2026-09-20。

`GODOT` 下文指 `"D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`。

## 生成流水线（完整重建 M01）

```powershell
# 1. 基础纹理（headless，固定种子，可重复）
& $GODOT --headless --path . --script res://tools/gen_textures.gd

# 2. 首次导入
& $GODOT --headless --path . --import

# 3. 中文招牌（需窗口运行，用系统字体栅格化）
& $GODOT --path . res://tools/run_gen_signs.tscn
& $GODOT --headless --path . --import

# 4. 城市生成（几何+材质+场景+定义+测试夹具；固定种子）
& $GODOT --headless --path . --script res://tools/build_m01.gd
& $GODOT --headless --path . --import

# 5. LightmapGI 烘焙（编辑器插件自动触发；见下）
& $GODOT --path . --editor -- --auto-bake
& $GODOT --headless --path . --import
```

任何一步改动几何/灯光后，**必须重跑第 4-5 步**（光照是烘焙的）。

## LightmapGI 自动烘焙（addons/neon_bake）

Godot 4.7.2 未把 `LightmapGI.bake()` 暴露给脚本，也没有命令行烘焙参数；本插件在编辑器内打开场景、选中 LightmapGI、程序化点击 3D 工具栏的"烘焙光照贴图"按钮，完成后保存并退出。

关键实现细节（排障记录，勿"简化"掉）：

1. **`bake()` 需要保存路径**：`light_data` 为空且无路径时立即返回 `BAKE_ERROR_NO_SAVE_PATH`（表现为"Done baking in 00:00:00.00"且无数据）。插件先创建并保存一个空的 `LightmapGIData`（`<scene>_lightmap.res`）再触发按钮。
2. **网格必须带 `lightmap_size_hint`**：烘焙器对没有 hint 的网格回退到 64×64"basic size"（图集会缩成 256×128）。`gen_lib.gd` 的 `commit()` 负责设置，调用处按网格体量传 2048/512/64。
3. 烘焙要求表面同时具备 UV2 与法线（`ARRAY_FORMAT_TEX_UV2 | ARRAY_FORMAT_NORMAL`），收集从场景根递归，要求 `gi_mode == GI_MODE_STATIC` 且可见。

烘焙其他场景：`& $GODOT --path . --editor -- --auto-bake --scene res://path/to/scene.tscn`。

## 自动化截图 / 性能（运行主程序）

```powershell
# 三个机位 × 两档位成品截图 + 每档一张带诊断的验证图（存 user://captures/，同时复制到 artifacts/screenshots/）
& $GODOT --path . -- --shoot
& $GODOT --path . -- --shoot --graybox          # 灰盒对照（保留灰盒→成品证据链）
& $GODOT --path . -- --shoot --quality eco      # 只拍经济档

# 60 秒固定镜头路线 ×3 次 × 两档位 → artifacts/performance/chapter1_metrics.csv
& $GODOT --path . -- --perf
& $GODOT --path . -- --perf --quality eco --runs 1 --occlusion off   # 遮挡剔除开/关对照
```

## 生命周期测试

```powershell
& $GODOT --headless --path . --script res://tests/test_map_lifecycle.gd
```

## 脚本可重复性

所有生成脚本使用固定随机种子（纹理 20260919、几何 730001、背景 99001）；同一输入必然产出相同资产。手工修改产物前先确认是否会被下次生成覆盖——需要精修的内容请在 `build_m01.gd` 中改参数后重新生成，保持"生成即真实来源"。

## 辅助

- `tools/analyze_shots.gd`：对 `artifacts/screenshots/*.png` 输出亮度/暖色/天空/地面统计（无图形环境时的客观检查）。
- `tools/serve_artifacts.ps1`：本地静态服务器（可选，人工浏览器查看截图用）。
