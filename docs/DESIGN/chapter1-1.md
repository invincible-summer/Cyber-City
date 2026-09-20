# Chapter 1.1 — 余晖街区：空间扩展、场景精修与低负担交付

> 项目：霓湾 / Neon Haven  
> 文档版本：1.0 · 2026-09-20  
> 使用方式：让 Coding Agent 先读仓库实际 `AGENTS.md`、本文件、现有 `README.md` 与 `docs/handoff.md`，然后逐工作包实施。  
> 本章是第一阶段的完整升级工作单，包含地图扩展、美术精修、工具体验、性能优化、必要修复和独立发布。可跨多个每日约 6 小时的工作窗口完成。

## 0. 执行原则与证据边界

本章基于用户上传的第一阶段 `chapter1.md`、当前 `README.md` 以及第一阶段完成报告制定。规划时没有取得完整源码、原始性能 CSV、真实场景截图，因此以下接口属于**需要实现或适配的目标合同**，不宣称仓库已经具有相同类名、签名和节点路径。

你必须先检查实际代码，建立接口映射，再增量修改。已有实现满足合同时直接复用；只有行为不满足时才改动。不得为了匹配本文命名重建整个工程。用户希望降低开发歧义；本文件通过明确接口、迁移规则和验收门槛实现这一点，实际无错误运行仍须编译、图形检查和目标设备验证。

当前用户明确授权 1.1 扩展和优化 M01。以下新增内容覆盖旧章节“只有三个机位/固定首版尺寸”等阶段性限制：六个固定机位、三个扩展区域、相机书签、资源制作流程升级。以下约束继续有效：Godot 4.7.2 标准版、Mobile 渲染器、单活动地图、离线运行、无 NPC/玩法、经济档优先。

如旧 `AGENTS.md` 与本章新增范围冲突，在本轮只更新其与 1.1 直接相关的条目，记录差异；不要用旧的阶段范围阻止已经授权的新工作。保留第一阶段设计和报告作为历史记录。

本章交付条件同时包含内容、美术、工程、性能和发布。只有修复测试、增加统计脚本或完成灰盒，均不能宣布 1.1 完成。

## 1. 最终成果与阶段范围

### 1.1 用户可见成果

1. M01 从首版街景成长为包含主街、维修铺、生活广场、站前空间和屋顶露台的完整街区。
2. 三个原机位保留，新增三个机位；至少能获得六幅构图不同的完整画面。
3. 建筑有可信尺度和接触关系，近景有材质、结构与生活细节；经济档也保持主要美术质量。
4. 自由观察更顺手，支持保存少量摄影书签，截图附带可复现的相机与画质信息。
5. 性能报告分清帧率达标、实际计算耗时和系统资源占用；默认运行继续限帧和后台节流。
6. 制作流程可重复，生成不覆盖精修，烘焙不会误用旧结果，Windows 发布包可以独立运行。

### 1.2 本章不做

- 第二张正式地图；极小 B 测试地图继续保留为测试夹具。
- NPC、玩家角色、对话、物品交互、战斗、任务、车辆 AI、经济或居民模拟。
- 无缝大世界、运行时造城、地图内资源流式系统、动态昼夜、持续降雨和积水模拟。
- 完整导演时间轴、演员、配音或视频剪辑。可以保存书签和播放固定验收镜头，不开发通用拍片平台。
- 引擎迁移、自研 ECS、原生扩展、云服务、运行时 LLM。

### 1.3 范围级别

| 级别 | 含义 | 处理方式 |
| --- | --- | --- |
| 必做 | 本章明确列出的三处扩展、六机位、核心精修、接口、验收 | 不得因时间到期偷偷删除；跨天继续 |
| 按证据实施 | 遮挡剔除、局部 MultiMesh、额外探针、可见距离调整 | 只保留有实测价值且无视觉缺陷的改动 |
| 可选 | 少量背景音、额外摆件、非必要装饰动画 | 必做项通过后再评估；不计入完成门槛 |

## 2. 当前事实与第一轮审计

### 2.1 输入资料能确认的情况

| 已有内容/报告 | 1.1 处理 |
| --- | --- |
| M01、主场景、摄影机、两档画质、截图、地图管理器 | 检查并复用 |
| 13 栋建筑、22 个远景塔、约 6.1 万三角形、程序化纹理 | 视为报告值，先核对实际资产和统计口径 |
| 第一阶段 30/60 FPS、显存估计 161–227 MiB、暖加载 626 ms | 保存为旧报告，不等同于新版本基准或功耗结论 |
| Windows 导出模板缺失，导出预设尚未创建 | 创建预设并完成匹配模板下的 Release 验证 |
| 工作集等系统指标为 N/A | 增加进程级采样；不可用时明确原因 |
| 系统字体栅格化招牌 | 固定可再分发的制作字体、版本、来源及许可 |
| 编辑器插件 `addons/neon_bake`，自定义 `--auto-bake` | 审查现有调用方式与完成条件，再增强 |
| 报告说生命周期测试 5 轮 | 核对是否完整 A→B→A；达到 10 次完整往返 |
| 无直接视觉审核 | 增加真实图像检查；像素统计仅为辅助 |

### 2.2 审计输出

创建 `docs/chapter1_1/code_map.md`，记录下列职责的实际文件、类、方法、信号、资源格式及调用方：MapManager、地图根、MapDefinition、质量设置、相机、截图、基准脚本、城市生成脚本、烘焙插件、UI、导出设置。

每项标注“复用 / 兼容适配 / 需要新增”，并与本文第 7–10 节目标接口对应。若现有质量配置是 JSON，则保留 JSON；不为了示例改成 `.tres`。同一份配置只允许一个权威存储来源。

同时完成：

- 保存基线提交 ID、引擎实际 `--version`、硬件/驱动/供电状态；未知项明确标记。
- 检查用户未提交修改，不覆盖。建立本地 `chapter1-1` 工作分支或等价独立工作区；不推送。
- 保存三个原机位的坐标、朝向、FOV、曝光、窗口尺寸和两档截图；可观察的动态效果固定在相同时间。
- 复核旧测量采样代码。无效数据留作历史但标记原因，不用于性能对比。
- 先做一轮原版 Release 导出尝试，尽早暴露导出资源缺失；不是等全部美术完成再首次导出。

阶段门槛 G0：代码映射、基线截图、现有问题清单齐备；无法获取图像时保留待验收状态，其他工作继续。

## 3. 地图扩展：三处新空间与三个原空间升级

### 3.1 空间边界

保持 `map_id = m01_afterglow`。全部新区域属于同一张地图，不在区域之间复制应用外壳，也不变相加载 M02。

原设计核心为约 120×160 米。1.1 的设计上限扩展为约 **160×200 米**，并非必须填满。保持城市比例与原点附近坐标；优先利用现有空地和边缘，不平移/缩放全部旧建筑。

规划坐标仍为 X 东西、-Z 北、Y 向上，单位米。下表坐标依据 chapter1 设计给出；真正实施前必须对照当前地图测量。若原版已偏离设计，使用现有侧巷出口、站口、修理铺作为语义参照平移新区域，记录最终 bounds，避免覆盖现有建筑。

| 区域 ID | 任务 | 参考范围 / 规模 | 必须呈现的画面 |
| --- | --- | --- | --- |
| `main_street` | 原主街精修 | 原范围内 | 路面层次、连续但有变化的立面、清晰远景终点 |
| `repair_square` | 原维修铺广场精修 | 原范围内 | 有可信结构和工具布置的近景主场所 |
| `service_court` | 新增侧巷生活广场 | X 约 -73…-45，Z -17…17，约 28×34 米 | 小商铺/洗衣服务窗口、长椅、遮雨棚、温暖生活角落 |
| `station_forecourt` | 扩展站前空间 | X 约 10…43，Z -88…-62，约 33×26 米 | 站牌、阶梯、雨棚、连贯高架支撑和候车空间 |
| `roof_terrace` | 新增小型屋顶露台 | 优先在生活广场一侧两层附楼顶部，约 16×22 米，高约 8–11 米 | 栏杆、屋顶设备、少量花箱、能回望主街的城市层次 |

`service_court` 必须与旧侧巷视觉和空间相连；`station_forecourt` 必须与现有站口一致；`roof_terrace` 必须有合理的承重建筑、楼梯或封闭检修门作为建筑表达。镜头可以飞行，不要求实现可行走楼梯或角色物理。

建筑主体总量可以从约 13 栋增加到约 16–20 栋，实际以空间需要为准。不得为凑数量加入重复空盒；新增内容优先为三个空间服务。远景塔楼数量不作为目标，必要时减少/重排以形成更好的轮廓。

