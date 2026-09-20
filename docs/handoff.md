# 本轮交接

- **当前工作包**：chapter1-1 WP3/WP4 美化精修 + 关键管线修复（WP5 烘焙验证部分）。G0–G4 达成，G5/G6 未跑（见下）。
- **本轮核心修复（按影响排序）**：
  1. **场景"里外翻转"根因**：`GenLib.MeshBuilder` 四角约定（从法线侧看逆时针）与 Godot 正面绕序（屏幕顺时针）相反，全部生成面片正面朝反侧——单面招牌不可见、双面站牌镜像、路面顶面被剔除（街面无细节平面）、窗框悬浮。修复：`tools/gen_lib.gd _flush()` 输出三角形反转。修复后所有招牌（余晖维修/海风便利/湾流洗衣/霓湾站等）可见、可读、方向正确，路面标线/铺装/道具恢复可见。
  2. **烘焙 X2 复制循环**：编辑器烘焙 LightmapGI 子树内的 PackedScene 实例会复制出 X2 副本网格并写回场景（每次烘焙 13 users 且自我延续）。修复：`tools/assemble_m01.gd` 改为展平嵌入（保留 `Generated/`、`Authored/` 容器节点名与 region_manifest 路径一致，map.tscn 无 `instance=` 引用）；owner 不再进入实例内部节点。修复后 precheck 11 网格/7 UV2，烘焙 users=7（6 网格+Backdrop）、missing=0，map.tscn 干净。
  3. **灯光能量收敛**（§13.1 FAIL 项消除）：维修铺大门面 glass_shop 1.0→0.55（原为整片白）；店内灯 10/7→2.2/1.8；interior_back 1.4→0.6；串灯 3.2→1.2 且半径缩小；站前烘焙灯 4.0/2.6/2.2→2.6/1.8/1.6；生活广场补 2 盏灯；灌木改三簇八面体。
  4. **三个新机位重构**（§3.2）：service_court_view（原视线穿附楼实体）→ 拱门内框景洗衣店；station_forecourt_view（原被售票亭空白墙占 1/3）→ 站牌+阶梯+雨棚构图；roof_terrace_view → 栏杆前景+主街天际线。原三机位姿态未动（street_view/repair_shop_view 保持原版；station_view 沿用 WP1 修正值）。
- **实际执行过的验证及结果**：
  - `tools/verify_build.gd` 全部 PASS（bake_status=succeeded、指纹一致、authored 未被覆盖、合同校验、6 锚点/40 禁入体积）。
  - `tests/test_map_lifecycle.gd`：生命周期测试全部通过（A→B→A、缺锚点/无效 ID、失败恢复）。
  - `tests/test_chapter11_contract.gd`：64/64 PASS（CameraPose/书签/互斥/画质快照/帧率生效）。
  - 最终烘焙 `bake_report_*.json`：users=7 expected=6 missing=0（无 X2）。
  - 六机位 × 两档 = 12 张成品截图 + JSON 元数据（`artifacts/chapter1_1/screenshots_final/`），逐张目检：招牌可读方向正确、无整片过曝、无镜像、无缺字、构图达标。
  - 完整管线（generate→authored→assemble→import→bake→verify→shoot）全绿：`artifacts/chapter1_1/pipeline_v5.log`。
- **本轮确认的关键机制（后续必读）**：
  1. Godot 正面 = 屏幕顺时针绕序；GenLib 四角按"从法线侧看逆时针"输入，`_flush()` 负责反转输出。**新增面片一律走 mb.quad，不要自行 push 三角形**（bulb 除外，其材质 cull_disabled）。
  2. **不要在 LightmapGI 子树内使用 PackedScene 实例**（烘焙会复制 X2）；assemble 的展平嵌入是既定方案。
  3. 编辑器烘焙前必须删除 `.godot/editor/project_metadata.cfg` 与 `map.tscn-editstate-*.cfg`（防编辑器恢复旧场景状态）。
  4. 修改材质/灯能量后必须重跑 generate→assemble→bake（指纹自动判定 stale）；仅改锚点/禁入体积只需 authored+assemble。
- **截图/日志路径**：`artifacts/chapter1_1/screenshots_final/`、`pipeline_v5.log`、`bake_report_*.json`、`docs/chapter1_1/review.md`（门槛状态矩阵）。
- **尚未验证的内容与原因**：
  1. **G5 性能采样**：内容变更后需按 §8.3 重跑 legacy_v1 对照 + expanded_v11 两档×3 轮 + `tools/sample_process.ps1` 进程采样 + 10 次 A→B→A 生命周期记录（本轮全部重做内容，未采样）。
  2. **G6 发布**：干净检出 Release 导出与独立目录运行（模板已装，预设已建）。
  3. 失焦/最小化节流交互实测（逻辑有测试覆盖，交互项待人工）。
- **当前阻塞问题**：无。
- **下一轮第一项任务**：跑 G5（`-- --perf` 双路线采样 + sample_process.ps1），达标后做 G6 导出验收。
- **精确启动/测试命令**（`$G = "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`）：
  - 完整重建：`.\tools\build_chapter11.ps1 -GodotExe $G -ProjectPath . -Stage all -MapId m01_afterglow`（或按 pipeline_v5.log 内的逐步命令）。
  - 生命周期：`& $G --headless --path . --script res://tests/test_map_lifecycle.gd`
  - 合同测试：`& $G --headless --path . --script res://tests/test_chapter11_contract.gd`
  - 截图：`& $G --path . -- --shoot`（产物在 `user://captures/`，复制到 artifacts 时排除 *diag*）
  - 性能：`& $G --path . -- --perf [--quality eco|balanced] [--route legacy_v1|expanded_v11]`
- **需要保留的美术或技术决定**：
  1. 面片朝向修复是全局行为变更：历史烘焙数据作废重建是预期行为（清单指纹判定）。
  2. 玻璃橱窗保持不透明自发光面板（风格化暖光，0.55 能量），不引入透明排序问题；如需内景可后续单独验证。
  3. 站牌双面构造：两面各自 c0 落在"该侧观察者左下"，配合反转后的 `_flush()` 读取正确。
