## M01「余晖街区」精修层构建（chapter1-1 §6.1 authored 层）。
## 运行：godot --headless --path . --script res://tools/build_authored.gd
## 职责：三处新空间（生活广场/站前空间/屋顶露台）+ 精修附加几何与灯光。
## 本脚本是 authored 层的唯一来源；build_m01.gd 与 assemble_m01.gd 不得覆盖其输出。
## 输出：authored/authored_static.tscn + authored_spec.json（锚点/禁入体积/环境件规格）
extends SceneTree

const GL := preload("res://tools/gen_lib.gd")
const TEX := "res://assets/m01_afterglow/textures"
const MAT_DIR := "res://assets/m01_afterglow/materials"
const AUTHORED_DIR := "res://maps/m01_afterglow/authored"
const AUTHORED_SCENE := "res://maps/m01_afterglow/authored/authored_static.tscn"
const AUTHORED_SPEC := "res://maps/m01_afterglow/authored/authored_spec.json"
const AUTHORED_MESH_DIR := "res://maps/m01_afterglow/meshes"

var mats := {}
var lights_spec: Array = []
var exclusions: Array[AABB] = []
var anchors: Dictionary = {}
var flickers: Array = []
var particles: Array = []
var region_manifest_path := ""

const KEYS := {
	"frame": "metal_dark", "glass": "glass_dark", "lit_warm": "lit_warm", "lit_cool": "lit_cool",
	"sill": "concrete_plain", "concrete": "concrete_plain", "metal": "metal_dark",
	"wood": "wood", "lamp": "metal_teal", "lens": "lamp_lens", "roof": "roof",
}
const FACE_NB := 55  # GL.FACE_NO_BOTTOM：盒体无底面


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== build_authored ===")
	DirAccess.make_dir_recursive_absolute(AUTHORED_DIR)
	_load_materials()

	var root := Node3D.new()
	root.name = "M01Authored"

	# 固定机位（新三处）：位置由实际布局确定（chapter1-1 §3.2）
	# service_court_view：立于巷口拱门内（z -3 在拱门通道 z -6…6 内），望向洗衣店门面；
	#   原姿态 (-43,2,0.8) 的视线穿过北翼附楼实体（x -67…-45, z 0…16），画面被堵死。
	anchors["service_court_view"] = {"pos": [-45.5, 1.8, -3.0], "look": [-63.0, 2.2, -6.5]}
	# station_forecourt_view：站前铺装东南角，收雨棚+北梯+站牌同框；
	#   避开售票亭禁入体（x 29.7…36.3, z -78.3…-71.7）。
	anchors["station_forecourt_view"] = {"pos": [32.0, 1.7, -86.5], "look": [15.0, 5.0, -66.0]}
	# roof_terrace_view：露台西南角沿对角线望向主街与天际线；
	#   避开设备箱区（x -66.2…-62.8, z 3.2…12.8）与楼梯间（x -52.5…-46.5, z 0.8…5.2）。
	anchors["roof_terrace_view"] = {"pos": [-61.5, 10.6, 14.0], "look": [-25.0, 9.0, 4.5]}

	# 三处扩展区域的静态几何与道具
	var geom := Node3D.new()
	geom.name = "AuthoredGeometry"
	var mb_static := GL.MeshBuilder.new()
	_service_court_static(mb_static)
	_station_forecourt_static_common(mb_static)
	_roof_terrace_static(mb_static)
	var mesh_static := mb_static.commit(mats, "%s/authored_static_mesh.res" % AUTHORED_MESH_DIR, Vector2i(2048, 2048))
	print("authored static: tris=", mb_static.tri_count(), " surf=", mesh_static.get_surface_count(), " uv2_max_y=%.3f overflow=%d" % [mb_static.packer.max_y(), mb_static.packer.overflow_count])
	var mi_static := MeshInstance3D.new()
	mi_static.name = "AuthoredStaticMesh"
	mi_static.mesh = mesh_static
	geom.add_child(mi_static)
	_add_occluders(geom)
	root.add_child(geom)

	var props := Node3D.new()
	props.name = "AuthoredProps"
	# 三个区域独立 props 网格：区域细节可见距离可分别控制（chapter1-1 §6.3）
	var prop_regions := [
		{"name": "PropsServiceCourt", "build": _service_court_props},
		{"name": "PropsStationForecourt", "build": _station_forecourt_props},
		{"name": "PropsRoofTerrace", "build": _roof_terrace_props},
	]
	var total_prop_tris := 0
	for region in prop_regions:
		var mb_props := GL.MeshBuilder.new()
		region["build"].call(mb_props)
		if mb_props.tri_count() == 0:
			continue
		var mesh_props := mb_props.commit(mats, "%s/authored_%s.res" % [AUTHORED_MESH_DIR, region["name"]], Vector2i(512, 512))
		total_prop_tris += mb_props.tri_count()
		var mi_props := MeshInstance3D.new()
		mi_props.name = str(region["name"])
		mi_props.mesh = mesh_props
		mi_props.add_to_group("detail_props")
		props.add_child(mi_props)
	print("authored props: tris=", total_prop_tris)
	root.add_child(props)

	var lighting := Node3D.new()
	lighting.name = "AuthoredLighting"
	for L in lights_spec:
		var o := OmniLight3D.new()
		o.position = L["pos"]
		o.light_color = L["color"]
		o.light_energy = L["energy"]
		o.omni_range = L["range"]
		o.light_bake_mode = Light3D.BAKE_STATIC
		o.shadow_enabled = false
		o.add_to_group("bake_only_light")
		lighting.add_child(o)
	root.add_child(lighting)

	_set_all_owners(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack 失败: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, AUTHORED_SCENE)
	print("authored scene saved: ", err)
	_save_spec()
	print("AUTHORED_DONE")
	quit(0)


# ============================ 三个新区域 ============================
# 坐标依据 chapter1-1 §3.1 参考范围 + 现有布局实测（见 docs/chapter1_1/plan.md）：
#   service_court      X -73…-45, Z -17…17（旧侧巷西端开口连通）
#   station_forecourt  X 10…43,  Z -88…-62（高架北侧地面层）
#   roof_terrace       生活广场附楼顶部 x -67…-45, z 0…16，楼层 9.1 米

# ---- 生活广场：西排小店（两层，x -73…-65）+ 北翼附楼（露台承重，x -67…-45, z 0…16, h8.6）+ 南翼低层 ----