### 3.2 六个固定机位

| 锚点 ID | 保留/新增 | 构图职责 |
| --- | --- | --- |
| `street_view` | 保留 | 主街纵深；作为原版同机位对照 |
| `repair_shop_view` | 保留 | 维修铺近景；检查门窗、雨棚、工具和光照 |
| `station_view` | 保留 | 原高位站口和城市轮廓 |
| `service_court_view` | 新增 | 从侧巷望向生活广场，前景适度框景 |
| `station_forecourt_view` | 新增 | 人眼高度观察站前雨棚、阶梯和站牌 |
| `roof_terrace_view` | 新增 | 露台前景与城市中远景组合 |

原三个机位的 ID 不变。为前后对照保存原相机姿态；正式构图允许微调，但报告同时保留“原姿态”和“正式新姿态”截图，不能用换角度掩盖退步。

新机位由实际布局确定位置/朝向，不在没有真实场景的情况下硬写最终坐标。六个机位均须满足：不进入楼体，不切近景墙面，有视觉焦点，不需要极端广角。默认 FOV 约 60°，可在约 45–70° 范围内按构图调整。

### 3.3 三处新增空间的详细设计

**生活广场**：保留约三分之一可见开敞地面；沿墙设置 2–3 个不同功能的门面，最多一个新主招牌。小尺度铺地、排水沟和路沿承接旧侧巷。道具按“等待、维修、清洁”形成三组，避免随机撒满物件。主要材质为暖灰墙砖、旧涂漆金属、深色窗面；暖光在门面附近聚集。

**站前空间**：补齐高架支柱与桥面的连接、楼梯起止、雨棚排水、站牌支撑和候车座椅。站名采用同一城市标识系统。采用一条清楚的视线通向站口，另一侧留少量开阔空间。禁止为表现科技感铺满透明全息屏。

**屋顶露台**：外缘栏杆有可信高度约 1.1 米；主要设备箱集中到一侧，保留取景空地。花箱使用简化几何，少量植物作为色彩点缀，避免多层透明叶片。城市背景以高低错落的轮廓呈现，不要求从露台看到整座精细街区。露台底部和侧面在低机位中也必须合理。

### 3.4 相机可用范围

参考外围 bounds 为 X ±78 米、Z ±98 米、Y 1.5–28 米，最终根据成品地图收紧。扩大 bounds 之前，补齐对应视角能看到的外墙、屋顶和边界。

外围 AABB 只限制最大范围；楼体禁入体积仍生效。露台建筑使用分层禁入体积，不能用从地面延伸到天顶的大 AABB 把可观赏屋顶一起封死。相机移动使用线段与膨胀 AABB 检测或等价连续检测，避免高速穿墙。

## 4. 美术精修规范

### 4.1 保留主题，增加可读细节

沿用雨停后的蓝调傍晚：冷蓝灰大体块、暖色窗光、少量青色/橙色科技标识。保持风格化真实比例；本章不切换为像素/体素风，也不追求写实特效堆叠。

| 层次 | 细化内容 | 不采用的替代办法 |
| --- | --- | --- |
| 体量 | 首层与上层区分、退台、檐口、屋顶轮廓 | 整栋楼随机缩放 |
| 结构 | 门窗进深、雨棚厚度、支撑、接缝、路沿 | 只在平面贴一张门窗纹理 |
| 材质 | 粗糙度、低强度法线、合理色差和磨损位置 | 所有表面使用同一塑料高光 |
| 生活痕迹 | 对齐建筑用途的工具、椅子、招贴、储物 | 随机散布垃圾与箱子 |
| 光照 | 接触明暗、冷暖引导、招牌可读性 | 提高 Bloom 或压暗全图 |

配色延续首版：深蓝灰 `#263445`、蓝灰墙面 `#607789`、暖灰混凝土 `#A59D90`、暖窗光 `#F2B66D`、青色标识 `#58C4C1`、橙红点缀 `#DF735A`。色值是材料搭配起点，不是最终屏幕像素硬指标。

PBR 参数起点：混凝土/普通墙面粗糙度约 0.65–0.9，涂漆金属约 0.35–0.65、metallic 接近 0，裸露金属可使用较高 metallic，干路面粗糙度约 0.7–0.95、局部湿润约 0.2–0.45。按实际光照微调；避免所有表面同时变亮变光滑。门框/雨棚等近景倒角只增加必要轮廓细节，不给远景同等几何密度。

### 4.2 原有重点改造

维修铺：检查雨棚受力、门窗厚度、玻璃后浅景、工具车轮子接地；轮胎堆和设备摆放有重力关系。主体三种表面至少在近景可区分：涂漆金属、混凝土/墙砖、橡胶。店招不能成为发白的色块。

主街：增加合理铺装边界、道路修补、排水方向、路沿转角、门前高差。重复窗户至少通过窗帘/开灯状态/面板差异打破机械规律；差异来自固定配置，不在运行时随机生成。

旧侧巷：管线有起止和支架；空调外机有安装方式；海报尺度可信。用冷暗过渡连接暖色生活广场，至少一个视角能读出这条空间联系。

站口：重点修补桥面/支柱/楼梯连接及近距离可见背面。远景塔楼按前中后三层组织，不排列为相同高度和间距的围墙。

### 4.3 贴图与字体

- 常用纹理 512/1024；少量关键近景允许 2048；不新增默认 4K/8K 资产。
- 同类材质复用，按立面/模块使用图集或 trim sheet；只有画面确实受益才增加材质槽。
- 固定一套明确许可的中文制作字体，保存文件版本/哈希及许可，按同一输入生成招牌。原系统字体使用不直接等同于违法，本章替换的主要工程目标是可重复构建和明确分发条件。
- 检查“余晖维修、霓湾站、海风便利”以及新增文字的可读性；字符覆盖统计不能代替目检。
- 招牌近景检查笔画、边缘锯齿、对比度；远景检查 mipmap 后是否严重闪烁。

### 4.4 低成本氛围

本章最多 6 个非相机持续动画节点、2 个局部粒子发射器，沿用首版上限。动画优先复用一个控制器或简单着色参数，静态道具不挂逐帧脚本。经济档关闭粒子。

允许新增 1–2 类可关闭环境声，默认静音；不得让音频工作阻碍必做项完成。没有音频也可以通过本章。

## 5. 性能与画质边界

本章扩大内容，但不提高已有的硬件要求。不要把第一阶段贴住帧率上限理解为可任意增加细节。

| 配置 | Eco（默认） | Balanced |
| --- | --- | --- |
| 输出窗口基准 | 1920×1080 | 1920×1080 |
| 3D 分辨率比例 | 0.80 | 1.00 |
| 帧率上限 | 30 | 60 |
| 抗锯齿 | FXAA | MSAA 2× |
| 光照 | 同一套静态 lightmap | 同左 |
| 实时局部补光 | 0 | 最多 2，无阴影 |
| 局部反射探针 | 0 | 最多 2，Once |
| 粒子 | 0 | 最多 2 个局部发射器 |
| Glow | 关闭 | 低强度 |
| 失焦/最小化 | 10 / 5 FPS；最小化暂停环境动画 | 同左 |

不得因 1.1 增加了三个区域，将探针/粒子预算变成“每区域两个”。上述都是活动地图全局上限。

初始资源上限继续沿用：常规机位约 ≤300k 可见三角形、最复杂机位 ≤500k；Draw calls 常规 ≤250、峰值 ≤450；活动地图节点约 ≤2,500；Release 稳态进程工作集目标 ≤2 GiB；GPU 资源占用初始目标 ≤1.5 GiB；lightmap GPU 预算约 ≤256 MiB；暖加载目标 ≤5 秒；地图内容体积尽量 ≤500 MiB。

这些是目标/调查阈值，不是已实测结果。三角形、引擎 primitives、光照贴图磁盘大小和显存大小必须分别统计。超过阈值需定位并在报告中明确，不能静默改门槛或删掉必做区域。

经济档允许减少远处小道具和特效，但六个主构图的重要建筑、地标、家具与材质层次必须保留。不能以关闭某个新增区域来实现性能达标。

## 6. 场景结构、配置权威来源与迁移

### 6.1 修改位置

下表给出推荐归属；先在 `code_map.md` 映射实际路径，功能等价的已有文件优先保留。

