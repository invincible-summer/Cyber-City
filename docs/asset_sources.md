# 资产与素材来源

> 所有运行时资产均为**原创程序化生成**，无外部商业素材。更新：2026-09-20。

## 程序化纹理（原创）

`assets/m01_afterglow/textures/*.png` 与 `textures/signs/*.png` 全部由离线脚本生成：

| 生成物 | 脚本 | 说明 |
| --- | --- | --- |
| 墙面/路面/铺装/屋面等 12 张基础纹理 | `tools/gen_textures.gd`（headless） | FastNoiseLite 噪声 + 程序绘制；重复生成结果确定（固定种子） |
| 10 张中文/双语招牌 | `tools/gen_signs.gd`（窗口运行 `tools/run_gen_signs.tscn`） | SubViewport 栅格化文字 |

## 字体许可说明（重要）

- 招牌纹理在**制作阶段**引用 Windows 系统字体（微软雅黑 / 黑体，通过 Godot `SystemFont` 按名称引用）栅格化为 PNG。
- **字体文件本身未被复制进本项目**，运行时也不加载系统字体做招牌渲染（UI 文字经 SystemFont 按名称引用本机字体，属操作系统正常调用）。
- 微软雅黑等系统字体许可**不允许**随项目再分发其文件。若本项目需要对外分发，应：换用可分发中文字体（如 OFL 许可的思源黑体），重跑 `tools/run_gen_signs.tscn` 与城市生成/烘焙流水线。
- 当前定位：本机自用的第一阶段交付，不构成字体的再分发。

## 几何与材质

- 全部建筑/街道/道具几何由 `tools/build_m01.gd` + `tools/gen_lib.gd` 程序化生成（含 lightmap UV2 自打包），材质为 Godot StandardMaterial3D，保存于 `assets/m01_afterglow/materials/`。
- 烘焙数据 `maps/m01_afterglow/map_lightmap.res/.exr` 由 LightmapGI 生成（制作阶段）。

## 引擎与工具

- Godot 4.7.2 stable（官方发行版二进制）。
- 离线制作脚本仅在本机运行；发布程序不依赖 Python/Blender/网络/LLM。

## 外部引用

无外部模型、贴图、音频。项目内所有 `.png/.tres/.res/.tscn` 均为上述流程产物。