func _service_court_static(mb: GL.MeshBuilder) -> void:
	# 地面：广场铺装（略低于人行道 0.12），排水沟与路沿承接旧侧巷
	mb.box("plaza", Vector3(-73, 0, -17), Vector3(-45, 0.12, 17), 1.0 / 8.0, 22.0)
	mb.box("pavement", Vector3(-45, 0, -6), Vector3(-44.6, 0.14, 6), 1.0 / 2.4, 20.0)  # 与巷道衔接条
	# 排水沟（西排店前）
	for zz in [-10.0, 2.0, 12.0]:
		mb.box("metal_dark", Vector3(-65.6, 0.02, zz - 1.2), Vector3(-65.2, 0.09, zz + 1.2), 0.8, 18.0)
	# 路沿（北侧、南侧）
	mb.box("concrete_plain", Vector3(-65, 0.0, 16.6), Vector3(-45, 0.24, 17), 0.5, 20.0)
	mb.box("concrete_plain", Vector3(-65, 0.0, -17), Vector3(-45, 0.24, -16.6), 0.5, 20.0)
	# 雨后湿区
	_flat_quad(mb, "asphalt_wet", Vector3(-56, 0.13, 4), 5.0, 3.0)

	# 西排小店（x -73…-65, z -14…14, h 7.5，front +x）
	_authored_building(mb, {
		"id": "SC_W", "x0": -73, "z0": -14, "x1": -65, "z1": 14, "h": 7.5,
		"wall": "wall_warm", "pattern": "grid", "floor_h": 3.4, "bay": 2.8,
		"win_w": 1.2, "win_h": 1.5, "front": "+x", "seed": 2101,
	})
	# 三个不同功能门面（洗衣/小吃/修理点），洗衣为主招牌
	_authored_shopfront(mb, "x", -65, 1, -11.5, -5.5, "sign_laundry", 2.6, 3.0, true, true)
	_authored_shopfront(mb, "x", -65, 1, -3.5, 2.5, "", 0.0, 2.8, false, false)
	_authored_shopfront(mb, "x", -65, 1, 4.5, 10.5, "", 0.0, 3.2, true, false)
	lights_spec.append(_omni(Vector3(-63.8, 2.0, -8.5), Color(1, 0.75, 0.47), 3.4, 8.0))
	lights_spec.append(_omni(Vector3(-63.8, 2.0, 7.5), Color(1, 0.74, 0.45), 2.6, 7.0))
	# 拱门内与北侧步道补光（烘焙灯，提升广场暗区可读性）
	lights_spec.append(_omni(Vector3(-46.5, 3.0, 0.0), Color(1, 0.78, 0.52), 1.6, 6.0))
	lights_spec.append(_omni(Vector3(-55.0, 3.2, 12.5), Color(1, 0.76, 0.5), 1.4, 7.0))

	# 北翼附楼（露台承重体，两层 h8.6；x -67…-45, z 0…16）
	_authored_building(mb, {
		"id": "SC_ANNEX", "x0": -67, "z0": 0, "x1": -45, "z1": 16, "h": 8.6,
		"wall": "wall_brick", "pattern": "grid", "floor_h": 4.0, "bay": 3.4,
		"win_w": 1.4, "win_h": 1.7, "front": "-z", "seed": 2102, "base_h": 0.45,
	})
	# 南翼低层（储物/后屋，x -65…-45, z -17…-11, h5.5）
	_authored_building(mb, {
		"id": "SC_S", "x0": -65, "z0": -17, "x1": -45, "z1": -11, "h": 5.5,
		"wall": "wall_panel", "pattern": "grid", "floor_h": 2.8, "bay": 3.0,
		"win_w": 1.1, "win_h": 1.2, "front": "+z", "seed": 2103, "base_h": 0.4,
	})
	# 东侧矮墙 + 巷口拱门（连接旧侧巷；墙 x -45.2…-44.9，z ±(7…17) 与 ±(6…17)）
	mb.box("wall_brick", Vector3(-45.4, 0, -17), Vector3(-44.9, 2.6, -6.4), 0.5, 20.0)
	mb.box("wall_brick", Vector3(-45.4, 0, 6.4), Vector3(-44.9, 2.6, 17), 0.5, 20.0)
	# 拱门梁（跨巷口 z -6…6）
	mb.box("concrete_plain", Vector3(-45.5, 2.6, -6.4), Vector3(-44.8, 3.6, 6.4), 0.5, 20.0)
	mb.box("metal_dark", Vector3(-45.6, 3.6, -6.4), Vector3(-44.7, 3.8, 6.4), 0.7, 18.0)
	exclusions.append(AABB(Vector3(-73.3, 0, -14.3), Vector3(8.6, 8.0, 28.6)))
	exclusions.append(AABB(Vector3(-67.3, 0, -0.3), Vector3(22.6, 8.55, 16.6)))   # 附楼分层：顶到露台楼板下
	exclusions.append(AABB(Vector3(-65.3, 0, -17.3), Vector3(20.6, 6.0, 6.6)))
	# 巷口拱门：两侧墙 + 顶部过梁（通道 y2.6 以下可通行）
	exclusions.append(AABB(Vector3(-45.9, 0, -17.3), Vector3(1.3, 4.0, 10.9)))
	exclusions.append(AABB(Vector3(-45.9, 0, 6.4), Vector3(1.3, 4.0, 10.6)))
	exclusions.append(AABB(Vector3(-45.9, 2.6, -6.4), Vector3(1.3, 1.2, 12.8)))

	# ---- 站前空间：高架支柱补齐 + 北梯 + 天桥 + 雨棚框架（z -88…-62, x 10…43）----
	_station_forecourt_static_common(mb)


