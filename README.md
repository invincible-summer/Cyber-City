# 霓湾 / Neon Haven

一座温暖、安静、带有复古科技气息的近未来滨海城市——以独立街区组成、可持续扩建的 3D 场景库。
当前形态：**可自由观察和摄影的城市场景展示程序**（无玩法、无 NPC）。

## 当前内容（第一阶段）

- 一张完整地图 **M01 余晖街区 `m01_afterglow`**：120×160 米核心街区，主街、侧巷、修理铺广场、街尾高架站口、远景塔楼与信号塔；固定傍晚"雨停后的蓝调时刻"光照（LightmapGI 静态烘焙）。
- 受限自由观察摄影机 + 三个固定机位（`street_view` / `repair_shop_view` / `station_view`）。
- 经济 / 均衡两档画质；失焦与最小化自动节流。
- 截图（F12，保存到 `user://captures/`）、诊断面板（F2）、隐藏全部 UI（F1）。
- 严格单活动地图的加载/卸载架构（见 `docs/chapter1_review.md` 的测试证据）。

## 环境要求

- Windows x86_64。
- Godot **4.7.2 stable**（本工程按此版本开发与验证）。无需 Python、Blender 或网络。

## 启动

```powershell
& "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path <项目目录>
```

默认进入余晖街区，经济档（0.80 渲染比例 / 30 FPS 上限）。

## 操作

| 输入 | 行为 |
| --- | --- |
| 鼠标右键按住 | 转向观察；松开恢复指针 |
| W/A/S/D + Q/E | 移动 / 下降 / 上升 |
| Shift | 加速（3→9 m/s） |
| 滚轮 | 调整移动速度 |
| 1 / 2 / 3 | 切换三个固定机位 |
| Home | 回默认机位 |
| F1 | 隐藏/恢复工具 UI |
| F2 | 诊断面板（FPS/绘制/节点/内存，4Hz） |
| F12 | 截图（自动隐藏 UI，PNG 存 `user://captures/`） |
| Esc | 释放指针 / 打开地图与工具菜单 |

## 画质档位

| 项目 | 经济 Eco（默认） | 均衡 Balanced |
| --- | --- | --- |
| 3D 渲染比例 | 0.80 | 1.00 |
| 帧率上限 | 30 | 60 |
| 抗锯齿 | FXAA | MSAA 2× |
| Glow | 关 | 低强度 |
| 粒子/探针/补光 | 关 | 开（≤2 探针、≤2 局部粒子） |
| 失焦 / 最小化 | 10 FPS / 5 FPS+暂停动画 | 同左 |

设置保存在 `user://settings.cfg`；非法值回落 Eco。两档共用同一套烘焙光照。

## 已知限制（第一阶段）

- **Windows 导出未验证**：本机未安装 4.7.2 导出模板（`%APPDATA%\Godot\export_templates\` 为空），`build/` 无产物。工程侧导出预设尚未创建——安装模板后按 `docs/handoff.md` 步骤补做。
- 招牌中文字形在制作阶段由 Windows 系统字体（微软雅黑）栅格化生成纹理；字体文件本身不随项目分发。若对外分发本项目，需替换为可分发字体并重新生成 `assets/m01_afterglow/textures/signs/`（见 `docs/asset_sources.md`）。
- GPU 性能数据见 `artifacts/performance/`；工作集等系统级指标标注 N/A（引擎内无法可靠采样，需外部工具）。

## 目录速览

```
scenes/app/main.tscn      主场景（外壳 + 相机 + UI）
scripts/app|maps/         外壳、地图管理（GDScript，带类型标注）
maps/m01_afterglow/       第一张地图（场景、定义、网格、烘焙数据）
assets/m01_afterglow/     材质与程序化纹理
data/                     地图注册表与画质配置（JSON）
tools/                    离线制作脚本（纹理/招牌/城市生成/烘焙插件）
tests/                    生命周期测试与极小测试地图（不进用户菜单）
docs/                     环境、待办、交接、资产来源、阶段复核
artifacts/                截图与性能证据
addons/neon_bake/         编辑器自动烘焙插件（--auto-bake）
```

更多规范见根目录 `AGENTS.md` 与 `docs/DESIGN/chapter1.md`。