| 位置 | 1.1 改动 |
| --- | --- |
| `maps/m01_afterglow/map.tscn` | 保持唯一生产入口；组合生成层、精修层、环境和六锚点 |
| `maps/m01_afterglow/generated/` | 离线生成产物，可重建；不得手工精修 |
| `maps/m01_afterglow/authored/` | 人工/Agent 精修的场景片段，生成器不得覆盖 |
| `maps/m01_afterglow/source/` | 布局参数、材质分配和固定随机种子等制作输入 |
| `maps/m01_afterglow/baked/` | 最终 lightmap 数据与必需纹理 |
| `maps/m01_afterglow/build_manifest.json` | 制作输入/输出指纹与烘焙有效性；不存运行状态 |
| `data/quality/` | 现有权威画质配置，增加校验和必要字段 |
| `scripts/maps/` | 地图合同、生命周期、区域细节配置 |
| `scripts/app/` | 相机、书签、截图、设置与输入互斥 |
| `scripts/diagnostics/` | 基准采样，按需激活 |
| `tools/`、`addons/neon_bake/` | 制作、验证、烘焙和发布工具 |
| `docs/chapter1_1/` | 代码映射、修复清单、美术复核、性能与验收 |
| `artifacts/chapter1_1/` | 真实截图、原始采样、日志和复核附件 |

`generated` 和 `authored` 是制作责任划分，不是两张地图。两层都被打包进同一个生产地图。第一阶段已有网格不必全部搬家，只有会被重建和精修冲突的资源才迁移。

### 6.2 光照节点归属

沿用现有有效的 LightmapGI 层级。推荐 `BakedWorld` 为 LightmapGI，其下同时包含 `GeneratedStatic` 与 `AuthoredStatic`；所有参与烘焙的静态网格在其扫描范围内。动态装饰和不烘焙的简化天际线独立放置。

移动/重命名烘焙网格或改变层级会影响 baked user 路径。先稳定最终层级再重新烘焙；不得把旧 lightmap 直接套在新层级上。新的生成层与精修层不能重叠放置同一面墙，避免 Z-fighting。

使用以下功能组，若已有等价组则映射复用：

| 组名 | 成员 | 用途 |
| --- | --- | --- |
| `active_map_root` | 仅当前地图根 | 检查活动地图数量 |
| `bake_only_light` | 完全烘焙的制作灯 | 运行时关闭，仅这些灯被关闭 |
| `runtime_fill_light` | 明确预算内的补光灯 | 由质量档控制 |
| `optional_probe` | 最多两个局部探针 | Eco 关闭，Balanced 按配置启用 |
| `optional_particle` | 最多两个粒子发射器 | 档位/后台策略控制 |
| `ambient_animation` | 少量环境动画控制器 | 暂停、恢复、固定采样时间 |
| `capture_ui` | 要从照片中隐藏的工具 UI | 截图时保存并恢复显隐状态 |

不再用“隐藏地图中的全部 Light3D”实现烘焙优化；必须区分制作灯和运行补光。编辑器制作/烘焙过程中不隐藏 `bake_only_light`，发布运行才关闭。保持一个 WorldEnvironment 和一个有效 Camera3D。

### 6.3 MapDefinition 版本迁移

保留所有 v1 字段、地图 ID 和三个原 anchor ID。逻辑格式升级到 `schema_version = 2`；实际可继续用已有 `.tres` 或 JSON。

| 新增字段 | 类型 / 默认 | 语义 |
| --- | --- | --- |
| `content_revision` | String，`"1.1.0"` | 内容版本，独立于格式版本 |
| `region_manifest_path` | String，空字符串 | 可选区域说明/细节档数据，路径字符串 |
| `occlusion_enabled` | bool，沿用现有值 | 最终值由本地图开关对照决定 |
| `bookmark_schema_version` | int，1 | 书签序列化版本 |
| `capture_anchor_names` | Array[StringName] | 六个有效锚点；缺省回落已有 anchor_names |
| `requires_baked_lighting` | bool，旧定义缺省 false | M01 的 v2 定义必须为 true；简单测试地图可为 false |

旧 `camera_bounds`、`camera_exclusion_bounds`、`anchor_names` 更新为实际成品范围和六锚点。两个锚点列表如无不同用途，应合并为一个权威字段，另一个通过访问器兼容，不能双份手工维护。

读取 v1 时补默认值，不破坏旧内容；未知未来 schema_version 返回明确错误，不猜测加载。写入 v2 前备份旧定义或保留 Git 基线。地图定义不得持有 PackedScene、完整地图节点、LightmapGIData 或大资源预加载引用。

区域数据示例（代表格式，不替代现场测量）：

```json
{
  "schema_version": 1,
  "map_id": "m01_afterglow",
  "regions": [
    {
      "region_id": "service_court",
      "bounds_min": [-73.0, 0.0, -17.0],
      "bounds_size": [28.0, 15.0, 34.0],
      "detail_root_path": "BakedWorld/AuthoredStatic/ServiceCourtDetails",
      "eco_detail_end_m": 45.0,
      "balanced_detail_end_m": 65.0,
      "hysteresis_m": 5.0
    }
  ]
}
```

区域细节可见距离只影响被明确标记的小装饰，不控制整栋建筑、地面或主要家具。优先使用引擎可见距离；需要脚本时只检查少量区域根，最多 4 Hz，并使用迟滞避免闪烁。不能每帧遍历全部道具。

## 7. 运行时代码接口合同

### 7.1 通用规则

以下 `text` 块是 **GDScript 风格的签名合同，不是可直接运行的空实现**。实现必须有真实方法体；不能复制成一堆 `pass` 后宣布完成。类型名代表职责，现有同功能类型可通过映射满足合同，无需新建同名 Autoload。

- `Error` 是 Godot 错误码：即时非法参数用 `ERR_INVALID_PARAMETER`，路径缺失用 `ERR_FILE_NOT_FOUND`，占用中用 `ERR_BUSY`；成功受理返回 `OK`。
- 异步方法的 `OK` 表示请求已受理，最终结果由信号发布，不能被 UI 当作已经完成。
- 每个受理事务拥有递增 ID，完成/失败结果恰好一次；被拒绝的请求不发布成功信号。
- 查询返回的 Dictionary/Array 必须是副本或只含值，不暴露可被外部改写的内部状态。
- 除 MapManager 在活动期间持有当前 MapRoot 外，常驻服务不强持有地图、网格、材质或锚点节点。相机姿态和报告使用值对象。
- 如保留旧方法/信号，提供薄适配并更新真实调用方；不要同时保留两套独立状态机。

### 7.2 值对象 CameraPose

定义轻量 `CameraPose extends RefCounted`，不含 Node/Resource 引用：

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `map_id` | StringName | 必须匹配当前地图 |
| `anchor_id` | StringName | 固定机位 ID；自由机位为空 |
| `transform` | Transform3D | 世界坐标，位置与旋转有限数值 |
| `fov_deg` | float | 按应用允许范围校验，建议 20–100 |
| `near_m` / `far_m` | float | 0 < near < far；采用实际相机值 |
| `keep_aspect` | int | 当前 Camera3D 的枚举值 |

书签 JSON 不直接写 Godot Variant 字符串。位置用 `[x,y,z]`、旋转用归一化四元数 `[x,y,z,w]`，单位米/度；反序列化显式校验数值有限、四元数长度、相机边界。零四元数拒绝。

### 7.3 MapManager（修改已有）

```text
signal map_loading(map_id: StringName, transaction_id: int, stage: StringName, progress: float)
signal map_loaded(map_id: StringName, transaction_id: int)
signal map_unloaded(map_id: StringName, transaction_id: int)
signal map_failed(map_id: StringName, transaction_id: int, error: Error, message: String)

func request_map(map_id: StringName, force_reload: bool = false) -> Error
func request_unload() -> Error
func get_current_map_id() -> StringName
func get_current_content_revision() -> String
func is_transitioning() -> bool
func get_state_snapshot() -> Dictionary
func get_anchor_pose(anchor_id: StringName) -> CameraPose
func get_camera_contract() -> Dictionary
func get_map_ambient_state() -> Dictionary
func set_map_ambient_paused(paused: bool) -> Error
func set_map_ambient_time(seconds: float) -> Error
func restore_map_ambient_state(snapshot: Dictionary) -> Error
```

`request_map`：相同地图且 force_reload=false 时保持原状态并返回 OK，不启动新事务、不发布假的 loaded 信号；测试显式使用 force_reload=true。切换期间、截图期间、基准期间返回 ERR_BUSY。缺失地图/路径在旧地图卸载前拒绝。

`request_unload`：EMPTY 时幂等返回 OK；READY 时启动卸载；其他忙碌状态返回 ERR_BUSY。卸载顺序为停止输入相关操作、停止旧地图活动、断开引用、移除旧根并等待释放，再清空当前 ID。

