# chapter1-3 实施记录（工程信任链 WP0–WP7 + 回归验收）

> 基线：main@07f135b（chapter1-3 计划三轮评审定稿，实施为零）。
> 本轮提交：3a08948（WP0–WP7 全量）+ 后续回归验收提交。
> 日期：2026-09-22。执行入口：`docs/DESIGN/chapter1-3.md`。

## 1. 本轮完成（WP0–WP7 全绿）

### WP0 基线冻结（只读）

`artifacts/chapter1_3/wp0_baseline.json`：commit 07f135b、street/interior manifest v1（succeeded/expected 为空——v1 缺陷实证）、authored 29 exclusions/8 组精确重复、generated 18/0、SC_ANNEX 双权威 h9.1 vs h8.55、WP7 候选引用扫描结论。与计划 §7.1 数字完全一致。

### WP1 BuildContract + manifest v2（C13-01/03/04/21 部分）

- `tools/build_contract.gd`：依赖闭包（普通/`uid://x::::res://`/文档 UID 形式统一取尾段 res://）、`bake_input_hash`（文件集+LightmapGI 烘焙设置快照+按 environment_mode 环境快照；实测 environment_mode=1=SCENE，环境纳入签名；数值 5 位小数规范化防 tscn 往返漂移）、expected/actual/missing（actual 允许超集——Backdrop 历史 user）、`can_reuse_bake`、`write_json_recoverable`（tmp→回读校验→prev 备份→替换→失败恢复）、`exact_duplicate_aabbs`。
- 排除规则严格按 §2.3（baked/**、清单自身、artifacts/docs/tests、.uid、.gd、.godot）；源图 .import 同路径入签名（T13-01 实证 asphalt.png+import 均在闭包）。
- 两 assemble 迁 manifest v2；停写 geometry/lighting/authored_input_hash 三旧字段。
- **实测关键发现**：三张生成场景的 mesh/material 全部内嵌 tscn sub_resource（外部 meshes/*.res 为旁路产物不被场景引用）——依赖闭包机制自动覆盖真实依赖，旧手工数组两方向都会漏，闭包方案实证正确。

### WP2 assemble/bake 状态机（C13-01/02/21）

- assemble 不再无条件清烘焙：`can_reuse_bake` 全过 → 绑定 fresh-load 验证过的旧数据（无破坏性写入）；不可复用 → **先**可恢复写 pending/stale 清单（失败即退出、未触数据），**后**清数据。v1 一律 stale（§2.6 一次性迁移）。
- bake 插件顺序：manifest 输入签名/expected 校验 → manifest=running 落盘 → 空数据 → fresh-load 重绑确认 user_count=0 → 触发烘焙 → missing=0 → `save_scene()` 检查 Error → 磁盘 fresh-load 终检 → succeeded → 报告。报告目录 `NEON_ARTIFACT_DIR`（只允许 res://artifacts 下，缺省 artifacts/build；chapter1_2 常量已移除）。
- C13-21：build_m01/build_authored/build_interior 所有必需输出 Error 检查链（材质/网格 commit last_save_error/场景/spec/region manifest/fixture），`_pack` 失败返回 null；gen_lib.MeshBuilder 增只读 `last_save_error`；build_stats（§26.1）入 generated/authored spec。
- `build_chapter11.ps1`：BuildId/ArtifactDir 参数、validate 全项（含 BuildContract 可加载、注册表逐条校验）、MapId=both 顺序改共享输入先稳定+street 先+interior 后、ownership 指纹断言、export 前必过完整 verify、ch13 测试入 verify 阶段。

### WP3 authored 去重（C13-05）

- 根因修复：`_station_forecourt_static_common` 只由顶层调用一次（此前 service_court 末尾重复调用导致站前几何+6 组 exclusion 双份）；`_authored_building(register_exclusion:=true)`，SC_W/SC_S 删手工重复保自动，SC_ANNEX `register_exclusion=false` 只保手工 8.55 特殊高度盒。
- 生成器内 exclusion 精确重复即 exit 1（fail 不静默 dedupe）。
- **实测结果与计划 §7.4 预测一致**：authored 29→20、0 精确重复；street = 18+20 = 38。
- C13-04：删除 `authored/authored_input_hash.baseline`；verify 不再写 res://；ownership 保护移入 build 脚本（前后指纹断言，本轮实测 PASS）。

### WP4 运行时（C13-06/08/09/15/22）

- SettingsManager：`_apply_profile` 完整顺序（视口→帧率→**活动地图**→信号）；`apply_to_map` 含地图默认 occlusion；`apply_no_map_defaults()`（工程默认，不硬编码 true）；启动 UI 同步用真实持久化档位（C13-22）。
- MapManager：registry 原子加载（全条目校验过才替换；map_id 与定义一致性、重复检测）、`_validate_request` 防御校验、orphan 超时不再被 `set_process(false)` 卡死（`_update_process_enabled` 唯一布尔权威；`load_timeout_sec` 测试可注入）、回 EMPTY 两条路径恢复工程默认 occlusion。
- Main：`_on_map_failed` 按 tx==0/tx>0 分叉（preflight 拒绝保留 READY 壳层，只有 transient message）。
- CaptureService：请求上下文收敛到字段 + 统一幂等 `_finish`（abort 立即收尾不依赖下一帧；UI/输入恢复、guard 释放、信号只发一次）。
- MapRoot：`get_occlusion_enabled()` 只读访问器。

### WP5 相机/UI/自动化（C13-10/11/12/13/14/16）

- ObserverCamera：`get_anchor_order()`/`go_to_anchor_index()` 公开接口；Main/UI/自动化不再读 `_anchor_order`；数字键统一 1–9（超界安全 no-op；street 7/interior 4 全可达，T13-18）。
- MapDefinition.validate：anchor 唯一、capture 子集/无重复；`get_capture_anchor_names()` 返回副本；`get_camera_contract` 增 `capture_anchor_ids`（截图自动化使用）。
- ToolUI：`set_bookmarks(entries, current_revision)`——当前版无标签/旧版 `[旧 rX]`/空 revision `[旧 未知]`（T13-19）；锚点提示最多 9 个数字键。
- 自动化：`_await_map_ready(35s)` 超时/失败出口（T13-20）；`--quality` 逐项验证（未知档非零退出）；截图任何目标失败整轮 exit 1（不再静默跳图）；删除自动 "_diag" 图（§29：诊断层属 capture_ui 本就会被隐藏，render_stats JSON 是权威）；perf 不再删除用户 settings.cfg（§9.2C）。

### WP6 Benchmark（C13-07 + §10）

- measured snapshot：测量环境应用后首帧冻结 `_measured_environment/_measured_map_state`，输出只读快照（修复"报告读恢复后状态"）。
- 恢复顺序：VSync → `restore_runtime_state`（FPS 唯一权威，删除 `_saved_max_fps`）→ saved occlusion（不再硬编码 true）→ 相机/环境 → guard → 写文件 → emit。
- PerfRoutes 收敛为 ROUTE_SPECS 单一结构（map_id+segment_seconds+segments）；新增 `interior_v13`（60s 四段各 15s：entry/workbench/gallery/dining，同层不穿墙）；start_run 校验路线存在、map 匹配（mismatch → ERR_INVALID_PARAMETER 带可读原因）、capped duration=60 且 route_duration 覆盖。
- 输出安全：目录规范化后只允许 user://benchmarks(/…)（benchmarks_evil/../ 穿越拒绝，T13-23）；run_id 限 `[A-Za-z0-9_-]`；run.json/summary/environment 记 build_id（NEON_BUILD_ID，缺省 unknown）；summary.csv 表头变更时轮转旧表。

### WP7 死资产删除（C13-17）

门槛全过后删除：根级 `map_lightmap.res/.exr/.exr.import`、`meshes/authored_props_mesh.res`、`tools/bake_m01.gd(+uid)`、`tools/run_bake.tscn`、`tools/finalize_bake_manifest.gd(+uid)`、`authored_input_hash.baseline`。保留 `build_bake_probe.gd`（诊断工具）与 debug_*/sample_* 系列（review 仍引用）。删除后 import 0 错、verify 23+28、lifecycle、ch13 全绿。

