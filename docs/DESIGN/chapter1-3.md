# Chapter 1.3 — 工程收口、构建可信性与运行时合同修复

> 项目：霓湾 / Neon Haven  
> 审阅基线：`main@5b95b25903f638a7c35c32015d54921dae53a168`  
> 审阅日期：2026-09-22  
> 文档性质：基于当前仓库完整树、核心运行时代码、双地图构建链、测试、已提交验收工件与交接文档的**修复实施计划**。  
> 本章不扩展新地图/NPC/玩法；先把 chapter1-2 后的工程闭环做实，再进入新的内容扩展。

---

## 0. 审阅结论

### 0.1 总体判断

当前仓库的**主架构方向完整且恰当，不需要推倒重写**。

已形成的核心边界是正确的：

- 应用外壳与地图内容分离：`scenes/app/main.tscn` + `scripts/app/` 持有相机、UI、截图、设置、诊断；
- 地图生命周期分离：`MapManager` 负责严格单活动地图的异步卸载/加载/激活；
- 地图数据合同轻量化：`MapDefinition` 只保存路径、边界、锚点、门户、行走面等值数据；
- 地图运行时统一：两张生产地图都使用 `MapRoot`；
- 室外/室内拆成独立地图，稳态只加载一张，符合当前“低负担本地城市展示程序”的优先级；
- `generated / authored / assemble / bake / verify` 分层制作链已经建立；
- Eco / Balanced、截图、书签、性能采样、ActivityGuard 已经是独立职责；
- 生命周期测试已经覆盖双图往返与弱引用回收；
- chapter1-2 已形成真实截图、LightmapGI 报告和多轮视觉验收历史。

因此 chapter1-3 的策略是：**保留现有主架构，修复已经确认的闭环缺口，并给这些缺口补上自动化验收。**

### 0.2 本章确认存在、需要修复的问题

按优先级排序：

| ID | 级别 | 问题 | 结论 |
| --- | --- | --- | --- |
| C13-01 | P0 | Lightmap 覆盖缺失仍可能被标记为成功 | 必修；会让漏烘焙进入“succeeded” |
| C13-02 | P0 | `build_authored.gd` 重复生成站前静态几何，并产生重复禁入 AABB | 必修；真实重复几何/重复运行时检查 |
| C13-03 | P0 | 已加载地图切换 Eco/Balanced 时，MapRoot 侧质量项不会重新应用 | 必修；当前“Balanced”可能只切了 Viewport 参数 |
| C13-04 | P0 | 地图级 `occlusion_enabled` 没有成为运行时权威，Benchmark 结束还硬恢复 true | 必修；室内定义明确为 false，却可能实际为 true |
| C13-05 | P1 | 无效地图请求在 MapManager 保留当前图，但 `main.gd` 会把 UI/相机清成“未加载” | 必修；违反既有状态机合同 |
| C13-06 | P1 | 街区已有 7 个机位，但主输入只处理数字键 1–6 | 必修；README/UI 与真实输入不一致 |
| C13-07 | P1 | 书签“旧版本”判断硬编码 `1.1.0` | 必修；当前 1.2.0 新书签也会被误标 |
| C13-08 | P1 | 门户 verify 只确认目标 definition 文件存在，不确认目标 anchor 存在 | 应修；错误只能到实际按 F 时才暴露 |
| C13-09 | P1 | 最终验收证据存在断链：文档引用被 `.gitignore` 排除的 log；v9 最终图缺对应 JSON 元数据 | 必修；结论无法从干净检出完整复核 |
| C13-10 | P1 | chapter1-2 Windows Release/G6、expanded_v11 ×3、室内稳态、人工门户巡走仍未闭环 | 本章收口 |
| C13-11 | P2 | `docs/environment.md`、`tools/README.md` 等仍包含 1.1 时期状态 | 必修文档同步，但不应先于代码/实测改结论 |

### 0.3 本章明确不改的部分

以下内容经本轮审阅没有发现需要重构的证据，**保持现状**：

1. 不重写 `MapManager` 状态机；其“先卸载旧图、等待释放、再加载新图”的方向正确。
2. 不把室内并回街区；两图独立加载是当前低负担目标下更合适的结构。
3. 不引入 CharacterBody、物理碰撞、导航、NPC、任务、联网、运行时生成。
4. 不把 `MapDefinition` 改成持有 PackedScene/材质/lightmap 的重资源对象。
5. 不新增复杂地图内流式系统；当前地图粒度仍足够。
6. 不为了“代码更漂亮”拆掉现有 CaptureService、BenchmarkRunner、ActivityGuard。
7. 不因为 `build_chapter11.ps1` 名称带历史版本就强行重命名；它当前已经支持双图，重命名收益不足以抵消文档与自动化迁移成本。
8. 不删除 v7–v9 排障期留下、仍具有复核价值的图像/材质/取色诊断工具；只有确认完全重复、无文档引用的临时工具才可在本章末单独清理。
9. `MapDefinition.schema_version` 继续保持 2；本章修复没有新增破坏性持久化字段语义，不需要为了章节号升 schema。

---

## 1. 本次仓库审阅范围与结构判断

### 1.1 审阅范围

本次以 GitHub `main` 为唯一权威基线，递归树共 **517** 个条目，重点核对：