`get_anchor_pose`：无当前地图或缺少锚点返回 null，调用方处理错误；不返回锚点 Node。

`get_state_snapshot` 至少含 `state`、`map_id`、`transaction_id`、`active_map_count`、`content_revision`、`last_error`；只含可序列化值。

状态集合为 EMPTY、UNLOADING、LOADING、ACTIVATING、READY、ERROR。首载 EMPTY→LOADING→ACTIVATING→READY；切换 READY→UNLOADING→LOADING→ACTIVATING→READY；独立卸载 READY→UNLOADING→EMPTY。参数校验失败不改变旧状态；卸载后的失败进入 ERROR，清理完成后回 EMPTY。

`get_camera_contract` 返回 map_id、bounds、exclusions 的值副本；无图时返回空 Dictionary。环境转发方法仅在当前图 READY 时可操作，无图返回 `ERR_UNCONFIGURED`。环境快照带 map_id，恢复到不同地图时拒绝。无图时 current_map_id/content_revision 返回空值。

主场景作为组合根初始化并注入既有 QualityController、ObserverCamera 与共享活动 guard，依赖接线方式沿用工程现状并写入 code_map。MapManager 实例化并持有活动 MapRoot；在 ACTIVATING 内先应用质量档，再将边界值交给 ObserverCamera.bind_map_contract 并应用默认 CameraPose。全部成功之后才进入 READY、发布一次 map_loaded 并撤下遮罩。任一步失败都不能先发 map_loaded；应清理新图、解除相机绑定并发布失败。BenchmarkRunner 通过上述转发接口控制环境，不直接缓存 MapRoot。

进度 stage 固定为 `unloading`、`resource_loading`、`activating`。progress 为当前阶段的 0…1，无法确定则 -1；UI 显示阶段名，不把资源 100% 当作整个地图已完成。

后台资源完成后才能取回 PackedScene，实例化在主线程。旧图必须先卸载，新图才开始加载。加载失败清理部分实例、恢复空外壳。超时不等于线程已取消：若 API 不支持取消，标记本事务失效并安全收尾/排空结果，未收尾前不接收第二个同路径事务。

所有异步继续执行点检查 transaction_id 是否仍有效；失效结果不得发布 loaded、覆盖当前地图 ID 或重设相机。清理完成后再释放本事务持有的活动 token。

参考：[Godot 后台资源加载](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)。

### 7.4 MapRoot（修改已有）

```text
func validate_runtime_contract() -> PackedStringArray
func get_anchor_ids() -> Array[StringName]
func get_anchor_pose(anchor_id: StringName) -> CameraPose
func get_camera_bounds() -> AABB
func get_camera_exclusion_bounds() -> Array[AABB]
func apply_quality(profile: Dictionary) -> Error
func set_ambient_paused(paused: bool) -> void
func set_ambient_time(seconds: float) -> void
func get_ambient_state() -> Dictionary
func restore_ambient_state(snapshot: Dictionary) -> Error
func begin_deactivation() -> void
```

验证方法返回错误列表，空列表表示通过；检查其 MapDefinition 声明的锚点唯一/可用、环境数量、bounds、所需烘焙数据、区域路径。生产 M01 必须声明六锚点并要求烘焙；极小测试 B 按自己的一个锚点和非烘焙合同验证，不能硬编码为所有地图都需要六锚点。关闭可选功能不得改写磁盘资产或共享材质的权威值。

`begin_deactivation` 幂等，停止地图内 Timer/Tween/动画/粒子/音频并解除由地图建立的外部信号；不能清空仍被别的系统使用的全局资源缓存。`set_ambient_time` 只影响已经实现的少量装饰动画，不能产生新的模拟系统。

环境快照保存受控动画的稳定 ID、时间、播放/暂停状态和发射器启用状态；不含节点引用。恢复时只处理仍存在的同地图对象，缺失对象返回可解释的错误并安全恢复其他项。

### 7.5 QualityController 与后台节流（复用现有）

```text
signal quality_changed(requested_id: StringName, effective_state: Dictionary)

func set_profile(profile_id: StringName, persist: bool = true) -> Error
func get_profile_id() -> StringName
func get_effective_state() -> Dictionary
func apply_to_map(map_root: MapRoot) -> Error
func set_window_state(focused: bool, minimized: bool) -> void
func capture_runtime_state() -> Dictionary
func restore_runtime_state(snapshot: Dictionary) -> Error
```

配置 ID 固定 `eco` / `balanced`。未知值从用户配置加载时回落 Eco并记录；运行时 UI 调用未知 ID 则返回错误。质量控制器应用后不保留 map_root 强引用。

有效帧率优先级：最小化 5 → 失焦 10 → 正常所选档位；最小化同时暂停地图环境动画。恢复窗口后恢复用户选择，不把 5/10 写入用户帧率设置。

`effective_state` 至少含 `profile_id`、`frame_cap`、`render_scale`、`aa_mode`、`glow_enabled`、`probe_count`、`particle_emitter_count`、`runtime_fill_count`、`occlusion_enabled`、`focused`、`minimized`、`renderer`。每个字段来自实际应用后的状态，不能只回显配置。

基准使用临时覆盖，结束时恢复快照，不写入 settings.cfg。捕获快照时只存值和所需 UI/控制状态，不把整张地图保存进 Dictionary。

恢复时恢复用户请求档位及临时覆盖前的首选项，并重新读取真实 focused/minimized 状态计算有效帧率；不能把快照中的旧前台状态覆盖当前失焦状态。旧配置迁移保持用户选择，只有非法字段回落默认。

### 7.6 ObserverCamera（复用现有）

```text
signal pose_changed(pose: CameraPose)

func bind_map_contract(map_id: StringName, bounds: AABB, exclusions: Array[AABB]) -> void
func unbind_map() -> void
func get_pose() -> CameraPose
func validate_pose(pose: CameraPose) -> PackedStringArray
func apply_pose(pose: CameraPose, immediate: bool = true) -> Error
func set_input_enabled(enabled: bool) -> void
```

绑定时复制边界数组，不持有地图。固定机位切换默认 immediate=true，避免补间穿楼；需要平滑时只能沿已验证的小范围路线。普通移动保持帧率无关、速度上限和滚轮范围。

位姿无效返回错误并保持原位，不默默跳到地图中心。地图升级导致旧书签位置不可用时，提示失效，可让用户选择默认机位；不自动覆盖原书签。

相机未绑定地图时 get_pose 返回 null；调用方不得保存空书签。

`pose_changed` 用于工具显示时最多约 10 Hz，静止时不重复发布；真实渲染位置仍按每帧更新。书签/截图直接读取当前 get_pose，不使用可能较旧的 UI 缓存。

### 7.7 BookmarkStore（小型新增，可并入设置模块）

```text
func list_bookmarks(map_id: StringName) -> Array[Dictionary]
func save_bookmark(label: String, pose: CameraPose, content_revision: String) -> Dictionary
func load_bookmark(bookmark_id: String) -> CameraPose
func delete_bookmark(bookmark_id: String) -> Error
```

每地图最多 12 个书签；label 去除首尾空白，长度 1–40 个字符。ID 使用独立随机/唯一标识，不以 label 当文件路径。`save_bookmark` 返回 `{ "error": int, "bookmark_id": String, "message": String }`，失败时 ID 为空。

保存到 `user://camera_bookmarks.json`，顶层 schema_version=1。写临时文件、成功后替换，并保留一份最近可读备份。损坏文件不覆盖为空，隔离损坏副本并提示恢复；其余设置正常运行。

原 1/2/3 快捷键保留，新机位使用 4/5/6。书签通过简洁菜单保存/选择/删除，不新增复杂时间线。

`list_bookmarks` 的每项至少包含 ID、label、map_id、content_revision、created_utc。`load_bookmark` 在缺失或解析失败时返回 null；UI 显示“书签不存在或数据无效”，保留当前相机。实际应用前由 ObserverCamera 校验地图和位置。

### 7.8 AppActivityGuard（轻量互斥职责）

```text
func try_begin(kind: StringName) -> int
func end(token: int) -> Error
func get_active_kind() -> StringName
```

kind 只允许 `map_transition`、`capture`、`benchmark`；空闲时返回 >0 token，忙碌返回 0；end 仅释放匹配 token。可以在已有主控制器中实现，不必增加 Autoload。

MapManager、截图和基准操作通过同一互斥状态协调，避免 UI 恢复顺序、截图错图和测量污染。持有者内部的相机切换/设置覆盖不再次申请同一锁。窗口关闭走统一清理；不得因忘记释放 token 永久失去操作能力。

