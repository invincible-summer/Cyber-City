# 资产与素材来源

> 所有运行时资产均为**原创程序化生成**，无外部商业素材。更新：2026-09-20。

## 程序化纹理（原创）

`assets/m01_afterglow/textures/*.png` 与 `textures/signs/*.png` 全部由离线脚本生成：

| 生成物 | 脚本 | 说明 |
| --- | --- | --- |
| 墙面/路面/铺装/屋面等 12 张基础纹理 | `tools/gen_textures.gd`（headless） | FastNoiseLite 噪声 + 程序绘制；重复生成结果确定（固定种子） |
| 10 张中文/双语招牌 | `tools/gen_signs.gd`（窗口运行 `tools/run_gen_signs.tscn`） | SubViewport 栅格化文字 |

## 字体许可说明（chapter1-1 FIX-10 已固定）

- 招牌纹理在**制作阶段**使用项目内固定的可再分发字体栅格化为 PNG：
  - **Noto Sans SC Regular**（思源黑体同源，Google Noto CJK）
  - 文件：`assets/fonts/source/NotoSansSC-Regular.otf`
  - 版本哈希（sha256）：`faa6c9df652116dde789d351359f3d7e5d2285a2b2a1f04a2d7244df706d5ea9`
  - 许可：**SIL Open Font License 1.1**（全文见 `assets/fonts/source/LICENSE-OFL.txt`）；OFL 允许项目内保存与随制作管线再分发，招牌 PNG 为渲染产物。
  - 来源：`https://github.com/notofonts/noto-cjk`（Sans/SubsetOTF/SC）
- `tools/gen_signs.gd` 以 `FontFile` 加载上述文件生成招牌；同输入必产同输出，换目录可复现（不再依赖本机系统字体）。
- UI 文字仍经 Godot `SystemFont` 按名称调用本机字体渲染（运行时行为，属操作系统正常调用，不随包分发字体文件）。

## 几何与材质

- 全部建筑/街道/道具几何由 `tools/build_m01.gd` + `tools/gen_lib.gd` 程序化生成（含 lightmap UV2 自打包），材质为 Godot StandardMaterial3D，保存于 `assets/m01_afterglow/materials/`。
- 烘焙数据 `maps/m01_afterglow/map_lightmap.res/.exr` 由 LightmapGI 生成（制作阶段）。

## 引擎与工具

- Godot 4.7.2 stable（官方发行版二进制）。
- 离线制作脚本仅在本机运行；发布程序不依赖 Python/Blender/网络/LLM。

## 外部引用

无外部模型、贴图、音频。项目内所有 `.png/.tres/.res/.tscn` 均为上述流程产物。