- 根工程：`project.godot`、`export_presets.cfg`、`README.md`、`AGENTS.md`；
- 应用层：`scripts/app/*.gd`；
- 地图层：`scripts/maps/*.gd`；
- 性能层：`scripts/diagnostics/*.gd`；
- 双图：`maps/m01_afterglow/`、`maps/m01_repair_interior/`；
- 构建：`tools/build_*.gd`、`assemble_*.gd`、`verify_build.gd`、`build_chapter11.ps1`；
- 烘焙：`addons/neon_bake/bake_plugin.gd`；
- 配置：`data/map_registry.json`、`data/quality/*.json`；
- 测试：`tests/test_map_lifecycle.gd`、`test_chapter11_contract.gd`、`test_chapter12_contract.gd`；
- 文档与证据：`docs/DESIGN/`、`docs/handoff.md`、`docs/backlog.md`、`docs/environment.md`、`docs/chapter1_2/review.md`、`artifacts/`；
- 最近 chapter1-2 终验提交及其变更说明。

本次是**仓库静态审阅 + 已提交证据复核**。本章中的“当前代码确认”来自 GitHub 当前文件；既有 review 中记录的 Godot 实跑结果不冒充本次重新执行。chapter1-3 实施阶段仍必须重新跑完整验证门槛。

### 1.2 当前代码架构

#### 应用壳

`main.gd` 是组合根，动态创建：

- `MapSlot`
- `CameraRig / ObserverCamera`
- `SettingsManager`
- `MapManager`
- `ToolUI`
- Loading overlay
- Diagnostics
- CaptureService
- BenchmarkRunner

这种动态组合目前规模仍可控，且各服务脚本职责已经独立。chapter1-3 不因为主脚本较长就进行无收益拆分。

#### 地图生命周期

`MapManager` 的主流程：

`EMPTY → LOADING → ACTIVATING → READY`

切图：

`READY → UNLOADING → LOADING → ACTIVATING → READY`

已具备：

- 事务 ID；
- ActivityGuard；
- threaded resource loading；
- 超时与 orphan load 收尾；
- 旧图真正释放后才加载下一张；
- 激活失败移除部分实例；
- 相机合同绑定；
- portal entry anchor；
- 单活动 MapRoot。

这是目前仓库最重要的正确架构之一，chapter1-3 只修外围状态同步，不改主状态机。

#### 地图合同

`MapDefinition` v2 已包含：

- 基础路径/显示信息；
- camera bounds / exclusions；
- anchors；
- content revision；
- region manifest；
- occlusion 开关；
- capture anchor 回落；
- baked-lighting 要求；
- fly / walk 模式；
- walk surfaces；
- portals。

接口粒度适合继续逐张增加地图，不需要另造第二套地图描述系统。

#### 地图根

`MapRoot` 已统一承担：

- 运行时合同验证；
- 锚点读取；
- 摄影边界数据；
- portal door 动画；
- quality profile 对地图内节点的应用；
- 区域细节距离；
- 环境动画暂停/固定时间/快照；
- deactivation 清理。

这层应继续作为“地图运行时行为的单一入口”。

#### 制作与构建

当前生产链是：

1. 纹理/招牌生成；
2. 街区 generated；
3. 街区 authored；
4. 室内 generated；
5. assemble；
6. import；
7. LightmapGI bake；
8. verify；
9. lifecycle/contract tests；
10. screenshot/perf/export。

方向正确；本章主要修复“成功判定是否可信”和“生成层是否重复”。

---

## 2. C13-01 — Lightmap 覆盖完整性必须成为硬失败条件

### 2.1 当前事实

`addons/neon_bake/bake_plugin.gd` 当前已经能计算：

- `expected`：LightmapGI 子树内应参与烘焙、静态且带 UV2 的 MeshInstance3D 路径；
- `actual`：LightmapGIData 实际 user paths；
- `missing = expected - actual`。

但当前逻辑在 `missing.size() > 0` 时只打印警告，随后仍：

- 把 manifest 写成 `bake_status = "succeeded"`；
- 报告成功条件使用 `missing.is_empty() or actual.size() > 0`；
- 只要实际烘到了至少一个 user，即使还有 expected 缺失，也可能最终 `NEON_BAKE_EXIT=0`。

同时，两份 assemble 脚本虽然已有 `expected_baked_user_paths` 字段，但每次写 manifest 都初始化为空；`verify_build.gd` 目前只要求：

- `bake_status == succeeded`
- `actual_baked_user_paths.size() > 0`

因此 verify 无法独立证明“所有应烘焙网格均被覆盖”。

这是构建门槛语义错误，不是单纯文档问题。

### 2.2 修复原则

烘焙成功必须满足：

- expected 非空；
- actual 非空；
- `expected ⊆ actual`；
- missing 为空。

允许 actual 是 expected 的超集。当前实际报告中 Backdrop 可能作为额外 user 出现在 actual，因此不能要求两个集合严格相等。

### 2.3 接口修改

#### bake_plugin

将 manifest 回写职责明确为完整覆盖结果，而不是只写 actual：

`_update_manifest(job_id, expected, actual, missing, status, manifest_path)`

至少持久化：

- `bake_job_id`
- `bake_status`
- `expected_baked_user_paths`
- `actual_baked_user_paths`
- `missing_baked_user_paths`
- `bake_finished_utc`

成功路径：

- missing 为空；
- 写 `succeeded`；
- report `success=true`；
- `NEON_BAKE_EXIT=0`。

