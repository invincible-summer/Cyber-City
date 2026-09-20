# Chapter 1.1 实施计划（本轮 Agent 执行版）

> 依据：`docs/DESIGN/chapter1-1.md`（v1.0）· 基线提交 `404edeb` · 分支 `chapter1-1`
> 引擎实测：`4.7.2.stable.official.ed1daf0bf` · 本机路径 `D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`

## 硬件/环境记录（G0）

- 引擎：Godot 4.7.2 stable（`--version` 实测，与 MCP 报告一致）。
- OS：Windows 10.0.26200 x64；渲染 API：Vulkan（mobile 渲染器，上一轮 CSV 记录 renderer=mobile）。
- CPU/GPU/驱动型号：**未获取**（环境无 wmic/系统信息读取记录，标为未知；不据此下功耗结论）。
- 导出模板：`%APPDATA%\Godot\export_templates\` 为空（第一阶段交接记录），WP0 重新核对。
- 基线截图：`artifacts/chapter1_1/baseline/`（三机位 × 两档，1920×1080，FOV 60，原姿态见下表）。

## 原三机位姿态（原版对照基线）

| 锚点 | 位置 | 注视点 | FOV |
| --- | --- | --- | --- |
| street_view | (-3, 1.7, 52) | (1, 8, -45) | 60 |
| repair_shop_view | (15, 1.8, 31) | (33, 2.5, 25) | 60 |
| station_view | (18, 12, -35) | (0, 12, -62) | 60 |

## 现有地图实测布局（新区域定位依据）

- 主街路面 X ±6，人行道至 ±11；西楼群 X -38…-12（W1/W2/W3/W5/W6/W7），东楼群 X 12…34（E1/E3–E7）；修理铺 X 33…44, Z 18…36；高架站 Z -66.8…-59.6（柱 X ±(12.6…15)，桥面 X -20…26）；侧巷地面 X -45…-12, Z -6…6，巷尾栅栏门 X ≈ -45.1；远景塔环半径 95…165。
- 现有相机 bounds X -50…50 / Y 1.5…24 / Z -70…70。

新区域按 chapter1-1 §3.1 参考坐标落位（service_court X -73…-45 接侧巷西端；station_forecourt X 10…43, Z -88…-62 位于高架北侧地面层；roof_terrace 落于生活广场附楼顶部）。全部为**新增几何**，不平移旧建筑；与生成层不重叠放置同一面墙。

## 工作包执行顺序与完成条件

| WP | 内容 | 完成条件（本章门槛） |
| --- | --- | --- |
| WP0 | 审计、基线、code_map、导出预设、首轮导出尝试 | G0：code_map/基线/问题清单/预设齐备 |
| WP1 | 生成/精修分层、MapDefinition v2、运行时接口合同、字体固定、build_chapter11.ps1 | G1：原地图不退步，重建安全，迁移测试通过 |
| WP2 | 三处新空间灰盒、六机位、边界与禁入体积 | G2：灰盒图 + 空间检查清单 |
| WP3 | 主街/维修铺/旧侧巷精修（生成参数 + 精修层） | G3 原区域部分：前后对照清楚 |
| WP4 | 三处扩展成品化 | G3 新增区域部分 |
| WP5 | 重烘焙 + 覆盖验证、书签、截图元数据、互斥、两档复核 | G4 |
| WP6 | BenchmarkRunner、双路线、进程采样、10 往返、遮挡对照 | G5 |
| WP7 | 导出发布、干净目录运行、README/review/验收矩阵 | G6（模板缺失时按 §15 处理并保留缺口） |

## 关键实现决定（对本章设计的落地选择）

1. **分层归属**：`build_m01.gd` 继续作为基础城市生成器，输出改写到 `generated/map_generated.tscn`（StaticGeometry/Props/Lighting）；新增 `tools/build_authored.gd` 产出 `authored/authored_static.tscn`（三个新区域 + 精修附加几何，生成器不覆盖）；新 `tools/assemble_m01.gd` 组合最终 `map.tscn`（BakedWorld=LightmapGI 下双实例 + Backdrop + Environment + 六锚点 + Ambient + Reserved）并写 MapDefinition v2 与 `build_manifest.json` 输入指纹。旧 `map.tscn` 单体生成方式废止（历史场景由 Git 保留）。
2. **锚点权威**：`anchor_names` 为唯一权威字段（六项），`capture_anchor_names` 提供访问器回落，不双份维护。
3. **灯组**：`bake_only_light`（原 q_runtime_light 迁移，运行期一律隐藏）+ `runtime_fill_light`（原 q_extra_light，档位控制）+ `optional_probe` / `optional_particle`（原 q_probe / q_particle 更名）。
4. **测量路线**：`legacy_v1` = 现 ROUTE_SEGMENTS 三段 60s；`expanded_v11` = 六段各 10s。
5. **基准自动化**：`--perf` 改为调用 BenchmarkRunner；进程级采样用新 `tools/sample_process.ps1`（外部 PowerShell，1 Hz）。
6. **字体**：优先下载 OFL 可再分发中文字体并改造 `gen_signs.gd`；不可达时保留系统字体栅格化并在 asset_sources/review 中隔离缺口（§15 授权做法）。
7. **导出**：创建 `Windows Desktop` 预设并核对资源规则；模板缺失则按 §15 完成预设与安装步骤，G6 相应项保持未通过，不删除发布要求。
