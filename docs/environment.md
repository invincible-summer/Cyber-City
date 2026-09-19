# 环境记录

> 更新：2026-09-19。本文件记录实际检查到的工具与硬件环境，未知项如实标注。

## 引擎

- 可执行文件：`D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
- `--version` 实测输出：`4.7.2.stable.official.ed1daf0bf`（2026-09-19）
- Godot MCP 可用，报告同一版本。
- 导出模板：`%APPDATA%\Godot\export_templates\` 目录存在但为空，**未安装 4.7.2 模板** → Windows 导出标记为待验证。

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

- 系统存在 `msyh.ttc`（微软雅黑）、`msjh.ttc`（正黑）、`simhei.ttf`（黑体）。
- 制作阶段用系统字体栅格化招牌纹理；字体文件不进入发布包（许可限制，见 docs/asset_sources.md）。

## 运行工具链

- Shell：Git Bash（win32）。Python/Blender：未安装、不作为运行依赖。
- 网络可用（可下载资源，但导出模板约 1 GB，未获用户明确要求不自动下载）。

## 测量口径备注

- 本机为笔记本双显卡平台；NVIDIA 驱动可能按负载切换 GPU，性能数据记录时注明是工程运行还是导出运行。