失败路径：

- expected 为空、actual 为空或 missing 非空，均为失败；
- manifest 写 `failed`，同时保留 expected/actual/missing 供排障；
- report `success=false`；
- `NEON_BAKE_EXIT=1`；
- PowerShell wrapper 必须中止，不能继续 verify/export 并宣称完成。

#### assemble_m01 / assemble_interior

输入指纹未变化且上一轮确为 succeeded 时：

- 同时保留 expected / actual / missing（missing 必须为空）；
- 不再把 expected 无条件重置为空。

输入变化时：

- 状态变 `stale`；
- 清空上一轮 expected/actual/missing，避免把旧覆盖信息带到新几何。

#### verify_build

新增独立验证：

1. manifest expected 非空；
2. manifest actual 非空；
3. manifest missing 为空；
4. 从当前 scene 重新计算“本次静态场景应烘焙节点路径集合”；
5. 当前 expected 与 manifest expected 对齐；
6. 当前 expected 全部包含于 actual；
7. 只有全部通过才允许“烘焙门槛 PASS”。

### 2.4 验收

必须增加负例验证：

- 人为构造 expected 中多一个不存在于 actual 的 path；
- verify 必须失败；
- bake coverage helper 必须返回失败；
- 不允许 manifest 保持 succeeded。

正常双图：

- street：expected 全覆盖；
- interior：expected 全覆盖；
- actual 允许多出非 expected user；
- 两图 `missing_baked_user_paths=[]`。

---

## 3. C13-02 — 清理 authored 重复站前几何与重复禁入体积

### 3.1 当前事实

`tools/build_authored.gd` 顶层创建 authored static 时依次调用：

1. `_service_court_static(mb_static)`
2. `_station_forecourt_static_common(mb_static)`
3. `_roof_terrace_static(mb_static)`

但 `_service_court_static()` 函数末尾又再次调用：

`_station_forecourt_static_common(mb)`

结果是站前区域的同一套静态几何被写入同一个 authored static mesh **两次**。

同一函数还存在禁入体积双来源：

- `_authored_building()` 自动注册建筑 AABB；
- `_service_court_static()` 又手工追加 west / annex / south AABB。

其中 west、south 为精确重复；annex 则是一份自动高度 + 一份手工特殊高度，导致特殊规则没有真正成为唯一权威。

当前 `authored_spec.json` 中站前一组 AABB 也出现成组精确重复，最终 `map_definition.tres` 只是把 generated 与 authored exclusions 直接拼接，不做重复检查。

### 3.2 影响

- identical triangles 重复写入网格；
- UV2/lightmap packing 和烘焙输入承担无意义重复数据；
- 可能增加 overdraw / lightmap 成本；
- 相机每次移动对相同 AABB 重复判断；
- authored spec 不再能作为可靠的“单一来源”；
- 后续增加地图时容易把这种重复模式复制出去。

### 3.3 修复方案

#### 站前几何

- 保留顶层 `_station_forecourt_static_common(mb_static)`；
- 删除 `_service_court_static()` 尾部的嵌套调用；
- 一个区域只由一个显式顶层调用负责。

#### 建筑 exclusion 权威

保留 `_authored_building()` 默认自动注册 exclusion，但给需要特殊规则的建筑一个显式参数，例如：

- `register_exclusion: bool = true`

对当前 service court：

- SC_W：使用自动 exclusion，删除手工重复项；
- SC_S：使用自动 exclusion，删除手工重复项；
- SC_ANNEX：`register_exclusion=false`，只保留手工的特殊高度 exclusion；
- 拱门、设备箱、栏杆、街道道具等非建筑特殊体积继续手工追加。

不要在 assemble 阶段用“静默 dedupe”掩盖生成器错误。assemble/verify 可以做**精确重复检测并失败/报警**，但源头必须先修。

### 3.4 重建要求

这个修复会改变 authored scene / mesh 输入，必须按真实光照修改处理：

1. generate street authored；
2. assemble street；
3. import；
4. street 重新 bake；
5. verify；
6. 双图 lifecycle；
7. street 全机位 Eco/Balanced 截图回归；
8. expanded_v11 性能重新采样后才能作为最终数据。

### 3.5 验收

- authored static 中 station forecourt 只构建一次；
- `authored_spec.exclusions` 精确重复项 = 0；
- 最终 `MapDefinition.camera_exclusion_bounds` 精确重复项 = 0；
- 不禁止“有意部分重叠”的 AABB，只禁止数值完全相同的重复项；
- authored static triangle 数应较当前基线下降；记录实际 before/after，不预设伪造目标值；
- 七个街区锚点截图不得因清理重复几何出现缺面、漏光、构图退化；
- 重烘焙 missing=0。

### 3.6 content revision

该修改改变了街区实际生成/烘焙输入。实施时将 **`m01_afterglow.content_revision` 从 1.2.0 升到 1.3.0**。

`m01_repair_interior` 若几何、锚点、行走面均未改变，则仍可保持 1.2.0；不要为了“版本看起来一致”让所有旧室内书签无意义变成 stale。

---

## 4. C13-03 / C13-04 — 让质量档与地图级遮挡配置真正闭环

### 4.1 当前质量切换缺口

`SettingsManager._apply_profile()` 目前直接应用的主要是 Viewport / Engine 全局状态：

- render scale；
- MSAA / FXAA；
- max_fps。