## 8. 截图、测量与导出接口

### 8.1 CaptureService

```text
signal capture_completed(request_id: int, image_path: String, metadata_path: String)
signal capture_failed(request_id: int, error: Error, message: String)

func request_capture(label: String = "") -> Error
func is_busy() -> bool
func abort_capture(reason: String) -> void
```

流程：申请 capture token → 保存当前 UI 显隐与输入状态 → 暂时隐藏 capture_ui → 等待真实绘制完成 → 从 Viewport 取图 → 写 PNG 与同名 JSON → 恢复原状态 → 释放 token → 发完成信号。

- 等待 `RenderingServer.frame_post_draw` 或本版本等价有效方法；读取必须来自实际渲染视口。不能 headless 生成假截图。
- 失败、写盘失败、退出和 abort 都走同一个幂等清理函数，恢复先前状态。不能简单将所有 UI 强制设为 visible=true。
- 每个 await/异步继续点检查 request_id 是否有效。abort 使本请求失效，旧回调不得继续写文件、再次发成功信号或覆盖下一次操作的 UI 状态。
- 截图过程中地图切换和基准请求返回 ERR_BUSY，禁止截图到一半切图。
- 每次独立请求使用唯一 ID/文件名；不覆盖旧证据。对快速连按节流，无需队列。
- 文件仅写 `user://captures/`；label 仅参与安全文件名片段，过滤路径分隔符和保留字符，不允许目录穿越。
- PNG 与 JSON 两者成功才发完成信号；若一项失败，清理本次半成品并报告，不删除既有文件。
- 测量过程中截图会造成读回/编码卡顿，不能与性能采样同时进行。

JSON 元数据至少含：schema_version=1、request_id、map_id、content_revision、anchor_id、CameraPose 的可序列化表示、profile_id、effective_state、实际图像宽高、UTC 时间、引擎版本、图形适配器名称、构建版本/提交 ID（若可得）。这些值从实际状态读取。

参考：[RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)。Headless 不提供正常 GPU 渲染结果。

### 8.2 BenchmarkRunner

```text
signal benchmark_started(run_id: String)
signal benchmark_completed(run_id: String, output_directory: String)
signal benchmark_aborted(run_id: String, reason: String)

func start_run(config: Dictionary) -> Error
func abort_run(reason: String) -> void
func is_running() -> bool
func get_run_status() -> Dictionary
```

`config` 先校验，至少包含以下字段：

| 字段 | 类型 / 允许值 | 语义 |
| --- | --- | --- |
| `schema_version` | int，1 | 基准配置格式 |
| `run_id` | String，非空唯一 | 原始数据关联键 |
| `profile_id` | `eco` / `balanced` | 两档分别测量 |
| `route_id` | `legacy_v1` / `expanded_v11` | 旧版对照路线 / 新全覆盖路线 |
| `mode` | `capped` / `headroom` | 正常限帧 / 短时余量诊断 |
| `warmup_seconds` | float，默认 15 | 预热，不进入稳态分位数 |
| `duration_seconds` | float，正常 60 | 固定路线时长 |
| `occlusion_override` | String，`default`/`on`/`off` | 只用于定向对照 |
| `output_directory` | String | 仅允许 user://benchmarks/ 下 |

运行前确认地图 READY、当前 renderer/分辨率/配置真实生效、图形环境可用，然后申请 benchmark token，快照用户设置、相机和环境状态，禁用人工相机输入。结束、失败、失焦或退出时通过同一个清理函数恢复快照、释放 token。

正常 `capped` 运行保持原始节流逻辑，窗口在采样期失焦/最小化即把本轮标记为无效并中止，不混入有效结果。不要再通过全局永久禁用节流解决自动化污染。自动化负责保持前台；无法保持则记录环境限制。

`headroom` 仅从开发入口启用，最长 60 秒，不出现在普通画质菜单。记录临时帧率/VSync 改动，完成后恢复。优先使用 profiler 时间；无上限 FPS 只是辅助，不能替代功耗或跨设备性能结论。

配置校验要求：正常路线 duration_seconds=60；headroom 为 1…60；warmup_seconds 为 0…30；所有时间为有限数值。有效稳态样本不足 30 个、时钟顺序异常或输出路径越界时，中止并记录无效原因，不计算伪分位数。

采样使用单调实际时钟逐帧记录。不得使用 `_physics_process` 固定步长、`1000/FPS`、Movie Maker 的固定模拟时间或配置里的理论帧率生成分位数。若使用 `_process` 调用间隔，报告明确其为引擎主循环间隔，不宣称是显示器实际呈现时间。

原始记录包含 `sample_index,timestamp_us,frame_interval_ms,phase,segment_id`；分位数按排序后的真实样本计算，采用 nearest-rank：Pq = sorted[ceil(q*N)-1]。每轮 FPS 使用实际帧间隔数/实际墙钟时长，不平均 `1/delta`。首个无前驱样本丢弃，不能填 0。

预热、加载、截图、无效轮次均单独标记，不静默删掉性能差但有效的帧。超过 100 ms 卡顿从有效稳态样本计数。

### 8.3 两条固定路线

`legacy_v1`：保持第一阶段三个原机位与原 60 秒路线，用于同画面回归；原始路线如没有可复现记录，先固定一次并注明“新建对照路线”，不能伪称完全复现旧测量。

`expanded_v11`：60 秒，六个机位各约 10 秒，顺序为主街、维修铺、生活广场、屋顶露台、站前广场、原站口高位。每段只做经检查的小幅移动，段间切镜，不跨楼插值。各段覆盖新区域最复杂构图。

最终验收对 expanded_v11 两档各 3 轮；legacy_v1 在基线和完成后每档各作 1 轮同条件对照，仅用于回归定位，不承担最终稳定性验收。中途微调不重复全部测试，只跑受影响区域，最终再做一组完整验收。

### 8.4 原始数据和统计文件

每轮输出：`run.json`（环境/配置/有效性）、`frames.csv`（原始样本）、`summary.json`（汇总）。整个版本输出 `summary.csv`，至少包含：

```text
run_id,map_id,content_revision,route_id,profile_id,mode,valid,invalid_reason,
engine_version,build_type,renderer,gpu_name,cpu_name,system_ram_mib,
window_width,window_height,render_scale,frame_cap,vsync_mode,occlusion_enabled,
sample_count,elapsed_seconds,average_fps,p50_ms,p95_ms,p99_ms,stutters_over_100ms,
draw_calls_peak,visible_primitives_peak,map_node_count,
process_working_set_mib_peak,process_private_bytes_mib_peak,
engine_video_memory_mib_peak,os_gpu_memory_mib_peak,
cpu_frame_ms_median,gpu_frame_ms_median,resource_load_ms,activation_ms,notes
```

真实 CSV 表头写为一行。无法采集的字段用空值/JSON null，并用 notes 标明 N/A 原因；不能用 0 表示未知。CSV 中 CPU/GPU profiler 时间没有可靠来源时允许为空。

不把引擎静态分配量当进程 RAM；不把引擎显存估计改名为操作系统进程显存。CPU/GPU 计算时间不包含限帧等待时才用于余量分析；如果来源包含等待，明确说明。

### 8.5 系统级采样工具

新增或适配一个 Windows PowerShell 采样工具，接收明确的 PID、进程启动时间和 run_id，1 Hz 采集目标游戏进程的 WorkingSet64、PrivateMemorySize64、累计 CPU 时间；不要采样编辑器或整个 Godot 进程组。

工具可使用正常用户权限下的 Get-Process；进程退出即停止，PID 被复用时不得继续归入原轮次。以 MiB=1024² 字节换算。CPU 占整机比例若计算，明确公式为 CPU 时间增量 / 墙钟增量 / 逻辑处理器数，乘 100；另报核等效占用时使用不同列名。

示例目标命令（工具是本章新增，创建后才可执行）：

```powershell
.\tools\sample_process.ps1 -GameProcessId 1234 -RunId 'v11_eco_01' -OutputDirectory '.\artifacts\chapter1_1\performance'
```

不能把 `$PID` 作为自定义可写变量名。GPU 进程内存/功耗不能可靠获取时不强行引入复杂驱动依赖；已有引擎估计保持明确标签。用户的“低负担”结论至少结合限帧下的实际 CPU/内存观察；功耗未知则不作低瓦数承诺。

## 9. 离线制作与烘焙接口

### 9.1 制作流程