## 2. 生产重建与验证证据

| 步骤 | 结果 |
| --- | --- |
| generate（textures→signs→ownership PASS→m01→authored→interior） | 全 exit 0；authored 20/0 重复；street 38 |
| assemble 两图 | v1→stale 正确迁移；7/4 锚点 |
| bake street | manifest=running 先落盘 → users=10 expected=9 **missing=0** → succeeded（job bake-20260921T152121） |
| bake interior | 同链 → users=4 expected=3 missing=0 → succeeded |
| **二次 no-op assemble** | **复用真实烘焙数据**（users 10/4）、bake_input_hash 稳定、succeeded 保留、无破坏性写入（§3.4 验收 1 实证） |
| verify_build v2 | street 23 项 + interior 28 项全 PASS（hash/expected/actual 从磁盘重算一致、portal 跨图完整） |
| 测试 | lifecycle 全过；ch11 全过；ch12 全过；**ch13 83 项全过**（tests/test_chapter13_contract.gd） |
| 截图 | 两图 22 PNG+22 JSON（7/4 锚点 × eco/balanced），(map,anchor,profile) 组合完整、build_id=3a08948-local（`artifacts/chapter1_3/screenshots/final/`） |
| Flash 独立验收 | GLM-5.3-Flash$max 双遍（中性描述→rubric）22 图回归验收：**22/22 PASS、0 硬失败、平均 13.2/18**（`artifacts/chapter1_3/visual_regression_flash.json`；<15 分属 WP8/9 美术深化空间，非回归） |