地图内质量状态由 `MapRoot.apply_quality(profile)` 负责：

- optional particles；
- runtime fill lights；
- optional probes；
- bake-only light 隐藏；
- Environment glow；
- detail prop range；
- ambient particle emission。

但 `MapManager` 当前只在**地图激活时**调用一次：

`_quality.apply_to_map(map_root)`

地图已经 READY 后，UI 再切 Eco/Balanced，只触发 `SettingsManager.quality_changed`，`main.gd` 当前只更新质量按钮并把 occlusion 强制设 true，没有重新调用 MapRoot。

因此：

- Eco → Balanced 后，Viewport 可能是 Balanced；
- 但 MapRoot 仍可能保留 Eco 的 particles/probes/extra_lights/glow/detail range；
- BenchmarkRunner 通过 `set_profile()` 切档时同样可能只得到部分档位状态；
- 现有测试只验证 frame_cap/effective_state 字段存在，没有验证活动地图节点真的跟档位变化。

### 4.2 当前 occlusion 缺口

室内 assemble 明确：

`def.occlusion_enabled = false  # 单个小室内，遮挡剔除无收益`

街区为 true。

但当前运行代码：

- `SettingsManager.apply_to_map()` 不读取 `MapDefinition.occlusion_enabled`；
- `main._on_quality_changed()` 无条件 `viewport.use_occlusion_culling = true`；
- `BenchmarkRunner._finish()` 也无条件恢复为 true。

所以 `MapDefinition.occlusion_enabled` 当前没有成为真实运行时权威。

### 4.3 目标架构

权威关系必须明确：

- **质量档 JSON**：决定 render scale / AA / FPS / particles / probes / extra lights / glow / detail range；
- **MapDefinition.occlusion_enabled**：决定“该地图默认是否启用遮挡剔除”；
- **Benchmark occlusion_override**：只在单次基准中临时覆盖地图默认；
- Benchmark 结束后恢复进入 benchmark 前的真实状态，而不是硬编码 true。

### 4.4 接口方案

#### MapManager

增加一个薄入口：

`apply_current_quality() -> Error`

语义：

- READY 且有活动 MapRoot：调用 `SettingsManager.apply_to_map(root)`；
- EMPTY：返回 `ERR_UNCONFIGURED` 或 OK-noop，二者选定一种后固定测试；
- 不保存额外 MapRoot 强引用。

更推荐在 `MapManager.setup()` 后由 MapManager 自己订阅 `quality_changed`，这样：

- 普通 UI 切档；
- benchmark 临时切档；
- runtime restore；

都经过同一条路径，不依赖 main 再手工编排。

`main._on_quality_changed()` 只保留 UI 同步，不再负责地图质量逻辑。

#### SettingsManager.apply_to_map

顺序：

1. `MapRoot.apply_quality(current_profile)`；
2. 从 `map_root.definition.occlusion_enabled` 应用 `Viewport.use_occlusion_culling`；
3. 返回 Error。

地图为空时不伪造 map 级状态。

#### BenchmarkRunner

运行开始：

- 保存实际 `Viewport.use_occlusion_culling`；
- 设置 profile 后先让正常质量链完成；
- `occlusion_override=default`：不改地图默认值；
- `on/off`：只对本轮临时覆盖。

运行结束/中止：

- restore quality/profile；
- 恢复保存的实际 occlusion；
- 删除当前 `vp.use_occlusion_culling = true` 的硬编码恢复。

### 4.5 验收矩阵

#### 地图默认

- 加载 street：occlusion=true；
- 切 interior：occlusion=false；
- 返回 street：occlusion=true。

#### 运行时质量切换

street READY 后：

- Eco：particles/probes/extra_lights/glow 按 Eco 实际状态，detail range=Eco；
- 切 Balanced：对应地图节点立即变为 Balanced；
- 切回 Eco：立即恢复。

interior READY 后：

- Eco ↔ Balanced 期间，occlusion 始终维持 false；
- 不因切质量档被 main 强制改 true。

#### Benchmark

- interior + `occlusion_override=default`：记录 false；
- interior + override=on：采样期 true，结束后 false；
- street + override=off：采样期 false，结束后 true；
- 中止路径与正常完成路径都必须恢复。

`get_effective_state().occlusion_enabled` 必须来自实际 Viewport，和上述状态一致。

---

## 5. C13-05 — 无效请求不能把仍然存在的当前地图“清空 UI”

### 5.1 当前事实

`MapManager` 已正确实现：

- 未知 map；
- definition 非法；
- scene path 缺失；
- entry anchor 非法；

在**卸载旧图前**拒绝，并保持当前 READY 地图不变。

`tests/test_map_lifecycle.gd` 也已经验证：当前 m01 READY 时请求 broken scene，MapManager 仍保持 m01 READY。

但 `main._on_map_failed()` 当前对所有 `map_failed` 一视同仁：

- UI 设为“未加载地图”；
- camera `unbind_map()`；
- portals 清空。

于是 manager 与 shell 会出现分裂：

- MapManager：当前地图仍 READY；
- 场景树：active_map_root 仍为 1；
- Main/UI：认为没有地图；
- Camera：合同被解绑。

### 5.2 修复语义

利用现有 signal 已有的 `transaction_id` 语义，不新增第二套错误信号：

