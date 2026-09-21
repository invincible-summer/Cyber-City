# 待办（chapter1 / 1-1 / 1-2 工作包）

> 状态：未开始 / 进行中 / 完成 / 待验证。更新：2026-09-21（chapter1-2 收尾）。

## chapter1-2（余晖维修·店内 + 街面丰富）

| # | 任务 | 状态 |
| --- | --- | --- |
| WP0 | 基线确认（1.1 验证入口全绿） | 完成 |
| WP1 | 运行时合同：MapDef v2 walk/portals、步行相机、门户接线（`tests/test_chapter12_contract.gd` 19/19） | 完成 |
| WP2 | 室内地图制作与烘焙（build_interior/assemble_interior/多图烘焙插件；users=4 missing=0） | 完成 |
| WP3 | 门户接线（街区门几何/门口锚点/门户；T10 双图往返 ×10 全过） | 完成 |
| WP4 | 街面丰富 street_enrich 六组道具 + 街区重烘焙（users=10 missing=0） | 完成 |
| WP5 | 验收采样：26 张截图 + 双图生命周期 + 性能 | 完成（见 review） |
| WP6 | 文档（AGENTS 修订/README/handoff/review）+ 提交 | 完成 |

## chapter1-1（已并入历史，遗留 G5/G6）

| # | 任务 | 状态 |
| --- | --- | --- |
| G5 | 全量性能采样（legacy_v1 + expanded_v11 两档×3 轮 + sample_process.ps1 进程采样） | 部分（1.2 轮已补 legacy_v1 两档×1 轮 valid；expanded_v11 与 ×3 轮未跑） |
| G6 | 干净检出 Release 导出与独立目录运行 | 待验证（模板已装、导出成功过一次；1.2 内容后未重导出） |

## 遗留清单（下一轮）

1. **G6 导出**：1.2 内容稳定后重导 `build/windows/neon_haven.exe`，中文+空格路径实测双图门户切换。
2. G5 补全：expanded_v11 路线 ×3 轮 + `--occlusion off` 对照 + `tools/sample_process.ps1` 工作集采样。
3. 室内稳态 60s 采样路线（当前用截图 render_stats 口径：draw 3-5 / primitives ~4.3k）。
4. 实机人工项：F 键门户往返步行体感、摄影模式巡走清单（`docs/chapter1_2/review.md` 末节）。
5. 街区图 `--perf` 在无人值守会话需 `tools/focus_keep.ps1` 保持前台焦点，否则失焦中止（设计行为）。
