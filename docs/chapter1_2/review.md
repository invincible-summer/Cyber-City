# chapter1-2 验收记录 — 余晖维修·店内 与 街面丰富

> 对应设计：`docs/DESIGN/chapter1-2.md` · 日期：2026-09-21
> 状态图例：PASS（有证据）/ FAIL（如实记录）/ NOT_RUN（未执行）。

## 门槛矩阵

| 门槛 | 内容 | 状态 | 证据 |
| --- | --- | --- | --- |
| H0 基线 | 1.1 验证入口全绿 | PASS | verify_build 42 项（双图）、lifecycle/1.1/1.2 三套件全绿 |
| H1 运行时合同 | walk/门户/MapDef 扩展 + 旧测试回归 | PASS | test_chapter12_contract 19/19、test_chapter11_contract 64/64、test_map_lifecycle 全过（含新增双图 T10 段） |
| H2 室内烘焙 | build_interior → assemble → bake → verify | PASS | bake_report_20260921T103955：users=4（3 网格+Backdrop）missing=0；verify 24 项过 |
| H3 门户接线 | 街区门几何/锚点/门户 + 往返 | PASS（数据/合同层） | assemble：anchors=7 portals=1 exclusions=47；T10 双图 10 往返全过；实机 F 键往返见"待图形环境人工项" |
| H4 街区丰富 | street_enrich 六组 + 重烘焙 | PASS（构建层） | authored props tris 4876（新增约 2.5k ≤ 1.5 万预算）；烘焙 users=10 missing=0 含 PropsStreetEnrich；视觉对照见 §视觉验收 |
| H5 验收采样 | 双图截图/性能/生命周期 | PASS（自动项全绿；逐张人工目检受限转人工复核，见"截图与视觉验收"节） | 26 张截图 + perf 两档 valid + T10 双图往返 |
| H6 文档 | AGENTS/README/handoff/review/backlog | PASS | 本文件 + AGENTS.md §0 修订写回 + handoff 更新 |

## 自动化验证明细

- `tools/verify_build.gd`（双图版，`--map` 参数化）：42 项 PASS。
  - 室内 walk 合同：4 锚点眼高全部贴合行走面（±0.02m）；门户目标定义存在。
  - authored 基线：street_enrich 合法更新（build_authored 重跑），指纹一致。
- `tests/test_map_lifecycle.gd`：全过，新增 §6b 双图（街区↔室内）×10 往返：
  活动地图恒 ≤1；两图网格资源弱引用双向失效；预热后内存下降 0 MiB（阈值 150）。
- `tests/test_chapter11_contract.gd` 64/64、`tests/test_chapter12_contract.gd` 19/19。
- 烘焙报告：室内 `artifacts/chapter1_2/bake_report_20260921T103955.json`（3.64s）；
  街区 `bake_report_20260921T105801.json`（11.38s，users=10/expected=9+Backdrop，missing=0）。

## 截图与视觉验收

- 室内 10 张（4 机位 × eco/balanced + 2 diag）：`artifacts/chapter1_2/screenshots_interior/`
- 街区 16 张（7 机位 × 两档 + 2 diag）：`artifacts/chapter1_2/screenshots_street/`
- **像素统计复核**（visual-judge 子代理，像素级）：26 张全部有效 1920×1080 可解码；
  无整帧死黑/整片过曝（过曝占比最高 0.26%）；室内暗部（<5 亮度）5–15% 属蓝调时刻阴影区，
  无全黑帧；eco 与 balanced 同机位统计高度一致（档位只降分辨率不改内容）。
- **逐张独立模型目检：受环境限制未完成，如实记录**。三条路线均受阻：
  ① 会话模型与 visual-judge 模型无图像输入（返回"Media omitted"）；
  ② GLM-5.3-Flash 子代理读 PNG 三次均"Turn execution failed"（多模态负载 turn 级失败）；
  ③ gpt-5.6-sol provider 认证过期（需用户重新登录，见 `docs/handoff.md`）。
  **补救与兜底**：新道具全部坐标在编码期逐一对照既有物件（路灯/长椅/电杆/配送箱/机位视线走廊/
  门户落点）核对避让，避让清单写入 `tools/build_authored.gd` street_enrich 头注释；
  烘焙覆盖（missing=0）、构图机位姿态（JSON 元数据）、渲染计数（render_stats）已程序化验证。
  26 张原图保留在 artifacts 供人工复核——这是本轮唯一待人工项（非跳过冒充完成）。

## 性能记录（真实测量，2026-09-21，RTX 5070 Ti Laptop / 4.7.2 project_run）

- 街区 `--perf` legacy_v1 ×1 轮 ×两档（均 valid，60s，vsync enabled）：
  - **Eco**：avg 30.0 FPS（顶格上限）、P50 33.3ms、P95 33.5ms、P99 33.5ms、>100ms 卡顿 0 —— **达标**（≥29 / P95≤40 / 无卡顿）。
  - **Balanced**：avg 60.0 FPS（顶格上限）、P50 16.7ms、P95 16.8ms、P99 16.8ms、>100ms 卡顿 0 —— **达标**（≥58 / P95≤20）。
  - 环境：draw_calls_peak 8、map_node_count 95、引擎显存峰值 Eco 242 / Balanced 282 MiB。
- 室内（截图 render_stats 口径，balanced）：draw calls 3–5、可见 primitives ~4.0–4.7k、
  显存 196 MiB —— 远低于预算（≤150 draw / ≤60k tris）；单点 FPS 受截图磁盘 IO 扰动不作稳态结论，
  完整 60s 静置采样列入遗留（backlog #3）。
- 双图生命周期 T10：10 往返，活动地图恒 ≤1，两图网格资源弱引用双向失效，预热后内存下降 0 MiB。

## 本轮修复的既有缺陷

1. **侧巷晾架穿模**（1.1 遗留）：洗衣晾架与水桶位于南翼 SC_S 建筑体内部（z≈-14.6），实际不可见；
   移除并在建筑外重做 G5 晾衣组。露台晾衣衣物单面绕序反（从南侧不可见），已改双面正确绕序。
2. **自动截图节流竞态**（1.1 遗留）：`_shoot_anchors` 每锚等待 0.45s < CaptureService 节流 500ms，
   balanced 档曾静默缺 entry/workbench 两张；已改 0.62s + 失败重试 + 警告。
3. bake_plugin 多地图化（`--scene` 推导 map_id/清单/报告路径）；`build_chapter11.ps1 -MapId both` 路由；
   verify_build 双图参数化（`--map` 缺省验注册表全部）。

## 待图形环境人工项（如实记录）

- 实机 F 键门户往返的步行体感（上楼节奏/门开合观感）——合同与数据层已自动验证。
- 摄影模式手动巡走检查清单（chapter1-2 §9.2 第 4 条）。
