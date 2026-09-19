# 本轮交接

- **当前工作包**：chapter1 全部工作包（A–G）完成；遗留见下。
- **已完成的可见成果**：
  - 可运行的 4.7.2 工程：主场景、单地图 MapManager 状态机、工具 UI、Eco/Balanced 画质档、截图/诊断、受限自由相机 + 三机位。
  - M01 余晖街区成品：程序化生成 14 万三角以内城市场景（主街/侧巷/修理铺广场/高架站口/22 塔远景+信号塔），10 张中文招牌，LightmapGI 静态烘焙（`map_lightmap.res/.exr`）。
  - 自动化：`--shoot`（截图）/`--perf`（60s×3×2 档位 CSV）/ `addons/neon_bake`（编辑器自动烘焙插件）。
- **实际执行过的验证及结果**：
  - 生命周期测试 `tests/test_map_lifecycle.gd`：49/49 通过（A→B→A×5、弱引用失效、≤1 活动地图、无效 ID/缺路径/缺锚点/重复请求）。
  - 性能：Eco 30.00 FPS（P95 33.3ms）、Balanced 59.1–60.0 FPS（P95 16.7ms）、显存 161/227MiB、暖加载 626ms —— 全部达标（`artifacts/performance/chapter1_metrics.csv`）。
  - 画面：6 成品 + 3 灰盒 + 1 诊断截图（`artifacts/screenshots/`），像素统计无黑区/过曝，灰盒→成品差异成立。
  - `--headless --import` 无脚本错误；烘焙经编辑器插件真实执行（8.4s / 13.2MB EXR）。
- **截图/日志路径**：`artifacts/screenshots/`、`artifacts/performance/`、`artifacts/logs/lifecycle_test.log`。
- **尚未验证的内容与原因**：
  1. **Windows 导出**：本机无 4.7.2 导出模板（`%APPDATA%\Godot\export_templates\` 为空）。补做步骤：编辑器 → 管理导出模板 → 下载 4.7.2 → 项目 → 导出 → 新建 `Windows Desktop` 预设（主场景、排除 `tools/`、`tests/`、`docs/`、`artifacts/`）→ 导出到 `build/neon_haven.exe` → 在含中文与空格的目录实测启动；或命令行 `& $GODOT --headless --path . --export-release "Windows Desktop" ./build/neon_haven.exe`。
  2. **人工目检**：本轮 Agent 无图形输入，画面验证采用像素统计 + 灰盒对照；请运行工程按 1/2/3 逐机位目检（构图、招牌可读性、氛围）。
  3. 失焦/最小化节流的交互实测（逻辑已实现并规避了测量污染）。
- **当前阻塞问题**：无。
- **下一轮第一项任务**：用户目检 M01 → 收集审美反馈（亮度/招牌/构图）→ 微调 `build_m01.gd` 参数并重跑生成+烘焙流水线；或先补导出模板做 Windows 导出验证。
- **精确启动/测试命令**（`$GODOT = "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`）：
  - 正常运行：`& $GODOT --path .`
  - 生命周期：`& $GODOT --headless --path . --script res://tests/test_map_lifecycle.gd`
  - 截图/性能：`& $GODOT --path . -- --shoot` / `& $GODOT --path . -- --perf`
  - 完整重建（改几何/灯光后）：见 `tools/README.md` 五步流水线（最后一步 `& $GODOT --path . --editor -- --auto-bake`）
- **需要保留的美术或技术决定**：
  1. Godot 4.7.2 **没有脚本可调的 `LightmapGI.bake()`**；烘焙唯一入口是编辑器 UI → 用 `addons/neon_bake` 插件自动化，且**必须**先放一个已保存的 `LightmapGIData`（否则秒退 `BAKE_ERROR_NO_SAVE_PATH`），网格**必须**带 `lightmap_size_hint`（否则回退 64×64）。
  2. UV2 由 `gen_lib.gd` 天际线打包器生成（利用率 95%+，溢出 0）；烘焙器会按实例再映射，二者兼容。
  3. 运行时隐藏全部烘焙灯（`q_runtime_light` 组）——静态光照只走 lightmap，杜绝双重照明与逐灯开销。
  4. 性能测量自动化必须禁用失焦节流并重置 user 配置（已内置 `--perf`）。
  5. 招牌字体=系统字体制阶段栅格化；对外分发前换 OFL 字体重跑（`docs/asset_sources.md`）。