- **tx == 0**：请求在事务开始前被拒绝，当前 READY 图必须完整保留；
- **tx > 0**：已进入加载/激活事务后失败，按当前空场景失败流程处理。

Main 收到 tx=0 且 manager 仍 READY 时：

- 不清 map info；
- 不 unbind camera；
- 不清 portals；
- 只显示 transient error。

### 5.3 验收

在 street READY：

1. request unknown map；
2. request broken scene；
3. request nonexistent target anchor。

每次都要求：

- active_map_root=1；
- current_map_id 仍 street；
- camera 仍 bound；
- map label 仍 street；
- portal 列表仍有效；
- 仅出现错误提示。

真正 activation failure 则仍必须清理为 EMPTY，不得为了修这个问题把失败实例留住。

---

## 6. C13-06 — 固定机位快捷键必须覆盖当前实际锚点数

### 6.1 当前事实

当前街区 `MapDefinition.anchor_names` 有 7 个：

- repair_shop_view
- station_view
- street_view
- repair_shop_door
- roof_terrace_view
- service_court_view
- station_forecourt_view

README 也写“街区 7 个 / 店内 4 个”。

`ToolUI.set_anchor_hint()` 会按数组真实长度显示 `1=... 7=...`。

但 `main._handle_key()` 只匹配：

`KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6`

所以第 7 个提示是假的。

### 6.2 修复方案

不要继续逐个堆 `match KEY_1...KEY_N`。

建立一个单一快捷键表，支持至少 1–9：

- `ANCHOR_KEYS = [KEY_1 ... KEY_9]`
- key → index；
- index < `camera_ctl._anchor_order.size()` 才调用。

ToolUI 只展示可通过这张表实际访问的机位；若将来超过 9 个锚点，数字键只显示前 9 个，其余通过菜单/未来摄影工作台访问，避免 UI 再次承诺不存在的按键。

### 6.3 验收

- street 1–7 全部可切；
- interior 1–4 全部可切；
- 8/9 在当前地图无对应锚点时不报错、不越界；
- UI 提示与真实键位一致。

---

## 7. C13-07 — 书签修订提示改为相对当前地图版本判断

### 7.1 当前事实

`BookmarkStore` 正确保存：

- map_id；
- content_revision；
- created_utc；
- pose。

问题在 `ToolUI.set_bookmarks()`：

当前把 `rev != "1.1.0"` 当作“旧版本”。

因此在当前 1.2.0 地图中新建书签，也会显示 `[r1.2.0]`，与注释“旧版本书签提示”相反。

### 7.2 修复边界

不要让 UI 自己猜当前 revision。

推荐由 main/MapManager 提供当前地图 revision，二选一：

**方案 A（优先）**

`ToolUI.set_bookmarks(entries, current_revision)`

UI 只做：

- rev 为空：不加版本提示；
- rev == current_revision：不加提示；
- rev != current_revision：追加 `[rX]` 或“旧版本 rX”。

**方案 B**

Main 在传入 UI 前给每项增加 `is_stale_revision` 布尔值，UI 不比较版本字符串。

两种都可以；只实现一种，不保留硬编码兼容分支。

### 7.3 加载行为

旧版本书签**不禁止加载**：

- 仍由 ObserverCamera 校验 map_id / bounds / exclusions；
- 可用则加载；
- 已失效则显示现有“位置不可用”提示。

revision 是提示与诊断信息，不变成强制迁移系统。

### 7.4 验收

在 street 1.3.0：

- 新建 1.3.0 书签：不显示旧版标签；
- 构造 1.2.0 书签：显示旧版本；
- 构造空 revision 旧数据：可显示但不误判；
- 加载合法旧书签仍可成功。

interior 如果仍为 1.2.0，同理按 1.2.0 比较，证明实现没有把章节号当全局常量。

---

## 8. C13-08 — 门户图关系在 verify 阶段一次性验证完整

### 8.1 当前事实

`MapDefinition.validate()` 能验证 portal 字段结构：

- pos；
- radius；
- target_map_id 非空；
- target_anchor 非空；
- label 非空。

`verify_build.gd` 对 walk 图当前额外检查目标 `map_definition.tres` 文件存在。

但还没有验证：

- target map 是否真的在生产 registry；
- target definition 是否可加载/validate；
- `target_anchor` 是否存在于目标的 `anchor_names`。

当前两条生产门户数据本身是正确的，但验证层不完整。

### 8.2 修复

在 verify 中建立 registry → MapDefinition 轻量表，只读取 definition，不加载目标大场景。

对所有生产地图（不只 walk 图）遍历 portals：

- target_map_id 必须在 registry；
- target definition validate 通过；
- target_anchor 必须存在；
- portal radius/label 已由 MapDefinition.validate 保证。

这样以后新增 fly→fly、fly→walk 门户也会得到同一检查，不把 portal verify 特判锁死在室内图。

### 8.3 验收

- 当前 street → interior 通过；
- interior → street 通过；
- 测试 fixture 中 target anchor 拼错必须让 verify/合同测试失败；
- 不需要为了验证 portal 加载目标 3D scene。

---

## 9. C13-09 — 验收证据必须能从干净仓库复核

### 9.1 当前断链

本轮审阅确认：

