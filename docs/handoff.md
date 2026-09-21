# 本轮交接

- **当前工作包**：chapter1-2（`docs/DESIGN/chapter1-2.md`）视觉验收收尾——Flash 独立模型验收循环与缺陷修复全部完成。
- **上一轮已提交 88d803d**（1.2 完整落地：室内地图+街面丰富+双图烘焙+性能达标）。本轮在其上完成「Flash 验收 → 修复 → 再验收」闭环。
- **本轮验收循环（GLM-5.3-Flash 独立模型，经 workflow 子代理读 PNG）**：
  1. 首轮 26 张：18 pass / 8 fail → 按缺陷修复（gallery/dining 构图、窗面死黑、中庭餐区暗、门口被轮胎挡、门不可辨、衣物彩色弱）。
  2. 复验 16 张受影响镜头：14 pass / 2 fail——仅剩 gallery_view 两档。
  3. gallery 终验 v3：0/2 FAIL 且描述与几何矛盾 → 排查证实锚点数据链无误（`tools/debug_anchor_pose.gd` 实测俯角 -41.08°），根因是**画面内容不可读**。
  4. 三轮内容修复（v4 灯光/材质 → v5 内容补充）：主灯 2.9/8.0 西移贴中庭、二层冷渗灯、地毯提亮、门头木檐板+发光店招+两幅挂画、路灯②移位、两处自发光光池 `pool_glow`（Backdrop 不烘焙无实时光，光池必须自发光）。
  5. v5 取色自检（`tools/sample_png_grid.gd` 12×8 网格）三项目标全中：光池 #815F48 级首次透橱窗可见、地毯带 +25%、门头带成带可读。
  6. 终验（v5 两档 gallery）**0/2 FAIL**，四个根因几何定位：栏杆近端粗带（距栏 0.38m 近俯视投影，占底 23%）、店招无字（uv2 是 lightmap UV 非文字）、可见街楔是斜线（对面楼/灯头全被橱窗檐墙挡）、黑色钩状物=停泊摩托远景剪影误读。
  7. 四轮修复（v6）：机位重算距栏 0.7m/两柱正中/俯 46°；店招换 `sign_repair` 字图材质（2.0×0.5m）；街景重排进 d≤3.4 人行道楔（双层光池+亮核/树×2/邮筒/挂旗/候车凳/斑马线/摩托塑形+尾灯）；灯串扩 9 灯；补修 `plant_green` 材质缺失（既有缺陷：_load_materials 无此键 → surface 挂 null 材质灰白）。
  8. v6"取色自检六项全中"事后证明是**语义误读**（颜色存在≠位置语义正确）：#D5B69C 实为挂画纸色/墙带而非店招字带、#425A43 实为 1F 室内绿物而非街树、#84634B 实为店内暖色而非街景光池。取色只能证明"该色出现在该格"，不能证明"该格是某物体"。双图回归 v6 全绿属实（`regression_20260922_v6.log`：verify 43/lifecycle/ch11 64/ch12）。
  9. 终验（v6 两档 gallery）**0/2 FAIL**（店招无字/栏杆粗横带/青绿横带碎片化/立柱斜穿/悬浮亮面片等六项）。
  10. v7 根因定位（runtime 隔离渲染二分）：generated/map.tscn 的 sign surface 材质绑定、UV1、纹理导入（decompress 采样亮度 0.06..0.75 确认有字）全部正常；`tools/debug_sign_isolate2.gd` 把同一 surface 抽出单独渲染，tres/动态材质/QuadMesh 正控制三块全部出字 → 材质链无罪，问题在全场景。**真因：前墙墙体 x -0.12..0.12，v6 门头组檐板(-0.02..0.1)/店招(0.11)/挂画背板(0.02..0.12) 全部埋在墙体内，深度失败从不渲染——画面那块"均匀暖米色"就是店招身后的墙**（旁证：poster quad x=0.13 在墙外 0.01m 所以海报一直渲染正常）。"栏杆粗横带/青绿横带"=贴栏机位下木质扶手(4.07..4.19)+metal_teal 中横杆(眼高)的近水平投影双带。
  11. v7 修复与取证：门头整组移到墙内面前方（檐板 0.12..0.24、店招 x=0.25、挂画背板 0.12..0.22/画面 x=0.23）；gallery_view 改中距俯 21°（pos [7.6,4.77,0.6] look [0.8,2.1,0.2]，距栏 4.2m）。重建链 generate→assemble→bake(users=4, 3.4s)→verify 24/24→截图 v7 10 张。客观取证（`tools/debug_grid_stats.gd` 炸亮像素统计）：两档 gallery 上部 7-28% 中央炸亮像素 17-35%（店招字迹首次进入成品截图）、dining 中部同见字迹亮区；粗横带消失。
  12. 终验（v7，Flash 中性判读+标准验收双轮）：eco 档 6/6 PASS；balanced 5/6，唯一 FAIL=D"分层可读"——**中距机位（x7.6）几何上根本看不到一层中庭**：楼板沿口对一层地面是位置性遮挡（推导：x_c>3.8 的站位恒不可见，与俯角无关）；店招"余晖维修/AFTERGLOW REPAIR"两档判读一致确认清晰可读。对照 chapter1-2 §3.7 构图职责"俯瞰中庭与一层橱窗街景"判定为真缺陷，必须修机位。
  13. v8 修复（投影几何解法）：**站栏杆正后方 0.2m（x3.6，两柱正中 z-0.93）正西俯 40°**——立柱方位角 ≥67° 出画、扶手/中横杆俯角 ≥73.7° 在画框底(70°)外、楼板沿口 84° 出画；画框 10°..70° 三层：2F 墙+店招（正对无斜角）/1F 橱窗暮色街景带/中庭地毯+等候椅。店招上移 y 3.20..3.70 避开檐板投射阴影（投射阴影与俯角无关，原埋墙修复后仍会遮店招下 27%）。摆拍验证（debug_pose_v8）→bake（users=4）→verify 24/24→v8 截图 10 张（`screenshots_v8/`，店招炸亮 5.8-40.5%，檐板下死黑带消除）。
  14. 终验（v8，Flash 中性判读+标准验收双轮）：eco 6/6 PASS；balanced 5/6，唯一 FAIL=B——裁判像素实测底部横带 y≥951、129px=11.9%（>8% 阈值）、R59/G24/B12 实心无立柱韵律。复核确认该带**不是栏杆**（立柱已全出画）而是掠射角下的近景地毯/地面暗带被读作"实心板"——但 12% 高度的平坦暗区确是构图弱点，判真实缺陷。
  15. v9 修复：中庭毯边加待修件木箱×2（叠放 0.47×0.34×0.46）+ 橙色工具箱，恰落在画框底部 83-89% 高度带打断横带、增加生活痕迹；重烘焙（users=4）→verify 24/24→v9 截图 10 张（`screenshots_v9/`，固定文件名；底部带内容值 0.15→0.15-0.57 有变化层次）。
  16. 终验（v9，Flash 中性判读+标准验收双轮）：**两档全部 PASS**。balanced 6/6（裁判 PowerShell 像素实测：店招区深底 10,758px/亮笔画 2,379px 确证字迹；橱窗带冷调 rgb(43,48,72) 与地毯 rgb(223,104,77) 冷暖对置；x=960 纵向三层色彩跃迁清晰；近死黑 9.68% 均为实体内容；底缘深棕窄带 70px=6.5%<8% 判废线，判 PASS 并附注"疑似楼面收边轻微入画，属可接受"）；eco 6/6（招牌六字完整无缺字、三层可辨、无渲染异常）。其余 6 张（entry/workbench/dining 两档）巡检无 FAIL 级缺陷。gallery_view 验收闭环：v6 0/2 → v7 店招入图但中庭不可见 → v8 中庭可见但底部带 11.9% → v9 全过。