func _station_forecourt_static_common(mb: GL.MeshBuilder) -> void:
	var pyl := "concrete_plain"
	var steel := "steel_station"
	# 地面：站前铺装（含桥下延伸）
	mb.box("pavement", Vector3(10, 0, -88), Vector3(43, 0.15, -61), 1.0 / 2.4, 20.0)
	mb.box("pavement", Vector3(10, 0, -61), Vector3(43, 0.15, -57), 1.0 / 2.4, 20.0)  # 桥南侧衔接带
	# 落客车道（东侧南北向）
	mb.box("asphalt", Vector3(36.5, 0, -86), Vector3(41.5, 0.02, -62), 1.0 / 12.0, 22.0)
	_flat_quad(mb, "marking", Vector3(39, 0.055, -74), 0.14, 20.0)
	# 高架支柱补齐（x=27、x=40 两柱，承接既有桥面梁位）
	for px in [27.0, 40.0]:
		mb.box(pyl, Vector3(px - 1.2, 0, -66.5), Vector3(px + 1.2, 10.4, -62.5), 0.5, 22.0)
		mb.box(steel, Vector3(px - 1.5, 9.9, -66.8), Vector3(px + 1.5, 10.6, -62.2), 0.6, 22.0)
	# 柱间联系梁（装饰性横撑）
	mb.box(steel, Vector3(13.8, 5.2, -66.4), Vector3(41.2, 5.5, -62.6), 0.6, 20.0)
	# 北侧楼梯（x 15.5…24.5 双跑，自北向南上升；1.1 补梯梁/平台/扶手消除悬空感）
	var sh := "concrete_plain"
	# 底部入场平台
	mb.box(sh, Vector3(24.6, 0.0, -67.6), Vector3(27.4, 0.18, -63.4), 0.5, 20.0)
	for i in 12:
		mb.box(sh, Vector3(15.5 + i * 0.75, 0.15 + i * 0.43, -65.6), Vector3(15.5 + (i + 1) * 0.75 + 0.1, 0.15 + i * 0.43 + 0.14, -63.8), 0.5, 20.0)
		mb.box(sh, Vector3(24.5 - (i + 1) * 0.75, 5.35 + i * 0.43, -67.3), Vector3(24.5 - i * 0.75 + 0.1, 5.35 + i * 0.43 + 0.14, -65.5), 0.5, 20.0)
	# 梯梁（斜向基梁：分四段阶梯盒承托两跑踏步）
	for i in 4:
		var sy := 0.15 + i * 1.45
		mb.box(sh, Vector3(15.6 + i * 2.25, sy - 0.35, -64.9), Vector3(15.6 + (i + 1) * 2.25, sy - 0.15, -64.5), 0.5, 18.0)
		mb.box(sh, Vector3(24.4 - (i + 1) * 2.25, sy + 4.85, -66.65), Vector3(24.4 - i * 2.25, sy + 5.05, -66.25), 0.5, 18.0)
	mb.box(sh, Vector3(13.6, 10.35, -67.5), Vector3(17.0, 10.5, -63.2), 0.5, 20.0)  # 北平台
	# 梯段侧栏板
	mb.box("concrete_plain", Vector3(15.3, 0, -63.7), Vector3(24.8, 5.4, -63.55), 0.5, 18.0)
	mb.box("concrete_plain", Vector3(15.3, 5.3, -67.45), Vector3(24.8, 10.6, -67.3), 0.5, 18.0)
	# 扶手（两跑开放侧，金属立柱 + 双横杆）
	for i in 8:
		var hx := 15.8 + i * 1.24
		mb.box("metal_dark", Vector3(hx - 0.03, 0.6 + i * 0.43 * 0.75, -63.95), Vector3(hx + 0.03, 1.7 + i * 0.43 * 0.75, -63.9), 0.8, 14.0)
		mb.box("metal_dark", Vector3(hx - 0.03, 5.8 + i * 0.43 * 0.75, -67.0), Vector3(hx + 0.03, 6.9 + i * 0.43 * 0.75, -66.95), 0.8, 14.0)
	mb.box("metal_dark", Vector3(15.6, 1.75, -63.97), Vector3(25.2, 1.87, -63.88), 0.8, 14.0)
	mb.box("metal_dark", Vector3(15.6, 6.95, -67.02), Vector3(25.2, 7.07, -66.93), 0.8, 14.0)
	# 天桥（跨轨道连接北平台与既有站台，x 20.6…25.0，桥面 y11.3）
	mb.box(steel, Vector3(20.6, 11.3, -67.2), Vector3(25.0, 11.58, -58.6), 0.6, 22.0)
	for i in 9:
		var zz := -66.8 + i * 0.95
		mb.box("metal_dark", Vector3(20.7, 11.58, zz), Vector3(20.8, 12.5, zz + 0.06), 0.8, 14.0)
		mb.box("metal_dark", Vector3(24.85, 11.58, zz), Vector3(24.95, 12.5, zz + 0.06), 0.8, 14.0)
	mb.box("metal_teal", Vector3(20.6, 12.4, -67.2), Vector3(25.0, 12.55, -58.6), 0.7, 14.0)
	# 天桥支柱
	mb.box(pyl, Vector3(22.2, 0, -68.4), Vector3(23.4, 10.4, -67.2), 0.5, 20.0)
	# 北平台雨棚 + 前廊雨棚
	mb.box(steel, Vector3(13.4, 12.6, -67.6), Vector3(25.2, 12.9, -63.0), 0.6, 18.0)
	for i in 3:
		var cx := 14.5 + i * 4.8
		mb.box("metal_dark", Vector3(cx - 0.09, 10.5, -65.6), Vector3(cx + 0.09, 12.6, -65.4), 0.7, 14.0)
	# 入口雨棚（前廊，金属板 + 排水檐沟）
	mb.box("metal_teal", Vector3(14.0, 3.4, -70.5), Vector3(26.0, 3.65, -67.4), 0.5, 22.0)
	mb.box("metal_dark", Vector3(13.9, 3.25, -70.6), Vector3(26.1, 3.4, -70.3), 0.6, 18.0)
	for sx in [14.6, 20.0, 25.4]:
		mb.box("metal_dark", Vector3(sx - 0.05, 0.15, -69.6), Vector3(sx + 0.05, 3.4, -69.5), 0.7, 16.0)
	# 雨棚下/平台补光（烘焙灯，消除雨棚底死黑；能量收敛避免橙色彩洗白）
	lights_spec.append(_omni(Vector3(19.5, 10.6, -65.3), Color(1, 0.8, 0.55), 2.6, 9.0))
	lights_spec.append(_omni(Vector3(20.0, 3.1, -69.0), Color(1, 0.78, 0.52), 1.8, 7.0))
	lights_spec.append(_omni(Vector3(27.0, 8.5, -74.5), Color(0.55, 0.86, 0.84), 1.4, 9.0))
	# 售票亭（x 30…36, z -78…-72）
	mb.box("wall_warm", Vector3(30, 0, -78), Vector3(36, 3.2, -72), 1.0 / 3.0, 24.0, FACE_NB)
	mb.box("concrete_plain", Vector3(29.96, 0, -78.04), Vector3(36.04, 0.4, -71.96), 0.55, 22.0, FACE_NB)
	mb.box("roof", Vector3(29.8, 3.2, -78.2), Vector3(36.2, 3.45, -71.8), 0.7, 20.0, FACE_NB)
	# 售票窗（朝西）
	var uv2 := Vector2(1.6 * 26.0 / GL.ATLAS_PX, 1.0 * 26.0 / GL.ATLAS_PX)
	mb.quad("glass_dark", Vector3(29.9, 1.1, -76.3), Vector3(29.9, 1.1, -74.7), Vector3(29.9, 2.1, -74.7), Vector3(29.9, 2.1, -76.3), Vector3(-1, 0, 0), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], uv2)
	mb.box("metal_teal", Vector3(29.8, 2.1, -76.4), Vector3(29.92, 2.2, -74.6), 0.7, 16.0)
	# 站前站牌（立柱式，同一城市标识：复用 sign_station；两面 UV 各自按观察方向排布）
	mb.cylinder("metal_dark", Vector3(27.5, 0.15, -74.0), 0.09, 3.2, 8, 0.7, 16.0)
	var sign_uv := Vector2(2.4 * 20.0 / GL.ATLAS_PX, 0.9 * 20.0 / GL.ATLAS_PX)
	# 南面（normal +z，自南看：右 = +x → 左下角 = min x）
	mb.quad("sign_station", Vector3(26.3, 2.55, -74.0), Vector3(28.7, 2.55, -74.0), Vector3(28.7, 3.45, -74.0), Vector3(26.3, 3.45, -74.0), Vector3(0, 0, 1), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], sign_uv)
	# 北面（normal -z，自北看：右 = -x → 左下角 = max x）
	mb.quad("sign_station", Vector3(28.7, 2.55, -74.0), Vector3(26.3, 2.55, -74.0), Vector3(26.3, 3.45, -74.0), Vector3(28.7, 3.45, -74.0), Vector3(0, 0, -1), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], sign_uv)
	lights_spec.append(_omni(Vector3(27.5, 3.9, -74.0), Color(0.5, 0.88, 0.85), 1.6, 6.0))
	# 站前灯柱 ×2
	for lp in [Vector3(15.5, 0.15, -72.0), Vector3(34.0, 0.15, -66.0)]:
		mb.cylinder("metal_dark", lp, 0.07, 5.2, 8, 0.6, 18.0)
		mb.box("metal_dark", lp + Vector3(-0.5, 5.0, -0.05), lp + Vector3(0.5, 5.15, 0.05), 0.7, 16.0)
		mb.bulb("lamp_lens", lp + Vector3(-0.4, 4.85, 0), 0.12)
		lights_spec.append(_omni(lp + Vector3(-0.4, 4.7, 0), Color(1, 0.78, 0.52), 3.0, 9.0))
	# 禁入体积
	exclusions.append(AABB(Vector3(26.0, 0, -66.7), Vector3(2.4, 10.6, 4.4)))      # 柱 x27
	exclusions.append(AABB(Vector3(38.8, 0, -66.7), Vector3(2.4, 10.6, 4.4)))      # 柱 x40
	exclusions.append(AABB(Vector3(15.2, 0, -67.6), Vector3(9.7, 10.8, 4.4)))      # 北梯体量
	exclusions.append(AABB(Vector3(20.5, 10.8, -67.4), Vector3(4.6, 3.8, 9.0)))    # 天桥
	exclusions.append(AABB(Vector3(22.1, 0, -68.5), Vector3(1.4, 10.6, 1.4)))      # 天桥支柱
	exclusions.append(AABB(Vector3(29.7, 0, -78.3), Vector3(6.6, 3.8, 6.6)))       # 售票亭


