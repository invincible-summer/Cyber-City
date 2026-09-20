# Chapter 1.1 代码映射（code_map）

> 建立于 WP0（基线提交 `404edeb` 后）。每项标注：**复用 / 兼容适配 / 需要新增**，并对应 chapter1-1 §7–10 目标接口。

## 1. 运行时职责映射

| 职责 | 实际文件 / 类 | 现状 | 1.1 处理 |
| --- | --- | --- | --- |
| 组合根/自动化入口 | `scripts/app/main.gd`（extends Node3D，`_build_shell()` 手工组合） | 复用 | 兼容适配：接线 ActivityGuard/BookmarkStore/CaptureService/BenchmarkRunner；`--perf` 改走 BenchmarkRunner；`--shoot` 走 CaptureService |
| MapManager | `scripts/maps/map_manager.gd`（Node，状态机 EMPTY/READY/UNLOADING/LOADING/ACTIVATING/ERROR） | 复用 | 兼容适配：信号加 `transaction_id/stage`、`Error` 返回值、`force_reload`、`get_state_snapshot`、环境转发、`map_unloaded`；旧 bool 返回与旧信号签名不保留（调用方全部同步更新） |
| MapRoot | `scripts/maps/map_root.gd`（class_name MapRoot） | 复用 | 兼容适配：`shutdown()` → `begin_deactivation()`；新增 `validate_runtime_contract/get_anchor_ids/get_anchor_pose/get_camera_bounds/get_camera_exclusion_bounds/apply_quality→Error`、环境快照四方法 |
| MapDefinition | `scripts/maps/map_definition.gd`（Resource，v1 字段） | 复用 | 兼容适配：新增 §6.3 v2 字段与访问器；`validate()` 校验 schema；v1 读入补默认 |
| 画质/设置 | `scripts/app/settings_manager.gd`（Node；`user://settings.cfg`） | 复用 | 兼容适配：合同更名 `set_profile/get_profile_id/get_effective_state/apply_to_map/set_window_state/capture_runtime_state/restore_runtime_state`；effective_state 含实际生效值；配置保持 JSON（`data/quality/*.json`），不迁移 .tres |
| 相机 | `scripts/app/camera_controller.gd`（Node3D + 子 Camera3D） | 复用 | 兼容适配：新增 `pose_changed/bind_map_contract/unbind_map/get_pose/validate_pose/apply_pose/set_input_enabled`；保留 `go_to_anchor/set_route_transform` 内部使用；`set_map_data` 改为薄适配 |
| CameraPose 值对象 | 无 | 需要新增 | `scripts/app/camera_pose.gd`（RefCounted；JSON 序列化/校验） |
| 书签 | 无 | 需要新增 | `scripts/app/bookmark_store.gd`（`user://camera_bookmarks.json`，原子写 + 备份，≤12/图） |
| ActivityGuard | 无（MapManager 用 `is_busy()` 自查） | 需要新增 | `scripts/app/activity_guard.gd`（RefCounted；map_transition/capture/benchmark 互斥） |
| 截图 | `scripts/app/screenshot_tool.gd`（`take_screenshot()` 返回路径） | 复用 | 兼容适配 → `scripts/app/capture_service.gd`：`request_capture` + 完成/失败信号 + JSON 元数据 + capture_ui 组隐藏 + token 互斥 |
| 诊断 | `scripts/app/diagnostics.gd`（4Hz 面板 + 采样缓冲） | 复用 | 兼容适配：采样口径迁移到 BenchmarkRunner（nearest-rank、单调时钟）；面板保留 |
| 基准 | `main.gd` 内联 `_run_automation_perf/_run_one_route/ROUTE_SEGMENTS/CSV` | 兼容适配 | 需要新增 `scripts/diagnostics/benchmark_runner.gd`；main.gd 旧内联路线迁出；`legacy_v1` 段原样保留 |
| 工具 UI | `scripts/app/tool_ui.gd`（CanvasLayer，程序化构建） | 复用 | 兼容适配：书签菜单、4/5/6 机位提示、加载阶段名显示 |
| 进程采样 | 无 | 需要新增 | `tools/sample_process.ps1`（PID+启动时间+run_id，1Hz WorkingSet64/PrivateMemorySize64/CPU） |

## 2. 制作/生成管线映射