- `.gitignore` 全局忽略 `*.log`；
- `docs/chapter1_2/review.md` / handoff 多处引用 `regression_*.log`；
- 当前 `main` 并不存在这些 log；
- README 指向 `artifacts/chapter1_2/perf_street.log`，该文件也不在仓库；
- v9 最终视觉 PNG 已提交，但没有与最终 v9 一一对应的 CaptureService JSON 元数据；
- 较早 v3/v5/v6 有 JSON，说明元数据链本身已经具备，只是最终证据整理时丢了配对。

这不推翻 chapter1-2 的实现结果，但会降低“从干净检出独立复核”的可信度。

### 9.2 证据策略

不要解除所有 `*.log` 忽略规则，也不要把大量临时终端日志塞进仓库。

chapter1-3 增加**结构化、可提交的最终摘要**：

`artifacts/chapter1_3/`

至少保留：

- `verification_summary.json`：各测试命令、exit code、关键计数、commit SHA；
- `verification_summary.md`：人工可读索引；
- `performance/summary.csv` 与各有效轮次 `summary.json`；
- `screenshots/`：最终 Eco/Balanced PNG + 同名 JSON；
- `export_check.md`：导出版本、SHA256、独立目录、中文+空格路径、门户往返结果；
- 必要 bake report JSON。

临时 verbose log 继续不入库。

### 9.3 Build ID

执行最终验收前设置统一 `NEON_BUILD_ID` 为当前 commit 短 SHA 或明确 release candidate ID，使：

- screenshot JSON；
- benchmark JSON；
- build manifest；
- verification summary

可以互相关联。

### 9.4 bake report 输出目录

`bake_plugin.gd` 目前硬编码 `artifacts/chapter1_2`。既然本章已经必须修改该插件的成功判定，应顺手消除这个章节硬编码。

建议：

- 支持 `NEON_ARTIFACT_DIR`；
- wrapper 在本章最终验证时指向 `res://artifacts/chapter1_3`；
- 未设置时使用稳定通用目录，例如 `res://artifacts/build`；
- 不再每进入一个 chapter 就修改插件常量。

### 9.5 验收

从干净 checkout 只看仓库即可回答：

- 哪个 commit 被验收；
- 两图 verify 是否通过；
- lifecycle/contract 各多少项；
- bake expected/actual/missing；
- 最终截图属于哪个 map/profile/revision；
- 性能样本来自什么环境；
- Windows export 是否实测；
- 仍有哪些人工项未做。

文档不得再链接一个被 gitignore 丢弃、仓库中不存在的文件作为唯一证据。

---

## 10. C13-10 — 收掉 chapter1-1 / 1-2 遗留的性能与发布门槛

本章不把“已有 backlog”重复写成新功能，而是作为工程完整性门槛执行。

### 10.1 性能

#### Street

完成 `expanded_v11`：

- Eco ×3；
- Balanced ×3；
- 默认 occlusion；
- 另做至少一轮 `--occlusion off` 对照；
- 每轮 60s steady；
- 15s warmup；
- 保持前台，失焦轮次无效；
- 使用 `sample_process.ps1` 对正式导出进程补 WorkingSet / PrivateBytes。

由于 C13-02 会改变 street authored/lightmap 输入，旧性能记录只能作为历史对照，不能直接作为 chapter1-3 最终值。

#### Interior

新增一条最小稳定路线或固定姿态稳态采样：

- 不需要为了室内强行套用 street `expanded_v11`；
- 60s；
- Eco / Balanced 至少各 1 个有效轮次；
- 默认 occlusion=false；
- 如做 on 对照，报告中明确是实验覆盖。

### 10.2 Windows Release / G6

按当前 `export_presets.cfg` 重新导出 chapter1-3 release candidate。

要求：

1. 从干净检出/干净构建链导出；
2. 复制 EXE + PCK 到一个**包含中文和空格**的独立目录；
3. 不依赖项目 `.godot/`；
4. 启动进入 street；
5. street 菜单/锚点可用；
6. F 门户进入 interior；
7. 步行、楼梯、返回 street；
8. 至少 3 次人工往返；
9. Eco / Balanced 都能切换；
10. F12 生成 PNG+JSON；
11. 退出无阻塞。

`build/` 继续被 Git 忽略，不提交二进制；只提交 export check、文件 SHA256、文件大小和实测结果。

### 10.3 人工体验

chapter1-2 尚未完成的人工项在本章一次收口：

- F 门接近开合是否自然；
- 门户提示是否遮挡构图；
- interior 楼梯上/下楼节奏；
- 边缘阻挡是否出现明显“吸墙/卡角”；
- street fly 7 个锚点；
- interior 4 个锚点；
- 手动自由摄影不看到明显世界空洞/背面；
- UI 隐藏/恢复、菜单、书签、截图。

这些属于人工门槛，不用伪装成 headless 自动测试。

---

## 11. C13-11 — 文档同步，但必须最后写结论

### 11.1 当前已确认的文档漂移

#### docs/environment.md

仍写：

- export template 未安装；
- 系统字体栅格化招牌；
- 更新日期 2026-09-19。

这与后续仓库状态/README/handoff 不一致。

#### tools/README.md

仍包含明显 1.1 时代描述：

- “六机位”；
- bake report 指向 chapter1_1；
- 单步 bake 命令仍以 street 默认场景为主；
- 测试列表未完整包含 chapter1-2；
- 对双图 `-MapId both` 的说明不足。

#### README / review / handoff

存在对仓库中不存在 `*.log` 的引用；需改为 chapter1-3 的结构化证据。