func _roof_terrace_static(mb: GL.MeshBuilder) -> void:
	## 露台本体在附楼（SC_ANNEX）之上：x -67…-45, z 0…16，楼板 8.6…9.1
	# 楼板与女儿墙基座（面层用铺装纹理，改善露台过暗）
	mb.box("concrete_plain", Vector3(-67.1, 8.6, -0.1), Vector3(-44.9, 9.1, 16.1), 0.6, 22.0, FACE_NB)
	mb.box("pavement", Vector3(-67.0, 9.08, 0), Vector3(-45.0, 9.12, 16.0), 1.0 / 2.4, 18.0, 4)
	# 楼梯间出屋顶小房（封闭检修门）+ 顶部小顶棚
	mb.box("wall_brick", Vector3(-52.5, 9.1, 0.8), Vector3(-46.5, 11.6, 5.2), 0.6, 20.0, FACE_NB)
	mb.box("roof", Vector3(-52.7, 11.6, 0.6), Vector3(-46.3, 11.85, 5.4), 0.7, 18.0, FACE_NB)
	mb.quad("door_dark", Vector3(-46.5, 9.15, 1.6), Vector3(-46.5, 9.15, 4.4), Vector3(-46.5, 11.0, 4.4), Vector3(-46.5, 11.0, 1.6), Vector3(1, 0, 0), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2(2.4 * 22.0 / GL.ATLAS_PX, 1.8 * 22.0 / GL.ATLAS_PX))
	exclusions.append(AABB(Vector3(-52.6, 9.0, 0.7), Vector3(6.2, 3.0, 4.7)))
	# 设备箱集中区（西侧）：基座 + 三台设备
	mb.box("concrete_plain", Vector3(-66.4, 9.12, 2.0), Vector3(-62.4, 9.5, 14.0), 0.6, 20.0, 4)
	for i in 3:
		var zz := 3.2 + i * 3.6
		mb.box("metal_dark", Vector3(-66.2, 9.5, zz), Vector3(-62.8, 11.1, zz + 2.4), 0.7, 20.0, FACE_NB)
		mb.cylinder("metal_dark", Vector3(-64.5, 11.4, zz + 1.2), 0.16, 0.5, 8, 0.6, 14.0)
	lights_spec.append(_omni(Vector3(-56.0, 10.6, 8.0), Color(1, 0.76, 0.5), 2.2, 8.0))


# ---- 露台栏杆/花箱/家具属于 Props（需要独立可见距离控制） ----

