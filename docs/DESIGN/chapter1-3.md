# Chapter 1.3 — 工程可信性收口、运行时合同修复与发布验收

> 项目：霓湾 / Neon Haven  
> 代码审阅基线：main@5b95b25903f638a7c35c32015d54921dae53a168（chapter1-2 最终视觉闭环代码）  
> 计划初稿提交：41aac560caf4a0f1bea181f40b8949198781eca0  
> 本次深化审阅仓库快照：main 含 518 个 Git tree 条目，递归树完整、未截断  
> 文档版本：1.1 · 2026-09-22  
> 性质：实施工作单。除本文明确列出的修复、清理、验证外，不扩展新地图、NPC、玩法或联网功能。

---

## 0. 本章目标、结论与执行边界

### 0.1 总体结论

当前工程的主架构是成立的，应保留而不是重写。

经过对根工程、scripts/app、scripts/maps、scripts/diagnostics、两张生产地图、tools、addons/neon_bake、tests、data、docs 与 artifacts 的再次完整核对，当前正确且应继续沿用的边界是：

| 层 | 当前职责 | 1.3 结论 |
| --- | --- | --- |
| scenes/app + main.gd | 组合应用壳、UI、自动化入口 | 保留，只修状态同步与自动化失败路径 |
| MapManager | 严格单活动地图、异步卸载/加载/激活 | 保留状态机，不重写 |
| MapDefinition | 轻量地图数据合同 | 保留 v2；补校验，不升版本 |
| MapRoot | 地图运行时合同、画质、环境动画、门户门扇 | 保留；增加极少只读接口 |
| ObserverCamera | fly / walk 观察相机 | 保留；补公开锚点访问器 |
| SettingsManager | 画质档与窗口节流权威 | 保留；补“当前活动地图同步” |
| CaptureService | PNG+JSON 截图 | 保留；修 abort 收尾与 build_id 接线 |
| BenchmarkRunner | 可复现性能采样 | 保留；修状态快照、环境记录、路线兼容 |
| generated/authored/assemble | 离线地图制作分层 | 保留；清重复生成与指纹漏洞 |
| neon_bake | 编辑器 LightmapGI 烘焙 | 保留为唯一生产烘焙入口 |
| verify/tests | 构建合同与运行时回归 | 强化；必须只读、不得自我“修正”被测数据 |

本章不新增新地图或玩法系统，但除了工程修复，还正式把第一张主场景推进到 1.3 成品质量。最终要让以下五件事都变成可证明事实：

1. 构建状态可信：任何影响 Lightmap 的输入变化都能让旧烘焙失效；任何漏烘焙都不能被标记成功。
2. 运行时状态可信：Eco/Balanced、地图级 occlusion、错误请求、截图、benchmark 的实际状态与报告一致。
3. 自动化可失败：坏地图、截图失败、benchmark 路线不匹配、烘焙缺失都必须非零退出，而不是卡住或静默跳过。
4. 主场景质量可信：m01_afterglow 的城市结构、材质、光照、赛博基础设施和七个构图达到本文 H11/H12，而不是只完成代码修复。\n5. 发布证据可信：最终截图、性能、双图生命周期、Windows Release 与人工巡走都能从仓库中的结构化证据追溯到同一 build_id。

### 0.2 本章不做

以下保持现状：

- 不重写 MapManager 状态机。
- 不把 m01_repair_interior 合并回 m01_afterglow。
- 不引入 CharacterBody3D、碰撞体、导航、NPC、任务、战斗、联网。
- 不增加复杂地图内流式系统。
- 不把 MapDefinition 变成持有 PackedScene、Mesh、Material、LightmapGIData 的重资源。
- 不拆出新的全局 Autoload。
- 不把 build_chapter11.ps1 仅因名字带 11 而改名；当前脚本已经承担双图统一入口，改名收益不足。
- 不删除仍有实际诊断价值的 build_bake_probe、debug_grid_stats、debug_sign_*、sample_png_grid、sample_process。
- MapDefinition.schema_version 继续为 2；本章新增的是运行时/构建实现合同，不是破坏性的地图定义格式迁移。

### 0.3 优先级

P0 必须先修，否则后续截图/性能/导出证据都不可信：

- C13-01：assemble 可清空 baked data 却保留 succeeded。
- C13-02：bake plugin 漏覆盖/保存失败仍可能成功。
- C13-03：烘焙输入指纹漏掉 authored mesh、材质、纹理等真实依赖。
- C13-04：verify 会自行更新 authored baseline，验证器不是只读。
- C13-05：authored 站前几何和 exclusions 重复生成。
- C13-06：Eco/Balanced 运行时只部分生效；occlusion 权威失真。
- C13-07：Benchmark 输出读取恢复后的环境，且 headroom/FPS 恢复顺序有误。
- C13-21：制作脚本的 required output 写失败没有统一 Error 传播，部分路径仍会 quit(0)。

P1 修复运行可靠性与用户可见合同：

- C13-08：MapManager 超时 orphan 轮询会被自己关闭。
- C13-09：无效 preflight 请求会让 Main 清掉仍然 READY 的地图 UI/相机。
- C13-10：自动化等待 READY 无失败/超时出口，截图失败仍可 exit 0。
- C13-11：street 有 7 锚点但快捷键只支持 1–6；外部代码直接读相机私有字段。
- C13-12：capture_anchor_names 是“存在但未实际使用”的接口。
- C13-13：书签旧版本提示硬编码 1.1.0。
- C13-14：门户目标只验证 definition 文件，不验证 registry/target anchor。
- C13-15：CaptureService abort 后可永久保持 busy。
- C13-16：生产 registry 与 verify 仍有硬编码/部分验证，新增地图容易被静默漏验。

P1/P2 收口：

- C13-17：旧单图烘焙脚本、旧根目录 lightmap、旧 props mesh 形成平行旧架构。
- C13-18：最终证据引用被 gitignore 排除的 log，v9 PNG 与 JSON 未完整配对。
- C13-19：expanded_v11、室内稳态、Windows 双图 Release、人工门户巡走仍未最终闭环。
- C13-20：README、environment、tools README、handoff/backlog 与当前事实漂移。
- C13-22：启动质量 UI 用硬编码 Eco，同持久化真实档位可能不一致；自动“diag 截图”实际被 capture_ui 隐藏，没有独立证据价值。

---

## 1. 当前仓库架构快照

### 1.1 目录事实

本次深化审阅的 main tree 共 518 个条目，主要内容：

| 区域 | 当前内容 |
| --- | --- |
| scripts/app | 9 个运行时脚本：guard、bookmark、camera、pose、capture、diagnostics、main、settings、tool_ui |
| scripts/maps | MapDefinition、MapManager、MapRoot |
| scripts/diagnostics | BenchmarkRunner、PerfRoutes |
| maps/m01_afterglow | generated、authored、baked、meshes、最终 scene/definition/manifest |
| maps/m01_repair_interior | generated、baked、meshes、最终 scene/definition/manifest |
| tools | 49 个制作/诊断文件 |
| tests | 3 套主测试 + fixtures |
| artifacts | 215 个已提交工件 |
| assets | 97 个字体、材质、纹理、招牌资源 |
| data | map_registry + Eco/Balanced |

### 1.2 运行时主链

正常启动：

main._ready
→ 创建 shell/services
→ MapManager.setup
→ registry load
→ request_map(m01_afterglow)
→ threaded load
→ MapRoot runtime validation
→ SettingsManager.apply_to_map
→ ObserverCamera.bind_map_contract / apply default pose
→ READY / map_loaded
→ Main 注入锚点位姿与门户值副本

这条主链本身不改。

### 1.3 制作主链

当前统一入口的语义是：

validate
→ generate
→ assemble
→ bake
→ verify
→ export

本章必须保证每个阶段只承担自己的职责：

- generate：生成可重建内容；不修改有效 baked data。
- assemble：组合最终 scene/definition，计算当前烘焙签名，决定旧 bake 是否可安全复用。
- bake：只有这里允许主动重建 LightmapGIData。
- verify：只读验证；绝不修改 baseline、manifest、scene、definition。
- export：只在前述门槛通过后进行。

---

## 2. 构建可信性的目标数据模型：BuildContract + manifest v2

### 2.1 为什么不能继续补手工文件数组

当前 street manifest 手工哈希：

- generated/map_generated.tscn
- baked_static.res
- baked_props.res
- backdrop.res
- authored/authored_static.tscn

但 authored_static.tscn 引用的外部二进制资源实际还包括：

- authored_static_mesh.res
- authored_PropsServiceCourt.res
- authored_PropsStationForecourt.res
- authored_PropsRoofTerrace.res
- authored_PropsStreetEnrich.res
- authored_door_frame.res
- authored_door_leaf.res

同时两图都依赖 shared materials、纹理、招牌纹理与导入设置。只要资源路径不变、内容变化，当前 authored_input_hash 或 geometry_input_hash 可能保持不变。

因此 1.3 禁止继续靠“发现漏项后往数组里补一个路径”修复。

### 2.2 新增 tools/build_contract.gd

新增一个非常小的纯制作辅助层：

class_name BuildContract  
extends RefCounted

职责只限于：

1. 递归解析资源依赖；
2. 生成稳定输入文件列表和 hash；
3. 计算当前应烘焙 user paths；
4. 比较 expected/actual/missing；
5. 提供 AABB 精确重复检查等纯函数。

不负责：

- 生成场景；
- 决定 manifest 状态机；
- 启动 bake；
- 修改地图场景；
- 运行测试。

它可以提供“读取 JSON / 可恢复替换 JSON”的底层文件函数，目的是让 assemble、bake、verify 不再各自复制一套容易分叉的 manifest I/O；状态转换仍由调用方决定。

建议公开接口：

| 接口 | 语义 |
| --- | --- |
| normalize_dependency_path(raw: String) -> String | 解析 ResourceLoader.get_dependencies 的普通路径或 UID::fallback 格式 |
| collect_dependency_closure(root_paths: PackedStringArray) -> PackedStringArray | 递归收集依赖闭包，排序去重 |
| collect_bake_input_files(root_paths, extra_paths=[]) -> PackedStringArray | 过滤运行脚本/烘焙输出后得到真实 bake 输入 |
| stable_file_hash(path: String) -> String | 文本资源做稳定规范化，二进制按字节 hash |
| hash_file_set(paths) -> String | 路径+hash 排序后生成总签名 |
| load_resource_fresh(path: String, type_hint: String = "") -> Resource | 用 CACHE_MODE_REPLACE_DEEP 读取磁盘当前内容，禁止旧 Resource cache 冒充新 baked data |
| expected_bake_users(root: Node) -> Array[String] | LightmapGI 下 GI_STATIC + UV2 的应烘焙节点路径 |
| actual_bake_users(lm: LightmapGI) -> Array[String] | 从 LightmapGIData 读取 user paths |
| missing_paths(expected, actual) -> Array[String] | expected - actual |
| exact_duplicate_aabbs(boxes) -> Array | 只查完全相同 AABB，不把有意重叠判错 |
| load_json_dict(path: String) -> Dictionary | 只读 JSON，非法返回空并由调用方决定失败语义 |
| write_json_recoverable(path: String, data: Dictionary) -> Error | 临时文件写入+回读校验+旧文件备份+替换+失败恢复，统一 manifest 写盘语义 |

Godot 官方 ResourceLoader.get_dependencies 会返回资源直接依赖，并明确 dependency 可能为单一路径，也可能是 UID::空::fallback 三段形式；实现必须按该合同解析，而不能把原字符串直接当文件路径。官方 4.x/4.7 文档作为实施参考：
https://docs.godotengine.org/en/4.7/
https://docs.godotengine.org/en/stable/classes/class_resourceloader.html

### 2.3 bake 输入根

street：

- maps/m01_afterglow/generated/map_generated.tscn
- maps/m01_afterglow/authored/authored_static.tscn

interior：

- maps/m01_repair_interior/generated/interior_generated.tscn

递归依赖闭包必须覆盖 mesh/material/texture 等资源。

对于源图片，如果同路径存在 .import 文件，必须把 .import 也纳入输入，因为压缩、mipmap 等导入参数会影响最终资源。

明确排除：