| 职责 | 实际文件 | 现状 | 1.1 处理 |
| --- | --- | --- | --- |
| 纹理生成 | `tools/gen_textures.gd`（SceneTree，种子 20260919）→ `assets/m01_afterglow/textures/` | 复用 | 按需增加新区域纹理；输出路径不变 |
| 招牌生成 | `tools/gen_signs.gd`（窗口运行 + SystemFont 栅格化）→ `textures/signs/` | 复用 | FIX-10：改为固定字体文件（OFL 优先），记录版本/哈希/许可 |
| 网格构建库 | `tools/gen_lib.gd`（GenLib：MeshBuilder + ShelfPacker UV2 + roof_kit/window_unit/streetlight/bench/ac_unit） | 复用 | 新区域直接使用；不改打包器核心 |
| 城市生成 | `tools/build_m01.gd`（SceneTree，种子 730001）→ 单体 `map.tscn`+`map_definition.tres` | 复用 | 兼容适配：输出改为 `generated/map_generated.tscn`（含 StaticGeometry/Props/Lighting）；不再写 map.tscn/definition/anchors/environment |
| 精修层构建 | 无 | 需要新增 | `tools/build_authored.gd` → `authored/authored_static.tscn`（三新区域 + 精修附加件，含 AuthoredLighting） |
| 场景组装 | `build_m01.gd` 内联 | 兼容适配 | 需要新增 `tools/assemble_m01.gd`：组 map.tscn（BakedWorld 双实例 + Backdrop + Environment + 六锚点 + Ambient）、写 v2 定义、`build_manifest.json` 输入指纹 |
| 烘焙插件 | `addons/neon_bake/bake_plugin.gd`（编辑器内点"烘焙光照贴图"按钮） | 复用 | 兼容适配 → BakeCoordinator 合同（`bake_started/bake_finished/get_status`、烘焙后 user 路径核对、清单状态写回） |
| 烘焙产物 | `maps/m01_afterglow/map_lightmap.res/.exr`（插件在场景旁落盘） | 复用 | 迁移说明：组装后 LightmapGI 在 `map.tscn` 根下，数据文件放 `maps/m01_afterglow/baked/`；以实际保存路径为准并记录 |
| 构建入口 | `tools/README.md` 五步流水线 | 复用 | 需要新增 `tools/build_chapter11.ps1`（validate/generate/assemble/bake/verify/export/all） |
| 资源分析 | `tools/analyze_shots.gd`（像素统计辅助） | 复用 | 保留为辅助；目检改由可看图 Agent 执行 |

## 3. 数据与配置映射

| 文件 | 现状 | 1.1 处理 |
| --- | --- | --- |
| `data/map_registry.json` | v1，仅 m01 | 保持（新增字段在定义层） |
| `data/quality/eco.json` / `balanced.json` | 档位 JSON | 保持 JSON；新增字段若需要（如 occlusion_enabled）在此扩展，单一权威 |
| `maps/m01_afterglow/map_definition.tres` | v1，三锚点，bounds ±50/±70 | 迁移 v2：content_revision=1.1.0、六锚点、bounds X ±78/Z ±98/Y≤28、分层禁入体积、requires_baked_lighting=true |
| `tests/fixtures/mini_test_map*` | 极小 B 图 | 保留；定义补 v2 默认值兼容 |
| `docs/asset_sources.md` | 字体=系统字体记录 | 更新字体来源/许可/哈希 |

## 4. 测试映射

| 文件 | 现状 | 1.1 处理 |
| --- | --- | --- |
| `tests/test_map_lifecycle.gd` | 49 项，A→B→A×5 | 适配新信号签名；往返 ×10；增加地图专有资源弱引用 + 对象计数 + 内存趋势；T01/T02（v1 补默认/未来版本拒绝）、T05（force_reload）用例 |
| 新增测试 | 无 | `tests/test_chapter11_contract.gd`：CameraPose 序列化、书签存取/损坏恢复、ActivityGuard 互斥、QualityController 快照恢复、T11/T12 清单 stale 与重建保护（headless 可运行） |

## 5. 兼容性决定记录

- 旧信号 `map_loading(map_id, progress)` / `map_loaded(map_id)` / `map_failed(map_id, reason)` 与 bool 返回值**不保留双轨**：调用方（main.gd、test_map_lifecycle.gd）全部一次性迁移，避免两套状态机（§7.1）。
- `MapRoot.shutdown()` 更名为 `begin_deactivation()`，调用方仅 MapManager 一处。
- `settings_manager.set_quality()/force_apply()/get_profile()` 保留为合同方法的薄适配（tool_ui/main.gd 现有接线沿用）。
- `screenshot_tool.take_screenshot()` 由 CaptureService.request_capture 替代；main.gd 的 `--shoot`/F12 路径同步改写。
- 渲染器/分辨率/配置仍是 `data/quality/*.json` 权威，QualityController 只做加载/应用/恢复，不落第二份配置。