func _service_court_props(mb: GL.MeshBuilder) -> void:
	# 等待组：长椅 ×2 + 站牌小柱
	GL.bench(mb, -63.5, -1.5, PI / 2, KEYS)
	GL.bench(mb, -63.5, 12.0, PI / 2, KEYS)
	# 清洁组：洗衣晾架（南墙前）+ 水桶
	for i in 2:
		var px := -58.0 + i * 2.2
		mb.box("metal_dark", Vector3(px - 0.03, 0.12, -14.6), Vector3(px + 0.03, 1.9, -14.54), 0.8, 14.0)
	mb.box("wire", Vector3(-58.0, 1.82, -14.62), Vector3(-55.8, 1.85, -14.58), 0.9, 8.0)
	mb.quad("cloth", Vector3(-57.7, 1.1, -14.6), Vector3(-57.3, 1.1, -14.6), Vector3(-57.3, 1.8, -14.6), Vector3(-57.7, 1.8, -14.6), Vector3(0, 0, -1), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(0.4 * 20.0 / GL.ATLAS_PX, 0.7 * 20.0 / GL.ATLAS_PX))
	for b in [Vector3(-56.2, 0.27, -13.6), Vector3(-55.6, 0.27, -13.9)]:
		mb.cylinder("metal_teal", b, 0.16, 0.3, 8, 0.7, 14.0)
	# 维修组：工具箱 + 油桶 + 板条箱（修理点门前 x≈-63）
	mb.box("metal_teal", Vector3(-63.9, 0.29, 6.2), Vector3(-62.7, 0.85, 7.1), 0.7, 20.0)
	mb.box("metal_dark", Vector3(-63.85, 0.85, 6.25), Vector3(-62.75, 1.0, 7.05), 0.7, 18.0)
	for i in 2:
		mb.cylinder("metal_orange", Vector3(-62.2, 0.42 + i * 0.0, 9.4), 0.24, 0.85, 10, 0.55, 16.0)
	mb.box("wood", Vector3(-62.6, 0.12, 5.4), Vector3(-61.9, 0.72, 5.9), 0.7, 20.0)
	# 花箱（沿东矮墙）
	for p in [Vector3(-46.3, 0.12, -10.0), Vector3(-46.3, 0.12, 9.0)]:
		mb.box("wood", p + Vector3(-0.5, 0, -0.4), p + Vector3(0.5, 0.55, 0.4), 0.6, 18.0)
		_plant(mb, p + Vector3(0, 0.55, 0), 0.5)
	# 巷口拱门壁灯（托架→吊杆→灯泡，避免穿模）
	mb.box("metal_dark", Vector3(-45.35, 3.2, -0.3), Vector3(-45.0, 3.5, 0.3), 0.8, 14.0)
	mb.box("metal_dark", Vector3(-45.15, 2.95, -0.04), Vector3(-45.05, 3.25, 0.04), 0.8, 12.0)
	mb.bulb("bulb_warm", Vector3(-45.1, 2.86, 0), 0.08)
	lights_spec.append(_omni(Vector3(-44.8, 2.7, 0), Color(1, 0.78, 0.5), 2.0, 5.0))


func _station_forecourt_props(mb: GL.MeshBuilder) -> void:
	# 候车座椅（入口雨棚下）
	GL.bench(mb, 16.5, -71.8, 0, KEYS)
	GL.bench(mb, 24.0, -71.8, 0, KEYS)
	# 自行车架（落客道旁）
	for i in 3:
		mb.box("metal_teal", Vector3(37.0, 0.15, -80.0 + i * 1.4), Vector3(37.6, 0.55, -79.9 + i * 1.4), 0.7, 14.0)
	mb.cylinder("metal_dark", Vector3(36.6, 0.35, -79.3), 0.34, 0.06, 10, 0.7, 12.0)  # 车轮剪影
	mb.cylinder("metal_dark", Vector3(37.9, 0.35, -77.9), 0.34, 0.06, 10, 0.7, 12.0)
	# 排水沟篦子（雨棚檐下）
	for zz in [-69.5, -68.2]:
		mb.box("metal_dark", Vector3(19.5, 0.02, zz), Vector3(21.0, 0.09, zz + 0.5), 0.8, 18.0)
	# 导流柱（落客道西侧）
	for i in 4:
		mb.cylinder("metal_teal", Vector3(35.6, 0.15, -84.0 + i * 5.0), 0.08, 0.7, 8, 0.8, 14.0)
	# 岗亭旁邮筒
	mb.cylinder("metal_orange", Vector3(29.0, 0.35, -71.5), 0.26, 1.1, 10, 0.55, 16.0)