- **本轮修复的管线级缺陷（重要机制，后续必读）**：
  1. **指纹假 stale**：Godot 4.7 保存 .tscn 时每节点写随机 `unique_id=NNN` → 清单永 stale、烘焙被无谓重跑。三处 `_hash_files`（assemble_m01 / assemble_interior / verify_build）统一先剥离 `unique_id=\d+` 再哈希；mesh .res 字节稳定按原样。
  2. **截图光标残留**：`_shoot_anchors` 应用机位后把鼠标 warp 到右下角。
  3. **多模态验收机制更正**：GLM-5.3-Flash`$max` workflow 子代理**可以**读 PNG（此前“多模态不可用”记录过时）；用法：CreateWorkflow + `subagent_model=account:bigmodel-individual-coding-plan/GLM-5.3-Flash$max`，草稿 `.zcode/workflow-drafts/gallery_final_check.dwf.ts`（TS 不支持 `:=`）。
  4. **无图像输入时的目检替代**：`tools/sample_png_grid.gd` 网格取色（用法 `--script ... -- <png绝对路径> 12 8`），配合几何坐标推带位可判定画面内容。
  5. **像空间几何必须用 tan 映射**：画面 y 像素↔俯仰角用 f=540/tan30°=936px 的 tan 校正（θ=atan((540−y)/936)），线性行假设会错 20°；水平角同理 (x−960)/960×tan(45.7°)。
  6. **二层俯瞰橱窗的可见街楔**：从 y4.77 透过橱窗（y0.45..3.0）看街，可见街高 y ≤ 3.0 − (1.77/x_cam)×距离（x_cam=4.1 时斜率 0.4317/m）——对面楼与路灯头全被檐墙挡；可读街景必须放 d≤3.4 人行道带。
  7. **栏杆投影几何**：相机高出扶手 0.67m、距栏 d 时扶手成俯角 −atan(0.58/d) 细线、楼板边成 −atan(1.62/d) 切割线；d 越大切掉越多近处地面；立柱 z 网格 −4.78+1.1k，机位 z 必须居两柱之间。
  8. **贴墙 quad 埋墙检查**：手工 quad 贴墙面时必须先核对墙体盒的实际范围（内表面位置≠墙面中心线），凸出 ≥0.01m 才能通过深度测试；"隔离渲染正常、全场景不可见"先怀疑埋墙/遮挡而非材质。诊断路径：`tools/debug_sign_material.gd`（运行时材质/UV）→ `tools/debug_sign_texture.gd`（decompress 验纹理内容）→ `tools/debug_sign_isolate2.gd`（surface 抽出单独摆拍二分）。
  9. **炸亮像素统计是取色的升级替代**：`tools/debug_grid_stats.gd -- <png> [cols rows]` 输出每格均值亮度+炸亮(>0.85)占比，可客观探测自发光字迹/灯牌有无与位置，无需视觉模型；但"该位置是什么物体"的语义判断仍须视觉模型中性描述交叉，取色/取亮都不能单独下语义结论。
