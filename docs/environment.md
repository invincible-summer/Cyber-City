# 环境记录

> 更新：2026-09-22。本文件记录实际检查到的工具与硬件环境，未知项如实标注。

## 引擎

- 可执行文件：`D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
- `--version` 实测输出：`4.7.2.stable.official.ed1daf0bf`（2026-09-19、2026-09-22 复测一致；Godot MCP 同版本）
- 导出模板：`%APPDATA%\Godot\export_templates\4.7.2.stable\` 已安装（chapter1-1 曾产出 `build/windows/neon_haven.exe`）。chapter1-3 最终内容的重导出列入 WP10。

## 硬件

| 项目 | 实测值 |
| --- | --- |
| CPU | Intel Core Ultra 7 255HX |
| 内存 | 32 GB（33,778,475,008 字节） |
| 独显 | NVIDIA GeForce RTX 5070 Ti Laptop GPU，驱动 32.0.15.7284 |
| 核显 | Intel(R) Graphics，驱动 32.0.101.6733 |
| 供电状态 | 未知（笔记本平台，存在动态功耗） |

- Vulkan 可用性：由 RTX 5070 Ti + 驱动版本推断可用；以实际窗口运行成功为准。
- AdapterRAM 字段（WMI）仅 ~4 GB，是 32 位字段截断值，不代表真实显存；真实显存未实测。

## 字体

- 招牌/A 牌中文字形由**项目内 `assets/fonts/source/NotoSansSC-Regular.otf`（OFL 1.1，随仓库分发）** 在制作阶段栅格化为纹理；不再使用系统字体制作（旧记录已废止）。
- 系统字体（微软雅黑/黑体）仅用于运行时 UI 文本（SystemFont 回退链），不参与资产制作。

## 运行工具链

- Shell：Git Bash（win32）。Python/Blender：未安装、不作为运行依赖。
- 网络可用（可下载资源；导出模板已安装，无需再下载）。

## 测量口径备注

- 本机为笔记本双显卡平台；NVIDIA 驱动可能按负载切换 GPU，性能数据记录时注明是工程运行还是导出运行。
