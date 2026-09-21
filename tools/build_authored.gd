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
var portals: Array = []
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
	# 维修铺门口锚点（chapter1-2 §3.10 门户落点；卷帘门行人小门在 z≈33.3）
	anchors["repair_shop_door"] = {"pos": [29.8, 1.7, 33.2], "look": [36.0, 2.0, 33.3]}
	# 门户：门外 → 店内地图（chapter1-2 §4.4）
	portals.append({
		"pos": [30.0, 1.7, 33.3],
		"radius": 2.2,
		"target_map_id": "m01_repair_interior",
		"target_anchor": "entry_view",
		"label": "进入 余晖维修·店内",
	})

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
		{"name": "PropsStreetEnrich", "build": _street_enrich_props},
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
		mi_props.set_meta("node_groups", PackedStringArray(["detail_props"]))
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
		o.set_meta("node_groups", PackedStringArray(["bake_only_light"]))
		lighting.add_child(o)
	root.add_child(lighting)

	# 门户门扇（chapter1-2 §3.10）：卷帘门上的行人小门，铰链 z 32.85，向街面(-X)开
	var mb_door := GL.MeshBuilder.new()
	mb_door.box("door_dark", Vector3(-0.035, 0.0, 0.0), Vector3(0.035, 2.1, 0.95), 0.55, 26.0)
	mb_door.box("metal_dark", Vector3(-0.04, 0.0, -0.02), Vector3(0.04, 0.14, 0.97), 0.7, 22.0)
	mb_door.box("metal_dark", Vector3(-0.04, 1.96, -0.02), Vector3(0.04, 2.14, 0.97), 0.7, 22.0)
	var guv := Vector2(0.34 * 20.0 / GL.ATLAS_PX, 0.42 * 20.0 / GL.ATLAS_PX)
	mb_door.quad("lit_warm", Vector3(0.041, 1.35, 0.6), Vector3(0.041, 1.35, 0.26),
		Vector3(0.041, 1.77, 0.26), Vector3(0.041, 1.77, 0.6), Vector3(1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	mb_door.box("metal_teal", Vector3(-0.1, 0.95, 0.83), Vector3(-0.045, 1.01, 0.91), 0.7, 16.0)
	var door_mesh := mb_door.commit(mats, "%s/authored_door_leaf.res" % AUTHORED_MESH_DIR, Vector2i(256, 256))
	var doors := Node3D.new()
	doors.name = "AuthoredPortalDoors"
	var pivot := Node3D.new()
	pivot.name = "ShopDoorPivot"
	pivot.position = Vector3(32.95, 0.0, 32.85)
	pivot.add_to_group("portal_door")
	pivot.set_meta("node_groups", PackedStringArray(["portal_door"]))
	pivot.set_meta("swing_deg", -100.0)
	pivot.set_meta("swing_axis", "y")
	var mi_door := MeshInstance3D.new()
	mi_door.name = "DoorLeaf"
	mi_door.mesh = door_mesh
	pivot.add_child(mi_door)
	doors.add_child(pivot)
	root.add_child(doors)
	# 小门框（贴卷帘门面，静态）
	var mb_frame := GL.MeshBuilder.new()
	mb_frame.box("metal_dark", Vector3(32.8, 0.0, 32.78), Vector3(33.1, 2.2, 32.86), 0.7, 20.0)
	mb_frame.box("metal_dark", Vector3(32.8, 0.0, 33.82), Vector3(33.1, 2.2, 33.9), 0.7, 20.0)
	mb_frame.box("metal_dark", Vector3(32.8, 2.1, 32.78), Vector3(33.1, 2.2, 33.9), 0.7, 20.0)
	var frame_mesh := mb_frame.commit(mats, "%s/authored_door_frame.res" % AUTHORED_MESH_DIR, Vector2i(256, 256))
	var mi_frame := MeshInstance3D.new()
	mi_frame.name = "DoorFrame"
	mi_frame.mesh = frame_mesh
	doors.add_child(mi_frame)

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
	# （chapter1-2：原"南墙前晾架/水桶"位于 SC_S 建筑体内部（z≈-14.6）属穿模，
	#   已移除并由 _street_enrich_props 的 G5 晾衣组在建筑外重做。）
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
	# 晾衣绳一段（西南角，生活气息；双面布片，绕序与法线一致）
	mb.box("metal_dark", Vector3(-65.9, 9.12, 15.2), Vector3(-65.84, 11.0, 15.26), 0.8, 14.0)
	mb.box("wire", Vector3(-65.87, 10.9, 15.2), Vector3(-62.6, 10.95, 15.2), 0.9, 8.0)
	var terrace_uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for cxx in [-65.2, -64.4, -63.6]:
		mb.quad("cloth", Vector3(cxx + 0.4, 10.2, 15.2), Vector3(cxx, 10.2, 15.2), Vector3(cxx, 10.85, 15.2), Vector3(cxx + 0.4, 10.85, 15.2), Vector3(0, 0, -1), terrace_uv, Vector2(0.4 * 20.0 / GL.ATLAS_PX, 0.65 * 20.0 / GL.ATLAS_PX))
		mb.quad("cloth", Vector3(cxx, 10.2, 15.2), Vector3(cxx + 0.4, 10.2, 15.2), Vector3(cxx + 0.4, 10.85, 15.2), Vector3(cxx, 10.85, 15.2), Vector3(0, 0, 1), terrace_uv, Vector2())


# ============================ chapter1-2 §5.2：街面丰富（六组叙事道具） ============================
# 坐标避让已核对：路灯（西 z -45/-9/27、东 z -36/0/36）、长椅（±8.8 与广场两处）、
# 配送箱（-9.0,37..39）、电杆（东 9.8, z -46/-26/-6）、既有机位视线走廊与门户落点。

func _street_enrich_props(mb: GL.MeshBuilder) -> void:
	_enrich_g1_trees(mb)
	_enrich_g2_parking(mb)
	_enrich_g3_storefront(mb)
	_enrich_g4_repair_plaza(mb)
	_enrich_g5_laundry_life(mb)
	_enrich_g6_street_details(mb)


# G1 人行道绿荫：花钵行道树 ×4 + 树下座椅 ×3
func _enrich_g1_trees(mb: GL.MeshBuilder) -> void:
	var spots := [
		{"x": -9.7, "z": 21.0, "seed": 3001, "stool": [-8.35, 22.3]},
		{"x": -9.7, "z": 44.0, "seed": 3002, "stool": [-8.35, 42.7]},
		{"x": 9.7, "z": -12.0, "seed": 3003, "stool": [8.35, -13.3]},
		{"x": 9.7, "z": 22.0, "seed": 3004, "stool": []},
	]
	for sp in spots:
		_tree_in_planter(mb, float(sp["x"]), 0.15, float(sp["z"]), int(sp["seed"]))
		if not sp["stool"].is_empty():
			var sx: float = sp["stool"][0]
			var sz: float = sp["stool"][1]
			mb.box("wood", Vector3(sx - 0.28, 0.15, sz - 0.28), Vector3(sx + 0.28, 0.58, sz + 0.28), 0.7, 18.0)
			mb.box("wood", Vector3(sx - 0.31, 0.58, sz - 0.31), Vector3(sx + 0.31, 0.64, sz + 0.31), 0.7, 16.0)
	# 树木禁入（东西各一条窄带，人行道靠路缘半幅；相机仍可从店侧通过）
	exclusions.append(AABB(Vector3(-10.35, 0, 20.3), Vector3(1.3, 4.6, 24.4)))
	exclusions.append(AABB(Vector3(9.05, 0, -12.65), Vector3(1.3, 4.6, 35.3)))


# G2 停靠与代步：自行车棚（3 辆）+ 共享滑板车站牌 ×2
func _enrich_g2_parking(mb: GL.MeshBuilder) -> void:
	# 棚体（西侧人行道北段，4 钢柱 + 青色平顶 + 侧挡板）
	for px in [-10.72, -8.88]:
		for pz in [12.68, 16.82]:
			mb.box("metal_dark", Vector3(px - 0.045, 0.15, pz - 0.045), Vector3(px + 0.045, 2.25, pz + 0.045), 0.8, 16.0)
	mb.box("metal_teal", Vector3(-10.95, 2.25, 12.35), Vector3(-8.65, 2.38, 17.15), 0.7, 20.0, FACE_NB)
	mb.box("wood", Vector3(-10.88, 0.35, 12.55), Vector3(-10.68, 1.45, 16.95), 0.7, 18.0)
	# 顶檐灯带（低亮度条，不加油）
	mb.box("lit_cool", Vector3(-10.6, 2.16, 12.6), Vector3(-10.52, 2.24, 16.9), 0.8, 14.0)
	for i in 3:
		_bike(mb, -9.75, 0.15, 13.35 + i * 1.3, "street")
	exclusions.append(AABB(Vector3(-11.0, 0, 12.3), Vector3(2.4, 2.5, 4.9)))
	# 共享滑板车站牌小柱 ×2（青色标识）
	for sp in [Vector3(-8.4, 0.15, 29.8), Vector3(8.8, 0.15, 16.0)]:
		mb.cylinder("metal_dark", sp, 0.05, 1.2, 8, 0.7, 14.0)
		mb.box("metal_dark", sp + Vector3(-0.14, 0, -0.14), sp + Vector3(0.14, 0.06, 0.14), 0.8, 14.0)
		mb.box("metal_teal", sp + Vector3(-0.19, 0.95, -0.025), sp + Vector3(0.19, 1.32, 0.025), 0.7, 16.0)
		mb.box("lit_cool", sp + Vector3(-0.16, 1.02, 0.028), sp + Vector3(0.16, 1.25, 0.034), 0.8, 14.0)


# G3 店外经营（海风便利门前）+ 夜宵摊车（侧巷口，收摊罩布）
func _enrich_g3_storefront(mb: GL.MeshBuilder) -> void:
	# 外摆冰柜（暖光灯箱观感：正门面两条 lit_warm 竖带）
	mb.box("metal_dark", Vector3(-8.62, 0.15, 31.0), Vector3(-7.82, 0.30, 34.2), 0.7, 20.0)
	mb.box("wall_warm", Vector3(-8.58, 0.30, 31.04), Vector3(-7.86, 1.12, 34.16), 0.6, 20.0)
	mb.box("lit_warm", Vector3(-8.50, 0.42, 31.09), Vector3(-8.36, 1.02, 34.11), 0.8, 16.0)
	mb.box("lit_warm", Vector3(-8.08, 0.42, 31.09), Vector3(-7.94, 1.02, 34.11), 0.8, 16.0)
	mb.box("glass_shop", Vector3(-8.58, 1.12, 31.04), Vector3(-7.86, 1.24, 34.16), 0.6, 16.0)
	# 报刊架（立背 + 层台 + 前缘挡条 + 三本立靠杂志）
	mb.box("wood", Vector3(-8.95, 0.15, 26.35), Vector3(-8.15, 1.35, 26.55), 0.7, 20.0)
	mb.box("wood", Vector3(-8.90, 0.62, 26.55), Vector3(-8.20, 0.72, 27.45), 0.7, 18.0)
	mb.box("wood", Vector3(-8.90, 0.72, 27.36), Vector3(-8.20, 0.88, 27.48), 0.7, 16.0)
	var mag_uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in 3:
		var mx := -8.72 + i * 0.26
		var my := 0.74 + (1 if i == 1 else 0) * 0.03
		mb.quad("poster", Vector3(mx - 0.1, my, 26.6), Vector3(mx + 0.1, my, 26.6), Vector3(mx + 0.1, my + 0.5, 26.6), Vector3(mx - 0.1, my + 0.5, 26.6), Vector3(0, 0.24, 0.97).normalized(), mag_uv, Vector2(0.3 * 20.0 / GL.ATLAS_PX, 0.5 * 20.0 / GL.ATLAS_PX))
	# A 字立牌（今日特惠；两片斜板 + 顶铰链 + 底撑）
	_a_frame_board(mb, Vector3(-7.95, 0.15, 34.4), Vector3(-0.25, 0, 0.97), "sign_special")
	# 夜宵摊车（收摊罩布，停巷口靠北墙）
	_food_cart(mb, Vector3(-14.3, 0.1, 4.0))
	# 忘关的摊灯（灯杆 + 暖光池落在巷口）——本轮新增烘焙灯 1/2
	mb.cylinder("metal_dark", Vector3(-15.55, 0.1, 4.0), 0.045, 1.85, 8, 0.7, 14.0)
	mb.box("metal_dark", Vector3(-15.62, 1.85, 3.8), Vector3(-15.48, 1.98, 4.2), 0.7, 14.0)
	mb.bulb("bulb_warm", Vector3(-15.55, 1.78, 4.0), 0.09)
	lights_spec.append(_omni(Vector3(-15.4, 1.6, 4.0), Color(1, 0.72, 0.45), 1.4, 5.5))
	exclusions.append(AABB(Vector3(-15.9, 0, 3.1), Vector3(2.5, 2.0, 2.1)))


# G4 修理铺广场：A 板（营业中）+ 待修自行车斜靠架 + 油桶托盘 + 手推车
func _enrich_g4_repair_plaza(mb: GL.MeshBuilder) -> void:
	# A 板面朝广场西南（门户锚点与 repair_shop_view 视线均可读到）
	_a_frame_board(mb, Vector3(31.5, 0.17, 31.2), Vector3(-0.78, 0, -0.63), "sign_open_board")
	# 斜靠架（三柱一杆）+ 待修自行车 ×2（贴柱斜靠）
	for px in [27.0, 27.6, 28.2]:
		mb.box("metal_teal", Vector3(px - 0.045, 0.17, 23.4), Vector3(px + 0.045, 0.78, 23.5), 0.8, 16.0)
	mb.box("metal_teal", Vector3(26.9, 0.72, 23.32), Vector3(28.3, 0.84, 23.44), 0.7, 16.0)
	_bike(mb, 27.3, 0.17, 24.1, "lean")
	_bike(mb, 27.9, 0.17, 25.5, "lean")
	# 油桶 ×2 + 木托盘 + 零件箱（贴维修铺墙根，与门户落点保持 2m 以上）
	mb.box("wood", Vector3(29.95, 0.17, 35.7), Vector3(31.25, 0.29, 36.6), 0.7, 18.0)
	mb.cylinder("metal_orange", Vector3(30.25, 0.29, 36.15), 0.24, 0.85, 10, 0.55, 16.0)
	mb.cylinder("metal_orange", Vector3(30.95, 0.29, 37.25), 0.24, 0.85, 10, 0.55, 16.0)
	mb.box("wood", Vector3(30.7, 0.29, 35.85), Vector3(31.2, 0.72, 36.35), 0.7, 18.0)
	# 工具手推车（车斗 + 斜把手 + 双轮）
	mb.box("metal_teal", Vector3(26.6, 0.55, 22.2), Vector3(27.35, 0.98, 22.9), 0.7, 18.0)
	mb.box("metal_dark", Vector3(26.62, 0.42, 22.22), Vector3(27.33, 0.56, 22.88), 0.7, 16.0)
	mb.box("metal_dark", Vector3(27.35, 0.9, 22.35), Vector3(27.95, 1.18, 22.5), 0.7, 14.0)
	mb.cylinder("rubber", Vector3(26.85, 0.17, 22.95), 0.16, 0.08, 8, 0.8, 12.0)
	mb.cylinder("rubber", Vector3(27.1, 0.17, 22.2), 0.16, 0.08, 8, 0.8, 12.0)
	exclusions.append(AABB(Vector3(26.4, 0, 22.0), Vector3(2.6, 1.9, 4.0)))
	exclusions.append(AABB(Vector3(29.8, 0, 35.5), Vector3(2.0, 1.2, 2.4)))


# G5 生活广场：晾衣绳两组 + 水池拖把 + 杂物木架 + 猫窝（南翼建筑外，替换原穿模晾架）
func _enrich_g5_laundry_life(mb: GL.MeshBuilder) -> void:
	# 晾衣绳组 1（5 件）与组 2（4 件）：立柱 + 拉线 + 交替色衣物
	_clothesline(mb, -62.0, -58.0, -9.6, ["cloth", "cloth_blue", "cloth_rose", "cloth", "cloth_blue"])
	_clothesline(mb, -55.5, -51.5, -9.6, ["cloth_rose", "cloth", "cloth_blue", "cloth"])
	# 水池 + 拖把（洗衣店东墙脚）
	mb.box("concrete_plain", Vector3(-63.35, 0.12, -10.15), Vector3(-62.45, 0.67, -9.45), 0.55, 20.0)
	mb.box("metal_dark", Vector3(-63.25, 0.67, -10.05), Vector3(-62.55, 0.85, -9.55), 0.6, 18.0)
	mb.cylinder("wood", Vector3(-62.3, 0.12, -9.7), 0.035, 1.35, 6, 0.7, 12.0)
	mb.bulb("cloth", Vector3(-62.3, 1.44, -9.7), 0.11)
	# 杂物木架（三层，纸箱错落）
	mb.box("wood", Vector3(-50.6, 0.12, -10.2), Vector3(-50.45, 1.75, -9.6), 0.7, 16.0)
	mb.box("wood", Vector3(-49.4, 0.12, -10.2), Vector3(-49.25, 1.75, -9.6), 0.7, 16.0)
	for i in 3:
		var sy := 0.5 + i * 0.5
		mb.box("wood", Vector3(-50.6, sy, -10.15), Vector3(-49.25, sy + 0.05, -9.65), 0.7, 16.0)
	mb.box("wall_warm", Vector3(-50.4, 0.55, -10.05), Vector3(-49.95, 0.98, -9.72), 0.6, 18.0)
	mb.box("wood", Vector3(-49.85, 1.05, -10.0), Vector3(-49.5, 1.4, -9.75), 0.7, 18.0)
	# 猫窝（南翼墙根，开口朝北）
	mb.box("wood", Vector3(-54.98, 0.12, -10.85), Vector3(-54.42, 0.55, -10.35), 0.7, 18.0)
	mb.box("wood", Vector3(-54.98, 0.55, -10.9), Vector3(-54.42, 0.62, -10.3), 0.7, 16.0)
	mb.box("cloth", Vector3(-54.88, 0.56, -10.72), Vector3(-54.52, 0.60, -10.48), 0.8, 10.0)
	# 晾衣区壁灯（南翼北墙）——本轮新增烘焙灯 2/2
	mb.box("metal_dark", Vector3(-56.15, 2.05, -10.95), Vector3(-55.85, 2.32, -10.78), 0.8, 14.0)
	mb.bulb("bulb_warm", Vector3(-56.0, 1.98, -10.86), 0.07)
	lights_spec.append(_omni(Vector3(-56.0, 1.8, -10.4), Color(1, 0.74, 0.5), 1.2, 5.0))
	exclusions.append(AABB(Vector3(-63.5, 0, -10.95), Vector3(14.6, 2.3, 2.95)))


# G6 街面细节：井盖 ×4 + 消防栓（西侧）+ 锥桶 ×3 + 排水篦 ×2
func _enrich_g6_street_details(mb: GL.MeshBuilder) -> void:
	for p in [Vector3(20.0, 0.19, 24.0), Vector3(-8.0, 0.17, -14.0), Vector3(8.2, 0.17, 44.0), Vector3(-54.0, 0.14, -2.0)]:
		mb.cylinder("metal_dark", p, 0.42, 0.025, 10, 0.8, 18.0)
	# 消防栓（与东侧 7.2,2.0 对称）
	mb.cylinder("metal_orange", Vector3(-7.2, 0.15, 38.0), 0.11, 0.62, 8, 0.7, 20.0)
	mb.cylinder("metal_orange", Vector3(-7.2, 0.74, 38.0), 0.09, 0.12, 8, 0.7, 16.0)
	# 锥桶 ×3（主街修补区边缘）
	for p in [Vector3(-3.3, 0.03, 5.0), Vector3(0.5, 0.03, 5.6), Vector3(-3.3, 0.03, 11.0)]:
		mb.box("metal_orange", p + Vector3(-0.2, 0, -0.2), p + Vector3(0.2, 0.045, 0.2), 0.7, 14.0)
		mb.cylinder("metal_orange", p + Vector3(0, 0.045, 0), 0.16, 0.2, 8, 0.6, 14.0)
		mb.cylinder("metal_orange", p + Vector3(0, 0.245, 0), 0.115, 0.2, 8, 0.6, 14.0)
		mb.cylinder("metal_orange", p + Vector3(0, 0.445, 0), 0.07, 0.16, 8, 0.6, 14.0)
		mb.cylinder("wall_warm", p + Vector3(0, 0.235, 0), 0.117, 0.05, 8, 0.7, 12.0)
	# 排水篦 ×2（广场西缘路沿）
	for z in [21.0, 33.5]:
		mb.box("metal_dark", Vector3(12.55, 0.18, z - 0.5), Vector3(12.95, 0.24, z + 0.5), 0.8, 18.0)


# ---- street_enrich 复用小件 ----

func _tree_in_planter(mb: GL.MeshBuilder, x: float, ground_y: float, z: float, seed: int) -> void:
	## 花钵行道树：双层收分木箱 + 矮干 + 三簇错位叶冠（延续 _plant 的八面体语汇，尺度放大）。
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	mb.box("wood", Vector3(x - 0.55, ground_y, z - 0.55), Vector3(x + 0.55, ground_y + 0.4, z + 0.55), 0.7, 20.0)
	mb.box("wood", Vector3(x - 0.46, ground_y + 0.4, z - 0.46), Vector3(x + 0.46, ground_y + 0.56, z + 0.46), 0.7, 18.0)
	mb.box("rubber", Vector3(x - 0.4, ground_y + 0.52, z - 0.4), Vector3(x + 0.4, ground_y + 0.57, z + 0.4), 0.8, 12.0)
	mb.cylinder("wood", Vector3(x, ground_y + 0.54, z), 0.13, 2.55, 7, 0.7, 16.0)
	# 支撑枝两根（低模树冠的"骨架感"）
	mb.box("wood", Vector3(x - 0.02, ground_y + 1.7, z - 0.02), Vector3(x + 0.5, ground_y + 1.82, z + 0.04), 0.7, 14.0)
	mb.box("wood", Vector3(x - 0.5, ground_y + 2.1, z - 0.04), Vector3(x + 0.02, ground_y + 2.22, z + 0.02), 0.7, 14.0)
	# 叶冠（中心大簇 + 两错位小簇）
	mb.bulb("plant_green", Vector3(x, ground_y + 3.35, z), 1.02)
	mb.bulb("plant_green", Vector3(x + 0.42, ground_y + 2.78, z - 0.22), 0.66)
	mb.bulb("plant_green", Vector3(x - 0.34, ground_y + 2.9, z + 0.3), 0.58)
	mb.bulb("plant_green", Vector3(x + 0.1, ground_y + 3.95, z - 0.06), 0.5)


func _bike(mb: GL.MeshBuilder, x: float, ground_y: float, z: float, mode: String) -> void:
	## 轴对齐低模自行车（薄盒轮 + 五段车架 + 前筐）。mode: street=棚下直立 / lean=斜靠架旁贴靠。
	var lean_x := 0.14 if mode == "lean" else 0.0
	var lean_z := -0.1 if mode == "lean" else 0.0
	var wheel := "rubber"
	var frame := "metal_dark"
	# 前后轮（面法线朝 X 的薄盒）
	mb.box(wheel, Vector3(x - 0.025, ground_y + 0.3, z + lean_z - 0.52), Vector3(x + 0.025, ground_y + 0.9, z + lean_z - 0.44), 0.8, 14.0)
	mb.box(wheel, Vector3(x - 0.025, ground_y + 0.3, z + lean_z + 0.44), Vector3(x + 0.025, ground_y + 0.9, z + lean_z + 0.52), 0.8, 14.0)
	# 车架：踏板中轴 + 座管 + 下管 + 前立管
	mb.box(frame, Vector3(x - 0.03, ground_y + 0.42, z + lean_z - 0.1), Vector3(x + 0.03, ground_y + 0.5, z + lean_z + 0.12), 0.8, 14.0)
	mb.box(frame, Vector3(x - 0.025, ground_y + 0.48, z + lean_z - 0.22), Vector3(x + 0.025, ground_y + 0.95, z + lean_z - 0.14), 0.8, 14.0)
	mb.box(frame, Vector3(x - 0.025, ground_y + 0.48, z + lean_z + 0.12), Vector3(x + 0.025, ground_y + 0.62, z + lean_z + 0.4), 0.8, 14.0)
	mb.box(frame, Vector3(x - 0.025, ground_y + 0.6, z + lean_z + 0.36), Vector3(x + 0.025, ground_y + 0.98, z + lean_z + 0.44), 0.8, 14.0)
	# 座垫 + 把横
	mb.box("rubber", Vector3(x - 0.09, ground_y + 0.95, z + lean_z - 0.3), Vector3(x + 0.09, ground_y + 1.01, z + lean_z - 0.12), 0.8, 14.0)
	mb.box(frame, Vector3(x - 0.2, ground_y + 1.0, z + lean_x + lean_z + 0.38), Vector3(x + 0.2, ground_y + 1.06, z + lean_x + lean_z + 0.46), 0.8, 14.0)
	# 前筐（共享单车语汇）
	if mode == "street":
		mb.box("metal_teal", Vector3(x - 0.02, ground_y + 0.66, z + lean_z + 0.52), Vector3(x + 0.02, ground_y + 0.95, z + lean_z + 0.54), 0.8, 12.0)
		mb.box("metal_teal", Vector3(x - 0.18, ground_y + 0.66, z + lean_z + 0.5), Vector3(x - 0.16, ground_y + 0.95, z + lean_z + 0.56), 0.8, 12.0)
		mb.box("metal_teal", Vector3(x + 0.16, ground_y + 0.66, z + lean_z + 0.5), Vector3(x + 0.18, ground_y + 0.95, z + lean_z + 0.56), 0.8, 12.0)
		mb.box("metal_teal", Vector3(x - 0.18, ground_y + 0.93, z + lean_z + 0.5), Vector3(x + 0.18, ground_y + 0.95, z + lean_z + 0.56), 0.8, 12.0)


func _a_frame_board(mb: GL.MeshBuilder, base: Vector3, face_dir: Vector3, sign_key: String) -> void:
	## A 字立牌：前后两片斜板（字面 + 背板）+ 顶铰链 + 底部横撑。face_dir 为字面朝向（水平）。
	var f := Vector3(face_dir.x, 0, face_dir.z).normalized()
	var side := Vector3(-f.z, 0, f.x)
	var h := 1.15
	var w := 0.36
	var tilt := 0.16  # 顶部向背侧收进的进深
	var top := base + Vector3(0, h, 0) - f * tilt
	var bot := base + Vector3(0, 0.02, 0)
	var uv_full := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var size := Vector2(0.72 * 20.0 / GL.ATLAS_PX, h * 20.0 / GL.ATLAS_PX)
	# 前板（字面）：顶点序按"从法线侧看逆时针"（e1×e2 指向法线）；底部 v=1 对应图像底部
	mb.quad(sign_key, bot + side * w - f * 0.02, bot - side * w - f * 0.02, top - side * w, top + side * w, f, uv_full, size)
	# 背板（法线 -f，观察者一侧的左右翻转）
	mb.quad("wood", bot - side * w + f * 0.02, bot + side * w + f * 0.02, top + side * w, top - side * w, -f, uv_full, Vector2())
	# 顶铰链与底撑
	mb.box("metal_dark", top + side * -w - f * 0.05, top + side * w + f * 0.05 + Vector3(0, 0.05, 0), 0.7, 14.0)
	mb.box("wood", bot + side * -w + f * 0.16 + Vector3(0, 0.08, 0), bot + side * w + f * 0.16 + Vector3(0, 0.13, 0), 0.7, 14.0)


func _food_cart(mb: GL.MeshBuilder, base: Vector3) -> void:
	## 夜宵摊车（收摊罩布）：底盘 + 角柱 + 两坡罩布 + 侧垂帘 + 车轮。
	var x := base.x
	var y := base.y
	var z := base.z
	# 底盘与台面
	mb.box("metal_dark", Vector3(x - 0.95, y + 0.32, z - 0.48), Vector3(x + 0.95, y + 0.58, z + 0.48), 0.7, 20.0)
	mb.box("wood", Vector3(x - 0.98, y + 0.58, z - 0.5), Vector3(x + 0.98, y + 0.66, z + 0.5), 0.7, 18.0)
	# 角柱（撑起罩布）
	for cx in [x - 0.88, x + 0.88]:
		for cz in [z - 0.42, z + 0.42]:
			mb.box("metal_dark", Vector3(cx - 0.035, y + 0.66, cz - 0.035), Vector3(cx + 0.035, y + 1.78, cz + 0.035), 0.8, 14.0)
	# 罩布：屋脊两坡 + 前后垂边（顶点序 e1×e2 指向坡面外法线）
	var ridge_y := y + 2.02
	var eave_y := y + 1.8
	var uv_full := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var cloth_size := Vector2(2.0 * 20.0 / GL.ATLAS_PX, 0.9 * 20.0 / GL.ATLAS_PX)
	# 北坡（法线朝 -z 偏上）与南坡：两坡朝向相反，顶点序的 x 方向随 s 翻转
	# （验证：e1×e2 = (0, +0.72, +0.42·s 的镜像) 与坡面外法线同向）
	for s_val in [-1.0, 1.0]:
		var s: float = s_val
		var n := Vector3(0, 0.55, s * 0.83).normalized()
		var xa: float = x - 0.95 * s
		var xb: float = x + 0.95 * s
		mb.quad("cloth",
			Vector3(xa, eave_y, z + s * 0.46),
			Vector3(xb, eave_y, z + s * 0.46),
			Vector3(xb, ridge_y, z + s * 0.08),
			Vector3(xa, ridge_y, z + s * 0.08), n, uv_full, cloth_size)
	# 东西两侧三角垂片（退化 quad：底边两点 + 脊点重复；东侧法线 +x 顶点序反向）
	for ex in [x - 0.95, x + 0.95]:
		var n2 := Vector3(signf(ex - x), 0, 0)
		var tri_size := Vector2(0.9 * 16.0 / GL.ATLAS_PX, 0.35 * 16.0 / GL.ATLAS_PX)
		if ex < x:
			mb.quad("cloth",
				Vector3(ex, eave_y, z - 0.46),
				Vector3(ex, eave_y, z + 0.46),
				Vector3(ex, ridge_y, z + 0.08),
				Vector3(ex, ridge_y, z + 0.08), n2, uv_full, tri_size)
		else:
			mb.quad("cloth",
				Vector3(ex, eave_y, z + 0.46),
				Vector3(ex, eave_y, z - 0.46),
				Vector3(ex, ridge_y, z + 0.08),
				Vector3(ex, ridge_y, z + 0.08), n2, uv_full, tri_size)
	# 车轮（巷地面 y=0.1，双侧双轮）
	for wx in [x - 0.75, x + 0.75]:
		for wz in [z - 0.44, z + 0.44]:
			mb.cylinder("rubber", Vector3(wx, 0.1, wz), 0.17, 0.09, 10, 0.8, 14.0)
	# 推车把手（东端）
	mb.box("metal_dark", Vector3(x + 0.98, y + 0.78, z - 0.06), Vector3(x + 1.35, y + 0.9, z + 0.06), 0.7, 14.0)


func _clothesline(mb: GL.MeshBuilder, x0: float, x1: float, z: float, cloth_keys: Array) -> void:
	## 晾衣绳：双柱 + 拉线 + 交替色衣物（暖色生活痕迹）。
	for px in [x0, x1]:
		mb.box("wood", Vector3(px - 0.05, 0.12, z - 0.05), Vector3(px + 0.05, 2.14, z + 0.05), 0.7, 16.0)
	mb.box("wire", Vector3(x0, 2.05, z - 0.012), Vector3(x1, 2.08, z + 0.012), 0.9, 8.0)
	var uv_full := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in cloth_keys.size():
		var cx: float = lerpf(x0 + 0.35, x1 - 0.35, float(i) / maxf(1.0, float(cloth_keys.size() - 1)))
		var w := 0.34 + 0.1 * float(i % 3)
		var top_y := 2.02 - 0.06 * float(i % 2)
		var bot_y := top_y - (0.62 + 0.1 * float((i + 1) % 3))
		var key := str(cloth_keys[i])
		var size := Vector2(w * 20.0 / GL.ATLAS_PX, (top_y - bot_y) * 20.0 / GL.ATLAS_PX)
		# 北面（法线 -z：x 递减序）与南面（法线 +z：x 递增序），布片双面各一片
		mb.quad(key, Vector3(cx + w / 2, bot_y, z), Vector3(cx - w / 2, bot_y, z), Vector3(cx - w / 2, top_y, z), Vector3(cx + w / 2, top_y, z), Vector3(0, 0, -1), uv_full, size)
		mb.quad(key, Vector3(cx - w / 2, bot_y, z), Vector3(cx + w / 2, bot_y, z), Vector3(cx + w / 2, top_y, z), Vector3(cx - w / 2, top_y, z), Vector3(0, 0, 1), uv_full, Vector2())


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
		"portals": portals,
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
	# chapter1-2 §5.2：街面丰富专属——A 牌字图（非发光）与彩色衣物
	for k in ["special", "open_board"]:
		var board_path := "%s/signs/%s.png" % [TEX, k]
		var bm := StandardMaterial3D.new()
		if ResourceLoader.exists(board_path):
			bm.albedo_texture = load(board_path)
			bm.roughness = 0.9
		else:
			push_warning("authored: A 牌字图缺失 %s（重跑 gen_signs），回退纯色" % board_path)
			bm.albedo_color = Color(0.8, 0.78, 0.74)
			bm.roughness = 0.9
		mats["sign_%s" % k] = bm
	var cloth_blue := StandardMaterial3D.new()
	cloth_blue.albedo_color = Color(0.42, 0.50, 0.62)
	cloth_blue.roughness = 0.95
	mats["cloth_blue"] = cloth_blue
	var cloth_rose := StandardMaterial3D.new()
	cloth_rose.albedo_color = Color(0.70, 0.52, 0.55)
	cloth_rose.roughness = 0.95
	mats["cloth_rose"] = cloth_rose
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