顺序固定为：验证源数据 → 生成纹理/招牌/基础模块 → 生成地图基础层 → 组合精修层与最终层级 → 导入/UV2 校验 → 烘焙 → 烘焙覆盖和画面验证 → 导出。

公开一个统一入口 `tools/build_chapter11.ps1`，包装现有脚本而非全部重写。阶段定义：

| Stage | 行为 | 成功条件 |
| --- | --- | --- |
| `validate` | 校验引擎、输入、字体、路径和布局结构 | 输出明确校验报告 |
| `generate` | 生成可重建层，保留 authored | 输入/输出清单和资源有效 |
| `assemble` | 组合最终地图，完成导入与基础资源检查 | 无缺失引用，节点路径稳定 |
| `bake` | 在真实图形编辑器中请求烘焙 | 完成信号/状态和烘焙内容验证通过 |
| `verify` | 验证资源、烘焙指纹和需要的运行检查 | 明确通过/失败/待图形验证 |
| `export` | 匹配模板下导出 Windows Release | 预设、资源、产物正确 |
| `all` | 顺序执行上述阶段，遇失败停止 | 不能跳过 bake 失败继续宣称成功 |

工具参数：`-GodotExe`（实际路径）、`-ProjectPath`（默认当前工程）、`-Stage`、`-MapId`（本章仅 m01_afterglow）。Godot 路径从参数或未提交的本地配置取得，不能把 README 中个人机器路径硬编码。

完整重建只在需要时执行。仅改变 UI 文案、相机书签或不参与烘焙的显示设置，不应重新生成城市和烘焙。

### 9.2 生成数据、精修数据与重建安全

- 稳定对象 ID 从语义名称/固定输入生成，不根据节点遍历顺序随意编号。
- 同输入和种子产生等价几何、布局、材质分配；不要求 GPU 烘焙文件跨设备逐字节相同。
- 生成器只写自身输出清单中的文件，不递归清空整个地图目录。
- 手工精修保持独立源场景或明确的覆盖数据；每次重建验证这些文件未被修改。
- 删除一个已不存在的生成资源前，检查引用并记录删除清单；不误删 authored 或用户文件。
- 多文件构建不是天然原子操作。记录本轮改动清单和可恢复基线，失败时只恢复本工具修改的生成产物，保留用户改动。
- 可以在临时目录生成并验证，再更新最终产物；移动后的路径/UID/引用必须再次验证，不能直接假定临时烘焙绑定在新位置仍正确。

### 9.3 构建与烘焙清单

`build_manifest.json` 至少包含：

```json
{
  "schema_version": 1,
  "map_id": "m01_afterglow",
  "content_revision": "1.1.0",
  "engine_version": "4.7.2.stable",
  "build_id": "example-build-id",
  "geometry_input_hash": "sha256-placeholder",
  "lighting_input_hash": "sha256-placeholder",
  "authored_input_hash": "sha256-placeholder",
  "font_source_hash": "sha256-placeholder",
  "bake_job_id": "example-bake-id",
  "bake_status": "pending",
  "expected_baked_user_paths": [],
  "actual_baked_user_paths": [],
  "outputs": []
}
```

上面仅为数据形状；实际成功清单不能保留 example/placeholder。`outputs` 每项含 path、size_bytes、sha256、role。bake_status 仅允许 pending/running/succeeded/failed/stale，只有成功验证本轮输入和结果时才写 succeeded。

哈希输入包含：最终参与烘焙的几何/UV2/变换/节点层级、材质的烘焙相关部分、灯光、环境、烘焙设置和引擎版本。排除清单自身、时间戳、既有烘焙输出，避免循环依赖和每次必然失效。

字体/招牌变化可能改变烘焙材质或发光贡献，按实际依赖标记 stale；不得只按 EXR 是否存在判断有效性。多个修改可以合并后重烘焙一次。

### 9.4 BakeCoordinator（增强现有编辑器插件）

```text
signal bake_started(job_id: String, map_id: StringName)
signal bake_finished(job_id: String, success: bool, report_path: String)

func request_bake(map_id: StringName, job_id: String) -> Error
func get_status(job_id: String) -> Dictionary
func fail_job(job_id: String, reason: String) -> void
```

前置检查：正确地图已在编辑器打开、没有未处理保存冲突、LightmapGIData 路径已设置、目标网格有有效 UV2 和 lightmap 尺寸提示、最终节点路径固定、制作灯处于烘焙所需状态。

用户报告已用插件定位编辑器按钮完成真实烘焙，本章保留这条已验证路线。先检查本机类 API，不能臆造公共 `LightmapGI.bake()`；若继续调用按钮，使用可解释的控件定位并验证唯一匹配，不依赖屏幕绝对坐标或仅固定等待 8.4 秒。

`--auto-bake` 是项目自定义参数，不是 Godot 通用开关。保持现有解析方式；若迁移为用户参数，在 `--` 后传入，并同步工具调用/README。不得只改一端。

烘焙完成判断结合编辑器工作结束、日志/状态、新结果和覆盖验证；文件修改时间不能单独证明成功。超时可配置，默认上限例如 15 分钟，仅在有明确进度时延长；超时不能强杀整个系统的 Godot 进程。