H3（verify 只读）实证：verify 运行后 git 工作区无任何由 verify 产生的改动。

## 3. 偏差与说明

1. **T13-07b（预失效顺序）**：headless 单测锁定的是数据合同（预失效清单=非 succeeded+actual 清空）；"先写清单再清数据"的代码顺序由 bake/assemble 生产链日志实证（manifest=running 先于空数据写入）。
2. **§20.3 StreetEnrich 拆区、§22 backdrop 重构、§21 各区美术深化**：属 WP8/WP9（主场景美术），本轮未开始——见 §5。
3. `content_revision` 维持 1.2.0 开发基线（§7.5：升 1.3.0 须等 WP9 冻结后一次性执行）。
4. bake 报告本轮落 `artifacts/build/`（ArtifactDir 缺省值）；最终验收轮将按 §28.2 用 `res://artifacts/chapter1_3`。

## 4. 下一步（按 chapter1-3 顺序）

1. **WP8 主场景结构与城市系统深化**：art_baseline_v13 记录 → PropsStreetEnrich 拆 South/Mid/North（净增 2 个 expected bake user，重烘后 7 锚点对照）→ backdrop 四类 archetype → 主街立面机电/通信/检修层 → repair/station/service court/roof 分区内容。前置：新增 `tools/m01_detail_lib.gd`。
2. **WP9 材质/灯光/招牌/构图终验**：wet asphalt 非金属修正、roughness/detail、utility atlas、secondary signs、静态灯重平衡、≤2 Balanced 粒子、14 图逐图 ≥15/18（Hero 6 图 ≥16/18）→ 冻结后升 street 1.3.0。
3. **WP10 最终验收**：clean import → 全管线 → 22 PNG/JSON → 性能（expanded_v11 + interior_v13 两档×3 + occlusion 对照 + sample_process 四组）→ Windows Release + 中文/空格独立目录 + 人工门户巡走 → 文档 → Git clean。

## 5. 遗留人工项（沿 chapter1-2）

- 实机 F 键门户往返步行体感、摄影模式巡走清单（数据/合同层已自动验证）。
- 无人值守 perf 需 `tools/focus_keep.ps1` 保持前台焦点。