- maps/*/baked/**
- build_manifest.json
- artifacts/**
- docs/**
- tests/**
- *.uid
- 运行时 GDScript（除非未来 bake 资产生成直接依赖脚本内容且输出未能反映；当前不需要）
- 用户配置 user://**

### 2.4 bake 设置也必须进入签名

仅资源依赖还不够。LightmapGI 自身的烘焙设置变化也会影响结果。

BuildContract 必须从最终组装根读取并序列化一份稳定的 bake settings snapshot。第一版至少覆盖实际 4.7.2 LightmapGI 中本项目会使用的烘焙相关值，例如 quality、bounces、texel scale/bias、directional、environment mode 等；实际字段名以本机 4.7.2 property list 确认为准，不能臆造属性。

最终 bake_input_hash 由：

- dependency file set hash
- bake settings snapshot hash
- 在 LightmapGI 的 environment mode 会使用场景/自定义环境时，对应的 bake-relevant environment snapshot/hash

共同组成。

当前两图的 WorldEnvironment 主要承担运行时天空、雾、tone mapping 和 glow，但 BuildContract 不能把“Environment 永远不参与 bake”写死为假设。实施时读取实际 LightmapGI environment mode：若该模式不会使用环境输入，snapshot 明确记录 disabled/none；若会使用 scene/custom environment，则把真正影响 bake 的 Environment/Sky 资源或稳定属性纳入签名。

此外 expected_baked_user_paths 是独立的结构签名：即使资源内容不变，只要最终 LightmapGI 子树节点路径/参与资格变化，也不得复用旧 bake。

### 2.4.1 Resource cache 规则

所有“判断磁盘 baked data 是否仍有效”的读取都不得直接依赖默认 load() 缓存。

原因：assemble/bake 会在同一进程生命周期内替换 .res；若旧 LightmapGIData 已在 ResourceLoader cache 中，普通 load(path) 可能返回旧对象，让“磁盘已空、内存仍旧”伪装成有效数据。

统一规则：

- BuildContract.load_resource_fresh 使用 ResourceLoader.CACHE_MODE_REPLACE_DEEP；
- assemble 在 reuse 判定时用 fresh load；
- bake plugin 预保存空数据后重新绑定时用 fresh load；
- verify 从磁盘复核 LightmapGIData 时也用 fresh load；
- 测试必须覆盖“先缓存旧资源 → 覆盖磁盘 → fresh load 看到新内容”。

Godot ResourceLoader 文档明确 CACHE_MODE_REPLACE_DEEP 会把主资源及依赖从磁盘刷新到已有缓存对象；实现以本机 4.7.2 API 为准。

### 2.5 manifest v2

两图统一迁移到 schema_version=2。

manifest v2 的权威字段：

| 字段 | 语义 |
| --- | --- |
| schema_version | 2 |
| map_id | 稳定地图 ID |
| content_revision | 内容修订 |
| engine_version | 实际 Godot |
| build_id | 本次构建关联键 |
| bake_source_roots | 本地图制作层的输入根路径；street=generated+authored，interior=generated |
| bake_input_hash | 唯一的“是否可复用旧 bake”输入签名 |
| bake_input_files | 从 source roots 递归得到的排序输入文件与各自 sha256，便于审计 |
| bake_settings | 实际 LightmapGI 烘焙设置快照 |
| bake_job_id | 当前/最近一次 bake |
| bake_status | pending / stale / running / succeeded / failed |
| expected_baked_user_paths | 当前组装 scene 应烘焙节点 |
| actual_baked_user_paths | 实际 LightmapGIData user paths |
| missing_baked_user_paths | expected - actual |
| bake_finished_utc | 成功/失败收尾时间 |
| outputs | 可选制作输出索引，不作为 bake 成功权威 |

迁移到 v2 后停止写：

- geometry_input_hash
- lighting_input_hash
- authored_input_hash

这些旧字段曾用于诊断，但已经无法作为完整 stale 判断；保留它们会形成第二套权威。若确有历史分析需要，从旧 commit 读取，不在 v2 继续维护。

### 2.5.1 Manifest 状态转换

唯一允许的主要转换：

| 触发 | 新状态 |
| --- | --- |
| 首次 assemble，无旧 manifest | pending |
| assemble 发现输入/expected/真实 baked data 任一不匹配 | stale |
| assemble 证明 hash/expected/真实 baked data 全部一致 | succeeded（安全复用） |
| bake 在覆盖旧 baked data 之前 | running |
| bake 数据/coverage/scene save 失败 | failed |
| bake 数据有效且 coverage 完整、scene save 成功 | succeeded |

succeeded 的含义只表示“当前地图的烘焙数据有效且完整”，不表示附加证据文件一定写成功。bake report 写失败仍让本次命令非零退出，但不应反向伪称已经验证有效的 LightmapGIData 无效；最终发布门槛会要求 report/verification summary 补齐。

### 2.5.2 Manifest 可恢复替换

这里不宣称操作系统级原子覆盖。

write_json_recoverable 的最低流程：

1. 写 path.tmp；
2. flush/close；
3. 重新解析 tmp，确认 JSON 与 schema 可读；
4. 若旧目标存在，先复制到 path.prev；
5. 删除旧目标；
6. rename tmp → target；
7. rename 失败则尝试 prev 恢复；
8. 成功后删除 prev；恢复也失败时保留 tmp/prev 并返回错误，供人工取证。

所有调用方必须检查 Error。不能“print 一行失败后继续”。

### 2.6 v1 → v2 迁移规则

不能把旧 manifest 的 succeeded 直接迁移为 v2 succeeded。

第一次由 1.3 assemble 看到 schema_version=1 时：

- 计算 v2 bake_input_hash；
- 计算当前 expected；
- 状态置 stale；
- actual/missing 不作为当前有效覆盖证明；
- 必须真实执行一次 bake 后才能进入 succeeded。

这是一次性迁移成本，换取后续可信状态。

---

## 3. C13-01 — Assemble 不得“清空 bake 但保留 succeeded”

### 3.1 当前根因

assemble_m01 与 assemble_interior 在构建 MapRoot 时都会：

1. 新建空 LightmapGIData；
2. 保存覆盖 maps/<map>/baked/map_lightmap.res；
3. 把这个空数据挂给 LightmapGI；
4. 后续 _write_manifest 如果旧手工 hash 未变，仍可能保留旧 succeeded 和 actual paths。

于是 Stage=assemble 可以得到：

- 磁盘 LightmapGIData 已空；
- manifest 仍 succeeded；
- actual_baked_user_paths 仍是旧数组。

这在语义上是不可接受的。

### 3.2 目标 assemble 顺序

assemble 不再无条件覆盖 baked data。

建议流程：

1. 构建最终 MapRoot，但暂不破坏现有 baked 文件。
2. 从当前 root 计算 expected_baked_user_paths。
3. 由本地图声明的 bake_source_roots 计算 manifest v2 bake_input_hash / input files / settings/environment snapshot。
4. 读取上一 manifest + 已有 baked/map_lightmap.res；baked data 必须通过 BuildContract.load_resource_fresh 读取。
5. 判断 can_reuse_bake。
6. 若可复用，把 fresh-load 后验证通过的已有 LightmapGIData 绑定到当前 LightmapGI；此分支没有破坏性 baked 写入。
7. 若不可复用，**先用 write_json_recoverable 把磁盘 manifest 写成 pending/stale，写入当前 source roots/hash/expected，并清 actual/missing/job id**。这一步失败立即 quit(1)，尚未触碰旧 baked data。
8. 只有预失效 manifest 成功后，才创建并保存空 LightmapGIData，再用 fresh-load 绑定；保存/读取失败立即 quit(1)，manifest 已是非 succeeded。
9. pack/save map.tscn，检查 Error。
10. save MapDefinition，检查 Error。
11. 最后再次写 manifest：reuse 分支写 succeeded+真实 actual；invalidated 分支保持 pending/stale。任何写失败非零退出。

can_reuse_bake 必须同时满足：

- 前一 manifest schema_version=2；
- prev.bake_source_roots 与当前 roots 排序后相同；
- 前一 bake_status=succeeded；
- prev.bake_input_hash == current.bake_input_hash；
- prev.expected_baked_user_paths == current expected（排序后相等）；
- 现存 baked data 可加载；
- 从现存 baked data 重新读取 actual；
- missing_paths(current expected, actual) 为空。

只看 manifest 中缓存的 actual 不够；必须读取真实 LightmapGIData。

### 3.3 不可复用时

若任何条件不满足：

- 新建空 baked data；
- bake_status=stale（已有旧 manifest）或 pending（全新地图）；
- expected 写当前值；
- actual=[]；
- missing=[]（未烘焙不是“覆盖缺失结果”，因此先空；真正 bake 后再写 missing）；
- bake_job_id 清空。

此时运行时 requires_baked_lighting 地图不应作为最终发布状态通过 verify。

### 3.4 验收

T13 必须证明：

- 连续两次 no-op assemble：第二次安全复用真实 baked data，user_count 不变，succeeded 保留。
- 修改一个 bake 输入后 assemble：状态 stale，旧 bake 不复用。
- 删除/损坏 baked data 后 assemble：即使旧 manifest 写 succeeded，也必须降级 stale。
- 修改最终 expected user path 后 assemble：不得复用旧 bake。

---

## 4. C13-02 — Bake 必须先使旧成功状态失效，再写空数据

### 4.1 当前根因

neon_bake 在真正 bake 前会预保存空 LightmapGIData，但当前只修改插件内存 job state，没有先把磁盘 manifest 切到 running。

如果进程在“空数据已写、manifest 尚未回写”之间失败，旧 manifest 仍可能显示 succeeded。

### 4.2 原子顺序

生产 bake 唯一允许顺序：

1. 打开目标 scene。
2. 完成 precheck。
3. 计算/读取当前 expected。
4. 读取 manifest v2，并确认其 bake_input_hash 与当前 scene 输入一致；不一致直接失败，要求重新 assemble。
5. **先可恢复替换 manifest：bake_status=running、job_id、本轮 expected、actual=[]、missing=[]。**
6. manifest 写成功后，才允许覆盖 baked/map_lightmap.res 为新空数据。
7. 空数据保存成功后，用 CACHE_MODE_REPLACE_DEEP/fresh-load 重新绑定 LightmapGI，确认 user_count=0；不能让 ResourceLoader cache 中的旧数据继续挂在节点上。
8. 触发编辑器 Bake Lightmaps。
9. 等实际 user_count 稳定。
10. 计算 actual/missing。
11. missing 为空才继续。
12. EditorInterface.save_scene()，检查返回 Error。
13. 再次从磁盘/scene fresh-load 必要状态做终检。
14. 可恢复替换 manifest succeeded + expected/actual/missing=[] + finished time。
15. 写 report success=true。
16. 输出 NEON_BAKE_EXIT=0。

任何一步失败：

- 尽最大可能写 manifest failed；
- report success=false；
- NEON_BAKE_EXIT=1；
- PowerShell wrapper 停止；
- 不允许 export。

Godot EditorInterface.save_scene() 返回 Error，官方文档明确成功为 OK、失败可返回 ERR_CANT_CREATE；当前代码忽略返回值，1.3 必须检查：
https://docs.godotengine.org/zh-cn/4.x/classes/class_editorinterface.html

### 4.3 覆盖判定

成功条件固定为：

- expected 非空；
- actual 非空；
- missing 为空。

允许 actual 是 expected 的超集。当前历史 bake report 中 Backdrop 可能作为额外 actual user，因此不能强制集合严格相等。

### 4.4 manifest/report 写盘失败也是 bake 失败

当前 _update_manifest 遇到 manifest 不存在/JSON 非法只打印并返回，仍可能继续成功。

1.3 要求所有制作写操作返回 Error：

- _write_manifest_state(...) -> Error
- _write_report(...) -> Error

成功链必须检查它们。

### 4.5 负例

至少自动覆盖：

- expected 中人为增加一个 actual 不存在 path → failed。
- manifest 不可解析 → failed。
- manifest bake_input_hash 与当前不一致 → failed。
- report 目录不可写（可用测试 helper 模拟）→ 不允许 success helper 返回 true。
- save_scene 返回非 OK 的分支通过纯 helper/包装测试验证“成功门槛不成立”。

---

## 5. C13-03 — 完整烘焙输入签名

### 5.1 必测变化

BuildContract 的 bake_input_hash 必须对以下变化敏感：

1. generated mesh 内容变化；
2. authored_static_mesh 内容变化；
3. 任一区域 authored props mesh 变化；
4. 门框/门扇 mesh 变化；
5. shared Material 参数变化；
6. Material 引用的 PNG 内容变化；
7. 对应 PNG.import 导入参数变化；
8. 静态 bake light 的能量/颜色/位置变化；
9. LightmapGI bake settings 变化。

对以下变化不应强制重烘：

- README 文案；
- bookmark 用户文件；
- UI 文案；
- ToolUI 布局；
- camera bookmark 数据；
- artifacts 输出。

### 5.2 no-op 稳定性

Godot 4.7 保存 tscn/tres 会写可能变化的 unique_id。stable_file_hash 必须继续沿用已验证的 unique_id 规范化思想。

实现完成后执行：

generate → assemble → 记录 bake_input_hash  
再次相同 generate → assemble → 再记录

两次必须相同。

如果还有其他非语义字段导致漂移，先定位并只规范化已证明的字段，不做泛化正则“删所有数字”。

---

## 6. C13-04 — Verify 必须只读

### 6.1 当前缺陷

verify_build._check_authored_baseline 在 baseline 不一致时会直接把当前 hash 写成新 baseline，并打印“合法更新”。

这意味着 verify 能修改被测对象，并把未知变化自动变成新基线，不能作为保护门槛。

### 6.2 处理

删除：

- maps/m01_afterglow/authored/authored_input_hash.baseline
- verify_build 中自动建立/更新 baseline 的逻辑

verify 从此不得写 res://。

### 6.3 如何证明 build_m01 不覆盖 authored

把“所有权保护”放到真正会执行生成器的 build_chapter11.ps1：

street generate 顺序：

1. 生成纹理/招牌。
2. 对现有 authored 所有权路径做 pre-city 指纹。
3. 运行 build_m01.gd。
4. 对同一路径做 post-city 指纹。
5. 不相等立即失败：build_m01 越界修改 authored。
6. 然后才运行 build_authored.gd；这是 authored 的合法写入者。

所有权路径至少包括：

- maps/m01_afterglow/authored/**
- maps/m01_afterglow/meshes/authored_*

这比“长期 baseline”更准确：它验证的是一个工具有没有越界写，而不是阻止 authored 自身合法演进。

### 6.4 Verify v2

verify_build 必须：

- 从 registry 枚举所有生产地图；
- 读取 MapDefinition；
- manifest 路径由 def.scene_path.get_base_dir().path_join("build_manifest.json") 推导，不按 map_id 硬编码目录；
- 读取 manifest v2；
- 校验 bake_source_roots 非空、均存在且位于 res://；
- 根据 manifest.bake_source_roots 重新递归收集依赖并计算当前 bake_input_hash；
- 重新算 current expected；
- 从真实 LightmapGIData 读 actual；
- 校验 status succeeded；
- 校验 current hash == manifest hash；
- 校验 current expected == manifest expected；
- 校验 missing(current expected, actual).is_empty；
- 校验 manifest actual 与真实 actual 至少一致到集合语义；
- 校验 manifest missing 为空；
- 校验 MapRoot runtime contract；
- 再做 walk/portal 等地图合同。

verify 失败只输出错误并非零退出，绝不“顺手修”。

---

## 6.5 C13-21 — 制作 required output 必须传播失败

### 6.5.1 当前事实

当前多处写盘错误只 push_error/print 后继续：

- build_m01 保存 generated scene/spec/material/fixture；
- build_authored 保存 authored scene/spec/region manifest；
- build_interior 保存 generated scene/spec；
- assemble_m01 / assemble_interior 保存 map scene、definition、manifest；
- GenLib.MeshBuilder.commit 保存外部 mesh 时只 push_error。

最危险的情况不是“文件不存在”，而是旧文件还在：新保存失败后流程继续，后续 assemble/verify 可能读到上一次成功产物。

### 6.5.2 修复范围

本章不把所有工具重写成事务系统，但所有**生产必需输出**必须可观察失败并让当前 Godot 进程 quit(1)。

street assemble 的输入本身也必须成为硬前置：GENERATED_SPEC、AUTHORED_SPEC、GENERATED_SCENE、AUTHORED_SCENE 任一缺失/不可解析都必须失败。当前 AUTHORED_SPEC 为空或 AUTHORED_SCENE 缺失时不能继续组出“缺精修层但看似成功”的 street。

GenLib.MeshBuilder 保持 commit 的现有返回形态，增加只读 last_save_error/get_last_save_error；每次 commit 开始先清 OK，path 非空且 ResourceSaver.save 失败时记录错误。

build_m01 当前 _pack 即使 ps.pack 失败也仍返回 PackedScene；本章改为失败返回 null/明确 Error，上层不得继续 ResourceSaver.save。

build_m01/build_authored/build_interior 对每个需要落盘的 mesh、scene、spec、material/region manifest 逐项检查；任一 required output 失败立即停止本阶段。

assemble 的三个关键写入必须返回 Error：

- save map scene；
- save MapDefinition；
- write manifest。

只有三者全 OK 才输出 ASSEMBLE_DONE。

fixture/诊断输出如果明确不属于生产门槛，可以标 optional；但不能让 optional 与 production required 混在同一个无返回值 helper 里。

### 6.5.3 输出后校验

Stage=generate/assemble 结束前至少确认：

- 本轮预期文件存在；
- 必要 JSON 可重新解析；
- 必要 Resource 可 fresh-load；
- 不是仅凭“旧路径存在”判成功。

### 6.5.4 验收

用 user:// 临时路径/专用 fixture 模拟写失败或非法 JSON，不修改 tracked production 文件。

至少证明：

- required scene save Error → exit1；
- required spec open null → exit1；
- manifest replace Error → exit1；
- MeshBuilder required mesh save error 能被上层观察；
- 成功路径仍输出原有 DONE marker。

## 7. C13-05 — 清掉 authored 重复生成

### 7.1 当前实测数据

当前 authored_spec.json：

- exclusions 总数：29
- 精确重复 key：8 组
- 多出来的重复 entry：8 个

8 组精确重复包括：

- SC_W 建筑 1 组；
- SC_S 建筑 1 组；
- station forecourt 6 组。

此外 SC_ANNEX 有两份 x/z 完全一致但高度不同的 exclusion：

- 自动建筑 exclusion 高度约 9.1；
- 手工特殊规则高度约 8.55。

这不是“精确重复”，但仍是同一建筑的双权威。

generated_spec exclusions=18，精确重复=0。

### 7.2 几何根因

build_authored._run 顶层已经调用：

- _service_court_static
- _station_forecourt_static_common
- _roof_terrace_static

但 _service_court_static 末尾又调用一次 _station_forecourt_static_common。

因此 station forecourt 静态几何也被写入同一 authored static mesh 两次。

### 7.3 源头修复

_station_forecourt_static_common 只由顶层调用一次。

_authored_building 增加一个最小参数：

register_exclusion: bool = true

然后：

- SC_W：默认自动 exclusion，删除手工重复。
- SC_S：默认自动 exclusion，删除手工重复。
- SC_ANNEX：register_exclusion=false，只保留手工特殊高度 exclusion。
- 拱门、树带、车棚、设备箱、街面道具等特殊盒继续手工定义。

禁止在 assemble 阶段“静默 dedupe”来掩盖生成器错误。

### 7.4 预期数量

在不新增其他 exclusion 的前提下：

- authored 29
- 删除 8 个精确重复 extra
- 再删除 1 个 SC_ANNEX 自动重叠盒
- 预计 authored = 20
- generated = 18
- 最终 street exclusions 预计 = 38

实施时以真实重建输出为准。如果不是 38，必须解释差异；硬门槛仍是“精确重复=0、每个特殊重叠有明确语义”。

### 7.5 content revision 时点

C13-05 去重已经会改变 street 几何，但本章后续 WP8/WP9 还会继续改变正式场景内容和可能微调锚点。不能在中途先把同一个 1.3.0 发布语义占掉。

实施规则：

- 工程修复和中间美术 pass 阶段，assemble 常量暂维持开发基线 revision；这些中间工件不得作为正式 Release。
- WP9 完成所有 street 几何、材质、灯光和锚点冻结后，**一次性把 m01_afterglow content_revision 从 1.2.0 升到 1.3.0**。
- 升 revision 后必须再执行最终 generate → assemble → bake → verify → screenshot/perf；升版前的 bake/screenshot 只算过程证据。
- m01_repair_interior 若其几何、锚点、walk surface 以及实际引用的共享材质均未改变，则保持 1.2.0。
- 若 1.3 为了街区美术直接修改了 interior 实际引用的共享材质/招牌资源并造成可见变化，则 interior 也属于内容变更：必须重新目检并将其 revision 升至 1.3.0。不能让“1.2.0”在相同 revision 下出现两套可见室内。

不要为了章节号整齐机械同步升版；以实际内容是否改变为准。

---

## 8. C13-06 — 画质档与地图级 occlusion 的唯一权威

### 8.1 当前问题

SettingsManager._apply_profile 真实应用：

- render scale
- MSAA/FXAA
- frame cap

MapRoot.apply_quality 负责：

- particles
- runtime fill lights
- optional probes
- bake-only light 隐藏
- glow
- detail prop range

但 READY 后切 Eco/Balanced 不会重新调用 MapRoot.apply_quality。

另外：

- street definition occlusion_enabled=true；
- interior definition occlusion_enabled=false；
- main._on_quality_changed 当前无条件把 Viewport occlusion=true；
- BenchmarkRunner._finish 也硬恢复 true。

### 8.2 权威关系

固定为：

| 状态 | 权威 |
| --- | --- |
| render scale / AA / FPS / particles / probes / extra lights / glow / detail range | data/quality/*.json，经 SettingsManager 应用 |
| 地图默认 occlusion | MapDefinition.occlusion_enabled |
| benchmark 临时 occlusion on/off | BenchmarkRunner 单轮覆盖 |
| benchmark 结束 | 恢复进入 benchmark 前的实际值 |
| 无活动地图 | project.godot 的 rendering/occlusion_culling/use_occlusion_culling 默认值 |

### 8.3 SettingsManager 实施

不让 MapManager再订阅一套 quality_changed，避免两个控制者。

SettingsManager._apply_profile 的完整顺序：

1. 设置 current_quality/current_profile。
2. 应用 Viewport scale/AA。
3. 应用有效 FPS。
4. 调用私有 _apply_to_active_map_if_present()。
5. 所有真实状态完成后，emit quality_changed(..., get_effective_state())。

_apply_to_active_map_if_present：

- 从 active_map_root 组找当前 MapRoot；
- 0 个：no-op；
- 1 个：调用 apply_to_map；
- >1 个：push_error，返回错误（这是生命周期违约）。

SettingsManager.apply_to_map(map_root)：

1. MapRoot.apply_quality(current_profile)；
2. 读取 map_root 的地图 occlusion 默认值；
3. 应用 Viewport.use_occlusion_culling；
4. 返回 Error。

MapRoot 增加只读：

get_occlusion_enabled() -> bool

### 8.4 MapManager 激活

MapManager 激活时仍显式调用 _quality.apply_to_map(map_root)。

原因：地图刚进入树时可能没有发生新的 quality_changed，必须把当前档位作用到新图。

### 8.5 Main

main._on_quality_changed 只做 ToolUI 状态同步。

删除：

Viewport.use_occlusion_culling = true

Main 在接线后做首次 UI 同步时，不能再写死 requested_id=&"eco"。必须使用：

settings.get_profile_id() + settings.get_effective_state()

这样 user://settings.cfg 持久化 Balanced 时，真实档位与按钮状态一致。

### 8.6 卸载

进入 EMPTY 后恢复 project default occlusion，而不是硬编码 true。

SettingsManager 增加唯一入口：

apply_no_map_defaults() -> void

它只负责恢复“不属于任何地图”的全局视口覆盖，当前至少包含：

Viewport.use_occlusion_culling = ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", true)

MapManager 在以下两条真正离开地图的路径调用：

- 正常 unload 完成且没有 pending next map；
- activation/load 失败最终回 EMPTY。

切图 READY→UNLOADING→LOADING→READY 不需要在中间反复切 project default；新图激活时由 apply_to_map 一次落最终值。

### 8.7 启动画质 UI 同步（C13-22 的运行时部分）

Main 当前在 SettingsManager 已从 user://settings.cfg 恢复真实 profile 后，仍手工调用：

_on_quality_changed(&"eco", settings.get_effective_state())

这会让 UI 的 requested_id 与真实持久化 profile 不一致。

改为：

_on_quality_changed(settings.get_profile_id(), settings.get_effective_state())

或者提供一个无 signal 的 _sync_quality_ui_from_settings()，只读 SettingsManager 当前值。

验收：

- settings.cfg=balanced 启动时 UI 直接显示 Balanced；
- settings.cfg=eco 显示 Eco；
- 非法配置仍由 SettingsManager 回落 Eco，UI 与回落结果一致；
- 不为“初始化 UI”再次 set_profile，避免多余持久化/quality_changed。

### 8.7 验收

街区：

Eco → Balanced → Eco 时，MapRoot 内真实节点与 glow/detail range 随档切换；occlusion 始终 true。

室内：

Eco → Balanced → Eco 时，地图内质量项随档切换；occlusion 始终 false。

地图切换：

street → interior → street = true → false → true。

get_effective_state 必须反映实际 Viewport/MapRoot 状态，不是配置回显。

---

## 9. C13-07 — BenchmarkRunner 正确性修复

### 9.1 当前三个确定性错误

#### 错误 A：报告读取了恢复后的状态

_finish 当前先 restore user quality、恢复 occlusion，再调用 _write_outputs。

而 _write_outputs 内部 _environment_info 会读取当前实时：

- render_scale
- frame_cap
- vsync
- occlusion_enabled

于是报告可能写的是用户恢复后的环境，不是刚才测量环境。

#### 错误 B：headroom FPS 恢复顺序错误

start_run 先切 benchmark profile，再保存 _saved_max_fps。

例如用户 Eco 30 → benchmark Balanced 60：

- set Balanced 后 Engine.max_fps=60
- 保存 60
- headroom 设 0
- finish 恢复 Eco → 30
- 随后又写回 saved 60

最终用户 Eco 标签下可能变成 60 FPS。

#### 错误 C：main 永久删除用户 settings.cfg

_run_automation_perf 为了“保证确定”直接删除 user://settings.cfg。

Benchmark 本来已经有 persist=false + runtime snapshot，不应破坏用户偏好文件。

### 9.2 measured snapshot

BenchmarkRunner 增加：

- _measured_environment: Dictionary
- _measured_map_state: Dictionary
- _saved_vsync
- _saved_occlusion

开始流程：

1. 校验 map/route/config。
2. 申请 ActivityGuard。
3. 快照用户 quality/camera/ambient/vsync/occlusion。
4. set_profile(target,false)，确保完整 map quality 已生效。
5. 应用 benchmark occlusion override。
6. 如 headroom，关闭 VSync、Engine.max_fps=0。
7. 等实际设置稳定一个 process frame。
8. 冻结 _measured_environment 与 _measured_map_state。
9. 开始 warmup/sample。

写输出只使用这两个测量快照。

### 9.3 restore 顺序

结束/中止统一：

1. 停采样。
2. 先保存统计与 measured snapshot 到输出内存结构。
3. 恢复 VSync。
4. restore_runtime_state(user quality)，让它成为 FPS 唯一恢复权威。
5. 恢复 saved occlusion（或由恢复后的当前地图默认再次确认，二者应相同）。
6. 恢复 camera/ambient/input。
7. release guard。
8. 最终写文件。
9. emit completed/aborted。

删除 _saved_max_fps；不要再维护第二份 FPS 权威。

### 9.4 output path 安全

现有 output_directory 只用 begins_with("user://benchmarks") 不够严格。

规范化后只允许：

- user://benchmarks
- user://benchmarks/...

拒绝：

- user://benchmarks_evil
- user://benchmarks/../outside

run_id 禁止路径分隔符与 ..，只允许简短安全字符集。

虽然后台自动化当前自己生成 run_id，但公共接口既然存在，就把合同做完整。

### 9.5 build_id

Benchmark run.json/summary.json/environment 增加 build_id：

优先 OS.get_environment("NEON_BUILD_ID")，为空时记录 "unknown"，不伪造 commit。

---

## 10. 性能路线：明确 route 与 map 的兼容关系

### 10.1 当前缺口

PerfRoutes 只有 street 坐标，但 main 已支持 --perf --map <id>。

如果传 interior，BenchmarkRunner 会直接调用 set_route_transform 使用 street 世界坐标，而这个接口刻意绕过相机 bounds 校验。

所以 route 必须声明适用地图。

### 10.2 PerfRoutes 单一数据结构

把当前并行的 ROUTES + SEGMENT_SECONDS 收敛成一个 ROUTE_SPECS：

每个 route 定义：

- map_id
- segment_seconds
- segments

公开只读 helper：

- has_route(route_id)
- route_map_id(route_id)
- route_duration(route_id)
- route_transform(route_id,t)
- segment_id(route_id,t)

已有：

- legacy_v1 → m01_afterglow
- expanded_v11 → m01_afterglow

新增：

- interior_v13 → m01_repair_interior

### 10.3 interior_v13

60 秒，四段各 15 秒：

1. entry
2. workbench
3. gallery
4. dining

优先使用固定/极小安全移动，不在 benchmark 中重新实现 walk navigation。

路线必须使用已通过的最终机位空间，不穿墙、不跨楼插值。

### 10.4 校验

BenchmarkRunner.start_run：

route 不存在 → ERR_INVALID_PARAMETER。

route_map_id != 当前 READY map_id → ERR_INVALID_PARAMETER，并输出可读原因。

capped 正式路线 duration=60；route_duration 也必须覆盖 60 秒。

### 10.5 warmup

删除 main 中额外的固定 15 秒外层 timer。

warmup 只由 BenchmarkRunner config 控制。

为保证 ×3 可比较，默认每轮都 warmup 15 秒；用户明确 --warmup 0 才关闭。不要只在 r==0 设置 warmup、后两轮为 0。

---

## 11. C13-08 — MapManager timeout orphan 必须能收尾

### 11.1 当前根因

加载超时时：

- _process 把 path 放入 _orphan_paths；
- 随后 _fail_load 调用 set_process(false)。

这样 orphan 的 threaded load 不再被轮询，path 永远留在字典；之后再请求同一路径会一直 ERR_BUSY。

### 11.2 修复

_fail_load 不再无条件 set_process(false)。

统一规则：

- state == LOADING → 必须 process；
- _orphan_paths 非空 → 必须 process；
- 只有“非 LOADING 且 orphan 为空”才能 set_process(false)。

建议抽一个极小私有 helper：

_update_process_enabled()

所有状态变化后调用，避免多个分支各写一套布尔逻辑。

### 11.3 验收

需要一个可控测试，不依赖真的让大资源卡 30 秒。

允许给 MapManager 增加测试可注入的 timeout 或测试 helper，但生产默认仍 30s。优先方案：

- var load_timeout_sec := 30.0
- setup 测试后可 set 为极小值；正式代码不从用户配置暴露。

用 fixture 触发/模拟 orphan 后：

- 失败信号收到；
- orphan 最终被清除；
- 同 path 后续不永久 ERR_BUSY。

不要为了测试修改正常 threaded load 语义。

---

## 12. C13-09 — preflight 失败不能破坏当前 READY shell

### 12.1 当前事实

MapManager 对未知 ID、坏 definition、缺 scene、坏 entry anchor 都在卸载前拒绝，map_failed transaction_id=0，并保持当前图。

但 Main._on_map_failed 当前总是：

- 显示未加载；
- unbind camera；
- 清 portals。

### 12.2 信号语义固定

沿用已有 transaction_id，不增加第二套 signal：

- tx == 0：preflight rejection，没有开始切图事务。
- tx > 0：加载/激活事务已经发生。

Main 收到 tx==0 且 MapManager 仍 READY：

- 保持 loading overlay 隐藏；
- 保持当前 map info；
- 保持 camera binding；
- 保持 anchors/portals；
- 仅 show_transient_message("加载失败：...")。

tx>0 且 manager 回 EMPTY：

- 执行当前完整清空逻辑。

### 12.3 验收

street READY 时依次请求：

- unknown map
- broken scene
- nonexistent entry anchor

每次：

- active_map_root=1
- current_map_id=street
- camera.is_bound=true
- anchor order 不变
- portal 列表不变
- map label 不变
- UI 只出现错误提示

activation failure 的旧测试继续要求清理到 EMPTY。

---

## 13. C13-10 — 自动化必须有失败出口

### 13.1 当前死等

_run_automation_shoot / _run_automation_perf：

await _await_map_ready()

而 _await_map_ready 只循环 state != READY，没有：

- timeout；
- map_failed；
- EMPTY failure；
- last_error 检查。

坏 --map 可以永久挂住进程。

### 13.2 接口

改为：

_await_map_ready(timeout_sec: float = 35.0) -> Error

规则：

- READY → OK
- ERROR/EMPTY 且 last_error 非空 → ERR_CANT_OPEN 或 ERR_INVALID_PARAMETER
- 超时 → ERR_TIMEOUT

_ready 自动化入口在 request_map 时先检查返回 Error；同步 preflight 失败立即 quit(1)，不进入 await。

### 13.3 screenshot 自动化不能静默跳图

当前 _shoot_anchors 截图两次失败后只 warning，最后仍 SHOOT_DONE/exit0。

改为返回 Error/结果对象：

- go_to_anchor false → fail
- request_capture 最终非 OK → fail
- capture_failed signal → fail
- 诊断图失败 → fail
- 任何要求的最终图缺失 → 整轮 automation exit 1

只有全部目标成功才打印 SHOOT_DONE。

### 13.4 quality 参数

_tier_args 后必须逐项验证 profile 存在。

--quality nonsense 不能用旧 profile 渲染却把文件命名为 nonsense。

---

## 14. C13-11 / C13-12 — 锚点接口与 capture anchors 真正落地

### 14.1 禁止外部读 _anchor_order

当前 Main 多处直接读取 camera_ctl._anchor_order。

给 ObserverCamera 增加：

- get_anchor_order() -> PackedStringArray（副本）
- go_to_anchor_index(index: int) -> bool

Main、UI、automation 只走公开接口。

### 14.2 数字键

统一 ANCHOR_KEYS = 1..9。

不再 match 写死 KEY_1..KEY_6。

规则：

- index 在当前 anchor 数组内 → 切换。
- 超界 → no-op。
- ToolUI 最多显示前 9 个数字快捷键。
- 将来 >9 个锚点时，额外锚点不伪造数字键提示。

当前验收：

- street 1–7 全可达。
- interior 1–4 全可达。
- 8/9 无锚点时安全 no-op。

### 14.3 capture_anchor_names

MapDefinition 已经存在 get_capture_anchor_names，但截图自动化从未使用它。

MapManager.get_camera_contract 增加：

capture_anchor_ids

来自 def.get_capture_anchor_names()。

MapDefinition.validate 增加：

- anchor_names 不允许重复；
- capture_anchor_names 非空时不允许重复；
- capture_anchor_names 每项必须存在于 anchor_names。

MapDefinition.get_capture_anchor_names 返回 PackedStringArray 副本；不能把 Resource 内部数组引用直接交给调用方。

自动截图：

- 使用 capture_anchor_ids；
- 交互快捷键仍使用 anchor_ids。

当前两图 capture list 为空，因此自动回落全部 anchors，不改变现有预期，只把接口真正接通。

---

## 15. C13-13 — 书签版本提示使用当前地图 revision

ToolUI.set_bookmarks 改成唯一方案：

set_bookmarks(entries: Array, current_revision: String)

规则：

- entry revision == current revision → 不显示额外标签。
- entry revision 非空且不同 → 显示 [旧 rX]。
- entry revision 为空 → 显示 [旧 未知]，但不拒绝加载。

Main._refresh_bookmark_menu 传：

map_manager.get_current_content_revision()

旧版本书签仍交给 ObserverCamera.validate_pose 决定是否能加载；revision 只提示兼容风险，不做强制迁移。

street 升 1.3.0 后：

- street 1.2.0 bookmark 标旧；
- 新 1.3.0 不标旧。

interior 保持 1.2.0：

- interior 1.2.0 不标旧。

---

## 16. C13-14 / C13-16 — Registry 与 Portal 完整性

### 16.1 registry 原子加载

MapManager.load_registry_file 不应边解析边写 _registry。

新语义：

0. Main 必须检查 load_registry_file 的 bool 返回值；失败时停止默认地图请求/自动化入口，显示“地图注册表不可用”的明确错误。不能忽略返回值后继续假装正常启动。
1. 解析 JSON。
2. schema_version 必须为 1。
3. maps 必须为 Array。
4. 每个 map_id 非空且唯一。
5. definition_path 必须 res:// 且唯一性/存在性合理。
6. definition 可加载。
7. definition.validate 通过。
8. definition.map_id 必须与 registry map_id 相同。
9. 全部通过后一次性替换 _registry/_definitions。
10. 任一失败 → 返回 false，保留旧 registry（若有），不留下半加载状态。

### 16.2 request 防御

_validate_request 再做 def.map_id == requested map_id 的防御校验。

### 16.3 Portal 图关系

verify 对所有 production definitions 的 portals 检查：

- target_map_id 在 registry；
- target definition validate 通过；
- target_anchor 在 target.anchor_names；
- 不需要加载目标 3D scene。

当前：

street → interior / entry_view  
interior → street / repair_shop_door

都必须通过。

### 16.4 verify 不再静默跳过新增地图

当前 verify 有硬编码 MAP_CONFIGS，registry 新增未配置 map 时可能不进入验证。

manifest v2 的 bake_source_roots 是制作期元数据，正是为了解决“通用 verify 不知道每张地图的 generated/authored 输入层在哪里”这一问题；verify 不再内置 street/interior 的源文件数组。

1.3 后：

- 主枚举权威是 data/map_registry.json；
- scene/definition 从 MapDefinition 取得；
- manifest 默认 maps/<map_id>/build_manifest.json；
- walk、portal、region 等特殊检查根据 definition 字段触发；
- 不以 map_id hardcode 决定“要不要验”。

如果未来某地图确需特殊制作元数据，应在 manifest/definition 增加明确字段，而不是悄悄加 MAP_CONFIGS 分支。

---

## 17. C13-15 — CaptureService abort 收尾

### 17.1 当前根因

abort_capture 只把 _request_id=0。

_run_capture 下一次 await 回来发现 request invalid，会 cleanup 后 return，但这些早退分支没有把 _busy=false。

结果：调用 abort 后服务可能永久 ERR_BUSY。

### 17.2 修复

把请求上下文从 _run_capture 的局部变量收敛到当前请求字段（active token、saved UI state、request id、cancel reason），再集中到一个幂等 finish helper：

- 恢复 UI；
- 恢复 camera input；
- 释放 guard token；
- _busy=false；
- _request_id=0；
- 清 active token/context；
- 成功时 emit completed；
- 失败/取消时 emit failed 一次。

abort_capture 不只把 request id 置零，而是立即标记取消并调用统一 finish；已经挂起在 frame_post_draw 的旧 continuation 以后恢复时会看到 request id 已失效，只能 return，不能再次 cleanup/emit。

这样取消不依赖“下一帧一定会到来”，也能在 headless/退出边界可靠释放 ActivityGuard。

### 17.3 验收

- 正常成功后 is_busy=false。
- PNG 写失败后 is_busy=false。
- JSON 写失败后 is_busy=false。
- abort 后最终 is_busy=false，guard 空闲。
- abort 旧请求不能在下一请求完成后再次写盘或发 success。

---

## 18. C13-17 — 删除旧烘焙平行路径与死资产

### 18.1 当前候选

当前生产路径明确使用 maps/<map_id>/baked/map_lightmap.res，但 street 目录仍有早期根级产物：

- maps/m01_afterglow/map_lightmap.res
- maps/m01_afterglow/map_lightmap.exr
- maps/m01_afterglow/map_lightmap.exr.import

当前 tree 中旧 root EXR 约 13.3 MB，而当前 baked EXR 约 16.8 MB；两套并存没有意义。

另有：

- maps/m01_afterglow/meshes/authored_props_mesh.res：当前代码搜索无引用，已被四个区域 props mesh 结构取代。
- tools/bake_m01.gd：旧直接 LightmapGI.bake 单图脚本，输出 baked/lightmap_gi.res，与当前生产插件路径不同。
- tools/run_bake.tscn：只服务旧 bake_m01。
- tools/finalize_bake_manifest.gd：单图、chapter1_1 report path、重复一套 coverage/manifest 写逻辑。
- authored/authored_input_hash.baseline：随 C13-04 移除。

### 18.2 删除前硬条件

不能凭文件名直接删。

WP 清理时先执行：

1. GitHub/本地文本引用搜索；
2. ResourceLoader dependency closure 检查；
3. 当前两张最终 scene 能加载；
4. BuildContract 输入集合不依赖候选；
5. 删除后 --headless --import + verify 全绿。

全部满足才删除。

### 18.3 保留

保留 build_bake_probe.gd + fixture：它是最小烘焙 API/UV2 诊断工具，不是生产平行路径。

保留本轮仍被 review/handoff 引用的 debug_sign_*、debug_grid_stats、sample_png_grid，除非后续单独证明完全无用。

### 18.4 为什么要在本章清

export_presets 使用 all_resources；即便 Godot 最终可能按过滤策略处理资源，旧大体积地图资源留在 maps 下仍会造成认知和发布风险。生产烘焙路径必须只有一个。

---

## 19. 正式场景构建总目标 — 把 m01_afterglow 做成 1.3 成品主场景

### 19.1 当前场景不是推倒重做对象

当前主场景已经具备可保留的骨架：

- generated 层已有 12 栋主要街道楼体（西侧 6、东侧 6），并有真实楼层尺度、窗格、店面、阳台/屋顶差异；
- 维修铺是明确的主地标，已有大橱窗、卷帘门、主招牌、雨棚、工具/轮胎/油桶、门口门户；
- 高架站已经形成街尾视觉终点，包含桥面、轨道、站台、雨棚、站牌和楼梯；
- authored 层已有 service court / station forecourt / roof terrace 三个空间；
- chapter1-2 已增加行道树、自行车棚、便利店外摆、夜宵摊、维修广场、晾衣生活区等静态叙事物；
- 当前街区有 7 个正式锚点；
- Backdrop 已有 22 个低模塔楼 + 西北信号塔；
- chapter1-1 的街区 6 机位曾完成一轮构图/可读性验收。

所以 1.3 的美术任务是**在既有空间关系上深化**，而不是换一张图、换一套世界观，或者用大量霓虹覆盖现有问题。

以下现有决定默认保留，只有截图证据证明退化才调整：

- 主街南北纵深和街尾高架站终点；
- 余晖维修作为主地标；
- service court 的拱门框景；
- roof terrace 的“生活前景 + 城市中远景”职责；
- station forecourt 的人眼高度站牌/阶梯/雨棚构图；
- 固定“雨停后的蓝调时刻”；
- 暖店内 / 冷环境 / 青色交通导视 / 橙色维修点缀的基础色语法；
- Mobile renderer + LightmapGI + 少量 Balanced 可选实时效果；
- strict single-active-map。

### 19.2 当前还不足以达到“真实赛博都市”的位置

这里不是把已有内容判为失败，而是定义从“合格成品街区”到“项目主视觉场景”之间的差距。

从当前构建代码能直接确认：

1. 主要楼体变化已经存在，但多数立面的二级/三级信息仍集中在窗格、店招、屋顶套件；外挂机电、楼层服务设施、检修层、线缆/桥架、消防/通信细节仍偏少。
2. “赛博”信息目前主要来自发光招牌、青色金属、共享滑板车牌和少量终端感小件；城市的**技术改造痕迹**还没有形成系统。
3. Backdrop 的 22 栋塔楼本质仍是随机长方体 + 3 种发光 facade 材质；远景有层次，但城市轮廓的建筑类型辨识度不足。
4. 当前材质体系以程序化 albedo + scalar roughness/metallic 为主，近景“材料响应差异”还能进一步加强；尤其 wet asphalt 当前带 metallic 值，不适合作为真实潮湿沥青的最终表现。
5. 已有生活细节是有效的，但部分街段仍主要靠均匀窗格/店招建立信息密度；缺少“旧建筑被新设备逐步加装”的垂直层。
6. 主街 PropsStreetEnrich 覆盖范围较大；继续把新小件全部堆进一个跨全街的大 mesh，会削弱 visibility range / 区域剔除价值。

因此正式构建的重点不是“再加更多随机小物”，而是建立**有层级的城市系统**。

### 19.3 1.3 艺术方向：滨海旧城上的复古未来改造层

目标不是高饱和“霓虹夜店街”，而是：

**真实旧城区 + 长期维修痕迹 + 近未来公共基础设施 + 克制的电子标识 + 雨后蓝调。**

画面分三层：

1. **城市本体层**：混凝土、砖、金属窗框、雨棚、排水、店铺、住居、站体，比例可信。
2. **改造技术层**：通信盒、传感器、充电桩、公共终端、电子导视、线缆桥架、外挂机电、检修灯、站务设备。
3. **生活痕迹层**：自行车、配送箱、晾衣、维修件、花盆、纸箱、摊车、座椅、垃圾/回收设施、墙面补丁。

“赛博感”主要由第 2 层和冷暖照明关系产生，不依赖把第 1 层全部做成发光表面。

### 19.4 视觉语言硬约束

- 单个主构图中，强发光文字/灯带应是焦点而不是背景噪声；不要让大部分建筑轮廓同时发光。
- 洋红/紫色不是本项目默认主色；如使用，只能是极小面积第三色点缀。
- 维修/生活区以暖橙、旧木、灰墙为主；站务/公共系统以青绿/冷白为主。
- 近景必须先靠实体厚度、接触、粗糙度和明暗成立，再靠 emissive。
- 不新增持续下雨、全屏扫描线、色差、SSR、体积雾等“赛博滤镜”掩盖场景。
- 城市应有安静暗面和无广告区域；没有留白就没有地标。

---

## 20. 正式场景制作架构 — 扩内容但不继续堆巨型脚本

### 20.1 generated / authored 的职责继续不变

generated 继续负责：

- 主街道路/建筑主量体；
- 基础店面；
- 维修铺主体；
- 高架站主体；
- 基础远景；
- 可重复基础材质。

authored 继续负责：

- 近景 hero detail；
- service court / station forecourt / roof terrace；
- 街区生活痕迹；
- 新增赛博基础设施；
- 最终构图精修。

不把 1.3 的美术新增全部塞回 build_m01 的基础建筑算法，也不让 assemble 变成内容生成器。

### 20.2 新增一个且只新增一个通用细节库

新增：

tools/m01_detail_lib.gd

职责是“可复用的小型静态构件”，不保存场景状态，不写文件。

第一批只实现真实会重复使用的 primitive：

- wall_conduit：墙面电缆/管束；
- cable_tray：桥架/线槽；
- service_box：配电/通信箱；
- vent_duct：方/圆风管与支架；
- ac_rack：2–4 台空调外机组合；
- utility_meter_bank：电表/水表组；
- lightbox_sign_frame：非文字灯箱结构；
- public_terminal：公共信息/支付终端；
- parcel_locker：快递/储物柜；
- charging_pedestal：轻型代步/维修充电柱；
- vending_bank：1–3 台售货机组合；
- rooftop_antenna：小型通信杆/天线阵列；
- service_railing：检修栏杆/小平台；
- pipe_bridge：跨墙/跨巷管线；
- hazard_marker：低成本警示条/编号牌载体。

只抽取真正重复的构件。某个物件只出现一次时直接留在对应 region builder，不为了“库化”再造抽象。

### 20.2.1 共享材质与室内边界

build_interior 会实际使用 street 共享库中的 wall_warm、wall_brick、sign_repair 等资源，窗外小景还使用 pavement/asphalt；因此“改街区材质”并不天然只影响 street。

1.3 默认策略：

- 已被 interior 实际 mesh surface 使用的基础共享 key 视为冻结接口；没有明确双图收益时不直接改它们。
- 街区近景需要更强表面差异时，优先新增少量 outdoor-only variant，例如 service/aged/painted 变体，并只分配给 street 建筑。
- asphalt_wet 的修正可以实施，但最终以 dependency closure 判断 interior 是否实际引用；若 interior scene 不引用该 surface，不产生 revision 影响。
- sign_repair 等真正双图共用视觉资产如修改，必须同时跑 interior 四机位回归，并按 §7.5 判断是否升 interior revision。
- BuildContract 应让真正被 interior scene 引用的共享材质/纹理自动进入 interior bake_input_hash；“脚本只是 load 了但 mesh 没用”不应被手工猜测成依赖。

这条边界优先于“为了统一风格顺手全库调 roughness”。

### 20.3 authored region mesh 重新分组

保留现有：

- PropsServiceCourt
- PropsStationForecourt
- PropsRoofTerrace

不再继续把所有新增主街细节塞入 PropsStreetEnrich。

将主街新增内容按实际可见区域分为最多 3 个区域 mesh：

- PropsStreetSouth：Z 约 18…58，便利店/维修铺/南段住商混合；
- PropsStreetMid：Z 约 -20…18，主街中心/侧巷入口；
- PropsStreetNorth：Z 约 -58…-20，高架站南侧/北段街面。

现有 PropsStreetEnrich 的物件在 1.3 实施时按坐标迁入上述三个 mesh；迁移后删除旧单体 PropsStreetEnrich，避免同时维护两套。

当前 G1/G6 等函数里的摆放点横跨多个 Z 区域，不能简单把“一个 G 函数 = 一个新 region”。迁移时将**摆放数据**按区域拆分，而不是复制一套生成逻辑：

- 通用几何 primitive 进 m01_detail_lib；
- 现有 _bike / _a_frame_board / _food_cart / _clothesline 等仍可保留为 authored 私有 helper，只有第二个区域真正复用时才上移；
- 每个新 region builder 只列本区 placements，并调用同一 helper；
- 禁止同一个 placement 同时出现在旧 G 数组和新 region 数组。

拆分属于 lightmap 结构变化：一个 PropsStreetEnrich 变成三个 MeshInstance3D，expected bake user paths 预计净增 2。当前历史 users=10/expected≈9 的固定数字从此失效；所有测试和文档必须以 manifest 的 expected/actual/missing 集合为权威，禁止写死“street 必须 users=10”。

拆分完成后先重烘焙，再用 7 个 Balanced 锚点与 art_baseline_v13 做像素/目检对照。由于 UV2 packing 会变化，“几何坐标没变”不能替代截图验证。

每个 region 都：

- 作为 detail_props；
- 在 region_manifest 中有 bounds；
- 有 Eco/Balanced 可见距离；
- 保持自身 MeshBuilder 合并，避免每个小物变一个节点。

### 20.3.1 Lightmap hint 与相机 exclusion

新 region mesh 默认 lightmap_size_hint=512×512，与现有 authored props 保持同量级。

只有 repair/station 等 Hero 区域在实际重烘后出现可见 texel 破碎、且 512 确认为根因时，才单独升到 1024；不把每个小物 region 都设 1024。

新 props 的 camera exclusion 继续采用“少量簇级 AABB”原则：

- 大型固定设备柜/储物柜/成组售货机等如果位于自由摄影可达路线并足以产生明显穿模，按整个功能簇加 1 个 exclusion；
- 小招牌、线缆、垃圾桶、单车等不逐物体加 AABB；
- 不给远景和屋顶不可达微细节加 exclusion；
- 新 exclusion 必须经过 7 锚点与自由摄影路线检查，避免为了防穿模反而把镜头通道封死。

Occluder 同样只用于建筑/大体量遮挡面，不为 L2/L3 小道具创建。

### 20.4 为什么不用大量 MultiMesh

当前新增量仍是几十到几百个低模构件，不是上万实例。

Godot 4.7 文档说明 MultiMesh 的实例是整批可见/不可见，不能对每个实例单独做常规屏幕/视锥剔除。因此本章只在“同一区域内数量明显很多、材质和 lightmap 需求允许”的物件上评估 MultiMesh；否则继续使用制作阶段按区域合并后的 ArrayMesh。

参考：

https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html

### 20.5 细节层级

每个正式区域遵循：

- L0：建筑/道路/站体主量体，永远存在；
- L1：雨棚、外挂机电、大招牌、平台、栏杆，构图必需；
- L2：公共终端、售货机、管线、箱柜、街具，Balanced/Eco 都保留，但可按合理距离裁；
- L3：小纸箱、工具、杯罐、线夹、贴纸等微细节，只进 detail_props，远距离裁掉。

不要把能决定轮廓/叙事的 L1/L2 误放进很短 visibility range。

---

## 21. 分区正式施工任务

### 21.0 新增前先做“已有物件占位审计”

正式添加每个区域前，先把 generated 与 authored 中已存在的物件列成一张 region inventory，避免“为了丰富”重复造同一功能。

当前已经明确存在的例子：

- repair plaza：generated 已有工具车、门外轮胎、长椅、花坛、围桩、串灯；authored G4 又已有 A 板、自行车架、油桶托盘、手推车。
- station：generated 已有指示牌/候车椅/导流柱；authored forecourt 又已有长椅、自行车架、排水沟、导流柱、邮筒。
- service court：已经有长椅、维修工具箱/油桶/木箱、花箱、壁灯、晾衣/水池/杂物架/猫窝。
- main street：已经有路灯、电杆、长椅、垃圾桶、消防栓、便利店配送箱与 chapter1-2 六组 enrich。

新增任务必须回答“它补的是哪个尚未表达的城市功能”，不能因为同类物件好做就继续叠加。

region inventory 作为 docs/chapter1_3/review.md 的制作记录，不需要另建运行时数据格式。

### 21.1 主街 — 从“有商铺的街”升级为“近未来旧城主轴”

保留现有建筑位置与 12 栋主要量体。

新增重点不是继续加楼，而是增加**立面纵深和城市系统**。

#### 建筑立面二级层

至少在 6 栋主视线建筑上做差异化处理：

- 2 栋：外挂机电架 + 成组空调机 + 冷凝排水管；
- 2 栋：外挑检修小平台/服务栏杆；
- 2 栋：竖向电缆槽 + 配电/通信盒；
- 至少 2 栋：屋顶增加通信杆、天线或水箱/设备体；
- 至少 3 栋：窗户加入卷帘、百叶、窗帘/半遮状态，不再所有窗同一逻辑；
- 重要街角增加建筑编号、维修标签或小型非发光铭牌。

不要求每栋都不同；要求人眼能识别 4–6 种“建筑被改造过的方式”。

#### 商业信息层

现有主招牌继续保留。

新增：

- 4–6 块小型垂直/侧挂 secondary signs；
- 2–3 块纯印刷/非发光价目/服务牌；
- 2 个公共区域编号/导视牌；
- 1 个街道信息终端；
- 1 组快递柜/智能储物柜；
- 1 组售货机，优先放在主街中段或站前过渡区。

约束：

- secondary sign 不得比“余晖维修”“霓湾站”更亮；
- 同一画面不要同时出现 10 块同权重招牌；
- 中文为主、英文为辅，继续使用项目内 Noto Sans SC；
- 不新增外部商业品牌。

#### 地面与街道系统

增加：

- 局部路缘编号/色带；
- 2–3 处更明确的排水沟/落水路径；
- 一处道路修补/检查井组合；
- 站前与人行过街位置加入有限触觉铺装/导向纹理；
- 维修铺附近增加“服务区/禁止堆放”地面标线；
- wet patch 只出现在低洼/排水附近，不均匀撒满全路。

目标：让地面看起来有市政逻辑，而不是纹理平面。

### 21.2 维修铺广场 — 全图第一近景 Hero Zone

现有 repair_shop_view 与 repair_shop_door 是最重要的人眼高度近景，不改其空间职责。

新增：

- 雨棚真实支架/排水链或落水管；
- 墙面电气盒、服务编号、摄像/传感器小件；
- 1 个充电/诊断柱，与维修主题对应；
- 1 组零件笼/废旧件架，放在不挡门户的位置；
- 卷帘门侧增加软管卷盘/消防/电源接口；
- 橱窗后工作台增加 2–3 个可读工具/零件剪影层；
- 广场地面增加轮胎/维修拖行痕和局部油污，但避免“脏贴纸铺满”；
- 门框、雨棚、招牌检查实体厚度和接触，继续遵守“贴墙 quad 必须离墙足够距离”的 v7 教训；
- 门扇摆动范围、repair_shop_door 视线、2.2m portal radius 内不得放新障碍。

色彩：

- 主暖色仍来自店内/余晖维修；
- 技术设备采用深灰 + 少量橙；
- 不在维修铺再加第二套强青色主招牌，避免抢主视觉。

### 21.3 主街中段与侧巷入口 — 形成“信息密度过渡”

当前主街到 service court 的空间已经连通。

新增：

- 侧巷口上方 1 组低密度线缆/桥架；
- 1 组通信/电表箱；
- 1–2 个墙面小风机/排气口；
- 垃圾/回收分类箱一组；
- 夜宵摊周边加折叠凳/收纳箱/菜单牌，不加人物；
- 巷道墙面继续用少量海报，但新增 1 个“旧海报撕除/贴补”层次；
- 落水管下方加强水痕和局部湿地联系。

这一区域的角色是从“主街商业”过渡到“后场生活”，不能亮度和招牌密度高于主街。

### 21.4 Service Court — 最强生活气息区

保留“拱门 → 湾流洗衣”的构图。

在当前洗衣、维修、小吃三个门面基础上增加：

- 洗衣门口公共洗衣推车/篮筐；
- 1 组储物柜/配送柜；
- 1 台旧式自动售货机或饮水机；
- 外墙管线、表箱、冷凝水排管；
- 北翼附楼增加服务梯/小检修平台中的一种；
- 晾衣区补少量衣夹/杆件逻辑，不增加高面数布料模拟；
- 现有猫窝、杂物架继续保留，不再额外“撒垃圾”；
- 拱门内只保留 1 个暖光焦点，湾流洗衣仍是视觉终点。

安静留白必须保留。广场中心至少留一块能让画面呼吸、也能供未来演员站位的空地。

### 21.5 Station Forecourt — 全图最强公共未来基础设施区

这是最适合强化“赛博城市”而不破坏生活区真实性的位置。

新增：

- 1 个公共信息/票务终端；
- 1 个时刻/方向电子牌，发光强度低于主站牌；
- 1 组站务配电/通信柜；
- 入口雨棚下 cable tray/灯具结构；
- 高架桥底增加少量检修梁、编号标识、管线；
- 应急电话/消防箱/维修门中的 1–2 类；
- 入口附近有限触觉铺装和排队导向；
- 自行车/轻型代步停放继续存在，但整理成明确停放系统；
- 售票亭增加门、檐口、服务窗细节，避免继续表现为大块墙盒；
- 站牌/公共系统统一青绿/冷白色语法。

不新增动态列车。远处轨道只需要结构和少量静态信号灯形成交通想象。

### 21.6 Roof Terrace — “人住在赛博城市里”而不是设备展览

现有桌椅、花箱、晾衣、设备箱全部保留。

增加：

- 小型通信天线/中继杆 1 组；
- 风向/天气传感器 1 个；
- HVAC 排气帽/短风管 2–3 个；
- 设备到楼梯间之间的 cable tray；
- 局部维护标线/设备编号；
- 仅 Balanced 开启的轻微 HVAC 蒸汽/暖气排气可占一个粒子名额。

不要用巨型全息广告占领屋顶。这里的核心是“居民生活 + 城市技术背景”的反差。

### 21.7 高架站与 Station View

现有站体轮廓已经成立，1.3 只补中景结构：

- 轨道侧增加少量固定件/检修走道轮廓；
- 雨棚边缘加排水沟；
- 桥面/支柱增加编号与警戒色小块；
- 站台远处可加入 2–3 个静态发光信息块形成尺度；
- 站下空间保持可读，不堆满设备。

station_view 的优先级是轮廓、基础设施尺度和城市远景，不需要让高位镜头看到每个近景小道具。

---

## 22. 远景与城市轮廓重构

### 22.1 当前问题

当前 Backdrop 的 22 栋建筑主要由随机宽/深/高 Box 组成，再分配 3 个 backdrop 发光材质。

它已经解决“世界尽头”问题，但不够表达一座有结构的近未来滨海城市。

### 22.2 保持低成本，改成 4 类远景 archetype

不把 22 增到 100。

改造为约 18–24 个主体，但从以下类型中生成：

1. residential_slab：宽而中高，屋顶水箱/机房，暖窗少量；
2. commercial_tower：有 1–2 次退台、冷色竖向窗带；
3. infrastructure_block：较低、宽、顶部大量设备/天线；
4. landmark_tower：仅 1–2 栋，轮廓不对称，有通信顶冠。

西北 signal tower 保留，并作为第五种特殊轮廓。

每个远景 archetype 仍使用低面数 Box/Cylinder 组合；不做完整窗框几何。

### 22.3 远景发光策略

当前 backdrop1/2/3 是整材质 emissive texture。

1.3 调整为：

- 建筑主体保持低亮度非发光/弱发光；
- 只有窗带/顶部标识/通信灯承担 emissive；
- 不让整栋楼像自发光塑料块；
- 不需要真实动态窗灯；
- 雾负责统一远景，不靠降低模型质量到纯剪影。

### 22.4 城市层次

street_view / roof_terrace_view / station_view 中至少形成：

- 近景：街具/栏杆/路沿；
- 中景：主街楼体/站体；
- 远中景：高架/商业塔；
- 远景：通信塔和 2–3 个高轮廓；
- 天空留白。

若新 skyline 让 station_view 或 roof_terrace_view 的主地标被吃掉，优先删背景体量，不要移动全部机位迁就背景。

---

## 23. 材质、表面与招牌正式精修

### 23.1 保留当前材料库主体

现有主材质：

- bluegray / warm / panel / brick；
- concrete；
- dark / teal / orange metal；
- asphalt / pavement / plaza / alley；
- wood / rubber；
- warm/cool emissive；
- shop glass / interior back；
- station steel；
- signs。

已经足够形成项目统一身份，不新建几十个近似材质。

### 23.2 修 wet asphalt 的物理语义

当前 asphalt_wet 通过 _tex_mat_dark 使用 metallic=0.22。

潮湿沥青不应靠金属度产生高光。

1.3：

- metallic=0；
- roughness 约 0.20–0.35，以实际截图决定；
- 颜色只略深；
- 通过湿区形状和烘焙/环境反差表现雨后，而不是镜面地板。

### 23.3 选择性增加 roughness/detail，而不是全材质 PBR 重做

允许新增少量制作纹理：

- asphalt_rough；
- pavement_rough；
- outdoor wall_grime/detail mask；
- metal_painted_rough；
- 可选 compact signage/utility atlas。

实现时优先让这些纹理服务 outdoor-only variant，不直接覆盖 interior 正在使用的 wall_warm/wall_brick/sign_repair 基础 key。StandardMaterial3D roughness texture 的通道/导入设置以 Godot 4.7 实际属性为准，并纳入 BuildContract 依赖；不凭名称假定通道。

尺寸以 512 为主，地面可 1024。

不要求 normal map 全覆盖。近景若通过几何厚度 + roughness 已成立，就不为“PBR 完整”强加法线贴图带宽。

### 23.4 Utility / decal atlas

新增一个小型原创 atlas，服务于静态 quad：

- 建筑编号；
- 检修标签；
- 高压/维修警示；
- 站务编号；
- 箭头/方向；
- 回收/公共设施图标；
- 贴补/旧标识。

不用 Godot Decal 节点堆满街区；直接在 authored mesh 中以少量 quad 贴在明确位置，继续参与正常区域 mesh 管理。

### 23.5 招牌层级

保留现有主品牌：

- 余晖维修；
- 霓湾站；
- 海风便利；
- 湾流洗衣；
- 岬角咖啡；
- 老巷面馆；
- 临港药房；
- 蓝鸟电器；
- 湾区旅社等。

新招牌原则：

- 新增 4–6 secondary business/service signs 即可；
- 至少一半非发光；
- secondary sign 字号与亮度明显低于主招牌；
- 不复制现实品牌；
- 继续走 gen_signs + 固定 Noto Sans SC；
- 生成后检查 mipmap 下远景闪烁和中文缺字。

### 23.6 透明材质边界

不把全街橱窗改成高成本真实透明玻璃。

继续采用：

- 浅景 interior box；
- 深色/低粗糙玻璃；
- 必要时单独小面积透明 surface。

Godot 3D 性能文档提醒透明物体需要按后到前排序，数量过多会增加成本；1.3 优先保持当前“低成本可读玻璃”策略。

参考：

https://docs.godotengine.org/en/latest/tutorials/performance/optimizing_3d_performance.html

---

## 24. 光照与氛围正式精修

### 24.1 固定色彩剧本

一张图只讲一个时间：

“雨停后 10–20 分钟的蓝调时刻”。

四个光色角色：

| 角色 | 色彩 | 用途 |
| --- | --- | --- |
| 冷环境 | 蓝灰 | 天空、阴影、远景 |
| 暖生活 | 琥珀/暖白 | 店内、维修铺、洗衣、摊位 |
| 公共科技 | 青绿/冷白 | 站务、导视、终端 |
| 服务警示 | 橙红 | 维修、消防、路障、小面积点缀 |

不要再新增一个与它们同权重的紫/粉主色体系。

### 24.2 LightmapGI 仍是主光照

Godot 4.7 的 Mobile renderer 支持 LightmapGI，LightmapGI 的运行时开销适合本项目这种静态场景；Mobile 对同一 mesh 的实时 Omni/Spot 数量有固定限制，因此新增视觉密度继续优先通过静态 bake 和 emissive，而不是大量实时灯。

参考：

https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html

### 24.3 静态灯布置原则

每个区域不是“每块招牌一个灯”，而是建立少量真实光池：

- repair plaza：主橱窗/雨棚暖光；
- main street：路灯 + 店铺内光，局部冷标识；
- service court：洗衣店 + 拱门/小吃摊；
- station forecourt：雨棚暖白 + 站务青色；
- roof terrace：生活小灯 + 城市反差。

烘焙完成后检查：

- 墙面接触不漂；
- 雨棚底不死黑；
- 强招牌不把周围墙体烧白；
- 青/橙光池有边界，不整区染色；
- 近景暗部仍能看出材料。

### 24.4 动态氛围预算

总预算仍遵守 AGENTS：

- 持续动画节点 ≤6；
- 粒子发射器 ≤2；
- Eco particles=false；
- Balanced particles=true。

优先候选：

1. 夜宵摊轻微蒸汽；
2. roof HVAC 轻微排气。

若现有 ambient 已占满 2 个 emitter，不新增第三个；先比较哪个对画面价值更高。

### 24.5 Glow

Balanced 的 glow 修复为真正生效后再调强度。

原则：

- Glow 用于灯牌和灯泡的光晕；
- 不用 Glow 把普通白墙变成亮块；
- Eco 关闭后，所有主招牌仍靠自身 albedo/emission 可读；
- 美术验收必须同时看 Eco，不能只以 Balanced bloom 画面判断。

---

## 25. 七个街区固定机位的 1.3 构图职责

锚点 ID 不变。允许小幅移动位置/look target，但任何调整必须有 before/after 证据，不能靠换机位隐藏缺陷。

| 锚点 | 1.3 构图目标 | 必须读到的层次 |
| --- | --- | --- |
| street_view | 全图主宣传构图 | 前景路沿/街具 → 两侧住商立面 → 高架站 → 远景塔楼 |
| repair_shop_view | Hero 近景 | 余晖维修招牌、雨棚厚度、橱窗/卷帘、维修道具、暖光池、技术服务件 |
| station_view | 高位基础设施构图 | 高架桥/站台轮廓、街区屋顶层、远景城市/信号塔 |
| repair_shop_door | 人体尺度与门户 | 小门清晰、门扇可读、入口不堵、墙面服务细节不过度 |
| service_court_view | 生活后场构图 | 拱门框景、湾流洗衣、管线/表箱、晾衣/推车、中心留白 |
| roof_terrace_view | “人住在未来城市” | 栏杆/桌椅/花箱前景、通信/HVAC 中景、城市远景 |
| station_forecourt_view | 公共未来城市构图 | 霓湾站牌、阶梯、雨棚、公共终端/导视、结构与天际线 |

### 25.1 Hero 三机位

以下三张作为 1.3 主视觉：

- street_view
- repair_shop_view
- station_forecourt_view

它们优先获得最高精细度和最后一轮构图时间。

### 25.2 评分

继续使用既有 6 项：

- 空间/比例；
- 几何/接触；
- 材质；
- 光照；
- 构图；
- 细节一致性。

硬失败：

- 任一单项 <2；
- 缺面/世界空洞；
- 明显 z-fighting；
- 主要中文招牌不可读；
- 近景物体悬浮/穿墙；
- 大面积无解释纯色盒；
- 发光整片过曝；
- 机位位于 exclusion 内。

项目原有合格线仍是 ≥14/18。

1.3 成品目标提高为：

- 7 个 street 锚点全部 ≥15/18；
- Hero 三机位目标 ≥16/18。

若某镜头只有 14/18，不能把它写成 1.3 美术完成；要修到 15 或在 review 中明确列为未完成项。

---

## 26. 场景性能预算与 HLOD 规则

### 26.1 先记录 post-fix 基线

C13-01…C13-17 修完、authored 去重完成后，在任何正式美术新增之前记录：

- generated static tris；
- generated props tris；
- authored static tris；
- 每个 authored region props tris；
- node count；
- Lightmap users；
- lightmap/texture video memory；
- expanded_v11 两档一轮基线；
- 7 锚点截图。

这套叫 art_baseline_v13。

后面所有美术比较都相对它，而不是相对 chapter1 旧 50-node 数据。

### 26.2 新增几何预算

默认预算：

- 1.3 新增 authored detail 净增 ≤15k triangles；
- 单个新 region props mesh 建议 ≤6k triangles；
- backdrop 重构不超过约 8k 新 triangles；
- 若某一 hero 改动明显超预算，先证明实际帧时间仍稳定再接受。

这些是控制线，不是为了少 1 个三角做微优化。

### 26.3 surface / material 控制

每个区域 mesh 优先复用已有 key。

1.3 新增独立材质 key 控制在约 6 个以内，不把每个招牌/设备做一个新 StandardMaterial。

### 26.4 Visibility range

所有 L2/L3 region props 设置 visibility range。

参考原则：

- Eco：45–60m；
- Balanced：65–100m；
- Hero 构图中会成为轮廓的 L1 不裁；
- 具体值以 7 锚点看不到 pop 为准。

Godot 4.7 提供手工 Visibility ranges/HLOD；当前已有 region detail range 机制，应继续利用而不是另建 LOD 框架。

参考：

https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html

### 26.5 实时负担不因“更赛博”增长

最终仍满足：

- Eco：0 optional probe、0 optional particle、0 runtime fill light；
- Balanced：≤2 probe、≤2 particle、≤2 runtime fill light；
- 主体光照全靠 baked LightmapGI；
- 不增加持续逐帧脚本到每个招牌/终端；
- 不新增动态大屏视频。

### 26.6 纹理/显存增长警戒线

art_baseline_v13 记录完成后，新增纹理与重烘焙带来的引擎估计 video-memory 峰值：

- 目标：不超过 baseline +25%；
- 若绝对增量先达到 +64 MiB，即进入强制调查，即使百分比尚未到 25%；
- 该指标是调查线，不单独作为 GPU 真显存判定，因为当前 Performance.RENDER_VIDEO_MEM_USED 本身是引擎估计值；
- Windows WorkingSet/PrivateBytes 仍由 sample_process.ps1 作为系统级主要证据。

纹理方面：

- 常规 utility/roughness/atlas 512；
- 大面积地面最多 1024 起步；
- 不新建 4K；
- 同类小标识优先 atlas，不一牌一纹理。

### 26.7 性能目标

最终正式数据以 §30 为准。

美术阶段的快速红线：

- Eco 正式 60s 路线 average_fps 目标 ≥29；
- Balanced 正式 60s 路线 average_fps 目标 ≥58；
- capped P95 应接近对应帧预算（Eco≈33.3ms、Balanced≈16.7ms）；若明显高于预算或 >100ms stutter 增长，必须定位，而不是只看平均 FPS；
- 最终性能不得比 art_baseline_v13 出现无法解释的持续退化；
- 发现连续掉帧先定位区域 mesh / transparency / real-time light / texture memory，再继续加内容；
- draw_calls monitor 在当前 Mobile 项目历史上口径偏低，不能单独作为真值；同时看 frame time、visible primitives、video memory 与 Windows 工作集。

---

## 27. 正式场景施工顺序与验收

### 27.1 施工顺序

工程修复完成后，严格按以下顺序做 m01_afterglow：

1. 记录 art_baseline_v13。
2. 拆分 PropsStreetEnrich → South/Mid/North，画面必须无变化。
3. 重构 backdrop archetypes，先只看 street/station/roof 三机位。
4. 主街 6 栋重点立面增加机电/通信/检修层。
5. repair plaza Hero pass。
6. station forecourt Public-Tech pass。
7. service court Life-Tech pass。
8. roof terrace Life-Tech pass。
9. 主街公共终端/快递柜/售货机/secondary signs。
10. 地面排水、标线、wet patch 逻辑。
11. 材质 roughness/detail 与 wet asphalt 修正。
12. utility/sign atlas 与 secondary signage。
13. 静态灯光重新平衡。
14. Balanced 动态氛围最多 2 emitter。
15. 七机位构图微调。
16. 全量重烘。
17. 7×2 截图 review。
18. 性能与内存。
19. 若性能不达标，优先减 L3/远景/透明，不删 Hero 必需层。
20. 最终两图回归与 Release。

### 27.2 每个区域使用“三级细节”验收

一个区域不能只靠“多几个盒子”算完成。

每个 Hero/正式区域至少有：

- 一级焦点：1 个，如维修铺/站牌/洗衣；
- 二级支撑：2–4 组，如公共终端、售货机、设备架、雨棚；
- 三级生活/维护细节：3–8 组，如箱子、编号、管线、排水、椅子。

三级细节不能均匀撒点，要围绕功能摆放。

### 27.3 before/after 证据

artifacts/chapter1_3/scene_review：

- baseline/：7 个 Balanced 锚点；
- pass_backdrop/：受影响 3 个锚点；
- pass_regions/：每区域主锚点；
- final/：最终 14 张 street 两档。

过程图不需要全部长期保留；最终 review 只提交能解释关键决策的代表图和最终图。

### 27.4 视觉 review 顺序

每轮不先看“赛博不赛博”，先检查：

1. 比例/穿模/厚度；
2. 主焦点；
3. 前中远层次；
4. 材质响应；
5. 光照可读；
6. 赛博技术层是否自然；
7. 生活逻辑；
8. 性能。

如果基础层失败，不允许靠新增发光牌继续“丰富”。

### 27.5 1.3 主场景完成标准

除了工程 H0–H10 外，新增两个场景门槛：

**H11 — 城市美术完整性**

- 7 个 street 锚点全部 ≥15/18；
- Hero 三机位目标 ≥16/18；
- 主要街景不再出现“连续大面纯盒 + 只有窗格/招牌”的最终立面；
- 至少 6 栋主视线建筑有明确不同的二级改造语言；
- main street / repair / service court / station / roof 五个功能区一眼可区分；
- 赛博技术元素能被识别，但强发光不淹没建筑；
- 远景至少有 4 类轮廓语言；
- Eco 仍然保留完整主题，不退化为无氛围版本。

**H12 — 场景性能与可维护性**

- 新增 detail 按 region 分组，不回到一个全图 giant props mesh；
- 新增静态 detail 净增默认 ≤15k tris，超出必须有性能证据；
- Balanced optional light/probe/particle 仍在原预算；
- expanded_v11 正式性能通过；
- 7 个锚点和自由摄影路线不出现明显 visibility pop；
- build_m01 / build_authored 不因 1.3 美术继续复制大量相同 primitive；重复构件通过 m01_detail_lib 收敛；
- 新材质/纹理都有真实画面用途，不保留未引用实验资产。

---

## 28. C13-18 — 最终证据格式

### 19.1 不再提交 verbose log 作为唯一证据

.gitignore 继续忽略 *.log。

不取消这个规则。

旧 docs 中对 regression_*.log、perf_street.log 的唯一引用要替换为结构化可提交摘要。

### 19.2 artifacts/chapter1_3

最终至少：

- verification_summary.json
- verification_summary.md
- bake_report_*.json
- screenshots/final/*.png
- screenshots/final/*.json
- performance/summary.csv
- performance/<run_id>/summary.json
- performance/process_<...>.csv
- export_check.md

临时过程截图/日志只有对排障有长期价值时才保留。

### 19.3 build_id

最终验收前设置统一 NEON_BUILD_ID。

优先：

- Git short SHA + rc 标识，例如 41aac56-rc1（真正实施时使用最终代码 SHA，不照抄此示例）。

CaptureService.setup 由 main 传：

OS.get_environment("NEON_BUILD_ID")

为空则 metadata 写 unknown，不伪造。

Benchmark 同样记录此值。

### 19.4 bake artifact 目录

移除 bake_plugin 的 chapter1_2 常量。

支持：

NEON_ARTIFACT_DIR

要求：

- 只允许 res://artifacts 下；
- 未设置时 fallback res://artifacts/build；
- build wrapper 在 chapter1-3 最终验收时设 res://artifacts/chapter1_3。

---

## 29. 最终截图验收

当前两图 capture list 为空，回落所有锚点。

当前 _shoot_anchors 末尾还尝试每档拍一张 “diag” 图，但 CaptureService 会隐藏 capture_ui，而 diagnostics 所在 CanvasLayer 正属于 capture_ui；因此这一步不会可靠得到“带诊断面板”的画面，只增加重复截图。chapter1-3 直接删除这段自动 diag 拍摄，不新增 include_ui 参数。F2 诊断用于人工查看，截图瞬间的客观渲染计数继续以 JSON render_stats 为准。

最终截图固定数量：

street：

- 7 anchors × Eco/Balanced = 14
- 合计 14 PNG + 14 JSON

interior：

- 4 anchors × Eco/Balanced = 8
- 合计 8 PNG + 8 JSON

总计：

- 22 PNG
- 22 同名 JSON

每个 JSON 必须含：

- map_id
- content_revision
- anchor_id
- profile_id
- effective_state
- image dimensions
- engine_version
- gpu_adapter
- build_id
- render_stats

任何缺一张都不允许 SHOOT_DONE 成功。

视觉重点：

- street 清重复几何后 7 机位无缺面/z-fighting/漏光；
- repair_shop_door 入口保持清晰；
- interior gallery_view 保持 chapter1-2 v9 已通过的三层构图；
- Eco/Balanced 不因质量链修复出现不可接受构图差异。

---

## 30. 性能最终验收

### 21.1 street

expanded_v11：

- Eco ×3 valid
- Balanced ×3 valid
- 每轮 warmup 15s
- steady 60s
- default occlusion=true

额外：

- 至少 Eco 或 Balanced 各做一轮 --occlusion off 对照；最好两档各一轮，报告不与正式默认轮混算。

### 21.2 interior

interior_v13：

- Eco ×3 valid
- Balanced ×3 valid
- warmup 15s
- steady 60s
- default occlusion=false

额外可做 on 对照，必须标实验覆盖。

### 21.3 外部进程采样

使用 sample_process.ps1。

至少保留四组代表性正式采样：

- street Eco
- street Balanced
- interior Eco
- interior Balanced

记录：

- WorkingSet64
- PrivateMemorySize64
- CPU 时间
- PID + process start time 防复用

不把引擎 MEMORY_STATIC 当 Windows 工作集。

### 21.4 正式输出正确性

每个 run.json/summary：

- map_id 与 route_map_id 一致；
- content_revision 正确；
- build_id 正确；
- measured profile 正确；
- frame_cap 是测量期值；
- render_scale 是测量期值；
- occlusion_enabled 是测量期值；
- VSync 是测量期值；
- restore 后用户状态另行验证，不写进 measured environment。

---

## 31. Windows Release / G6

### 22.1 构建

用当前最终 commit 从完整流水线：

generate → assemble → bake → verify → export

不得拿 chapter1-1 的旧 build 作为 1.3 证据。

### 22.2 独立目录

复制 EXE + PCK 到例如：

D:\霓湾 发布验证\Release Candidate\

要求：

- 路径包含中文；
- 路径包含空格；
- 不依赖项目目录 .godot；
- 不依赖 Python/Blender/网络。

### 22.3 人工检查

至少：

1. 启动进入 street；
2. 1–7 锚点；
3. Eco/Balanced 切换；
4. 维修铺门接近自动开；
5. F 进入 interior；
6. walk 上楼/下楼；
7. 1–4 室内锚点；
8. F 返回 street；
9. 至少 3 次双向门户往返；
10. F1/F2/F12；
11. 新建/加载/删除书签；
12. F12 生成 PNG+JSON；
13. 正常退出。

export_check.md 记录：

- build_id
- commit SHA
- exe/pck 文件大小
- SHA256
- 实际测试目录
- 每项 PASS/FAIL/NOT_RUN
- 失败现象

build/ 二进制继续不提交 Git。

---

## 32. 文档同步

代码与真实验收全部完成后再更新结论，不提前写 PASS。

更新顺序：

1. docs/chapter1_3/review.md（新增）
2. docs/handoff.md
3. docs/backlog.md
4. docs/environment.md
5. tools/README.md
6. README.md
7. docs/asset_sources.md（修正旧根 map_lightmap 路径）
8. AGENTS.md 仅修事实漂移，不扩大范围

明确修正：

- environment 中“导出模板为空”的过期状态；
- environment 中“系统字体制作、字体不随仓库”的旧描述；
- tools README 的“六机位”；
- tools README 的 chapter1_1 bake report 路径；
- README 指向不存在 perf_street.log；
- handoff/review 对被 gitignore 掉的 regression log 的唯一证据引用。

---

## 33. 实施工作包与严格顺序

### WP0 — 冻结基线，不改生产数据

产出：

- 记录当前 commit/tree；
- 记录两图 manifest；
- 记录真实 baked user_count；
- authored exclusions=29、8 组精确重复；
- generated exclusions=18、0 精确重复；
- 记录候选旧文件引用扫描；
- 建立 artifacts/chapter1_3 目录约定。

门槛：只记录，不修改。

### WP1 — BuildContract + manifest v2

涉及：

- 新增 tools/build_contract.gd
- assemble_m01.gd
- assemble_interior.gd
- verify_build.gd

先完成纯依赖/signature/coverage helper 和测试，再迁 manifest。

门槛：

- dependency closure 可解释；
- material/texture/import/mesh/light/settings 变化会改 hash；
- no-op 重建 hash 稳定；
- v1 不继承 succeeded。

### WP2 — Assemble/Bake 状态机

涉及：

- 两 assemble
- neon_bake plugin
- build_chapter11.ps1

门槛：

- assemble 不会产生“空 bake + succeeded”；
- bake 写空数据之前 manifest 已 running；
- missing/save/report/manifest 任一失败均 exit1；
- 成功时真实数据与 manifest 一致。

WP2 先用 build_bake_probe/受控 fixture 验证状态机，不把此阶段产生的 production bake 当最终证据。manifest v2 第一次正式生产重烘安排在 WP3 authored 去重之后，避免对同一 street 无意义烘焙两次。

### WP3 — Authored 去重 + ownership 保护 + 旧 baseline 移除

涉及：

- build_authored.gd
- build_chapter11.ps1
- 删除 authored_input_hash.baseline
- 记录 street revision_pending=1.3.0；本阶段不提前发布 1.3.0

然后 street 必须重建+重烘。

门槛：

- authored exact duplicates=0；
- 预计 authored exclusions=20、final street≈38；差异有解释；
- build_m01 前后 authored ownership hash 不变；
- 重烘 missing=0。

### WP4 — Runtime quality / occlusion / lifecycle 修复

涉及：

- settings_manager.gd
- map_root.gd
- main.gd
- map_manager.gd
- capture_service.gd

内容：

- 完整质量档实时应用；
- map occlusion；
- orphan timeout；
- preflight fail shell；
- capture abort。

门槛：T13 相关项全过，原 lifecycle 不退化。

### WP5 — Camera / bookmarks / registry / portals / automation

涉及：

- camera_controller.gd
- map_definition.gd
- map_manager.gd
- tool_ui.gd
- main.gd
- verify_build.gd

门槛：

- 1–9 key；
- capture anchors；
- bookmark revision；
- registry atomic；
- portal target anchor；
- automation fail-fast。

### WP6 — Benchmark 正确性 + interior route

涉及：

- benchmark_runner.gd
- perf_routes.gd
- main.gd

门槛：

- measured snapshot；
- headroom restore；
- settings file 不删除；
- warmup 单一权威；
- route-map mismatch 被拒；
- interior_v13 可跑。

### WP7 — 删除旧架构/死资产

仅在 WP1–WP6 全绿后。

候选删除：

- root old street map_lightmap.res/exr/import
- authored_props_mesh.res
- bake_m01.gd + uid
- run_bake.tscn
- finalize_bake_manifest.gd + uid
- authored_input_hash.baseline

门槛：引用/依赖扫描为空、import/verify 全绿。

### WP8 — 主场景结构与城市系统深化

前置：WP0–WP7 全绿；用修复后的真实代码先完成一次 street assemble+bake+verify，再记录 art_baseline_v13（7 个 Balanced 锚点 + 构建/网格/性能基线）。这次只作为美术 before，不作为最终 1.3 Release。

涉及：

- 新增 tools/m01_detail_lib.gd；
- PropsStreetEnrich 拆 South/Mid/North；
- backdrop 四类 archetype；
- 主街立面机电/通信/检修层；
- repair / service court / station / roof 分区内容；
- region_manifest 更新。

门槛：

- 拆分前后视觉不变；
- 新区域 mesh 都有 detail range；
- 主要构图没有新增穿模/遮挡；
- BuildContract 能正确把新增资源纳入 bake hash。

### WP9 — 主场景材质、灯光、招牌与构图终验

涉及：

- selective roughness/detail textures；
- wet asphalt 非金属修正；
- utility/sign atlas；
- secondary signs；
- baked lighting 重新平衡；
- ≤2 Balanced particles；
- 7 锚点微调与评分。

门槛：

- 7 锚点全部 ≥15/18；
- Hero 三机位目标 ≥16/18；
- H11/H12 通过；
- 冻结 street 几何/材质/灯光/锚点后才把 content_revision 升到 1.3.0；随后必须再跑 WP10 最终完整链。

### WP10 — 最终重建、双图视觉、性能、Release、人工巡走、文档

顺序不可交换：

1. clean import
2. generate both
3. assemble both
4. bake both
5. verify all
6. lifecycle/ch11/ch12/ch13
7. 最终截图
8. 性能
9. process sampling
10. export
11. 独立目录人工检查
12. 文档
13. 最终 Git clean 状态检查

---

## 34. tests/test_chapter13_contract.gd

新增一套 1.3 专用合同测试，不把原测试塞成巨型文件。

### 34.1 Build/manifest

| ID | 测试 |
| --- | --- |
| T13-01 | BuildContract dependency path 可解析普通与 UID::fallback |
| T13-02 | bake_input_hash no-op 稳定 |
| T13-03 | mesh/material/texture/.import 任一变化可导致签名变化（fixture） |
| T13-04 | expected⊆actual 时覆盖通过，actual 超集允许 |
| T13-05 | expected 有 missing 时失败 |
| T13-06 | manifest v1 不能复用 succeeded |
| T13-07 | manifest v2 只有 source roots+hash+expected+真实 data 全一致才能 reuse |
| T13-07b | assemble 不可复用分支必须先持久化 pending/stale，再允许覆盖 baked data |

### 34.2 地图数据

| ID | 测试 |
| --- | --- |
| T13-08 | street/interior exclusion 无精确重复 |
| T13-09 | anchor_names 唯一 |
| T13-10 | capture anchors 是 anchor_names 子集 |
| T13-11 | registry map_id 与 definition.map_id 一致、无重复 |
| T13-12 | 双向 portal target map + anchor 存在 |

### 34.3 运行时

| ID | 测试 |
| --- | --- |
| T13-13 | READY 图 Eco→Balanced→Eco 会改变地图内质量状态 |
| T13-14 | street→interior→street occlusion true→false→true |
| T13-15 | preflight invalid request 保留当前 camera/map/portal 合同 |
| T13-16 | orphan 收尾后同 path 不永久 busy |
| T13-17 | capture abort 最终 busy=false 且 guard 释放 |
| T13-18 | anchor index 7 可达，8/9 无目标安全 |
| T13-19 | bookmark current/stale/unknown revision 标签语义 |
| T13-20 | automation wait READY 可 timeout/failure，不永久 await |

### 34.4 Benchmark

| ID | 测试 |
| --- | --- |
| T13-21 | PerfRoutes route metadata 与 map_id 匹配/不匹配的纯合同 |
| T13-22 | measured snapshot 数据对象复制后不受后续 source Dictionary 变化影响 |
| T13-23 | output path traversal/run_id 路径字符拒绝 |

BenchmarkRunner.start_run 明确拒绝 headless，因此“真实 headroom 恢复、真实 measured Viewport 状态、settings.cfg 不被修改”不能伪装成 headless 单测。它们进入 WP10 的窗口化 integration smoke：

- Eco 用户状态 → Balanced headroom 5s → 退出后仍 Eco/30；
- Balanced 用户状态 → Eco headroom 5s → 退出后仍 Balanced/60；
- 每轮前后 settings.cfg SHA256 相同；
- run.json 中 measured_environment 是测量档，而不是恢复档。

为此 main 的开发自动化允许 --mode headroom 时接收 --duration 1..60；capped 仍固定 60，不开放缩短正式采样。

EditorPlugin 真烘焙本身同样不能用 headless 单元测试替代；其覆盖集合与状态判定由 BuildContract helper 测试，真实 editor bake 由 WP10 图形门槛验证。

---

## 35. 原有测试不得缩减

必须继续跑：

- tests/test_map_lifecycle.gd
- tests/test_chapter11_contract.gd
- tests/test_chapter12_contract.gd
- tests/test_chapter13_contract.gd

不得为了通过 1.3 删除旧断言或调低泄漏/状态机覆盖。

如果旧测试因正确接口迁移需要更新，只改调用方式，不降低语义。

---

## 36. 构建入口具体化

build_chapter11.ps1 保持统一入口，并深化以下能力：

### 参数

保留：

- GodotExe
- ProjectPath
- Stage
- MapId

新增可选：

- BuildId（默认优先 NEON_BUILD_ID；为空可尝试 Git short SHA；仍不可得则 local timestamp + 明确 local）
- ArtifactDir（默认 res://artifacts/build；最终验收传 res://artifacts/chapter1_3）

### validate

除现有检查外：

- Godot 4.7.2；
- registry 可解析；
- 两 quality JSON 可解析；
- Noto Sans SC source 存在；
- build contract helper 可加载；
- export preset 存在；
- MapId 与 registry 一致。

### generate

所有调用的 required output Error 必须向 PowerShell 的非零 exit 传播；DONE marker 只是附加证明，不能替代 exit code。

MapId=both 的顺序必须改为“共享输入先稳定、street 先、interior 后”。当前脚本先 build interior、后 build_m01，而 build_interior 会加载 assets/m01_afterglow/materials，build_m01 又会重建这些共享材质；这个顺序会让一次完整构建依赖上一次提交中已有材质状态。

MapId=both：

- gen_textures
- import
- gen_signs
- import
- authored ownership prehash
- build_m01（同时把共享材质更新到本轮状态）
- authored ownership posthash + assert unchanged
- build_authored
- build_interior（此时读取的共享材质已是本轮最新）
- import

MapId=m01_afterglow：

- gen_textures → import → gen_signs → import → ownership prehash → build_m01 → posthash → build_authored → import

MapId=m01_repair_interior：

- 只 build_interior + import，但 Step-Validate 必须先确认其依赖的已提交共享 materials/textures/signs 全部存在；
- 如果本轮同时修改了共享材质/招牌生成规则，必须使用 MapId=both，不允许只跑 interior 并声称全量重建完成。

### assemble

- 调对应 assemble；
- import；
- 不主动 bake。

### bake

- 为每 map 调 editor plugin；
- 要求 NEON_BAKE_EXIT；
- 非零即停；
- report 放 ArtifactDir。

### verify

- verify_build（registry/指定 map）
- lifecycle
- ch11
- ch12
- ch13

### export

Stage=export 不能假设调用者刚跑过 verify。独立 export 入口必须先执行完整 Step-Verify（verify_build + lifecycle + ch11/ch12/ch13），全部通过才允许 Godot --export-release。

Stage=all 继续严格顺序；进入 export 时可复用本次 all 中刚完成的 Step-Verify 结果，避免同一进程脚本重复跑两遍，但实现上必须保证不存在“直接 export 跳过门槛”的路径。

---

## 37. 最终命令矩阵

以下命令是实施完成后的目标入口，实际 $G 路径按环境传入。

构建：

PowerShell: .\tools\build_chapter11.ps1 -GodotExe $G -ProjectPath . -Stage all -MapId both -BuildId <id> -ArtifactDir res://artifacts/chapter1_3

只验证：

Godot: --headless --path . --script res://tools/verify_build.gd

测试：

Godot: --headless --path . --script res://tests/test_map_lifecycle.gd  
Godot: --headless --path . --script res://tests/test_chapter11_contract.gd  
Godot: --headless --path . --script res://tests/test_chapter12_contract.gd  
Godot: --headless --path . --script res://tests/test_chapter13_contract.gd

截图：

Godot window: --path . -- --shoot --map m01_afterglow --quality both  
Godot window: --path . -- --shoot --map m01_repair_interior --quality both

性能：

Godot window: --path . -- --perf --map m01_afterglow --route expanded_v11 --quality both --runs 3 --warmup 15  
Godot window: --path . -- --perf --map m01_repair_interior --route interior_v13 --quality both --runs 3 --warmup 15

occlusion 对照：

street route + --occlusion off  
interior route + --occlusion on

所有自动化失败必须非零退出。

---

## 38. 最终验收门槛 H0–H12

### H0 — 仓库与构建输入

PASS：

- clean checkout 可 import；
- 生产 registry 两图有效；
- BuildContract 能完整计算；
- no-op hash 稳定。

### H1 — Bake 状态机

PASS：

- assemble 不产生“空 data + succeeded”；
- bake 开始前磁盘 manifest 已 running；
- failed 不保留 succeeded；
- 成功时 expected 非空、actual 非空、missing=0；
- scene save、manifest、report 写失败不能成功。

### H2 — Authored 唯一性

PASS：

- station forecourt 静态生成一次；
- authored exclusion 精确重复=0；
- SC_ANNEX 只有一个权威 exclusion；
- build_m01 不修改 authored ownership；
- street r1.3.0 重烘成功。

### H3 — Verify 纯度

PASS：

- verify 前后 Git tracked files hash 不变；
- verify 不创建/更新 baseline；
- stale/missing/坏 portal 都能非零失败。

### H4 — Runtime quality

PASS：

- Eco/Balanced 完整生效；
- street occlusion true；
- interior false；
- map switch 与 quality switch 不覆盖地图默认；
- effective_state 是实际状态。

### H5 — 生命周期/错误路径

PASS：

- 双图 ×10 active_map_root ≤1；
- 资源弱引用回收；
- timeout orphan 可收尾；
- preflight fail 保留 READY 图；
- activation fail 回 EMPTY；
- capture abort 不锁死 guard。

### H6 — 摄影/UI

PASS：

- street 1–7；
- interior 1–4；
- UI 数字提示真实；
- capture_anchor contract 生效；
- current bookmark 不误标，旧 revision 有提示；
- 所有 final PNG 与 JSON 一一对应；
- 自动化不再生成名为 diag 但实际隐藏诊断层的重复截图，render_stats JSON 是截图时诊断权威。

### H7 — Benchmark 正确性

PASS：

- route/map 强校验；
- measured state 在 restore 前冻结；
- headroom 完整恢复；
- settings.cfg 前后不变；
- warmup 没有双重计时；
- run output build_id/revision/profile/occlusion 正确。

### H8 — 性能数据

PASS：

- street expanded_v11 Eco/Balanced 各 3 valid；
- interior_v13 Eco/Balanced 各 3 valid；
- occlusion 对照单列；
- 至少四组代表性 Windows 进程采样；
- 不使用截图瞬时 FPS 当稳态结论。

### H9 — Windows Release

PASS：

- 当前 1.3 全管线后导出；
- 中文+空格独立路径；
- 双图门户至少 3 往返；
- 楼梯/锚点/quality/bookmark/F12 正常；
- export_check 有 hash 与结果。

### H10 — 文档与证据

PASS：

- final artifacts 可追溯同 build_id；
- README/handoff/backlog/environment/tools README/asset_sources 与实际一致；
- 不再把不存在的 *.log 作为唯一证据；
- NOT_RUN 如实保留，绝不伪写 PASS。

### H11 — 城市美术完整性

PASS：

- 7 个 street 锚点全部 ≥15/18；
- street_view / repair_shop_view / station_forecourt_view 三个 Hero 机位目标 ≥16/18；
- 至少 6 栋主视线建筑具有可辨识的二级改造语言（机电/通信/检修/窗态/屋顶设施）；
- main street、repair plaza、service court、station、roof terrace 五区功能和视觉语言可区分；
- Backdrop 至少 4 类轮廓语言，且不抢主地标；
- Eco 关闭 glow/particles 后仍保留赛博城市身份和主构图；
- 无主要中文招牌缺字、过曝成白块、近景埋墙、明显穿模或世界空洞。

### H12 — 场景性能与可维护性

PASS：

- PropsStreetEnrich 已按 South/Mid/North 或等价 20–40m 区域拆分，旧 giant mesh 不再作为新增细节容器；
- bake user 数不写死历史 10；manifest expected/actual/missing 能正确覆盖拆区后的新节点集合；
- 新增 detail 都有明确 region / visibility range；
- 1.3 新增 authored detail 默认净增 ≤15k triangles；超出时有实际性能证据与 review 说明；
- video-memory 相对 art_baseline_v13 的增长没有越过 §26.6 警戒线而未解释；
- optional runtime light/probe/particle 不超过既有预算；
- expanded_v11 两档正式性能与 Windows 工作集采样通过；
- 重复赛博小构件由 m01_detail_lib 收敛，没有继续复制大量同形函数；
- 未引用实验材质、纹理、旧区域 mesh 在最终提交前清理。

---

## 39. 文件级变更清单

### 新增

- tools/build_contract.gd
- tests/test_chapter13_contract.gd
- docs/chapter1_3/review.md（最终验收时）
- artifacts/chapter1_3/ 下结构化结果

### 修改

- addons/neon_bake/bake_plugin.gd
- tools/assemble_m01.gd
- tools/assemble_interior.gd
- tools/gen_lib.gd
- tools/build_m01.gd
- tools/build_authored.gd
- tools/build_interior.gd
- 新增 tools/m01_detail_lib.gd
- tools/gen_textures.gd
- tools/gen_signs.gd
- tools/verify_build.gd
- tools/build_chapter11.ps1
- scripts/app/settings_manager.gd
- scripts/app/main.gd
- scripts/app/camera_controller.gd
- scripts/app/tool_ui.gd
- scripts/app/capture_service.gd
- scripts/maps/map_definition.gd
- scripts/maps/map_manager.gd
- scripts/maps/map_root.gd
- scripts/diagnostics/benchmark_runner.gd
- scripts/diagnostics/perf_routes.gd
- 受上述生成器影响的 map_definition / map / authored / manifest / baked 产物
- README.md
- tools/README.md
- docs/handoff.md
- docs/backlog.md
- docs/environment.md
- docs/asset_sources.md
- 必要时 AGENTS.md 只修事实

### 条件删除

- maps/m01_afterglow/map_lightmap.res
- maps/m01_afterglow/map_lightmap.exr
- maps/m01_afterglow/map_lightmap.exr.import
- maps/m01_afterglow/meshes/authored_props_mesh.res
- maps/m01_afterglow/authored/authored_input_hash.baseline
- tools/bake_m01.gd
- tools/bake_m01.gd.uid
- tools/run_bake.tscn
- tools/finalize_bake_manifest.gd
- tools/finalize_bake_manifest.gd.uid

删除必须满足 §18.2 的引用与依赖门槛。

---

## 40. 风险与回滚

### R1 — manifest v2 首次强制重烘

这是预期迁移成本。不能为了省一次 bake 继承 v1 succeeded。

### R2 — authored 去重改变 lightmap packing

只做已确认重复清理，不同时进行大规模美术重做。用 chapter1-2 最终截图作视觉对照。

### R3 — Balanced 真正完整生效后性能/观感变化

若新启用的 particle/probe/fill light 成本不值得，应修改 data/quality/balanced.json，而不是让运行时代码偷偷不应用配置。

### R4 — interior occlusion=false 后数据与旧报告不同

新数据才是定义真实状态。旧数据作为历史，不冒充 1.3。

### R5 — dead asset 删除误伤

严格执行引用搜索 + ResourceLoader dependencies + clean import + verify；任一不确定先保留。

### R6 — BuildContract 过度敏感导致无谓 rebake

先保证“不漏变化”，再通过负例/no-op 测试缩小非语义噪声。不能为了减少 bake 把真实材质/纹理依赖排除。

### R7 — “赛博化”变成霓虹堆砌

处理：

- 每轮先看建筑/基础设施/生活逻辑；
- 强发光只保留主焦点；
- station 承担最高科技密度，service court/roof 保持生活气息；
- Eco 关闭 glow 后仍必须成立。

### R8 — 细节增加导致 region mesh 再次跨图巨大化

处理：

- PropsStreetEnrich 在正式加内容前先拆区；
- 每个新增区域只合并本区内容；
- 不为减少 node count 把不同街段重新拼成一个 mesh。

### R9 — 远景升级抢主地标

处理：

- skyline 先只在 street/station/roof 三机位审；
- 背景只服务轮廓层次；
- 与余晖维修、霓湾站、signal tower 争焦点的背景体量优先删除/降亮。

---

## 41. 完成状态定义

Chapter 1.3 只有同时满足以下条件才算完成：

1. 两张地图仍严格单活动；
2. 构建和烘焙只有一套生产权威；
3. manifest v2 能证明 bake 输入与真实数据一致；
4. verify 完全只读；
5. authored 重复几何/exclusion 已清；
6. Eco/Balanced 与地图 occlusion 真实生效；
7. Benchmark 报告记录的是测量期而非恢复后状态；
8. automation 不会永久等待或静默跳过失败；
9. street 7 / interior 4 锚点用户接口真实；
10. capture anchors、portal target、bookmark revision 都有明确合同；
11. timeout orphan、capture abort 等失败路径不会留下永久 busy；
12. 旧烘焙脚本/旧 lightmap/死 mesh 在确认无引用后清理；
13. m01_afterglow 已完成 §19–§27 的正式赛博都市场景深化，不只是工程修复；
14. 7 个 street 锚点全部达到 1.3 成品评分门槛，Hero 三机位达到目标；
15. 新增细节按区域分组且性能/HLOD 有效，没有回到 giant props mesh；
16. 最终 22 PNG + 22 JSON、双图性能、进程采样、Windows Release、人工门户巡走都有证据；
17. 文档与仓库当前事实一致；
18. 没有为了本章新增未来功能空框架。

完成本章后，项目才适合继续增加下一张地图或进入摄影工作台阶段。