成功后核对 LightmapGIData 的 user 路径与预期网格，以及输出纹理是否有效。引擎提供 `get_user_count()` / `get_user_path()` 等查询；具体版本 API 在本机确认。不能简单断言“一个 EXR 对应全部网格均正确”。参考：[LightmapGIData](https://docs.godotengine.org/en/stable/classes/class_lightmapgidata.html)。

只要求应烘焙的网格被覆盖；不把独立背景或明确不参与烘焙的装饰计为漏项。新增三个区域必须各有实际覆盖证据。烘焙失败时保留可诊断输出并阻止 Release 验收；继续修复其他独立任务。

### 9.5 发布接口

创建并提交名为 `Windows Desktop` 的实际导出预设；配置的资源规则须覆盖通过字符串加载的地图、JSON、lightmap、字体和所有运行资产。排除测试夹具、制作插件、源 `.blend`、报告与临时目录，检查依赖闭包没有误删实际所需资源。

发布目录建议 `build/windows/neon_haven.exe` 及其需要的 PCK/依赖文件，是否嵌入 PCK 遵循现有工程，交付整套运行文件。引擎版本与导出模板必须匹配。

```powershell
$NeonGodotExe = 'D:\Tools\Godot_v4.7.2-stable_win64.exe'
& $NeonGodotExe --version
.\tools\build_chapter11.ps1 -GodotExe $NeonGodotExe -ProjectPath . -Stage validate -MapId m01_afterglow
# 工具和预设实际创建后，再执行：
.\tools\build_chapter11.ps1 -GodotExe $NeonGodotExe -ProjectPath . -Stage all -MapId m01_afterglow
```

导出模板缺失时先完成导出预设、资源规则与明确安装步骤；环境允许获取官方匹配模板则继续完成。不能因模板暂时缺失把发布工作从计划删除，也不能改用其他版本悄悄导出。参考：[Godot 导出说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)。

## 10. 优化方案与修复清单

### 10.1 必查问题及其修复条件

| ID | 问题/风险 | 实施动作 | 完成证据 |
| --- | --- | --- | --- |
| FIX-01 | “贴上限=余量充足”的旧结论 | 修正文档；分开正常限帧和余量诊断 | 报告不混淆帧间隔与执行时间 |
| FIX-02 | Windows 没有导出预设/产物 | 创建预设、匹配模板、发布运行 | 独立目录运行日志和画面 |
| FIX-03 | 地图往返可能只有 5 轮 | 核对并完成 10 个 A→B→A | 每轮节点/引用/内存记录 |
| FIX-04 | 非法路径、缺锚点、重复请求处理 | 复用现有测试，验证兼容迁移未破坏 | 错误后可重试，无双活动地图 |
| FIX-05 | 测量永久关闭后台节流 | 测量与正常设置隔离，统一恢复 | 失焦/最小化/恢复实际验证 |
| FIX-06 | 只统计引擎内存 | 增加 Windows 进程采样 | 明确 working set/private bytes/显存来源 |
| FIX-07 | 全部烘焙灯无差别隐藏 | 区分 bake_only 与 runtime_fill | 烘焙场景正确，Balanced 补光按需工作 |
| FIX-08 | 旧 EXR 冒充新烘焙结果 | 构建输入指纹和覆盖验证 | 更改参与烘焙输入时清单标 stale |
| FIX-09 | 重建覆盖精修 | 分离生成层与精修层 | 重建前后精修源文件哈希不变 |
| FIX-10 | 字体生成依赖本机字体 | 固定字体来源/版本并重建招牌 | 换目录仍可复现，字形正确 |
| FIX-11 | 截图/UI/地图操作冲突 | 共用互斥状态、清理恢复 | 失败不锁死输入，不截图错地图 |
| FIX-12 | README 路径和文档入口漂移 | 参数化本机路径，维护实际规范路径 | 命令复制修改参数后可执行 |

上述“风险”不表示已确认存在代码错误。先审查；已正确实现的项目记录证据并复用，避免无必要改写。

### 10.2 CPU 优化

- 确认地图/静态道具不含无意义 `_process`；诊断 UI 4 Hz，区域状态最多 4 Hz。
- 相机边界只在移动时计算，使用少量 AABB；不遍历网格顶点、不新增物理角色系统。
- 不使用逐帧全树查找；地图加载时构建小索引，卸载时释放。
- 环境动画、粒子和探针受质量/后台策略约束；不可见且不需要更新的装饰停止处理。
- 关闭开发面板后不继续高频组装字符串/写日志；正常运行不采集逐帧 CSV。

### 10.3 GPU 优化

- 优先解决材质/绘制调用膨胀。按街段或立面组织实例，不把整个街区合并成一个巨型剔除单元。
- 只对适合共享网格/材质的重复小装饰使用局部 MultiMesh；需要独立 lightmap 的建筑保留可靠烘焙方案。
- 低层次几何和较短可见距离用于细小道具；六机位主要结构始终可见。检查切换边界与滞后，避免闪现。
- 参与明显烘焙阴影的小物件不能简单按距离隐藏并留下悬空阴影；保留关键投影轮廓，或将该物件排除在可隐藏组之外。LOD 也需检查 lightmap/UV2 与阴影一致性。
- 远景减少独立材质和无意义透明窗口。主要窗面用不透明或受控少量透明实现。
- 光照继续以静态烘焙为主，反射探针使用 Once，稳态不移动/重复更新。
- 移动渲染器下不加入 SSR、体积雾、SDFGI 等不适用功能。性能提升不能以切到未验收的 renderer 达成。

### 10.4 遮挡剔除的决定方式

使用街道遮挡明显的机位和屋顶较开阔机位各做一次定向对照。两组均固定相机路线、画质、分辨率和构建。

先比较实际 CPU/GPU 时间、Draw calls；若限帧掩盖差异，再进行短时 headroom 对照。重复 3 次观察差异是否超过波动；若变化接近噪声，结论写“不确定”，不能声称已提升。

- CPU 增加而 GPU/总耗时无收益：M01 可关闭。
- 总耗时/绘制负担有稳定改善且无错误剔除：保留开启。
- 无法取得执行时间：保留当前设置作为暂定值并标明未证实，不能写成“增加余量”。

不要为了一个 6 万面级场景引入复杂层级可见性系统。参考：[遮挡剔除的收益与成本](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)。

### 10.5 内存与加载优化

- 稳态只有一个生产地图实例；区域分组只是这张地图的组织方式，不能把“隐藏区域”称为释放资源。
- 清除常驻管理器、书签、截图元数据、诊断缓存中的地图资源强引用。
- 共享静态资产可缓存；地图专属资源应在无人引用后可回收。驱动缓存不要求字节级归零。
- 贴图/lightmap 选择合理尺寸、格式、层数和 mipmap；不把磁盘 EXR 大小当成显存。
- 暖加载拆分 resource_load_ms 与 activation_ms，并记录整体从请求到可操作的时长。
- 不为缩短暖加载偷偷提前加载全部地图；允许加载遮罩覆盖实例化和首次图形准备。

### 10.6 优化收益的报告规则

针对具体瓶颈实施；没有稳定收益的复杂改造撤回或不引入。扩展新内容后，整体 Draw calls/内存可能增加，应分别报告“相同旧路线回归”和“新增全覆盖路线预算”，不能把新增内容开销全部当优化失败，也不能用换轻场景冒充优化成功。

不预先承诺降低某个固定百分比。完成标准是：消除已识别浪费、解释关键选择、保持目标性能和美术质量，提供可重复证据。

## 11. 工作包与实施顺序

### WP0：基线、接口映射与发布探路

执行第 2 节审计，保留三个原机位两档共六张基线图；创建真实导出预设，进行第一次发布尝试。列出确定缺陷和未确认风险，先修会阻碍后续工作的启动/缺资源问题。

交付：code_map.md、基线记录、初始问题清单、导出预设。门槛 G0。

### WP1：制作流程与最小接口迁移

将生成层和精修层分离，固定字体输入，增加构建清单；对 MapDefinition v2、活动互斥和快照恢复做兼容适配。先确保原地图仍能运行，原三机位/质量档/设置不退步。

不要同时改造全部 UI。新的书签和扩展锚点等接口可在对应工作包完成时加入；每步保持可运行。

交付：可安全重建的旧地图、接口迁移测试、字体来源。门槛 G1。

### WP2：扩展灰盒与空间审核

建立三处新空间、连接关系、六机位、相机边界与禁入体积。只用足够表达结构的几何检查比例、遮挡、轮廓和视角；不先制作大量摆件。

交付：同一 M01 内的三处扩展灰盒、六机位截图、空间检查清单。门槛 G2；灰盒通过只允许进入精修，不代表本章完成。

### WP3：主街与维修铺精修

先完成维修铺近景，再处理主街与旧侧巷。统一建筑模块、材质、接缝、厚度、道具布置和招牌系统。用一个完成度高的近景确定美术标准，然后扩散到全街。

交付：原三机位有清楚的前后改善，精修源数据可保留。门槛 G3 的原区域部分。

### WP4：三处扩展成品化

按生活广场 → 站前空间 → 屋顶露台推进。每完成一处就确认其主机位和自由观察路径，避免三个区域同时半成品。根据实测选择几何密度，不突破活动地图预算。

交付：三个扩展机位和连接空间成品，边界完整。门槛 G3 的新增区域部分。

### WP5：光照、观察工具与截图体验

稳定最终层级后烘焙，验证覆盖与输入指纹。完成 4/5/6 机位、书签、截图元数据、输入/地图/基准互斥。完成两档美术复核，修复漏光、闪烁、过曝和遮挡错误。

交付：完整六机位体验、可复现截图、可靠烘焙。门槛 G4。

### WP6：定向性能优化与回归

执行第 10 节，补系统采样、帧时间口径和 10 次往返。先对识别到的问题做少量针对性优化，再运行最终两档全路线采样。不要在每次改一块砖后重跑整套性能测试。

交付：真实原始数据、开关对照、内存趋势、性能结论。门槛 G5。

### WP7：独立发布与完成验收

从全新检出/干净项目副本导入，验证生成层和精修层、依赖和烘焙资源；导出 Windows Release，并在非源码目录实际运行。更新 README、素材来源、操作说明和交接。

交付：完整运行包、最终十二张图、原始性能数据、验收矩阵。门槛 G6。

工作窗口结束时完成一个可检查的小成果并记录下一步。不要为填满每天 6 小时开始无关模块，也不要因为一轮额度用完就删减本章范围。

## 12. 回归与异常验证

优先复用已有测试，不以测试数量作为质量指标。以下每项验证针对本章明确风险。

| 测试 ID | 输入/操作 | 预期结果 |
| --- | --- | --- |
| T01 | 读取 v1 地图定义 | 补默认值，原地图/三锚点可用 |
| T02 | 读取不支持的未来版本或非法 bounds | 明确拒绝，不生成半活动地图 |
| T03 | 正式 A→极小 B→A，完整往返 10 次 | 全程活动根 ≤1；结束时稳定为 A |
| T04 | 切换中重复请求、缺路径、缺锚点 | 拒绝/失败后可恢复，旧引用清理 |
| T05 | 请求当前地图、force_reload 的两种情况 | 幂等与重新加载语义符合合同 |
| T06 | Eco→Balanced→Eco，失焦→最小化→恢复 | 设置、光照、帧率、动画恢复正确 |
| T07 | 六个固定机位、最高速度沿边界移动 | 不穿楼、不出已制作范围，无输入卡死 |
| T08 | 保存/加载/删除书签、损坏 JSON、旧地图版本位置 | 正常恢复或明确报错，不破坏现有数据 |
| T09 | 截图成功、写盘失败、连按、忙碌时请求切图 | PNG/元数据一致；UI/输入/锁恢复 |
| T10 | 基准正常结束、失焦、主动中止 | 有效性正确；相机/设置/动画/锁恢复 |
| T11 | 修改参与烘焙的几何/灯光后直接验证 | 清单 stale；不能通过发布光照门槛 |
| T12 | 同输入重建生成层 | authored 源文件不被覆盖，布局等价 |
| T13 | 干净检出导入和独立目录运行 Release | 无制作机器绝对路径依赖、资源完整 |
| T14 | 六机位两档图像与移动观察 | 无明显漏光、UV 问题、闪烁、空洞、错误剔除 |

生命周期测试不能仅检查根节点弱引用。至少另跟踪一个地图专有资源的引用状态、持续活动对象数量和系统内存趋势；共享资产明确排除。预热后观察后五轮，工作集持续增长超过约 10% 或 150 MiB 时定位原因；不能仅凭一次驱动缓存增长判泄漏。

测试 B 不进入生产地图菜单或正式发布包。生命周期可在独立 Godot 运行进程中完成；最终发布包另外验证真实 M01 的进入、退出和重新加载，不能为测试把夹具永久加入产品。

## 13. 明确的项目验收矩阵

每项状态只能为 `PASS`、`FAIL`、`NOT_RUN`、`BLOCKED`。`N/A` 只用于确实不适用的可选指标，例如无法可靠取得 GPU 功耗；不得用 N/A 绕过必做区域、视觉检查或发布运行。

| 门槛 | 必须通过的内容 | 必需证据 |
| --- | --- | --- |
| G0 基线可靠 | 输入审计、代码映射、真实版本和原机位记录 | code_map、环境、基线截图/缺口 |
| G1 工程兼容 | 原地图不退步；定义迁移、生成/精修分离 | 原功能回归、重建保护记录 |
| G2 空间成立 | 三处扩展相连，六机位安全，边界明确 | 灰盒图、布局说明、相机检查 |
| G3 内容成品 | 原场景精修＋三处扩展全部完成 | 成品图、细节审核、前后对照 |
| G4 功能/光照 | 书签、截图、质量档和烘焙绑定正确 | 接口回归、烘焙清单、截图元数据 |
| G5 性能可靠 | 两档达标、单地图、内存趋势有解释 | 原始样本、汇总、10 往返、对照报告 |
| G6 可交付 | 匹配模板导出，干净目录独立运行 | 发布包、运行记录、README、许可证 |

### 13.1 视觉门槛细则

六机位 × 两档 = 十二张 1920×1080 原始运行截图，另保留原三机位的前后对照。全部图像对应有效 metadata。至少再有一次沿街、进入新增区域、抬高到露台的实际移动检查，静态图无法替代闪烁/跳变验证。

每个机位按以下六项评分：空间/比例、几何/接触、材质、光照、构图、细节一致性。评分 0=严重问题，1=明显粗糙，2=合格，3=精修。作为本项目人为设定的质量门槛，每机位总分 ≥14/18、任何单项不得低于 2。

评分必须附实际可见理由和至少一个截图区域描述，不能机械填满分。经济档按同样主题和完整性要求评估，不因少量特效关闭扣为缺功能。分数不是客观画质测量，只用于让复核标准一致。

出现明显缺资源、漏光破坏主体、穿插悬空、中文缺字、近景明显 UV 拉伸、可达位置露出虚空、频繁闪烁时，无论总分多少均 FAIL。

审核由能直接查看真实图像的 Agent 或人执行；无图形输入能力时，完成截图采集和问题记录后将 G3 标为 BLOCKED/NOT_RUN，不能用像素统计代替通过。

### 13.2 性能门槛细则

- 目标用户设备、1920×1080 输出、相同供电/驱动条件下，Release expanded_v11 两档各三轮有效采样。
- Eco 每轮平均 FPS ≥29，P95 主循环帧间隔 ≤40 ms；Balanced 每轮平均 FPS ≥58，P95 ≤20 ms。
- P99 与 >100 ms 卡顿次数必须报告。稳定阶段反复出现 >100 ms 卡顿需定位；有效卡顿不能静默剔除。
- 内存、绘制与加载按第 5 节预算检查，注明数据来源。其他设备测量不能宣称已在用户电脑达标。
- 针对低负担目标，记录限帧下 CPU/进程内存表现；只有可用真实功耗数据时才作功耗结论。
- 数据采样正确但某档不达标时为 FAIL，进入定向优化，不降低目标或缩短路线冒充完成。

如果目标设备或模板不可用，可先交付工程和现有证据，但对应 G5/G6 保持未通过。未知 GPU profiler 时间不单独阻断 FPS 门槛；系统内存尚未测量则不能宣布内存预算达标。

### 13.3 发布门槛细则

从新目录运行完整 Release 包，目标机器无需安装 Godot 编辑器、Python、Blender 或启动本地服务器。重新导入/制作是开发过程，不能作为最终用户启动步骤。

验证：默认进入 Eco、六机位正确、设置重启恢复、书签正常、截图目录可写、失焦/最小化策略正确、无缺失 lightmap/字体/JSON、退出后无本项目残留辅助进程。

测试路径包含中文和空格。若使用外置 PCK，必须与 exe 一同交付；不能只发送 exe 就说资源完整。开发用插件/测试脚本不作为运行前置条件。

## 14. 最终文件与报告

交付物至少包括：

1. 完整 Godot 工程，新增内容仍在 M01 中，原地图 ID 和机位 ID 保持兼容。
2. Windows Release 运行目录，匹配预设与明确构建方式。
3. 六机位两档十二张图、必要近景与前后对照、截图元数据。
4. 真实性能原始样本、系统采样、统计报告、失效轮次原因。
5. 构建/烘焙清单、字体与外部资产来源及许可证。
6. `docs/chapter1_1/code_map.md`：实际接口映射与兼容处理。
7. `docs/chapter1_1/review.md`：新增内容、美术复核、优化依据、G0–G6 状态。
8. 更新后的 README、backlog、handoff；已有首版报告不被覆盖成新版本数据。

README 同时给出“开发者用 Godot 打开”和“用户运行发布包”两种方式。个人 Godot 路径只作为可替换示例。规范文档以仓库实际位置为准；若现有路径是 `docs/DESIGN/chapter1.md`，保留并新增 `docs/DESIGN/chapter1-1.md`，不要产生多个互相漂移的同名权威副本。

每轮交接写清：当前工作包、已完成内容、实际运行的验证、截图/日志路径、未验证项、下一项具体工作、精确命令、对本章设计的必要调整及原因。

## 15. 遇到问题时如何继续

| 情况 | 允许的处理 | 不允许的处理 |
| --- | --- | --- |
| 现有接口名不同 | 映射/薄适配，保留真实调用链 | 不看代码直接全部改名 |
| 美术效果不好 | 先修具体构图/材质/比例，保留性能基线 | 增大 Bloom/雾遮盖问题 |
| 扩展超预算 | 定位重区域、减少不可见细节/材质、优化组织 | 删除三个必做区域或悄悄降低验收分辨率 |
| 本机无法烘焙/看图 | 完成可做工作，给出操作入口并保持未验收 | 用旧 EXR/像素统计伪装通过 |
| 字体下载暂不可用 | 保留可运行旧资源，隔离制作输入缺口，推进其他区域 | 声称已替换但实际仍依赖系统字体 |
| 导出模板不可用 | 完成预设与资源规则，明确匹配模板步骤 | 从完成清单中删除发布要求 |
| GPU 时间采不到 | 保留原始帧间隔，GPU 时间标未知 | 用理论 16.67 ms 冒充 GPU 耗时 |
| 生成器破坏精修 | 恢复本轮生成改动，修正责任边界 | 重置整个用户工作区 |

运行时截图/基准/切图发生错误时优先恢复可操作状态，再报告错误。不要新增无关功能转移工作重心。

## 16. 参考依据与执行入口

引擎属性和 API 以本机 4.7.2 实测为准；以下 stable 文档可能随时间更新：

- [渲染器能力与差异](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)
- [后台资源加载](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)
- [LightmapGI 工作流](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html)
- [LightmapGIData 的资源/用户查询](https://docs.godotengine.org/en/stable/classes/class_lightmapgidata.html)
- [RenderingServer 与图形运行环境](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)
- [遮挡剔除](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)
- [Performance 指标口径](https://docs.godotengine.org/en/stable/classes/class_performance.html)
- [Time 单调计时](https://docs.godotengine.org/en/stable/classes/class_time.html)
- [Godot 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)

本文中的布局、接口组合、任务顺序、预算和美术评分是项目设计决定，不是官方性能保证。

**现在从 WP0 开始，按依赖顺序持续推进。最终必须同时交付看得见的地图升级、可靠的工程改动和真实验收证据。不要仅修复旧测试，也不要仅输出一份新的宏观计划。**