- **实际执行过的验证及结果**：
  - 双图 verify(43) + 生命周期 + ch11 + ch12 合同全绿（最终 v9：`artifacts/chapter1_2/regression_20260922_v9.log`；过程 v6/v7/v8 各有存档 log）。
  - 烘焙：室内 users=4 `bake_report_20260921T174248.json`（NEON_BAKE_EXIT=0）；街区 users=10 `...T125924.json`。
  - 截图：`screenshots_v9/`（最终验收版 10 张，固定文件名；gallery 两档终验 PASS）；过程存档 `screenshots_v6/`（FAIL 复盘用）、`screenshots_v7/`、`screenshots_v8/`。
- **尚未验证的内容与原因**：
  1. 实机 F 键门户往返步行体感与巡走清单（人工项）。
  2. G6：含 1.2 双图内容的 Windows Release 重导出与独立目录实测（现存 `build/windows/neon_haven.exe` 为 chapter1-1 内容）。
  3. G5：进程级采样补全；室内 60s 稳态 `--perf` 采样。
- **当前阻塞问题**：无。
- **下一轮第一项任务**：G6 重导出（含 1.2 双图内容）并独立目录实测；随后补 G5/室内稳态采样。
- **精确启动/测试命令**（`$G = "D:\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"`）：
  - 双图全管线：`.\tools\build_chapter11.ps1 -GodotExe $G -ProjectPath . -Stage all -MapId both`（注意：PS5.1 读 UTF-8 无 BOM 中文可能乱码解析失败，失败时直接逐条调 Godot）。
  - 单图验证：`& $G --headless --path . --script res://tools/verify_build.gd -- --map m01_repair_interior`
  - 生命周期（含双图 T10）：`& $G --headless --path . --script res://tests/test_map_lifecycle.gd`
  - 截图：`& $G --path . res://scenes/app/main.tscn -- --shoot --map m01_repair_interior --quality both`（按分钟前缀从 `user://captures` 收集）。
  - 取色自检：`& $G --headless --path . --script res://tools/sample_png_grid.gd -- <png绝对路径> 12 8`
- **需要保留的美术或技术决定**：
  1. gallery_view 预期画面=“暮色冷调玻璃带+暖色路灯光池”的冷暖对比（不是整面暖光带）；栏杆立柱属设计元素。
  2. Backdrop（不烘焙、无实时光）中需要可见的发光面必须用自发光材质（`pool_glow` 先例）。
  3. 手写 quad 绕序铁律、A 牌非发光层级、内外分图+门户架构均沿用（见 review.md 缺陷记录）。