### 11.2 更新顺序

文档必须在最终测试之后按真实结果更新：

1. `docs/chapter1_3/review.md`（新增最终验收记录）；
2. `docs/handoff.md`；
3. `docs/backlog.md`；
4. `docs/environment.md`；
5. `tools/README.md`；
6. 根 `README.md`；
7. 必要时 `AGENTS.md` 只修事实漂移，不扩新范围。

如果 G5/G6 某项仍没跑，写 NOT_RUN/待验证，不能为了“文档整齐”写成 PASS。

---

## 12. 实施工作包

### WP0 — 冻结基线与可复核证据格式

**目标**

- 记录 main commit；
- 新建 chapter1-3 artifact 目录规则；
- 记录当前双图 manifests、exclusion 数、authored triangle 日志基线；
- 不改场景。

**完成条件**

- 有 machine-readable verification summary 模板；
- 当前已知缺陷能在摘要中标为 baseline-known-failure，而不是被遗漏。

---

### WP1 — 修烘焙成功判定与 manifest

涉及：

- `addons/neon_bake/bake_plugin.gd`
- `tools/assemble_m01.gd`
- `tools/assemble_interior.gd`
- `tools/verify_build.gd`
- 必要合同测试

**完成条件**

- missing>0 必然 NEON_BAKE_EXIT=1；
- failed manifest 不会继续伪装 succeeded；
- expected/actual/missing 可持久化；
- verify 独立检查 expected⊆actual。

WP1 必须先于任何“重新烘焙”，否则后续烘焙仍使用不可信门槛。

---

### WP2 — 修 authored 重复生成并重建 street

涉及：

- `tools/build_authored.gd`
- street generated outputs / authored spec / map definition / manifest / lightmap
- street content_revision

**完成条件**

- station forecourt 静态几何只生成一次；
- exclusion 精确重复=0；
- street revision=1.3.0；
- bake missing=0；
- verify 通过；
- 七机位两档视觉无回归。

---

### WP3 — 修实时质量档与 occlusion 权威链

涉及：

- `scripts/app/settings_manager.gd`
- `scripts/maps/map_manager.gd`
- `scripts/app/main.gd`
- `scripts/diagnostics/benchmark_runner.gd`
- tests

**完成条件**

- 已加载地图 Eco/Balanced 实时完整切换；
- street true / interior false；
- benchmark override 可覆盖且可恢复；
- effective_state 与真实状态一致。

---

### WP4 — 修小型用户可见/错误状态合同

涉及：

- `scripts/app/main.gd`
- `scripts/app/tool_ui.gd`
- `tools/verify_build.gd`
- tests

内容：

- invalid request 不清当前 READY 图；
- 1–9 通用 anchor hotkey；
- bookmark stale revision 相对当前地图；
- portal target anchor verify。

**完成条件**

四项都有自动测试或确定的集成测试步骤，不仅靠人工点击。

---

### WP5 — 新增 chapter1-3 回归测试

新增：

`tests/test_chapter13_contract.gd`

建议测试矩阵：

| ID | 验证 |
| --- | --- |
| T13-01 | street / interior MapDefinition 无精确重复 exclusion |
| T13-02 | quality change 会重新应用活动 MapRoot |
| T13-03 | street→interior→street 的 occlusion = true→false→true |
| T13-04 | benchmark/临时 occlusion 恢复 helper 语义 |
| T13-05 | anchor hotkey 1–9 映射，7 可达、越界安全 |
| T13-06 | bookmark current/stale revision 标签 |
| T13-07 | READY 下 invalid request 保留地图合同 |
| T13-08 | portal target map + target anchor 完整校验 |
| T13-09 | build manifest expected/actual/missing 正常集合通过 |
| T13-10 | 构造 missing path 时 coverage 验证失败 |

如果某测试因 EditorPlugin/headless 边界不能直接调用 bake plugin，应把“集合覆盖判定”提取为无编辑器依赖的纯 helper 或由 verify 路径测试，**不要为了测试方便复制第二份判定逻辑**。

原有：

- `test_map_lifecycle.gd`
- `test_chapter11_contract.gd`
- `test_chapter12_contract.gd`

全部继续跑，不删除、不缩小。

---

### WP6 — 性能、Windows 导出、人工巡走与文档收口

顺序：

1. 双图完整 verify；
2. 四套合同/生命周期测试；
3. street 七机位 Eco/Balanced 最终截图；
4. interior 四机位 Eco/Balanced 最终截图；
5. expanded_v11 ×3；
6. interior 60s；
7. process memory sampling；
8. Windows Release；
9. 中文+空格目录独立运行；
10. 门户/楼梯/摄影人工检查；
11. 写 review/handoff/backlog/environment/tools README/root README。

只有完成到第 10 步，才能把 chapter1-3 标为“工程收口完成”。

---

## 13. 最终自动化验收命令

实际 Godot 路径使用 `-GodotExe` 或 `NEON_GODOT`，不在仓库硬编码个人路径。

核心门槛：

- `build_chapter11.ps1 -Stage generate -MapId both`
- `build_chapter11.ps1 -Stage assemble -MapId both`
- `build_chapter11.ps1 -Stage bake -MapId both`
- `build_chapter11.ps1 -Stage verify -MapId both`
- `test_map_lifecycle.gd`
- `test_chapter11_contract.gd`
- `test_chapter12_contract.gd`
- `test_chapter13_contract.gd`

