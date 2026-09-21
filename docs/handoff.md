# 本轮交接

- **当前工作包**：chapter1-2（`docs/DESIGN/chapter1-2.md`）WP2 续做 → WP6 收尾。室内地图与街面丰富全量落地，双图烘焙与验收完成。
- **本轮完成（按工作包）**：
  - **WP2 续**：室内烘焙续跑成功（users=4 含 Backdrop，missing=0，3.64s）；`tools/verify_build.gd` 重写为双图参数化版（`--map` 缺省验注册表全部；室内 walk/portals 合同 + 行走面×锚点眼高一致性 ±0.02m）；`tools/build_chapter11.ps1` 支持 `-MapId m01_repair_interior|both` 路由（generate/assemble/bake/verify 全阶段）。
  - **WP4 街面丰富**（`tools/build_authored.gd` 新增 `_street_enrich_props` 六组，约 2.5k tri）：
    G1 花钵行道树×4+树下凳、G2 自行车棚(3 车青顶)+滑板车站牌×2、G3 便利店外摆冰柜/报刊架/A 牌"今日特惠"+侧巷口罩布夜宵摊车+忘关摊灯、G4 维修铺广场 A 板"营业中"/斜靠自行车架/油桶托盘/手推车、G5 生活广场晾衣绳两组(三色衣物)+水池拖把+杂物架+猫窝、G6 井盖×4/消防栓/锥桶×3/排水篦×2。
    新增烘焙灯 2（摊车/晾衣各 1）、禁入 AABB 7。`tools/gen_signs.gd` 新增 `special`/`open_board` 两张非发光 A 牌字图（Noto Sans SC）。
  - **WP3/WP4 产物**：街区 revision 1.2.0 重烘焙（users=10 含 PropsStreetEnrich/门扇，missing=0，11.38s）。
  - **WP5**：26 张截图（室内 10+街区 16）；lifecycle 测试扩展 T10 生产双图往返 ×10（活动地图恒 ≤1、双向资源弱引用失效、预热后内存 0 MiB 增长）；街区 `--perf` legacy_v1 两档各 1 轮 valid（Eco 30.0 FPS/P95 33.5ms/0 卡顿；Balanced 60.0 FPS/P95 16.8ms/0 卡顿）；室内以截图 `render_stats` 口径记录（draw 3-5、primitives ~4.3k、video mem 156-196 MiB）。
- **本轮修复的既有缺陷**：
  1. **侧巷晾架/水桶穿模**（1.1）：原位于 SC_S 建筑体内（z≈-14.6）不可见——移除并由 G5 在建筑外重做；**露台晾衣单面绕序反**（从南侧不可见）改双面正确绕序。
  2. **自动截图节流竞态**（1.1）：`_shoot_anchors` 每锚 0.45s < capture 节流 500ms，balanced 档曾静默缺 2 张；改 0.62s+重试+警告。
  3. `capture_service` JSON 元数据新增 `render_stats`（fps/draw_calls/primitives/video_mem，截图瞬间与诊断面板同源）。
- **实际执行过的验证及结果**：
  - `verify_build` 双图 42 项 PASS；`test_map_lifecycle`（含双图 T10 扩展）/`test_chapter11_contract` 64/`test_chapter12_contract` 19 全绿。
  - 烘焙报告：`artifacts/chapter1_2/bake_report_20260921T103955.json`（室内）、`...T105801.json`（街区）。
  - 截图与性能：`artifacts/chapter1_2/screenshots_interior|screenshots_street/`、`perf_street.log`、`user://benchmarks/v11_legacy_v1_*_r0`。
- **本轮确认的关键机制（后续必读）**：
  1. **手写 quad 绕序铁律**：输入顶点序从法线侧看逆时针 ⇔ (p1-p0)×(p2-p1) 指向法线。box/cylinder 已内建；自写 quad（A 牌/罩布/衣物）必须按此验证——镜像面（背板/另一坡）要翻转顶点序。
  2. A 牌/白板类非发光字图用普通 StandardMaterial3D（区别于 sign_* 发光招牌）；字面 UV 底部 v=1。
  3. 无人值守会话 GUI 窗口拿不到前台焦点 → `--perf` 失焦中止（设计行为）；用 `tools/focus_keep.ps1`（ALT nudge+SetForegroundWindow 循环）配合采样。
  4. GLM-5.3 / GLM-5.3-Flash(offpeak) 子代理读 PNG 均 turn 失败（多模态不可用）；视觉验收受环境限制，以像素统计+render_stats+测试证据替代（见 review"待图形环境人工项"）。
- **尚未验证的内容与原因**：
  1. 实机 F 键门户往返步行体感与巡走清单（人工项；合同/数据/生命周期层已自动验证）。
  2. 独立模型逐张目检（多模态 turn 失败；26 张图与像素统计已在 artifacts 供人工复核）。
  3. G5/G6 剩余（expanded_v11×3、进程采样、1.2 内容后的 Release 导出）。
- **当前阻塞问题**：无。
- **下一轮第一项任务**：G6 重导出（含 1.2 双图内容）并独立目录实测；随后补 G5 采样。
- **精确启动/测试命令**（`$G = "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`）：
  - 双图全管线：`.\tools\build_chapter11.ps1 -GodotExe $G -ProjectPath . -Stage all -MapId both`
  - 单图验证：`& $G --headless --path . --script res://tools/verify_build.gd -- --map m01_repair_interior`
  - 生命周期（含双图 T10）：`& $G --headless --path . --script res://tests/test_map_lifecycle.gd`
  - 截图：`& $G --path . -- --shoot`（街区）/ `-- --shoot --map m01_repair_interior`（室内）
  - 性能（需前台焦点）：后台起 `& $G --path . -- --perf --runs 1`，同时 `powershell -File tools\focus_keep.ps1`
- **需要保留的美术或技术决定**：
  1. 内外分图 + 门户是既定架构（chapter1-2 D1）；室内坐标独立，不追求内外网格无缝。
  2. A 牌非发光（白板/黑板风）与发光霓虹招牌形成层级；摊车"忘关的灯"是有意的叙事微光。
  3. 行道树/衣物/罩布等风格化低模语汇（薄盒轮、八面体叶冠、双面布片）延续 GenLib 体系。
