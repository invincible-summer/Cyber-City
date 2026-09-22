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

本章目标不是新增功能，而是让以下四件事都变成可证明事实：

1. 构建状态可信：任何影响 Lightmap 的输入变化都能让旧烘焙失效；任何漏烘焙都不能被标记成功。
2. 运行时状态可信：Eco/Balanced、地图级 occlusion、错误请求、截图、benchmark 的实际状态与报告一致。
3. 自动化可失败：坏地图、截图失败、benchmark 路线不匹配、烘焙缺失都必须非零退出，而不是卡住或静默跳过。
4. 发布证据可信：最终截图、性能、双图生命周期、Windows Release 与人工巡走都能从仓库中的结构化证据追溯到同一 build_id。

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
- 写 manifest；
- 启动 bake；
- 修改地图；
- 运行测试。

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
| bake_input_hash | 唯一的“是否可复用旧 bake”输入签名 |
| bake_input_files | 排序后的输入文件与各自 sha256，便于审计 |
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
3. 计算 manifest v2 bake_input_hash。
4. 读取上一 manifest + 已有 baked/map_lightmap.res；baked data 必须通过 BuildContract.load_resource_fresh 读取。
5. 判断 can_reuse_bake。
6. 若可复用，把 fresh-load 后验证通过的已有 LightmapGIData 绑定到当前 LightmapGI。
7. 若不可复用，才创建空 LightmapGIData，并把 manifest 置 stale/pending。
8. pack/save map.tscn。
9. 写 manifest v2。

can_reuse_bake 必须同时满足：

- 前一 manifest schema_version=2；
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
5. **先原子写 manifest：bake_status=running、job_id、本轮 expected、actual=[]、missing=[]。**
6. manifest 写成功后，才允许覆盖 baked/map_lightmap.res 为新空数据。
7. 空数据保存成功后，用 CACHE_MODE_REPLACE_DEEP/fresh-load 重新绑定 LightmapGI，确认 user_count=0；不能让 ResourceLoader cache 中的旧数据继续挂在节点上。
8. 触发编辑器 Bake Lightmaps。
9. 等实际 user_count 稳定。
10. 计算 actual/missing。
11. missing 为空才继续。
12. EditorInterface.save_scene()，检查返回 Error。
13. 再次从磁盘/scene fresh-load 必要状态做终检。
14. 原子写 manifest succeeded + expected/actual/missing=[] + finished time。
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
- 读取 manifest v2；
- 重新算当前 bake_input_hash；
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

### 7.5 revision

street 实际几何与 lightmap 输入改变：

m01_afterglow content_revision：1.2.0 → 1.3.0

interior 若本章不改几何/锚点/walk surface：

m01_repair_interior 保持 1.2.0

不要为了章节号整齐无意义地让室内书签全部过期。

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

把请求收尾集中到一个幂等 finish helper：

- 恢复 UI；
- 恢复 camera input；
- 释放 guard token；
- _busy=false；
- _request_id=0；
- 成功时 emit completed；
- 失败/取消时 emit failed 一次。

abort 保存 cancel reason，下一继续点走统一 ERR_CANCELED 失败收尾。

不要在多个 return 分支分别手工清 busy/token。

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

## 19. C13-18 — 最终证据格式

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

## 20. 最终截图验收

当前两图 capture list 为空，回落所有锚点。

最终截图固定数量：

street：

- 7 anchors × Eco/Balanced = 14
- 每档 1 张 diag = 2
- 合计 16 PNG + 16 JSON

interior：

- 4 anchors × Eco/Balanced = 8
- 每档 1 张 diag = 2
- 合计 10 PNG + 10 JSON

总计：

- 26 PNG
- 26 同名 JSON

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

## 21. 性能最终验收

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

## 22. Windows Release / G6

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

## 23. 文档同步

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

## 24. 实施工作包与严格顺序

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

### WP2 — Assemble/Bake 原子状态机

涉及：

- 两 assemble
- neon_bake plugin
- build_chapter11.ps1

