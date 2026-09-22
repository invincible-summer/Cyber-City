# 本轮交接

- **当前工作包**：chapter1-3（`docs/DESIGN/chapter1-3.md`）——本轮完成 **WP0–WP7 工程信任链全部落地 + 两图生产重建 + 22 图回归验收**；WP8/WP9（主场景美术深化）与 WP10（最终发布验收）未开始。
- **本轮提交**：3a08948（工程链全量）+ 回归验收/文档提交（见 git log）。基线：07f135b（计划定稿，实施为零）。
- **本轮完成的核心事实**（细节与证据见 `docs/chapter1_3/review.md`）：
  1. `tools/build_contract.gd`：依赖闭包 + bake_input_hash（文件集+烘焙设置+环境快照）+ can_reuse_bake + write_json_recoverable。实测要点：三张生成场景的 mesh/material 均内嵌 tscn（外部 meshes/*.res 是不被引用的旁路产物），闭包机制自动覆盖真实依赖。
  2. manifest v2 状态机：assemble 不再"清空 bake 保留 succeeded"；v1 一律 stale（一次性迁移）；bake 先落 manifest=running 再清数据；no-op assemble 复用真实烘焙数据（hash 稳定、succeeded 保留）已生产实证。
  3. authored 去重：29→20 exclusions、0 精确重复、street=38——与计划 §7.4 预测一致；生成器内重复即 exit 1；build_m01 ownership 指纹断言 PASS。
  4. 运行时：质量档完整实时应用、地图 occlusion 唯一权威（street true/interior false/切图恢复）、orphan 超时收尾、preflight 拒绝保留 READY 壳层、capture abort 统一幂等 finish、锚点 1–9 公开接口、书签 revision 标签、registry 原子加载、自动化全失败出口（截图不再静默跳图）。
  5. Benchmark：measured snapshot 冻结（报告不再读恢复后状态）、headroom 由 restore_runtime_state 单一恢复、路线-map 强校验、interior_v13 路线、输出路径/run_id 安全、build_id。
  6. WP7 删除：根级旧 lightmap、authored_props_mesh.res、bake_m01.gd/run_bake.tscn/finalize_bake_manifest.gd、authored baseline（引用扫描门槛全过，删除后全绿）。
  7. 验证：verify_build v2 street 23 + interior 28 全 PASS；lifecycle/ch11/ch12/**ch13（新增 83 项）** 全绿；两图 22 PNG+22 JSON（§29 固定命名，`artifacts/chapter1_3/screenshots/final/`，build_id=3a08948-local）。
  8. **Flash 独立模型验收**：GLM-5.3-Flash`$max` 双遍（中性描述→rubric）22 图回归验收——**22/22 PASS、0 硬失败、平均 13.2/18**，工程重建未引入视觉回归、无需修复（逐图矩阵见 workflow 产物 quality-matrix；结构化结论 `artifacts/chapter1_3/visual_regression_flash.json`）。
- **本轮踩坑与机制（后续必读）**：
  1. **bake 输入排除规则会过滤 res://tests/**：ch13 敏感度 fixture 必须放 gitignored 目录（测试用 `.zcode/tmp/t13_fixture`，用完即删）。
  2. **ResourceLoader.get_dependencies 对伪造二进制 .res 会打印 ERROR 但返回空数组**（不中断）；闭包继续处理其余路径——正常现象，不是崩溃。
  3. **PS5.1 + UTF-8 无 BOM 中文 ps1 可能乱码**：本轮生产链按 tools/README.md 单步直调 Godot（与 ps1 阶段等价）；ps1 仍是官方统一入口。
  4. **headless 下 MapRoot 粒子节点无 node_groups meta**（由 _setup_ambient 运行时 add_to_group）；树遍历计数用 is GPUParticles3D 而非 meta。
  5. `quit(1)` 在嵌套函数里会先返回继续外层执行、末尾 quit(0) 会覆盖退出码——构建脚本的子步骤必须返回 Error 由 `_run` 链式检查（本轮已按此重构三个 build 脚本）。
- **尚未验证的内容与原因**：
  1. WP8/WP9 全部美术项（art_baseline_v13、StreetEnrich 拆区、backdrop archetype、分区内容、材质/灯光终验、14 图 ≥15/18 门槛）——未开始，下一轮首选。
  2. WP10：最终全管线重跑、正式性能（expanded_v11+interior_v13 两档×3+occlusion 对照+sample_process 四组）、Windows Release 重导出+中文/空格独立目录+人工门户巡走。
  3. 街区 content_revision 仍为 1.2.0（§7.5：等 WP9 冻结后一次升 1.3.0 再走最终链）。
- **当前阻塞问题**：无。
- **下一轮第一项任务**：WP8——记录 art_baseline_v13 → 新增 `tools/m01_detail_lib.gd` → PropsStreetEnrich 拆 South/Mid/North（画面无变化验证）→ backdrop 四类 archetype（§27.1 顺序 1–3）。
- **精确启动/测试命令**（`$G = "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`）：
  - 全管线（PS 入口）：`.\tools\build_chapter11.ps1 -GodotExe $G -ProjectPath . -Stage all -MapId both -BuildId <sha-rc1> -ArtifactDir res://artifacts/chapter1_3`（乱码时按 tools/README.md 单步直调）。
  - 只验证：`& $G --headless --path . --script res://tools/verify_build.gd [--map <id>]`
  - 测试：`test_map_lifecycle.gd` / `test_chapter11_contract.gd` / `test_chapter12_contract.gd` / `test_chapter13_contract.gd`
  - 截图：`& $G --path . -- --shoot --map m01_afterglow --quality both`（22 张两图命令见 tools/README.md；失败即非零退出）
  - 性能：`& $G --path . -- --perf --map m01_repair_interior --route interior_v13 --quality both --runs 3 --warmup 15`
- **需要保留的美术或技术决定**：
  1. BuildContract 的 bake_input_hash 数值统一 5 位小数规范化（内存值与 tscn 往返值同签名）；LightmapGI 属性清单以本机 4.7.2 property list 实测为准（quality/directional/interior/use_denoiser/bias/texel_scale/environment_mode/custom_*）。
  2. environment_mode=1(SCENE) 下两图 WorldEnvironment 纳入烘焙签名；改环境参数会正确触发 stale。
  3. "users=10/4"历史口径在 WP8 拆区后作废；以 manifest expected/actual/missing 为唯一权威（§20.3）。
  4. 沿用 chapter1-2 的全部美术决定（gallery 预期画面、Backdrop 自发光、贴墙 quad 凸出 ≥0.01m 等，见上一版 handoff 与 `docs/chapter1_2/review.md`）。