func _roof_terrace_props(mb: GL.MeshBuilder) -> void:
	# 露台栏杆（周圈，高1.1：立柱+双横杆），设备区一侧留缺口
	var rail_y := 9.12
	var posts: Array[Vector3] = []
	# 北边 z=0，南边 z=16，东边 x=-45，西边只到设备区南缘（z 14…16）
	var zz := 0.0
	while zz <= 16.0:
		posts.append(Vector3(-67.0, rail_y, zz))
		posts.append(Vector3(-45.0, rail_y, zz))
		zz += 2.17
	var xx := -67.0
	while xx <= -45.0:
		posts.append(Vector3(xx, rail_y, 0.0))
		posts.append(Vector3(xx, rail_y, 16.0))
		xx += 2.2
	for p in posts:
		mb.box("metal_dark", p + Vector3(-0.03, 0, -0.03), p + Vector3(0.03, 1.1, 0.03), 0.8, 14.0)
	# 横杆（四边；西边 z 0…2 保留以封设备区角）
	mb.box("metal_teal", Vector3(-67.0, rail_y + 0.42, -0.05), Vector3(-45.0, rail_y + 0.56, 0.05), 0.7, 14.0)
	mb.box("metal_teal", Vector3(-67.0, rail_y + 0.98, -0.05), Vector3(-45.0, rail_y + 1.1, 0.05), 0.7, 14.0)
	mb.box("metal_teal", Vector3(-67.0, rail_y + 0.42, 15.95), Vector3(-45.0, rail_y + 0.56, 16.05), 0.7, 14.0)
	mb.box("metal_teal", Vector3(-67.0, rail_y + 0.98, 15.95), Vector3(-45.0, rail_y + 1.1, 16.05), 0.7, 14.0)
	mb.box("metal_teal", Vector3(-45.05, rail_y + 0.42, 0.0), Vector3(-44.95, rail_y + 0.56, 16.0), 0.7, 14.0)
	mb.box("metal_teal", Vector3(-45.05, rail_y + 0.98, 0.0), Vector3(-44.95, rail_y + 1.1, 16.0), 0.7, 14.0)
	mb.box("metal_teal", Vector3(-67.05, rail_y + 0.42, 0.0), Vector3(-66.95, rail_y + 0.56, 2.0), 0.7, 14.0)
	mb.box("metal_teal", Vector3(-67.05, rail_y + 0.98, 0.0), Vector3(-66.95, rail_y + 1.1, 2.0), 0.7, 14.0)
	# 花箱（北/南栏杆内侧）
	for p in [Vector3(-58, 9.12, 0.6), Vector3(-52, 9.12, 0.6), Vector3(-58, 9.12, 15.4), Vector3(-52, 9.12, 15.4)]:
		mb.box("wood", p + Vector3(-0.7, 0, -0.28), p + Vector3(0.7, 0.5, 0.28), 0.6, 18.0)
		_plant(mb, p + Vector3(0, 0.5, 0), 0.55)
	# 露台家具：小桌 + 两椅（东南角取景空地）+ 长椅 + 地灯
	mb.cylinder("metal_dark", Vector3(-48.5, 9.4, 12.5), 0.5, 0.05, 12, 0.5, 16.0)
	mb.cylinder("metal_dark", Vector3(-48.5, 9.12, 12.5), 0.06, 0.32, 8, 0.6, 14.0)
	for cp in [Vector3(-49.6, 9.12, 12.0), Vector3(-47.4, 9.12, 13.0)]:
		mb.box("wood", cp + Vector3(-0.22, 0, -0.22), cp + Vector3(0.22, 0.45, 0.22), 0.7, 16.0)
		mb.box("wood", cp + Vector3(-0.24, 0.45, -0.24), cp + Vector3(0.24, 0.5, 0.24), 0.7, 16.0)
	GL.bench(mb, -54.0, 14.6, 0, KEYS)
	for lp in [Vector3(-51.0, 9.12, 3.0), Vector3(-51.0, 9.12, 13.0)]:
		mb.cylinder("metal_dark", lp, 0.05, 0.9, 8, 0.6, 14.0)
		mb.bulb("bulb_warm", lp + Vector3(0, 1.0, 0), 0.09)
	# 座椅区补光（烘焙灯）
	lights_spec.append(_omni(Vector3(-51.0, 10.9, 8.0), Color(1, 0.74, 0.48), 2.6, 7.0))
	# 晾衣绳一段（西南角，生活气息）
	mb.box("metal_dark", Vector3(-65.9, 9.12, 15.2), Vector3(-65.84, 11.0, 15.26), 0.8, 14.0)
	mb.box("wire", Vector3(-65.87, 10.9, 15.2), Vector3(-62.6, 10.95, 15.2), 0.9, 8.0)
	for cxx in [-65.2, -64.4, -63.6]:
		mb.quad("cloth", Vector3(cxx, 10.2, 15.2), Vector3(cxx + 0.4, 10.2, 15.2), Vector3(cxx + 0.4, 10.85, 15.2), Vector3(cxx, 10.85, 15.2), Vector3(0, 0, -1), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(0.4 * 20.0 / GL.ATLAS_PX, 0.65 * 20.0 / GL.ATLAS_PX))


func _plant(mb: GL.MeshBuilder, top: Vector3, radius: float) -> void:
	## 简化灌木：茎 + 三簇错位八面体，避免单片"宝石"观感与多层透明叶片。
	mb.cylinder("wood", top, radius * 0.12, 0.28, 6, 0.8, 12.0)
	mb.bulb("plant_green", top + Vector3(0, 0.30, 0), radius * 0.42)
	mb.bulb("plant_green", top + Vector3(radius * 0.28, 0.44, -radius * 0.16), radius * 0.30)
	mb.bulb("plant_green", top + Vector3(-radius * 0.24, 0.40, radius * 0.18), radius * 0.26)


func _flat_quad(mb: GL.MeshBuilder, key: String, center: Vector3, w: float, h: float) -> void:
	var uv2sz := Vector2(maxf(w, 0.1) * 16.0 / GL.ATLAS_PX, maxf(h, 0.1) * 16.0 / GL.ATLAS_PX)
	mb.quad(key, center + Vector3(-w / 2, 0, h / 2), center + Vector3(w / 2, 0, h / 2), center + Vector3(w / 2, 0, -h / 2), center + Vector3(-w / 2, 0, -h / 2), Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], uv2sz)


func _authored_building(mb: GL.MeshBuilder, spec: Dictionary) -> void:
	## 精修层简化建筑：主体 + 基座 + 窗（临街面）+ 屋顶套件。
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var x0: float = spec["x0"]; var x1: float = spec["x1"]
	var z0: float = spec["z0"]; var z1: float = spec["z1"]
	var h: float = spec["h"]
	mb.box(spec["wall"], Vector3(x0, 0, z0), Vector3(x1, h, z1), 1.0 / 3.0, 26.0, GL.FACE_NO_BOTTOM)
	var base_h: float = spec.get("base_h", 0.55)
	mb.box("concrete_plain", Vector3(x0 - 0.04, 0, z0 - 0.04), Vector3(x1 + 0.04, base_h, z1 + 0.04), 0.55, 24.0, GL.FACE_NO_BOTTOM)
	GL.roof_kit(mb, x0, z0, x1, z1, h, rng, {"parapet": "concrete_plain", "roof": "roof", "metal": "metal_dark"}, false)
	# 临街面窗
	_face_windows(mb, spec, str(spec["front"]), rng)
	exclusions.append(AABB(Vector3(x0 - 0.3, 0, z0 - 0.3), Vector3(x1 - x0 + 0.6, h + 0.5, z1 - z0 + 0.6)))