门槛：

- assemble 不会产生“空 bake + succeeded”；
- bake 写空数据之前 manifest 已 running；
- missing/save/report/manifest 任一失败均 exit1；
- 成功时真实数据与 manifest 一致。

### WP3 — Authored 去重 + ownership 保护 + 旧 baseline 移除

涉及：

- build_authored.gd
- build_chapter11.ps1
- 删除 authored_input_hash.baseline
- street revision 1.3.0

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

### WP8 — 最终重建、视觉、性能、Release、人工巡走、文档

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

## 25. tests/test_chapter13_contract.gd

新增一套 1.3 专用合同测试，不把原测试塞成巨型文件。

### 25.1 Build/manifest

| ID | 测试 |
| --- | --- |
| T13-01 | BuildContract dependency path 可解析普通与 UID::fallback |
| T13-02 | bake_input_hash no-op 稳定 |
| T13-03 | mesh/material/texture/.import 任一变化可导致签名变化（fixture） |
| T13-04 | expected⊆actual 时覆盖通过，actual 超集允许 |
| T13-05 | expected 有 missing 时失败 |
| T13-06 | manifest v1 不能复用 succeeded |
| T13-07 | manifest v2 只有 hash+expected+真实 data 全一致才能 reuse |

### 25.2 地图数据

| ID | 测试 |
| --- | --- |
| T13-08 | street/interior exclusion 无精确重复 |
| T13-09 | anchor_names 唯一 |
| T13-10 | capture anchors 是 anchor_names 子集 |
| T13-11 | registry map_id 与 definition.map_id 一致、无重复 |
| T13-12 | 双向 portal target map + anchor 存在 |

### 25.3 运行时

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

### 25.4 Benchmark

| ID | 测试 |
| --- | --- |
| T13-21 | route-map mismatch 拒绝 |
| T13-22 | measured_environment 在 restore 前冻结 |
| T13-23 | headroom 恢复后 Eco 仍为 30、Balanced 仍为 60 |
| T13-24 | output path traversal/run_id 路径字符拒绝 |
| T13-25 | benchmark 前后 settings.cfg 内容 hash 不变 |

EditorPlugin 真烘焙本身不能用 headless 单元测试替代；其覆盖集合与状态判定必须由 BuildContract 纯函数测试，真实 editor bake 由 WP8 图形门槛验证。

---

## 26. 原有测试不得缩减

必须继续跑：

- tests/test_map_lifecycle.gd
- tests/test_chapter11_contract.gd
- tests/test_chapter12_contract.gd
- tests/test_chapter13_contract.gd

不得为了通过 1.3 删除旧断言或调低泄漏/状态机覆盖。

如果旧测试因正确接口迁移需要更新，只改调用方式，不降低语义。

---

## 27. 构建入口具体化

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

只有 verify 已单独通过并不代表当前命令调用一定执行过 verify；因此 Stage=export 仍至少跑轻量 pre-export verify_build，避免导出 stale bake。

Stage=all 继续严格顺序。

---

## 28. 最终命令矩阵

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

## 29. 最终验收门槛 H0–H10

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
- 所有 final PNG 与 JSON 一一对应。

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

---

## 30. 文件级变更清单

### 新增

- tools/build_contract.gd
- tests/test_chapter13_contract.gd
- docs/chapter1_3/review.md（最终验收时）
- artifacts/chapter1_3/ 下结构化结果

### 修改

- addons/neon_bake/bake_plugin.gd
- tools/assemble_m01.gd
- tools/assemble_interior.gd
- tools/build_authored.gd
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

## 31. 风险与回滚

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

---

## 32. 完成状态定义

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
13. 最终 26 PNG + 26 JSON、双图性能、进程采样、Windows Release、人工门户巡走都有证据；
14. 文档与仓库当前事实一致；
15. 没有为了本章新增未来功能空框架。

完成本章后，项目才适合继续增加下一张地图或进入摄影工作台阶段。