最终 Release 前再执行一次从 generate 到 export 的完整链，不能只用中途产物拼接“最终验收”。

---

## 14. 最终验收标准

### H0 — 构建可信性

PASS 条件：

- 两图 manifest 输入指纹未过期；
- bake_status=succeeded；
- expected 非空；
- actual 非空；
- missing=0；
- 当前 scene 重新计算 expected 与 manifest 对齐；
- 任意 missing 负例可稳定让流程失败。

### H1 — authored 数据唯一性

PASS 条件：

- station forecourt 不再重复构建；
- street authored/final exclusion 精确重复=0；
- triangle/manifest before-after 有记录；
- 无新 z-fighting/缺面/烘焙遗漏。

### H2 — 运行时质量合同

PASS 条件：

- Eco/Balanced 在 READY 地图立即完整生效；
- MapRoot 可选节点与 glow/detail range 实际变化；
- street occlusion=true；
- interior occlusion=false；
- benchmark default/override/restore 全部正确。

### H3 — 生命周期与错误路径

PASS 条件：

- 双图 ×10 往返 active_map_root ≤1；
- 资源弱引用按现有阈值回收；
- invalid preflight request 不破坏当前 READY 图；
- activation failure 仍能回 EMPTY。

### H4 — 摄影/UI

PASS 条件：

- street 1–7 数字键可达；
- interior 1–4 可达；
- UI 不展示不可用数字键；
- 当前版本书签不误标旧版；
- 旧 revision 书签有提示但仍按 pose validation 决定是否加载；
- 门户 target anchor 全部在 verify 阶段可证明存在。

### H5 — 视觉

PASS 条件：

- street 七机位 × Eco/Balanced；
- interior 四机位 × Eco/Balanced；
- 每张最终 PNG 有同名 JSON；
- 无明显缺面、世界空洞、双几何闪烁、严重漏光、入口遮挡；
- chapter1-2 v9 已通过的 gallery_view 不退化。

### H6 — 性能

PASS 条件：

- street expanded_v11 两档各 3 个有效轮次；
- 有至少一组 occlusion 对照；
- interior 两档稳态样本；
- 正式报告明确 renderer、GPU、分辨率、frame cap、occlusion、revision、commit；
- 工作集/PrivateBytes 使用 Windows 进程采样，不用引擎静态内存冒充。

chapter1-1/1-2 的目标阈值继续作为调查/回归参考；如果真实数据未达标，如实记录并定位，不修改阈值迁就结果。

### H7 — Windows Release

PASS 条件：

- chapter1-3 当前内容重新导出；
- EXE/PCK 独立目录；
- 中文+空格路径；
- 双图门户实际往返；
- 质量档、书签、F12 正常；
- 有 export_check + hash；
- 不提交 build 二进制。

### H8 — 文档与证据

PASS 条件：

- review/handoff/backlog/environment/tools README/root README 与实际结果一致；
- 没有引用仓库不存在的文件作为唯一证据；
- 最终工件能追溯到 commit/build_id；
- 未执行项写 NOT_RUN，不写成 PASS。

---

## 15. 风险与回滚

### R1 authored 清理触发 lightmap 视觉变化

处理：

- 修改前保留当前最终截图；
- 只删除数学上重复的生成调用，不同时进行大规模美术重做；
- 重烘焙后逐机位对照；
- 若有视觉差异先定位 duplicate removal / UV2 repack / lightmap，再决定是否需要重新调光。

### R2 质量档重应用改变现有 Balanced 观感/性能

这是预期会暴露的真实状态差异。

处理：

- 不为了维持旧数字把 map quality 再关闭；
- 重新截图和性能采样；
- 如果 Balanced 新启用的 particles/probes/lights 无明显画面价值且成本高，应回到 `data/quality/balanced.json` 做证据驱动调整，而不是让运行时代码偷偷不应用配置。

### R3 occlusion=false 后室内性能变化

室内定义本来就声明 false，因此修复后才是设计真实值。

必须重新采样，不使用旧“可能实际为 true”的数据作为新结论。

### R4 证据目录增大

只保留最终 PNG+JSON、summary CSV/JSON、必要 bake reports 和简短 review；临时 verbose log、录屏、build 二进制继续忽略。

---

## 16. 完成后仓库应呈现的状态

chapter1-3 完成时，仓库应具备以下性质：

1. 两张地图仍严格单活动，不增加常驻场景负担；
2. 构建脚本不会重复生成已知 authored 区域；
3. Lightmap 漏覆盖无法被“成功”状态掩盖；
4. Eco/Balanced 的每一个声明项都真的作用于当前地图；
5. 每张地图自己的 occlusion 决策能真实生效；
6. benchmark 不污染运行时状态；
7. 第 7 个街区机位真实可用；
8. 书签 revision 提示不绑定历史常量；
9. 无效请求不会把仍在运行的地图 UI/相机清空；
10. portal 目标图与目标锚点在构建验收阶段就能证明有效；
11. street 重建、双图截图、性能、Release、人工门户巡走都有可复核证据；
12. 文档不再同时存在“模板未安装”“已经导出成功”“最终 log 不在仓库”等互相冲突的状态描述；
13. 不引入新的平行架构、死代码或为未来功能提前搭空框架。

完成这些后，再进入下一张地图或摄影工作台，会比现在继续堆内容更稳妥。