func _face_windows(mb: GL.MeshBuilder, spec: Dictionary, face: String, rng: RandomNumberGenerator) -> void:
	var x0: float = spec["x0"]; var x1: float = spec["x1"]
	var z0: float = spec["z0"]; var z1: float = spec["z1"]
	var axis := "x"
	var wall_c: float = x1
	var out_dir := 1
	var a0 := z0
	var a1 := z1
	if face == "-x":
		axis = "x"; wall_c = x0; out_dir = -1
	elif face == "+z":
		axis = "z"; wall_c = z1; out_dir = 1; a0 = x0; a1 = x1
	elif face == "-z":
		axis = "z"; wall_c = z0; out_dir = -1; a0 = x0; a1 = x1
	var h: float = spec["h"]
	var base_y: float = spec.get("base_h", 0.55) + 0.45
	var y := base_y
	var floor_idx := 0
	while y + float(spec["win_h"]) + 0.45 <= h - 0.6:
		var a := a0 + float(spec["bay"]) * 0.5
		while a + float(spec["win_w"]) * 0.5 + 0.2 <= a1 - 0.4:
			var r := rng.randf()
			var lit := 0
			if r < 0.32:
				lit = 1
			elif r < 0.4:
				lit = 2
			GL.window_unit(mb, axis, wall_c, out_dir, a, y, float(spec["win_w"]), float(spec["win_h"]), KEYS, lit)
			a += float(spec["bay"])
		y += float(spec["floor_h"])
		floor_idx += 1


func _authored_shopfront(mb: GL.MeshBuilder, axis: String, wall_c: float, out_dir: int, a0: float, a1: float, sign_key: String, sign_energy: float, depth: float, awning: bool, laundry_window: bool) -> void:
	## 精修层店面：踢脚 + 橱窗玻璃 + 内景盒 + 竖框 + 门 + 可选招牌/雨棚。
	var uv01 := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	_strip_box(mb, "concrete_plain", axis, wall_c, wall_c + out_dir * 0.02, a0, a1, 0.0, 0.45)
	var glass_c := wall_c + out_dir * -0.08
	var uv2sz := Vector2((a1 - a0) * 26.0 / GL.ATLAS_PX, 2.6 * 26.0 / GL.ATLAS_PX)
	_quad_face(mb, "glass_shop", axis, glass_c, a0 + 0.15, a1 - 0.15, 0.45, 3.05, out_dir, uv2sz)
	# 内景盒（洗衣店为服务窗口：柜台 + 悬挂衣物剪影）
	var back_c := wall_c + out_dir * -depth
	_quad_face(mb, "interior_back", axis, back_c, a0, a1, 0.1, 3.0, out_dir, Vector2((a1 - a0) * 20.0 / GL.ATLAS_PX, 2.8 * 20.0 / GL.ATLAS_PX))
	_strip_box(mb, "door_dark", axis, back_c, back_c + out_dir * -0.06, a0 - 0.05, a1 + 0.05, 0.0, 3.15)
	_strip_box(mb, "door_dark", axis, back_c, wall_c, a0 - 0.05, a0 + 0.05, 0.0, 3.15)
	_strip_box(mb, "door_dark", axis, back_c, wall_c, a1 - 0.05, a1 + 0.05, 0.0, 3.15)
	_strip_box(mb, "door_dark", axis, back_c, wall_c, a0, a1, 3.15, 3.3)
	if laundry_window:
		# 服务窗口柜台 + 吊杆
		_strip_box(mb, "wood", axis, wall_c + out_dir * -0.5, wall_c + out_dir * -0.2, a0 + 0.3, a1 - 0.3, 0.95, 1.15)
		_strip_box(mb, "metal_dark", axis, back_c + out_dir * 0.3, back_c + out_dir * 0.36, a0 + 0.4, a1 - 0.4, 2.2, 2.26)
	else:
		var n_mid := int((a1 - a0) / 2.2)
		for i in n_mid + 1:
			var a := a0 + (a1 - a0) * float(i) / maxf(1.0, float(n_mid))
			_strip_box(mb, "metal_dark", axis, wall_c + out_dir * -0.06, wall_c + out_dir * 0.04, a - 0.045, a + 0.045, 0.45, 3.05)
	# 门
	var door_a := a1 - 0.9
	_quad_face(mb, "door_dark", axis, wall_c + out_dir * -0.05, door_a, door_a + 0.9, 0.0, 2.4, out_dir, Vector2(0.9 * 22.0 / GL.ATLAS_PX, 2.3 * 22.0 / GL.ATLAS_PX))
	# 招牌（仅主招牌）
	if not sign_key.is_empty():
		var sign_y0 := 3.35
		var sign_y1 := 4.15
		var s_out := wall_c + out_dir * 0.35
		_strip_box(mb, "metal_dark", axis, minf(wall_c, s_out), maxf(wall_c, s_out), a0 - 0.25, a1 + 0.25, sign_y0, sign_y1)
		_quad_face(mb, sign_key, axis, s_out + out_dir * 0.01, a0 - 0.1, a1 + 0.1, sign_y0 + 0.08, sign_y1 - 0.08, out_dir, Vector2((a1 - a0) * 18.0 / GL.ATLAS_PX, (sign_y1 - sign_y0) * 18.0 / GL.ATLAS_PX))
		lights_spec.append(_omni(Vector3(-63.8, 1.9, (a0 + a1) / 2) if axis == "x" else Vector3((a0 + a1) / 2, 1.9, wall_c + out_dir * -1.2), Color(1, 0.72, 0.45), 3.0, 7.0))
	# 雨棚
	if awning:
		var aw_out := wall_c + out_dir * 1.5
		_strip_box(mb, "metal_teal", axis, wall_c + out_dir * 0.05, aw_out, a0 - 0.1, a1 + 0.1, 3.18, 3.42)
		for s in [0.2, 0.8]:
			var aa := lerpf(a0, a1, s)
			_strip_box(mb, "metal_dark", axis, wall_c + out_dir * 1.2, wall_c + out_dir * 1.45, aa - 0.03, aa + 0.03, 2.55, 3.2)


func _strip_box(mb: GL.MeshBuilder, key: String, axis: String, c0: float, c1: float, a0: float, a1: float, y0: float, y1: float) -> void:
	if axis == "x":
		mb.box_between(key, Vector3(c0, y0, a0), Vector3(c1, y1, a1), 0.5, 22.0)
	else:
		mb.box_between(key, Vector3(a0, y0, c0), Vector3(a1, y1, c1), 0.5, 22.0)


