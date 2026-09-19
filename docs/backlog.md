# 第一阶段待办（chapter1 工作包）

> 状态：未开始 / 进行中 / 完成 / 待验证。更新：2026-09-20。

| # | 任务 | 状态 |
| --- | --- | --- |
| A | 工程外壳与地图生命周期（主场景、MapDefinition、MapManager、注册表、UI、设置、截图、诊断） | 完成 |
| B | M01 布局与三个主构图（主街/侧巷/修理铺广场/高架站口/远景） | 完成 |
| C | 建筑模块、材质、中文招牌、近景细节（程序化生成 + 光照贴图 hint） | 完成 |
| D | 傍晚光照 + LightmapGI 烘焙（`addons/neon_bake` 编辑器插件方案） | 完成 |
| E | 相机、画质档、截图、诊断工具（含 `--shoot`/`--perf` 自动化） | 完成 |
| F1 | 生命周期测试 A→B→A ×10（`tests/test_map_lifecycle.gd`，49/49 通过） | 完成 |
| F2 | 60s×3×两档位固定路线性能 CSV（`--perf`） | 进行中 |
| G1 | 6 张主机位成品截图 + 灰盒对照 + 像素统计复核 | 完成 |
| G2 | README / asset_sources / tools README / review / handoff | 完成（review 待 F2 数据） |
| G3 | Windows 导出 | 待验证（本机无 4.7.2 导出模板；工程可运行，导出预设未建） |

## 遗留清单（下一轮）

1. 安装 4.7.2 导出模板 → 建 `Windows Desktop` 预设 → 导出 `build/neon_haven.exe` → 中文+空格路径实测（见 docs/handoff.md）。
2. 若 Eco 平均 FPS 未达 ≥29：检查 VSync 与 max_fps 组合（当前窗口 60Hz + 30 上限可能出现跳拍），做一次 `--vsync off` 对照或改用 60 上限对照测量后决定。
3. 遮挡剔除开/关对照（`--perf --occlusion off --runs 1`）补一组数据。
4. 人工目检三个机位画面（本轮为像素统计验证，缺少人工审美复核）。
