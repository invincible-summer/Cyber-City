# 待办（chapter1-3 工作包）

> 状态：未开始 / 进行中 / 完成 / 待验证。更新：2026-09-22（chapter1-3 工程信任链收口）。

## chapter1-3（工程可信性收口、主场景成品建设与发布验收）

| # | 任务 | 状态 |
| --- | --- | --- |
| WP0 | 冻结基线（manifest/重复计数/引用扫描） | 完成（`artifacts/chapter1_3/wp0_baseline.json`） |
| WP1 | BuildContract + manifest v2 + verify 只读化 | 完成（no-op hash 稳定；v1 不继承 succeeded） |
| WP2 | assemble/bake 状态机 + required output Error 传播 | 完成（无"空 bake+succeeded"；running 先落盘；missing/save/report 失败即 exit1） |
| WP3 | authored 去重 + ownership 保护 + street 重建重烘 | 完成（authored 20/0 重复、street 38；重烘 missing=0；no-op 复用实证） |
| WP4 | 运行时质量档/occlusion/orphan/preflight/capture abort | 完成（ch13 T13-13…17 全过） |
| WP5 | 锚点 1–9/capture anchors/书签 revision/registry 原子/portal/自动化失败出口 | 完成（ch13 T13-18…20、T13-08…12 全过） |
| WP6 | Benchmark 正确性 + interior_v13 路线 | 完成（measured snapshot/恢复顺序/路径安全；路线 map 校验） |
| WP7 | 删除旧架构/死资产 | 完成（引用扫描门槛过；删除后全绿） |
| — | 两图生产重建 + 22 图回归验收（Flash 双遍） | 完成（本轮；结果见 `docs/chapter1_3/review.md`） |
| WP8 | 主场景结构与城市系统深化（detail_lib/拆区/backdrop/立面/分区） | **未开始（下一轮首选）** |
| WP9 | 材质/灯光/招牌/构图终验 + street 升 1.3.0 | 未开始 |
| WP10 | 最终重建/22 图/性能/Release/人工巡走/文档 | 未开始 |

## chapter1-1/1-2 历史遗留

| # | 任务 | 状态 |
| --- | --- | --- |
| G5 | 全量性能采样（expanded_v11 + interior_v13 两档×3 + occlusion 对照 + sample_process） | 未跑（并入 WP10；截图 render_stats 口径：draw 3-5 / primitives ~4.3k） |
| G6 | 干净检出 Release 导出与独立目录运行 | 待验证（模板已装；1.3 最终内容后执行，并入 WP10） |

## 遗留清单（下一轮）

1. **WP8 起步**：记录 art_baseline_v13（tris/节点/lightmap users/显存/expanded_v11 一轮/7 锚点图）→ 新增 `tools/m01_detail_lib.gd` → PropsStreetEnrich 拆 South/Mid/North（画面无变化验证）→ backdrop 四类 archetype。
2. WP8 注意：拆区后 expected bake users 净增 2，所有"users=10"历史口径作废，以 manifest expected/actual/missing 为权威。
3. 实机人工项：F 键门户往返步行体感、摄影模式巡走清单。
4. 无人值守 perf 需 `tools/focus_keep.ps1` 保持前台焦点，否则失焦中止（设计行为）。
5. 本机 PS5.1 跑 `build_chapter11.ps1` 若中文乱码解析失败，按 tools/README.md 的单步命令直调（等价）。