func _quad_face(mb: GL.MeshBuilder, key: String, axis: String, c: float, a0: float, a1: float, y0: float, y1: float, out_dir: int, uv2sz: Vector2) -> void:
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	if axis == "x":
		var n := Vector3(out_dir, 0, 0)
		if out_dir > 0:
			mb.quad(key, Vector3(c, y0, a1), Vector3(c, y0, a0), Vector3(c, y1, a0), Vector3(c, y1, a1), n, uv, uv2sz)
		else:
			mb.quad(key, Vector3(c, y0, a0), Vector3(c, y0, a1), Vector3(c, y1, a1), Vector3(c, y1, a0), n, uv, uv2sz)
	else:
		var n := Vector3(0, 0, out_dir)
		if out_dir > 0:
			mb.quad(key, Vector3(a0, y0, c), Vector3(a1, y0, c), Vector3(a1, y1, c), Vector3(a0, y1, c), n, uv, uv2sz)
		else:
			mb.quad(key, Vector3(a1, y0, c), Vector3(a0, y0, c), Vector3(a0, y1, c), Vector3(a1, y1, c), n, uv, uv2sz)


# ============================ 规格输出 ============================

func _save_spec() -> void:
	var excl: Array = []
	for b in exclusions:
		excl.append([b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	region_manifest_path = "res://maps/m01_afterglow/source/region_manifest.json"
	_write_region_manifest()
	var spec := {
		"schema_version": 1,
		"authored_scene": AUTHORED_SCENE,
		"anchors": anchors,
		"exclusions": excl,
		"flickers": flickers,
		"particles": particles,
		"region_manifest_path": region_manifest_path,
		"total_exclusions": excl.size(),
	}
	var f := FileAccess.open(AUTHORED_SPEC, FileAccess.WRITE)
	if f == null:
		push_error("authored spec 写入失败")
		return
	f.store_string(JSON.stringify(spec, "  "))
	f.close()
	print("authored spec saved: anchors=", anchors.size(), " exclusions=", excl.size())


func _write_region_manifest() -> void:
	## 区域细节配置（chapter1-1 §6.3）：只约束被标记的小装饰网格，不控制建筑/地面/主要家具。
	DirAccess.make_dir_recursive_absolute("res://maps/m01_afterglow/source")
	var manifest := {
		"schema_version": 1,
		"map_id": "m01_afterglow",
		"regions": [
			{
				"region_id": "service_court",
				"bounds_min": [-73.0, 0.0, -17.0],
				"bounds_size": [28.0, 15.0, 34.0],
				"detail_root_path": "BakedWorld/AuthoredStatic/Authored/AuthoredProps/PropsServiceCourt",
				"eco_detail_end_m": 45.0,
				"balanced_detail_end_m": 65.0,
				"hysteresis_m": 5.0,
			},
			{
				"region_id": "station_forecourt",
				"bounds_min": [10.0, 0.0, -88.0],
				"bounds_size": [33.0, 15.0, 26.0],
				"detail_root_path": "BakedWorld/AuthoredStatic/Authored/AuthoredProps/PropsStationForecourt",
				"eco_detail_end_m": 45.0,
				"balanced_detail_end_m": 65.0,
				"hysteresis_m": 5.0,
			},
			{
				"region_id": "roof_terrace",
				"bounds_min": [-67.0, 8.0, 0.0],
				"bounds_size": [22.0, 6.0, 16.0],
				"detail_root_path": "BakedWorld/AuthoredStatic/Authored/AuthoredProps/PropsRoofTerrace",
				"eco_detail_end_m": 45.0,
				"balanced_detail_end_m": 65.0,
				"hysteresis_m": 5.0,
			},
		],
	}
	var f := FileAccess.open(region_manifest_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "  "))
		f.close()


# ============================ 辅助 ============================

func _load_materials() -> void:
	## 复用生成层材质（共享资产）；只按需添加 authored 专属材质。
	var keys := [
		"wall_bluegray", "wall_warm", "wall_panel", "wall_brick", "concrete_plain",
		"metal_dark", "metal_teal", "metal_orange", "glass_dark", "lit_warm", "lit_cool",
		"glass_shop", "interior_back", "asphalt", "pavement", "plaza", "alley", "roof",
		"wood", "rubber", "marking", "steel_station", "bulb_warm", "wire", "poster",
		"door_dark", "lamp_lens", "asphalt_wet",
		"sign_repair", "sign_station", "sign_convenience", "sign_cafe", "sign_noodle",
		"sign_pharmacy", "sign_electronics", "sign_hotel_v", "sign_soda", "sign_bar_v",
	]
	for k in keys:
		var path := "%s/%s.tres" % [MAT_DIR, k]
		if ResourceLoader.exists(path):
			mats[k] = load(path)
		else:
			push_warning("authored: 共享材质缺失 %s" % path)
	# authored 专属材质（生活广场/露台）：cloth、plant_green、sign_laundry
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.86, 0.82, 0.74)
	cloth.roughness = 0.95
	mats["cloth"] = cloth
	var plant := StandardMaterial3D.new()
	plant.albedo_color = Color(0.33, 0.46, 0.30)
	plant.roughness = 0.95
	mats["plant_green"] = plant
	var laundry_path := "%s/signs/laundry.png" % TEX
	if ResourceLoader.exists(laundry_path):
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = load(laundry_path)
		sm.roughness = 0.6
		sm.emission_enabled = true
		sm.emission_texture = sm.albedo_texture
		sm.emission_energy_multiplier = 2.6
		mats["sign_laundry"] = sm
	else:
		push_warning("authored: 洗衣招牌纹理缺失（重跑 gen_signs），回退平板")
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.55, 0.8, 0.78)
		fallback.emission_enabled = true
		fallback.emission = Color(0.5, 0.85, 0.82)
		fallback.emission_energy_multiplier = 2.0
		mats["sign_laundry"] = fallback


func _add_occluders(parent: Node3D) -> void:
	if not ClassDB.class_exists("BoxOccluder"):
		return
	# 各区域主体遮挡体在填充内容时按几何登记
	for occ_spec in get_meta("occluders", []):
		var occ := OccluderInstance3D.new()
		occ.name = str(occ_spec.get("name", "Occ"))
		var box = ClassDB.instantiate("BoxOccluder")
		box.size = occ_spec["size"]
		occ.occluder = box
		occ.position = occ_spec["pos"]
		parent.add_child(occ)


func _omni(pos: Vector3, color: Color, energy: float, range_m: float) -> Dictionary:
	return {"pos": pos, "color": color, "energy": energy, "range": range_m}


func _set_all_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child != root:
			child.owner = root
			_set_all_owners(child, root)
