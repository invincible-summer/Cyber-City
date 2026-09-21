## m01_repair_interior「余晖维修·店内」生成（chapter1-2 §3/§6）。
## 运行：godot --headless --path . --script res://tools/build_interior.gd
## 职责：两层室内（一层工坊 + 通高中庭 + 直跑楼梯 + 二层居家阁楼 + 后部储物间）
##       的全部静态几何、烘焙灯、门外小景（Backdrop）、门户门扇；输出 interior_spec.json。
## 坐标（chapter1-2 §3.2）：原点=临街门中心地面；+X 向店内/东，-Z 北，Y 上。
## 面片一律走 mb.box/mb.quad（绕序由 GenLib._flush 保证）；烘焙网格带 UV2。
extends SceneTree

const GL := preload("res://tools/gen_lib.gd")
const MAT_DIR := "res://assets/m01_afterglow/materials"
const TEX := "res://assets/m01_afterglow/textures"
const MAP_DIR := "res://maps/m01_repair_interior"
const GEN_DIR := MAP_DIR + "/generated"
const MESH_DIR := MAP_DIR + "/meshes"
const GEN_SCENE := GEN_DIR + "/interior_generated.tscn"
const GEN_SPEC := GEN_DIR + "/interior_spec.json"

# ---- 尺寸常量（与 walk_surfaces/exclusions 同源） ----
const WALL_T := 0.24           # 外墙厚（中心线 x=0 / x=10 / z=±6）
const FLOOR_2 := 3.15          # 二层板顶
const ROOF := 6.3              # 屋顶板顶
const STAIR_X0 := 3.6          # 楼梯起步
const STAIR_N := 16
const STAIR_TREAD := 0.32
const STAIR_RISE := FLOOR_2 / float(STAIR_N)   # 0.196875
const STAIR_Z0 := -5.88        # 楼梯带北缘（贴北墙内面）
const STAIR_Z1 := -4.78        # 楼梯带宽 1.1
const SLAB_X := 3.4            # 二层主板西缘（其西为通高中庭）
const DOOR_Z0 := 1.25          # 入户门开口
const DOOR_Z1 := 2.15
const STORE_X0 := 10.12        # 储物间内空（南墙 z 0.88，东墙 x 13.88）
const STORE_X1 := 13.88
const STORE_Z1 := 0.88
const IN_N := -5.88            # 内墙面
const IN_S := 5.88
const IN_E := 9.88

var mats := {}
var lights_spec: Array = []
var exclusions: Array[AABB] = []
var anchors: Dictionary = {}
var walk_surfaces: Array[AABB] = []
var fans: Array = []
var flickers: Array = []
var portals: Array = []
var door_spec := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== build_interior ===")
	DirAccess.make_dir_recursive_absolute(GEN_DIR)
	DirAccess.make_dir_recursive_absolute(MESH_DIR)
	_load_materials()

	var root := Node3D.new()
	root.name = "InteriorGenerated"

	# ---- 烘焙静态几何（不透明 + UV2） ----
	var mb := GL.MeshBuilder.new()
	_shell(mb)
	_stairs(mb)
	_furnish_ground(mb)
	_furnish_upper(mb)
	var baked_mesh := mb.commit(mats, "%s/interior_static.res" % MESH_DIR, Vector2i(2048, 2048))
	print("interior static: tris=", mb.tri_count(), " surf=", baked_mesh.get_surface_count(),
		" uv2_max_y=%.3f overflow=%d" % [mb.packer.max_y(), mb.packer.overflow_count])

	var geo := Node3D.new()
	geo.name = "StaticGeometry"
	var mi_static := MeshInstance3D.new()
	mi_static.name = "InteriorStaticMesh"
	mi_static.mesh = baked_mesh
	geo.add_child(mi_static)

	# ---- 玻璃（不烘焙：透明面不采 lightmap，避免零 UV2 采样伪影） ----
	var mb_glass := GL.MeshBuilder.new()
	_glass(mb_glass)
	var glass_mesh := mb_glass.commit(mats, "%s/interior_glass.res" % MESH_DIR, Vector2i(0, 0))
	var mi_glass := MeshInstance3D.new()
	mi_glass.name = "InteriorGlassMesh"
	mi_glass.mesh = glass_mesh
	geo.add_child(mi_glass)
	root.add_child(geo)

	# ---- 灯光（bake_only_light） ----
	var lighting := Node3D.new()
	lighting.name = "Lighting"
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

	# ---- 门外小景（Backdrop，不烘焙） ----
	var mb_bd := GL.MeshBuilder.new()
	_backdrop(mb_bd)
	var backdrop_mesh := mb_bd.commit(mats, "%s/interior_backdrop.res" % MESH_DIR, Vector2i(0, 0))
	var bd := Node3D.new()
	bd.name = "Backdrop"
	var mi_bd := MeshInstance3D.new()
	mi_bd.name = "InteriorBackdropMesh"
	mi_bd.mesh = backdrop_mesh
	bd.add_child(mi_bd)
	root.add_child(bd)

	# ---- 门户门扇（独立网格挂枢轴；烘焙随闭合位） ----
	var mb_door := GL.MeshBuilder.new()
	_door_leaf(mb_door)
	var door_mesh := mb_door.commit(mats, "%s/interior_door_leaf.res" % MESH_DIR, Vector2i(256, 256))
	var doors := Node3D.new()
	doors.name = "PortalDoors"
	var pivot := Node3D.new()
	pivot.name = "ShopDoorPivot"
	pivot.position = Vector3(0.07, 0.0, DOOR_Z0)
	pivot.add_to_group("portal_door")
	pivot.set_meta("node_groups", PackedStringArray(["portal_door"]))
	pivot.set_meta("swing_deg", 100.0)
	pivot.set_meta("swing_axis", "y")
	var mi_door := MeshInstance3D.new()
	mi_door.name = "DoorLeaf"
	mi_door.mesh = door_mesh
	pivot.add_child(mi_door)
	doors.add_child(pivot)
	root.add_child(doors)

	_set_all_owners(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack 失败: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, GEN_SCENE)
	print("interior generated scene saved: ", err)

	_build_contract_data()
	_save_spec()
	print("INTERIOR_DONE")
	quit(0)


# ============================ 外壳 ============================

func _shell(mb: GL.MeshBuilder) -> void:
	var wall := "wall_warm"
	var concrete := "concrete_plain"
	# 地面：一层水泥（大厅）+ 储物间
	mb.box(concrete, Vector3(-0.12, -0.12, -6.12), Vector3(IN_E, 0.0, 6.12), 1.0 / 3.0, 26.0, 4)
	mb.box(concrete, Vector3(STORE_X0, -0.12, -6.12), Vector3(STORE_X1 + WALL_T, 0.0, STORE_Z1), 1.0 / 3.0, 26.0, 4)
	# 黄色工位划线 + 橡胶垫（待修摩托区）
	_flat(mb, "marking", Vector3(5.6, 0.005, -1.6), 2.6, 2.0)
	mb.box("rubber", Vector3(1.5, 0.0, -5.5), Vector3(2.5, 0.02, -4.6), 0.7, 20.0, 4)
	mb.box("rubber", Vector3(1.6, 0.0, 3.4), Vector3(2.6, 0.02, 4.2), 0.7, 20.0, 4)

	# ---- 前墙 x=0（门 z1.25..2.15 / 大橱窗 z-5..1 y0.45..3.0 / 二层大窗 z-4.5..1 y3.9..6.0） ----
	var fx0 := -0.12
	var fx1 := 0.12
	mb.box(wall, Vector3(fx0, 0, -6.12), Vector3(fx1, ROOF, -5.0), 1.0 / 3.0, 26.0)                 # 西段
	mb.box(wall, Vector3(fx0, 0, -5.0), Vector3(fx1, 0.45, 1.0), 1.0 / 3.0, 26.0)                   # 橱窗下
	mb.box(wall, Vector3(fx0, 3.0, -5.0), Vector3(fx1, 3.9, 1.0), 1.0 / 3.0, 26.0)                  # 两窗间带
	mb.box(wall, Vector3(fx0, 6.0, -5.0), Vector3(fx1, ROOF, 1.0), 1.0 / 3.0, 26.0)                 # 上窗楣
	mb.box(wall, Vector3(fx0, 0, 1.0), Vector3(fx1, ROOF, DOOR_Z0), 1.0 / 3.0, 26.0)                # 门侧墙
	mb.box(wall, Vector3(fx0, 2.3, DOOR_Z0), Vector3(fx1, ROOF, DOOR_Z1), 1.0 / 3.0, 26.0)          # 门楣
	mb.box(wall, Vector3(fx0, 0, DOOR_Z1), Vector3(fx1, ROOF, 6.12), 1.0 / 3.0, 26.0)               # 东段（橱窗东侧宽带）
	# 橱窗竖梃（金属）+ 台阶式窗台
	for zz in [-3.4, -1.8, -0.2]:
		mb.box("metal_dark", Vector3(fx0, 0.45, zz - 0.04), Vector3(fx1, 3.0, zz + 0.04), 0.5, 24.0)
	mb.box("metal_dark", Vector3(fx0, 1.7, -5.0), Vector3(fx1, 1.78, 1.0), 0.5, 24.0)
	mb.box(concrete, Vector3(fx0 + 0.02, 0.32, -5.05), Vector3(fx1 + 0.1, 0.45, 1.05), 0.5, 24.0)   # 窗台
	# 上窗框 + 中梃
	mb.box("metal_dark", Vector3(fx0, 3.9, -4.5), Vector3(fx1, 3.98, 1.0), 0.5, 24.0)
	mb.box("metal_dark", Vector3(fx0, 5.92, -4.5), Vector3(fx1, 6.0, 1.0), 0.5, 24.0)
	mb.box("metal_dark", Vector3(fx0, 3.9, -1.75), Vector3(fx1, 6.0, -1.67), 0.5, 24.0)
	# 门框（金属 jamb）
	mb.box("metal_dark", Vector3(fx0, 0, DOOR_Z0 - 0.05), Vector3(fx1, 2.3, DOOR_Z0), 0.5, 24.0)
	mb.box("metal_dark", Vector3(fx0, 0, DOOR_Z1), Vector3(fx1, 2.3, DOOR_Z1 + 0.05), 0.5, 24.0)
	mb.box("metal_dark", Vector3(-0.16, 0, DOOR_Z0), Vector3(fx1, 0.02, DOOR_Z1), 0.6, 22.0)        # 门槛

	# ---- 北墙 z=-6（整面实墙；一层后部为储物间北墙共用） ----
	mb.box(wall, Vector3(fx0, 0, -6.12), Vector3(IN_E, ROOF, IN_N), 1.0 / 3.0, 26.0)
	mb.box(wall, Vector3(IN_E, 0, -6.12), Vector3(STORE_X1 + WALL_T, 3.0, IN_N), 1.0 / 3.0, 26.0)
	# ---- 南墙 z=6 ----
	mb.box(wall, Vector3(fx0, 0, IN_S), Vector3(STORE_X1 + WALL_T, ROOF, 6.12), 1.0 / 3.0, 26.0)
	# ---- 东墙 x=10（大厅侧）：开门洞 z -4.2..-2.4 h2.3；其余实墙；砖饰面在大厅内侧 ----
	mb.box("wall_brick", Vector3(IN_E, 0, -6.12), Vector3(10.12, ROOF, -4.2), 1.0 / 3.2, 26.0)
	mb.box("wall_brick", Vector3(IN_E, 2.3, -4.2), Vector3(10.12, ROOF, -2.4), 1.0 / 3.2, 26.0)
	mb.box("wall_brick", Vector3(IN_E, 0, -2.4), Vector3(10.12, ROOF, STORE_Z1), 1.0 / 3.2, 26.0)
	mb.box("wall_brick", Vector3(IN_E, 0, STORE_Z1), Vector3(10.12, ROOF, 6.12), 1.0 / 3.2, 26.0)
	# 门洞顶梁
	mb.box("metal_dark", Vector3(IN_E, 2.24, -4.25), Vector3(10.12, 2.36, -2.35), 0.6, 22.0)
	# 二层东窗（x=10 墙 z 2..4 y 4.0..5.6，阅读角）：框 + 玻璃（玻璃在 _glass）
	mb.box("metal_dark", Vector3(IN_E - 0.02, 4.0, 2.0), Vector3(IN_E + 0.06, 4.1, 4.0), 0.5, 24.0)
	mb.box("metal_dark", Vector3(IN_E - 0.02, 5.5, 2.0), Vector3(IN_E + 0.06, 5.6, 4.0), 0.5, 24.0)
	mb.box("metal_dark", Vector3(IN_E - 0.02, 4.0, 2.0), Vector3(IN_E + 0.06, 5.6, 2.08), 0.5, 24.0)
	mb.box("metal_dark", Vector3(IN_E - 0.02, 4.0, 3.92), Vector3(IN_E + 0.06, 5.6, 4.0), 0.5, 24.0)
	mb.box("metal_dark", Vector3(IN_E - 0.02, 4.75, 2.0), Vector3(IN_E + 0.06, 4.83, 4.0), 0.5, 24.0)

	# ---- 储物间：南墙 z 0.88..1.12、东墙 x 13.88..14.12（含两扇闭窗框）、平屋顶 ----
	mb.box(concrete, Vector3(10.12, 0, STORE_Z1), Vector3(STORE_X1 + WALL_T, 3.0, STORE_Z1 + WALL_T), 1.0 / 3.0, 26.0)
	mb.box(concrete, Vector3(STORE_X1, 0, -6.12), Vector3(STORE_X1 + WALL_T, 3.0, STORE_Z1 + WALL_T), 1.0 / 3.0, 26.0)
	mb.box("roof", Vector3(10.0, 3.0, -6.12), Vector3(STORE_X1 + WALL_T, 3.15, STORE_Z1 + WALL_T), 0.25, 18.0)
	# 储物间东墙闭窗 ×2（框 + 深色玻璃面，不开洞）
	for zz in [-4.5, 0.0]:
		mb.box("metal_dark", Vector3(STORE_X1 - 0.06, 1.0, zz - 0.66), Vector3(STORE_X1 + 0.02, 1.08, zz + 0.66), 0.5, 22.0)
		mb.box("metal_dark", Vector3(STORE_X1 - 0.06, 1.92, zz - 0.66), Vector3(STORE_X1 + 0.02, 2.0, zz + 0.66), 0.5, 22.0)
		mb.box("metal_dark", Vector3(STORE_X1 - 0.06, 1.0, zz - 0.66), Vector3(STORE_X1 + 0.02, 2.0, zz - 0.58), 0.5, 22.0)
		mb.box("metal_dark", Vector3(STORE_X1 - 0.06, 1.0, zz + 0.58), Vector3(STORE_X1 + 0.02, 2.0, zz + 0.66), 0.5, 22.0)
		var guv := Vector2(1.2 * 22.0 / GL.ATLAS_PX, 0.9 * 22.0 / GL.ATLAS_PX)
		mb.quad("glass_dark", Vector3(STORE_X1 - 0.055, 1.05, zz - 0.6), Vector3(STORE_X1 - 0.055, 1.05, zz + 0.6),
			Vector3(STORE_X1 - 0.055, 1.95, zz + 0.6), Vector3(STORE_X1 - 0.055, 1.95, zz - 0.6),
			Vector3(-1, 0, 0), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], guv)

	# ---- 二层楼板：主板（x3.4..9.88 z-4.78..5.88）+ 楼梯口落脚条；结构层混凝土 + 木地板面 ----
	mb.box(concrete, Vector3(SLAB_X, 3.0, STAIR_Z1), Vector3(IN_E, 3.12, 6.12), 0.55, 24.0)
	mb.box("wood_floor", Vector3(SLAB_X, 3.12, STAIR_Z1), Vector3(IN_E, FLOOR_2, 6.12), 0.9, 26.0, 4)
	var land_x0 := STAIR_X0 + STAIR_N * STAIR_TREAD   # 8.72
	mb.box(concrete, Vector3(land_x0, 3.0, STAIR_Z0), Vector3(IN_E, 3.12, STAIR_Z1), 0.55, 24.0)
	mb.box("wood_floor", Vector3(land_x0, 3.12, STAIR_Z0), Vector3(IN_E, FLOOR_2, STAIR_Z1), 0.9, 26.0, 4)
	# 二层板西缘封边（朝中庭可见的木封条）
	mb.box("wood", Vector3(SLAB_X - 0.06, 3.0, STAIR_Z0), Vector3(SLAB_X, FLOOR_2, 6.12), 0.7, 22.0)

	# ---- 屋顶板 + 梁 ----
	mb.box(concrete, Vector3(fx0, 6.15, -6.12), Vector3(IN_E, ROOF, 6.12), 0.55, 20.0, 8)
	for zz in [-4.5, -1.5, 1.5, 4.5]:
		mb.box("wood", Vector3(fx0, 5.98, zz - 0.09), Vector3(10.0, 6.15, zz + 0.09), 0.7, 22.0)

	# ---- 墙面挂画 / 招贴（一层两张、二层两张） ----
	var puv := Vector2(0.9 * 20.0 / GL.ATLAS_PX, 0.65 * 20.0 / GL.ATLAS_PX)
	mb.quad("poster", Vector3(6.4, 1.7, IN_S - 0.02), Vector3(5.5, 1.7, IN_S - 0.02),
		Vector3(5.5, 2.35, IN_S - 0.02), Vector3(6.4, 2.35, IN_S - 0.02), Vector3(0, 0, -1),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], puv)
	mb.quad("poster", Vector3(0.14, 1.8, 3.2), Vector3(0.14, 1.8, 2.3), Vector3(0.14, 2.45, 2.3), Vector3(0.14, 2.45, 3.2),
		Vector3(1, 0, 0), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], puv)
	mb.quad("poster", Vector3(5.4, 4.6, IN_S - 0.02), Vector3(4.6, 4.6, IN_S - 0.02),
		Vector3(4.6, 5.2, IN_S - 0.02), Vector3(5.4, 5.2, IN_S - 0.02), Vector3(0, 0, -1),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], puv)
	mb.quad("poster", Vector3(5.0, 4.6, IN_N + 0.02), Vector3(5.9, 4.6, IN_N + 0.02),
		Vector3(5.9, 5.2, IN_N + 0.02), Vector3(5.0, 5.2, IN_N + 0.02), Vector3(0, 0, 1),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], puv)


# ============================ 楼梯（实心踏步 + 南侧扶手） ============================

func _stairs(mb: GL.MeshBuilder) -> void:
	for i in STAIR_N:
		var x0 := STAIR_X0 + i * STAIR_TREAD
		var top := (i + 1) * STAIR_RISE
		mb.box("wood", Vector3(x0, 0.0, STAIR_Z0), Vector3(x0 + STAIR_TREAD, top, STAIR_Z1), 0.8, 26.0, 55)
	# 南侧开放扶手：立柱 + 双横杆（随踏步抬升）
	for i in STAIR_N:
		var cx := STAIR_X0 + i * STAIR_TREAD + 0.16
		var top := (i + 1) * STAIR_RISE
		mb.box("metal_dark", Vector3(cx - 0.03, top, STAIR_Z1 - 0.05), Vector3(cx + 0.03, top + 0.86, STAIR_Z1 + 0.01), 0.7, 16.0)
		mb.box("metal_teal", Vector3(cx - 0.02, top + 0.42, STAIR_Z1 - 0.04), Vector3(cx + STAIR_TREAD - 0.14, top + 0.54, STAIR_Z1), 0.7, 16.0)
		mb.box("metal_teal", Vector3(cx - 0.02, top + 0.82, STAIR_Z1 - 0.04), Vector3(cx + STAIR_TREAD - 0.14, top + 0.92, STAIR_Z1), 0.7, 16.0)
	# 楼梯侧串板（南侧包边，遮住实心踏步断面）
	for i in STAIR_N:
		var x0 := STAIR_X0 + i * STAIR_TREAD
		var top := (i + 1) * STAIR_RISE
		mb.box("wood", Vector3(x0, 0.0, STAIR_Z1 - 0.02), Vector3(x0 + STAIR_TREAD, top, STAIR_Z1), 0.8, 26.0, 10)
	# 北墙侧灯串（暖灯泡，自 z -5.5 沿踏步上方）
	for i in range(0, STAIR_N, 2):
		var cx := STAIR_X0 + i * STAIR_TREAD + 0.16
		var top := (i + 1) * STAIR_RISE
		mb.bulb("bulb_warm", Vector3(cx, top + 0.55, STAIR_Z0 + 0.1), 0.06)
	# 2F 画廊栏杆（x=3.4，z -4.78..5.88）
	var zz := STAIR_Z1
	while zz <= 5.88:
		mb.box("metal_dark", Vector3(SLAB_X - 0.03, FLOOR_2, zz - 0.03), Vector3(SLAB_X + 0.03, FLOOR_2 + 0.95, zz + 0.03), 0.7, 16.0)
		zz += 1.1
	mb.box("wood", Vector3(SLAB_X - 0.05, FLOOR_2 + 0.92, STAIR_Z1), Vector3(SLAB_X + 0.05, FLOOR_2 + 1.04, 5.88), 0.7, 18.0)
	mb.box("metal_teal", Vector3(SLAB_X - 0.04, FLOOR_2 + 0.45, STAIR_Z1), Vector3(SLAB_X + 0.04, FLOOR_2 + 0.55, 5.88), 0.7, 16.0)
	# 栏杆小灯串（二层，breathing 微光由 flicker 提供；v5 终验后扩到北段并微增球径
	# ——gallery 机位 0.7m 时灯串点应可读地排在扶手细线上方）
	for k in 9:
		var lz := -3.4 + k * 1.0
		mb.bulb("bulb_warm", Vector3(SLAB_X, FLOOR_2 + 1.1, lz), 0.055)


# ============================ 一层陈设（工坊） ============================

func _furnish_ground(mb: GL.MeshBuilder) -> void:
	# L 型接待柜台 + 收银机 + 台灯
	mb.box("wood", Vector3(0.7, 0.0, 3.9), Vector3(4.3, 0.92, 4.75), 0.7, 24.0, 55)
	mb.box("metal_teal", Vector3(0.66, 0.0, 3.86), Vector3(4.34, 1.0, 4.79), 0.6, 24.0, 10)
	mb.box("wood", Vector3(0.6, 0.0, 2.9), Vector3(1.4, 0.92, 3.9), 0.7, 24.0, 55)
	mb.box("metal_dark", Vector3(2.3, 1.0, 4.2), Vector3(2.9, 1.32, 4.6), 0.6, 20.0)           # 收银机
	var ruv := Vector2(0.35 * 22.0 / GL.ATLAS_PX, 0.2 * 22.0 / GL.ATLAS_PX)
	mb.quad("lit_cool", Vector3(2.32, 1.06, 4.61), Vector3(2.88, 1.06, 4.61), Vector3(2.88, 1.26, 4.61), Vector3(2.32, 1.26, 4.61),
		Vector3(0, 0, 1), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], ruv)
	mb.cylinder("metal_dark", Vector3(3.6, 1.0, 4.3), 0.03, 0.5, 6, 0.7, 16.0)                 # 柜台台灯杆
	mb.bulb("lamp_lens", Vector3(3.6, 1.56, 4.3), 0.09)
	lights_spec.append(_omni(Vector3(3.6, 1.7, 4.3), Color(1, 0.78, 0.5), 1.2, 3.5))
	# 高脚凳 ×2（柜台内侧）
	for px in [1.8, 3.0]:
		mb.cylinder("metal_dark", Vector3(px, 0.0, 3.5), 0.04, 0.62, 6, 0.7, 16.0)
		mb.cylinder("wood", Vector3(px, 0.62, 3.5), 0.17, 0.06, 10, 0.7, 18.0)
	# 门边等候长凳 + 雨伞桶 + 立牌
	mb.box("wood", Vector3(0.3, 0.0, 3.0), Vector3(0.78, 0.45, 4.4), 0.7, 22.0, 55)
	mb.box("wood", Vector3(0.3, 0.42, 3.0), Vector3(0.78, 0.5, 4.4), 0.7, 22.0)
	mb.cylinder("metal_dark", Vector3(0.5, 0.0, 2.6), 0.12, 0.5, 8, 0.7, 16.0)
	mb.box("metal_teal", Vector3(1.6, 0.0, 5.3), Vector3(2.1, 1.5, 5.7), 0.6, 20.0)            # 立式公告牌
	# 自动售货机（青色微光面板）
	mb.box("metal_dark", Vector3(4.55, 0.0, 5.0), Vector3(5.45, 1.9, 5.85), 0.7, 22.0, 55)
	var vuv := Vector2(0.6 * 22.0 / GL.ATLAS_PX, 1.2 * 22.0 / GL.ATLAS_PX)
	mb.quad("vending_panel", Vector3(5.42, 0.5, 4.98), Vector3(4.58, 0.5, 4.98), Vector3(4.58, 1.7, 4.98), Vector3(5.42, 1.7, 4.98),
		Vector3(0, 0, -1), [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	lights_spec.append(_omni(Vector3(5.0, 1.2, 4.6), Color(0.5, 0.88, 0.85), 0.9, 2.5))
	flickers.append({"mat_key": "vending_panel", "pos": [5.0, 1.1, 4.96], "size": [0.84, 1.2], "rot_y": 180.0})
	# 工作台（沿北墙）+ 虎钳 + 托盘 + 台灯
	mb.box("wood", Vector3(0.6, 0.0, -5.88), Vector3(3.4, 0.9, -5.1), 0.7, 24.0, 55)
	mb.box("metal_dark", Vector3(0.58, 0.0, -5.9), Vector3(3.42, 0.96, -5.08), 0.6, 22.0, 10)
	mb.box("metal_dark", Vector3(1.1, 0.9, -5.7), Vector3(1.4, 1.18, -5.45), 0.6, 20.0)        # 虎钳
	mb.box("wood", Vector3(2.0, 0.9, -5.75), Vector3(2.7, 0.98, -5.3), 0.7, 20.0)             # 托盘
	mb.cylinder("metal_dark", Vector3(3.0, 0.9, -5.5), 0.03, 0.45, 6, 0.7, 16.0)
	mb.bulb("lamp_lens", Vector3(3.0, 1.4, -5.5), 0.1)
	lights_spec.append(_omni(Vector3(3.0, 1.55, -5.4), Color(1, 0.8, 0.55), 1.6, 4.0))
	# 洞洞板工具墙（板 + 挂件剪影）
	mb.box("wood", Vector3(0.7, 1.5, -5.86), Vector3(3.3, 2.7, -5.78), 0.7, 22.0)
	for k in 8:
		var tx := 0.95 + k * 0.3
		var ty := 1.75 + (k % 3) * 0.3
		mb.box("metal_dark", Vector3(tx, ty, -5.82), Vector3(tx + 0.05 + float(k % 2) * 0.12, ty + 0.22, -5.76), 0.7, 14.0)
	# 零件抽屉柜 + 滚动工具车
	mb.box("metal_teal", Vector3(0.35, 0.0, -4.9), Vector3(1.15, 1.05, -4.2), 0.7, 22.0, 55)
	for k in 3:
		mb.box("metal_dark", Vector3(0.33, 0.15 + k * 0.3, -4.92), Vector3(1.17, 0.4 + k * 0.3, -4.18), 0.6, 18.0)
	mb.box("metal_dark", Vector3(3.7, 0.0, -4.5), Vector3(4.35, 0.85, -3.9), 0.7, 22.0, 55)
	for k in 2:
		mb.box("metal_teal", Vector3(3.68, 0.2 + k * 0.3, -4.52), Vector3(4.37, 0.45 + k * 0.3, -3.88), 0.6, 18.0)
	# 轮胎堆 ×3 + 木托盘旧机箱
	for k in 3:
		mb.cylinder("rubber", Vector3(1.0, 0.0 + k * 0.22, -5.3), 0.34, 0.2, 12, 0.6, 20.0)
	mb.box("wood", Vector3(1.8, 0.0, -4.1), Vector3(2.6, 0.14, -3.4), 0.7, 20.0)
	mb.box("metal_dark", Vector3(1.9, 0.14, -4.0), Vector3(2.5, 0.58, -3.5), 0.65, 18.0)
	# 待修电动摩托（近未来：青色灯带）
	var mx := 5.6
	var mz := -1.6
	mb.box("metal_dark", Vector3(mx - 0.65, 0.32, mz - 0.22), Vector3(mx + 0.65, 0.62, mz + 0.22), 0.65, 22.0)   # 车架
	mb.box("metal_teal", Vector3(mx - 0.28, 0.58, mz - 0.2), Vector3(mx + 0.3, 0.78, mz + 0.2), 0.65, 20.0)      # 座椅
	mb.box("metal_dark", Vector3(mx - 0.5, 0.62, mz - 0.05), Vector3(mx - 0.3, 1.0, mz + 0.05), 0.65, 18.0)      # 车头杆
	mb.box("metal_dark", Vector3(mx - 0.62, 0.98, mz - 0.3), Vector3(mx - 0.2, 1.04, mz + 0.3), 0.65, 18.0)      # 车把
	mb.cylinder("rubber", Vector3(mx - 0.55, 0.0, mz), 0.3, 0.12, 12, 0.6, 20.0)
	mb.cylinder("rubber", Vector3(mx + 0.55, 0.0, mz), 0.3, 0.12, 12, 0.6, 20.0)
	var tuv := Vector2(0.8 * 22.0 / GL.ATLAS_PX, 0.06 * 22.0 / GL.ATLAS_PX)
	mb.quad("terminal_screen", Vector3(mx + 0.3, 0.5, mz - 0.23), Vector3(mx - 0.5, 0.5, mz - 0.23),
		Vector3(mx - 0.5, 0.56, mz - 0.23), Vector3(mx + 0.3, 0.56, mz - 0.23), Vector3(0, 0, -1),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	# 三脚工作灯（摩托旁）
	mb.cylinder("metal_dark", Vector3(4.7, 0.0, -2.7), 0.03, 1.3, 6, 0.7, 16.0)
	mb.bulb("lamp_lens", Vector3(4.7, 1.4, -2.7), 0.12)
	lights_spec.append(_omni(Vector3(4.7, 1.5, -2.6), Color(1, 0.82, 0.58), 1.5, 4.5))
	# 南墙零件货架 ×2 组（立柱 + 层板 + 零件箱）
	for g in 2:
		var sx := 5.8 + g * 2.6
		for k in 4:
			mb.box("metal_dark", Vector3(sx, 0.0 + k * 0.6, 5.32), Vector3(sx + 2.2, 0.06 + k * 0.6, 5.86), 0.7, 18.0)
		for col in [[0.0, 0.0], [1.0, 0.3], [1.8, 0.0]]:
			var bx: float = sx + float(col[0])
			var by: float = 0.1 + float(col[1])
			mb.box("wood", Vector3(bx, by, 5.4), Vector3(bx + 0.36, by + 0.26, 5.8), 0.7, 18.0)
	# 油桶 ×2（东北角）
	for k in 2:
		mb.cylinder("metal_orange", Vector3(9.1 + k * 0.55, 0.0, 5.15), 0.24, 0.85, 10, 0.55, 18.0)
	# 中庭下地毯 + 两把等候椅 + 盆栽 + 毯边待修件木箱（打断 gallery_view 画框底部
	# 掠射角下的平坦地面带，v8 终验 B 项：11.9% 高度实心暗棕带读作"板"）
	_flat(mb, "rug", Vector3(1.5, 0.004, 0.0), 1.9, 2.6)
	for cp in [Vector3(1.0, 0.0, 0.7), Vector3(2.0, 0.0, -0.8)]:
		mb.box("wood", cp + Vector3(-0.22, 0.0, -0.22), cp + Vector3(0.22, 0.06, 0.22), 0.7, 18.0)
		mb.box("wood", cp + Vector3(-0.22, 0.06, 0.14), cp + Vector3(0.22, 0.5, 0.22), 0.7, 18.0)
	for k in 2:
		mb.box("wood", Vector3(1.15, 0.0 + k * 0.34, -2.12), Vector3(1.62, 0.34 + k * 0.34, -1.66), 0.7, 20.0)
	mb.box("metal_orange", Vector3(1.7, 0.0, -1.78), Vector3(2.05, 0.26, -1.44), 0.7, 20.0)
	_plant(mb, Vector3(0.6, 0.0, 5.4), 0.45)
	_plant(mb, Vector3(9.5, 0.0, -4.9), 0.4)
	# 储物间：货架 + 热水器 + 电池组（青色指示）+ 纸箱
	for k in 3:
		mb.box("metal_dark", Vector3(10.4, 0.0 + k * 0.75, -5.85), Vector3(13.6, 0.06 + k * 0.75, -5.2), 0.7, 18.0)
	for col in [[10.7, 0.1], [12.0, 0.85], [13.0, 0.1], [11.3, 1.6]]:
		mb.box("wood", Vector3(col[0], col[1], -5.8), Vector3(col[0] + 0.5, col[1] + 0.34, -5.4), 0.7, 18.0)
	mb.cylinder("metal_dark", Vector3(13.3, 0.0, 0.2), 0.32, 1.7, 10, 0.6, 20.0)               # 热水器
	mb.box("metal_teal", Vector3(10.5, 0.0, -0.2), Vector3(11.4, 1.3, 0.6), 0.7, 22.0, 55)     # 电池组
	for k in 3:
		mb.bulb("lit_cool", Vector3(11.44, 0.4 + k * 0.35, 0.2), 0.035)
	mb.box("wood", Vector3(12.6, 0.0, -1.4), Vector3(13.5, 0.6, -0.5), 0.7, 20.0)
	# 主照明（bake_only 暖光 ×2）+ 中庭黄昏冷渗 ×2 + 楼梯灯串主光
	# 1.2 终验修复：主光①西移到等待区正上方并提能（地毯/等候椅原烘焙后近黑不可读）
	lights_spec.append(_omni(Vector3(2.9, 2.6, 0.1), Color(1, 0.82, 0.6), 2.9, 8.0))
	lights_spec.append(_omni(Vector3(7.0, 2.6, -1.2), Color(1, 0.8, 0.58), 2.0, 7.0))
	lights_spec.append(_omni(Vector3(0.85, 2.3, -1.5), Color(0.55, 0.68, 0.92), 1.3, 6.0))
	lights_spec.append(_omni(Vector3(0.85, 5.0, -1.5), Color(0.55, 0.68, 0.92), 0.9, 6.0))
	lights_spec.append(_omni(Vector3(6.1, 2.7, -5.3), Color(1, 0.78, 0.5), 1.0, 4.0))
	# 门头檐板 + 字图店招 + 两侧挂画（v5 终验复盘：无字纯色光条被判“不可读店招”；
	# 换街面同款 repair_main 字图（4:1，2.0×0.5m 保持比例）——内外同一店铺身份）
	# v7 根因修复：前墙墙体 x -0.12..0.12，内表面在 x=0.12；v6 的檐板(-0.02..0.1)、
	# 店招(0.11)、挂画背板(0.02..0.12) 全部埋在墙体内 → 深度失败从不渲染，
	# 画面只剩墙面的暖米色（“店招无字”真因）。整组移到内面前方。
	mb.box("wood", Vector3(0.12, 3.0, -5.1), Vector3(0.24, 3.18, 1.1), 0.7, 24.0)
	var sign_uv := Vector2(2.0 * 26.0 / GL.ATLAS_PX, 0.5 * 26.0 / GL.ATLAS_PX)
	mb.quad("sign_repair", Vector3(0.25, 3.20, 0.6), Vector3(0.25, 3.20, -1.4),
		Vector3(0.25, 3.70, -1.4), Vector3(0.25, 3.70, 0.6), Vector3(1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], sign_uv)
	var poster_uv := Vector2(0.5 * 26.0 / GL.ATLAS_PX, 0.44 * 26.0 / GL.ATLAS_PX)
	for pz in [-3.9, 0.75]:
		mb.box("wood", Vector3(0.12, 3.06, pz - 0.3), Vector3(0.22, 3.54, pz + 0.3), 0.7, 22.0)
		mb.quad("poster", Vector3(0.23, 3.08, pz + 0.25), Vector3(0.23, 3.08, pz - 0.25),
			Vector3(0.23, 3.52, pz - 0.25), Vector3(0.23, 3.52, pz + 0.25), Vector3(1, 0, 0),
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], poster_uv)


# ============================ 二层陈设（居家阁楼） ============================

func _furnish_upper(mb: GL.MeshBuilder) -> void:
	var fy := FLOOR_2
	# 厨房角（北缘西段）：L 台面 + 水槽 + 水龙头 + 冰箱 + 吊架锅具
	mb.box("wood", Vector3(3.5, fy, -4.78), Vector3(7.5, fy + 0.86, -3.9), 0.7, 24.0, 55)
	mb.box("metal_teal", Vector3(3.46, fy, -4.8), Vector3(7.54, fy + 0.92, -3.86), 0.6, 24.0, 10)
	mb.box("metal_dark", Vector3(5.2, fy + 0.86, -4.5), Vector3(6.0, fy + 0.94, -4.1), 0.6, 20.0)  # 水槽
	mb.cylinder("metal_dark", Vector3(5.6, fy + 0.94, -4.35), 0.025, 0.3, 6, 0.7, 14.0)
	mb.box("metal_dark", Vector3(5.58, fy + 1.24, -4.5), Vector3(5.66, fy + 1.27, -4.2), 0.7, 14.0)
	mb.box("metal_dark", Vector3(7.5, fy, -4.75), Vector3(8.3, fy + 1.85, -3.95), 0.65, 22.0, 55)  # 冰箱
	for k in 2:
		mb.box("metal_dark", Vector3(3.9 + k * 0.55, fy + 1.9, -4.74), Vector3(4.42 + k * 0.55, fy + 2.02, -3.98), 0.7, 16.0)  # 吊架
		mb.cylinder("metal_dark", Vector3(4.16 + k * 0.55, fy + 1.55, -4.35), 0.12, 0.16, 8, 0.7, 14.0)
	# 餐桌（圆）+ 两椅（前窗光带）
	mb.cylinder("wood", Vector3(5.2, fy + 0.72, -2.0), 0.55, 0.05, 14, 0.7, 22.0)
	mb.cylinder("wood", Vector3(5.2, fy, -2.0), 0.06, 0.72, 8, 0.7, 18.0)
	for cp in [Vector3(4.5, 0, -1.3), Vector3(5.9, 0, -2.7)]:
		mb.box("wood", Vector3(cp.x - 0.2, fy + cp.y, cp.z - 0.2), Vector3(cp.x + 0.2, fy + cp.y + 0.44, cp.z + 0.2), 0.7, 18.0)
	# 床龛（东北）：床 + 床头板 + 床品 + 床头柜小灯 + 隔断 + 窗帘
	mb.box("wood", Vector3(8.6, fy, -2.0), Vector3(9.85, fy + 0.3, 0.8), 0.7, 24.0, 55)
	mb.box("bed_sheet", Vector3(8.62, fy + 0.3, -1.98), Vector3(9.83, fy + 0.46, 0.78), 0.85, 24.0, 4)
	mb.box("bed_sheet", Vector3(8.62, fy + 0.3, 0.2), Vector3(9.83, fy + 0.56, 0.78), 0.85, 24.0)   # 枕头区盖毯
	mb.box("wood", Vector3(8.55, fy, -2.05), Vector3(9.9, fy + 1.0, -1.85), 0.7, 22.0)             # 床头板
	mb.box("wood", Vector3(9.3, fy, 0.9), Vector3(9.85, fy + 0.5, 1.45), 0.7, 20.0)                # 床头柜
	mb.bulb("bulb_warm", Vector3(9.6, fy + 0.62, 1.18), 0.07)
	lights_spec.append(_omni(Vector3(9.6, fy + 0.8, 1.1), Color(1, 0.76, 0.5), 0.9, 2.5))
	mb.box("wall_warm", Vector3(8.3, fy, -2.05), Vector3(8.55, fy + 1.2, 0.85), 0.6, 24.0)         # 半墙隔断
	# 窗帘（东窗两侧）
	mb.box("cloth", Vector3(9.8, fy + 0.85, 1.7), Vector3(9.86, fy + 2.3, 2.3), 0.85, 18.0)
	mb.box("cloth", Vector3(9.8, fy + 0.85, 3.7), Vector3(9.86, fy + 2.3, 4.3), 0.85, 18.0)
	# 客厅角（南）：双人沙发 + 圆几 + 地毯 + 落地灯 + 书架
	mb.box("sofa_fabric", Vector3(4.9, fy, 4.9), Vector3(6.9, fy + 0.42, 5.85), 0.85, 24.0, 55)
	mb.box("sofa_fabric", Vector3(4.9, fy + 0.42, 5.5), Vector3(6.9, fy + 0.95, 5.85), 0.85, 24.0, 55)
	mb.box("sofa_fabric", Vector3(4.9, fy, 4.55), Vector3(5.25, fy + 0.7, 5.85), 0.85, 24.0)
	mb.box("sofa_fabric", Vector3(6.55, fy, 4.55), Vector3(6.9, fy + 0.7, 5.85), 0.85, 24.0)
	mb.cylinder("wood", Vector3(5.9, fy + 0.4, 4.0), 0.42, 0.05, 14, 0.7, 20.0)
	mb.cylinder("wood", Vector3(5.9, fy, 4.0), 0.05, 0.4, 8, 0.7, 16.0)
	_flat_upper(mb, "rug", Vector3(5.6, fy + 0.004, 4.2), 2.6, 2.2)
	mb.cylinder("metal_dark", Vector3(4.05, fy, 5.3), 0.03, 1.45, 6, 0.7, 16.0)
	mb.bulb("lamp_lens", Vector3(4.05, fy + 1.58, 5.3), 0.11)
	lights_spec.append(_omni(Vector3(4.05, fy + 1.75, 5.2), Color(1, 0.8, 0.55), 1.8, 5.0))
	mb.box("wood", Vector3(9.5, fy, 1.95), Vector3(9.85, fy + 2.0, 4.5), 0.7, 22.0)                # 书架
	for k in 4:
		mb.box("wood", Vector3(9.44, fy + 0.12 + k * 0.45, 2.0 + (k % 2) * 0.7), Vector3(9.9, fy + 0.17 + k * 0.45, 3.2 + (k % 2) * 0.7), 0.7, 18.0)
	# 终端桌（靠栏杆，面向中庭）
	mb.box("wood", Vector3(3.6, fy + 0.68, 1.0), Vector3(4.5, fy + 0.74, 2.4), 0.7, 22.0)
	for leg in [[3.66, 1.06], [3.66, 2.34], [4.44, 1.06], [4.44, 2.34]]:
		mb.box("metal_dark", Vector3(leg[0] - 0.03, fy, leg[1] - 0.03), Vector3(leg[0] + 0.03, fy + 0.68, leg[1] + 0.03), 0.7, 16.0)
	mb.box("metal_dark", Vector3(3.75, fy + 0.74, 1.35), Vector3(4.35, fy + 0.78, 1.95), 0.7, 18.0)  # 键盘
	mb.box("metal_dark", Vector3(3.85, fy + 0.74, 2.05), Vector3(4.25, fy + 1.05, 2.35), 0.65, 18.0) # 屏幕座
	mb.quad("terminal_screen", Vector3(3.84, fy + 0.78, 2.1), Vector3(3.84, fy + 0.78, 2.3),
		Vector3(3.84, fy + 1.04, 2.3), Vector3(3.84, fy + 1.04, 2.1), Vector3(-1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	lights_spec.append(_omni(Vector3(4.0, fy + 1.1, 2.1), Color(0.5, 0.88, 0.85), 0.8, 2.0))
	flickers.append({"mat_key": "terminal_screen", "pos": [3.83, fy + 0.91, 2.2], "size": [0.22, 0.28], "rot_y": 90.0})
	mb.box("wood", Vector3(3.9, fy, 2.6), Vector3(4.3, fy + 0.45, 3.0), 0.7, 18.0)                  # 椅
	# 衣架 + 挂衣 + 盆栽 + 纸箱
	mb.box("metal_dark", Vector3(3.5, fy, -4.3), Vector3(3.56, fy + 1.7, -3.5), 0.7, 16.0)
	for k in 3:
		mb.box("cloth", Vector3(3.58, fy + 1.0 + k * 0.22, -4.25 + k * 0.25), Vector3(3.94, fy + 1.5 + k * 0.22, -4.05 + k * 0.25), 0.85, 16.0)
	_plant(mb, Vector3(3.75, fy, 5.35), 0.42)
	mb.box("wood", Vector3(7.0, fy, 5.3), Vector3(7.8, fy + 0.55, 5.85), 0.7, 18.0)
	# 二层灯光：厨房主灯 + 餐区窗光冷补 + 过道微光
	lights_spec.append(_omni(Vector3(5.6, fy + 2.5, -4.3), Color(1, 0.82, 0.6), 1.6, 5.0))
	lights_spec.append(_omni(Vector3(0.9, fy + 1.6, -2.0), Color(0.55, 0.68, 0.92), 0.9, 5.0))
	lights_spec.append(_omni(Vector3(6.5, fy + 2.6, 1.5), Color(1, 0.8, 0.58), 1.5, 6.0))


# ============================ 玻璃（透明，不烘焙） ============================

func _glass(mb: GL.MeshBuilder) -> void:
	# 大橱窗（z -5..1, y 0.45..3.0）——normal +X：室内可见
	mb.quad("glass_interior", Vector3(0.0, 0.45, 1.0), Vector3(0.0, 0.45, -5.0),
		Vector3(0.0, 3.0, -5.0), Vector3(0.0, 3.0, 1.0), Vector3(1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	# 二层大窗（z -4.5..1, y 3.9..6.0）
	mb.quad("glass_interior", Vector3(0.0, 3.9, 1.0), Vector3(0.0, 3.9, -4.5),
		Vector3(0.0, 6.0, -4.5), Vector3(0.0, 6.0, 1.0), Vector3(1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	# 二层东窗（x 9.88 墙, z 2..4, y 4.0..5.6）
	mb.quad("glass_interior", Vector3(IN_E - 0.04, 4.0, 2.0), Vector3(IN_E - 0.04, 4.0, 4.0),
		Vector3(IN_E - 0.04, 5.6, 4.0), Vector3(IN_E - 0.04, 5.6, 2.0), Vector3(-1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())


# ============================ 门外小景（Backdrop，不烘焙） ============================

func _backdrop(mb: GL.MeshBuilder) -> void:
	# 人行道 + 街道（前窗/上窗外）
	mb.box("pavement", Vector3(-3.4, -0.12, -8.0), Vector3(-0.3, 0.0, 8.0), 1.0 / 2.4, 0.0, 4)
	mb.box("asphalt", Vector3(-10.5, -0.12, -9.0), Vector3(-3.4, -0.02, 9.0), 1.0 / 12.0, 0.0, 4)
	mb.box("concrete_plain", Vector3(-0.3, -0.12, -8.0), Vector3(-0.12, 0.09, 8.0), 0.5, 0.0, 4)  # 门前台阶
	# 对面店铺立面（暖窗）+ 二层体量错位
	# Flash 验收 1.2 修复：原楼顶 8.0m 高于二层窗顶视线(17m 外≈y7.4)，窗面看不到任何天光；
	# 主层降到 6.0、上叠层顶 6.4——窗上沿露出暮色天空，窗中段是加大的暖/冷窗与灯牌。
	mb.box("wall_panel", Vector3(-10.0, 0.0, -8.0), Vector3(-9.2, 6.0, 8.0), 1.0 / 3.0, 0.0, 55)
	mb.box("wall_warm", Vector3(-10.0, 6.0, -8.0), Vector3(-9.2, 6.4, 2.0), 1.0 / 3.0, 0.0, 55)
	for wz in [-6.0, -3.0, 0.0, 3.0]:
		mb.quad("lit_warm", Vector3(-9.18, 1.1, wz + 0.7), Vector3(-9.18, 1.1, wz - 0.7),
			Vector3(-9.18, 2.6, wz - 0.7), Vector3(-9.18, 2.6, wz + 0.7), Vector3(1, 0, 0),
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	for wz in [-5.0, -1.0, 3.0]:
		mb.quad("lit_cool", Vector3(-9.18, 4.3, wz + 0.65), Vector3(-9.18, 4.3, wz - 0.65),
			Vector3(-9.18, 5.7, wz - 0.65), Vector3(-9.18, 5.7, wz + 0.65), Vector3(1, 0, 0),
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	# 横向灯牌（对面店招，暮色天光下的中景亮点）
	mb.quad("lit_cool", Vector3(-9.18, 3.4, 1.2), Vector3(-9.18, 3.4, -3.8),
		Vector3(-9.18, 3.85, -3.8), Vector3(-9.18, 3.85, 1.2), Vector3(1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	# 街灯 ×2（含基座）+ 双层光池 + 停泊摩托 + 候车凳 + 斑马线 + 人行道树/邮筒
	# v5 终验复盘：二层俯瞰橱窗的可见街面是斜视线楔形（可见高度 y ≤ 3.0-0.43×距离），
	# 对面楼与路灯头全被橱窗檐墙遮挡——可读街景必须落在 d≤3.4 的人行道带内。
	for lz in [4.2, -2.4]:
		mb.cylinder("metal_dark", Vector3(-3.7, 0.0, lz), 0.07, 4.6, 8, 0.6, 0.0)
		mb.box("metal_dark", Vector3(-3.95, 4.45, lz - 0.1), Vector3(-3.5, 4.6, lz + 0.1), 0.7, 0.0)
		mb.bulb("lamp_lens", Vector3(-3.85, 4.35, lz), 0.11)
		mb.box("concrete_plain", Vector3(-3.88, 0.0, lz - 0.2), Vector3(-3.52, 0.24, lz + 0.2), 0.55, 0.0)
	_flat_bd(mb, "pool_glow", Vector3(-3.85, 0.02, 4.0), 2.2, 1.8)
	_flat_bd(mb, "pool_core", Vector3(-3.85, 0.024, 4.0), 1.1, 0.85)
	_flat_bd(mb, "pool_glow", Vector3(-3.85, 0.02, -2.2), 2.6, 2.2)
	_flat_bd(mb, "pool_core", Vector3(-3.85, 0.024, -2.2), 1.3, 1.05)
	# 停泊摩托（v5 远看被读作“悬浮黑钩”——补座垫/车把/尾灯使其成为可读剪影）
	mb.box("metal_dark", Vector3(-4.6, 0.0, -2.62), Vector3(-3.9, 0.55, -2.18), 0.65, 0.0)
	mb.box("metal_teal", Vector3(-4.45, 0.55, -2.54), Vector3(-4.05, 0.68, -2.26), 0.7, 0.0)
	mb.box("metal_dark", Vector3(-4.42, 0.68, -2.5), Vector3(-4.32, 0.98, -2.3), 0.7, 0.0)
	mb.cylinder("rubber", Vector3(-4.55, 0.0, -2.4), 0.26, 0.1, 10, 0.6, 0.0)
	mb.cylinder("rubber", Vector3(-3.95, 0.0, -2.4), 0.26, 0.1, 10, 0.6, 0.0)
	mb.bulb("bulb_warm", Vector3(-4.56, 0.62, -2.4), 0.045)
	# 灯杆②城市挂旗 + 候车凳（人行道家具，均在可见高度内）
	mb.quad("metal_teal", Vector3(-3.62, 1.15, -2.18), Vector3(-3.62, 1.15, -2.62),
		Vector3(-3.62, 1.72, -2.62), Vector3(-3.62, 1.72, -2.18), Vector3(1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	mb.box("wood", Vector3(-3.32, 0.36, -3.5), Vector3(-2.92, 0.46, -2.9), 0.7, 0.0)
	mb.box("metal_dark", Vector3(-3.26, 0.0, -3.44), Vector3(-3.2, 0.36, -3.38), 0.7, 0.0)
	mb.box("metal_dark", Vector3(-3.04, 0.0, -3.02), Vector3(-2.98, 0.36, -2.96), 0.7, 0.0)
	# 人行道树（花钵行道树缩小版，d=1.8 冠顶仍在可见楔内）+ 青色邮筒
	mb.box("wood", Vector3(-2.05, 0.0, 1.35), Vector3(-1.45, 0.32, 1.95), 0.7, 18.0)
	mb.cylinder("wood", Vector3(-1.75, 0.3, 1.65), 0.08, 1.2, 6, 0.7, 16.0)
	mb.bulb("plant_green", Vector3(-1.75, 1.75, 1.65), 0.5)
	mb.bulb("plant_green", Vector3(-1.45, 1.42, 1.45), 0.3)
	mb.box("metal_teal", Vector3(-2.75, 0.0, -1.1), Vector3(-2.45, 1.05, -0.8), 0.7, 0.0)
	mb.box("metal_dark", Vector3(-2.73, 1.05, -1.08), Vector3(-2.47, 1.13, -0.82), 0.7, 0.0)
	# 路缘斑马线（跨街方向条纹，楔形下部可读）
	for sz in [-1.5, -0.9, -0.3, 0.3]:
		_flat_bd(mb, "marking", Vector3(-4.9, 0.012, sz), 1.3, 0.4)
	# 东侧对面山墙（储物间东窗/二层东窗外）
	mb.box("wall_brick", Vector3(15.0, 0.0, -8.0), Vector3(15.8, 7.0, 4.0), 1.0 / 3.0, 0.0, 55)
	mb.box("wall_panel", Vector3(14.2, 0.0, -8.0), Vector3(15.0, 5.0, -2.0), 1.0 / 3.0, 0.0, 55)


# ============================ 门扇（挂枢轴的独立网格） ============================

func _door_leaf(mb: GL.MeshBuilder) -> void:
	## 局部坐标：铰链在原点，门扇向 +Z 延伸 0.9；开门绕 +Y 旋转 +100° 向店内开。
	mb.box("door_dark", Vector3(-0.035, 0.0, 0.0), Vector3(0.035, 2.1, 0.9), 0.55, 26.0)
	mb.box("metal_dark", Vector3(-0.04, 0.0, -0.02), Vector3(0.04, 0.12, 0.92), 0.7, 22.0)
	mb.quad("glass_interior", Vector3(0.036, 1.45, 0.2), Vector3(0.036, 1.45, 0.7),
		Vector3(0.036, 1.95, 0.7), Vector3(0.036, 1.95, 0.2), Vector3(1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	mb.quad("glass_interior", Vector3(-0.036, 1.45, 0.7), Vector3(-0.036, 1.45, 0.2),
		Vector3(-0.036, 1.95, 0.2), Vector3(-0.036, 1.95, 0.7), Vector3(-1, 0, 0),
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Vector2())
	mb.box("metal_teal", Vector3(-0.09, 1.0, 0.78), Vector3(-0.045, 1.06, 0.86), 0.7, 16.0)   # 把手


# ============================ 合同数据（定义/行走面/禁入/锚点/门户） ============================

func _build_contract_data() -> void:
	# 行走面：一层地面 + 16 级踏步 + 二层主板 + 楼梯口落脚条 + 储物间
	walk_surfaces.append(AABB(Vector3(0.4, 0.0, IN_N), Vector3(IN_E - 0.4, 0.001, IN_S - IN_N)))
	for i in STAIR_N:
		var x0 := STAIR_X0 + i * STAIR_TREAD
		walk_surfaces.append(AABB(Vector3(x0, 0.0, STAIR_Z0), Vector3(STAIR_TREAD, (i + 1) * STAIR_RISE, STAIR_Z1 - STAIR_Z0)))
	var land_x0 := STAIR_X0 + STAIR_N * STAIR_TREAD
	walk_surfaces.append(AABB(Vector3(land_x0, FLOOR_2, STAIR_Z0), Vector3(IN_E - land_x0, 0.001, STAIR_Z1 - STAIR_Z0)))
	walk_surfaces.append(AABB(Vector3(SLAB_X, FLOOR_2, STAIR_Z1), Vector3(IN_E - SLAB_X, 0.001, 6.12 - STAIR_Z1)))
	walk_surfaces.append(AABB(Vector3(STORE_X0, 0.0, IN_N), Vector3(STORE_X1 - STORE_X0, 0.001, STORE_Z1 - IN_N)))

	# 禁入体积：外墙 + 家具 + 栏杆/隔断（chapter1-2 §3.8）
	var wall_ex := [
		AABB(Vector3(-0.3, 0, -6.3), Vector3(0.65, ROOF, 6.6)),            # 前墙整面（门洞含）
		AABB(Vector3(-0.1, 0, -6.3), Vector3(14.3, ROOF, 0.4)),            # 北墙
		AABB(Vector3(-0.1, 0, 5.85), Vector3(14.3, ROOF, 0.45)),           # 南墙
		AABB(Vector3(9.85, 0, -6.12), Vector3(0.3, ROOF, 1.92)),       # 东墙 a（门洞西段）
		AABB(Vector3(9.85, 2.3, -4.2), Vector3(0.3, ROOF - 2.3, 1.8)), # 东墙门楣
		AABB(Vector3(9.85, 0, -2.4), Vector3(0.3, ROOF, 8.52)),        # 东墙 b（门洞东段+南段）
		AABB(Vector3(13.85, 0, -6.3), Vector3(0.35, 3.2, 7.5)),            # 储物间东墙
		AABB(Vector3(10.0, 0, 0.85), Vector3(4.2, 3.2, 0.4)),              # 储物间南墙
		AABB(Vector3(3.28, FLOOR_2, STAIR_Z1), Vector3(0.24, 1.25, 5.9 - STAIR_Z1)),   # 画廊栏杆
	]
	exclusions.append_array(wall_ex)
	var furn := [
		# 一层
		AABB(Vector3(0.55, 0, 2.8), Vector3(3.9, 1.35, 2.05)),    # 柜台 L + 台面
		AABB(Vector3(0.24, 0, 2.9), Vector3(0.6, 0.55, 1.6)),      # 等候凳
		AABB(Vector3(4.45, 0, 4.9), Vector3(1.1, 2.0, 1.05)),      # 售货机
		AABB(Vector3(1.5, 0, 5.2), Vector3(0.7, 1.6, 0.6)),        # 公告牌
		AABB(Vector3(0.5, 0, -5.95), Vector3(3.0, 2.85, 0.95)),    # 工作台+工具墙
		AABB(Vector3(0.28, 0, -5.0), Vector3(0.95, 1.15, 0.9)),    # 抽屉柜
		AABB(Vector3(3.6, 0, -4.6), Vector3(0.85, 0.95, 0.8)),     # 工具车
		AABB(Vector3(0.6, 0, -5.7), Vector3(0.85, 1.1, 0.85)),     # 轮胎堆
		AABB(Vector3(1.7, 0, -4.15), Vector3(1.0, 0.65, 0.85)),    # 托盘机箱
		AABB(Vector3(4.85, 0, -2.0), Vector3(1.55, 1.35, 0.85)),   # 摩托
		AABB(Vector3(4.4, 0, -2.95), Vector3(0.6, 1.5, 0.6)),      # 工作灯
		AABB(Vector3(5.7, 0, 5.2), Vector3(4.9, 2.5, 0.8)),        # 货架两组
		AABB(Vector3(8.85, 0, 4.85), Vector3(1.35, 0.95, 0.7)),    # 油桶
		AABB(Vector3(0.85, 0, -1.4), Vector3(1.35, 0.55, 1.45)),   # 中庭地毯+椅
		AABB(Vector3(0.3, 0, 4.9), Vector3(0.75, 0.7, 1.1)),       # 盆栽1
		AABB(Vector3(9.2, 0, -5.2), Vector3(0.75, 0.7, 0.8)),      # 盆栽2
		# 储物间
		AABB(Vector3(10.3, 0, -5.95), Vector3(3.4, 2.35, 0.85)),   # 储物货架
		AABB(Vector3(12.9, 0, -0.2), Vector3(0.85, 1.8, 0.9)),     # 热水器
		AABB(Vector3(10.4, 0, -0.35), Vector3(1.15, 1.45, 1.1)),   # 电池组
		AABB(Vector3(12.5, 0, -1.5), Vector3(1.1, 0.7, 1.15)),     # 纸箱
		# 二层
		AABB(Vector3(3.4, FLOOR_2, -4.82), Vector3(5.0, 1.3, 1.0)),   # 厨房台面+冰箱
		AABB(Vector3(4.6, FLOOR_2, -2.55), Vector3(1.25, 0.8, 1.15)), # 餐桌
		AABB(Vector3(8.5, FLOOR_2, -2.1), Vector3(1.45, 0.6, 3.05)),  # 床
		AABB(Vector3(8.25, FLOOR_2, -2.1), Vector3(0.35, 1.3, 3.05)), # 隔断
		AABB(Vector3(9.25, FLOOR_2, 0.85), Vector3(0.7, 0.6, 0.75)),  # 床头柜
		AABB(Vector3(9.42, FLOOR_2, 1.9), Vector3(0.55, 2.05, 2.7)),  # 书架
		AABB(Vector3(4.8, FLOOR_2, 4.5), Vector3(2.2, 1.25, 1.45)),   # 沙发
		AABB(Vector3(5.4, FLOOR_2, 3.5), Vector3(1.0, 0.65, 0.95)),   # 圆几
		AABB(Vector3(3.8, FLOOR_2, 4.85), Vector3(0.65, 1.75, 0.7)),  # 落地灯
		AABB(Vector3(3.5, FLOOR_2, 0.9), Vector3(1.1, 1.35, 1.6)),    # 终端桌+椅
		AABB(Vector3(3.42, FLOOR_2, -4.4), Vector3(0.6, 1.9, 1.0)),   # 衣架
		AABB(Vector3(6.9, FLOOR_2, 5.2), Vector3(1.05, 0.65, 0.75)),  # 纸箱
	]
	exclusions.append_array(furn)

	# 固定机位（chapter1-2 §3.7；y = 行走面 + 1.62）
	anchors["entry_view"] = {"pos": [1.7, 1.62, 1.8], "look": [6.0, 1.45, -1.0]}
	anchors["workbench_view"] = {"pos": [2.7, 1.62, -3.3], "look": [1.4, 1.35, -5.5]}
	# v7 终验复盘：中距(x7.6)看不见一层中庭——楼板沿口对一层地面是位置性遮挡
	# （x>3.8 站位恒不可见），而文档构图职责"俯瞰中庭与一层橱窗街景"要求贴近栏杆。
	# v8 解法（投影几何全推）：站栏杆正后方 0.2m（x3.6，两柱正中 z-0.93）正西俯 40°：
	# 立柱方位角 ≥67° 出画、扶手/中横杆俯角 ≥73.7° 在画框底(70°)外、楼板沿口 84°
	# 出画、檐板下阴影带(≥73°)切出画外；画框 10°..70° 三层：上部 2F 墙+店招(正对，
	# 约 19% 高度)、中部 1F 橱窗暮色街景带、下部中庭地毯+等候椅。
	# 店招上移 3.20..3.70 避开檐板投射阴影(原被遮下 27%)。
	anchors["gallery_view"] = {"pos": [3.6, FLOOR_2 + 1.62, -0.93], "look": [0.7, 2.34, -0.93]}
	# Flash 验收 1.2 修复：原机位距餐桌仅 0.9m 且俯角 3.7°，桌子被挤出画幅底部；
	# 退到东南 2.7m、视线落在桌面高度(4.35)朝窗——餐桌居中、二层大窗+暮色作背景。
	anchors["dining_view"] = {"pos": [7.8, FLOOR_2 + 1.62, -1.4], "look": [1.2, 4.35, -2.2]}

	# 门户：门内侧返回街道（chapter1-2 §3.10）
	portals.append({
		"pos": [0.95, 1.6, 1.7],
		"radius": 1.6,
		"target_map_id": "m01_afterglow",
		"target_anchor": "repair_shop_door",
		"label": "返回街道",
	})
	door_spec = {"pivot": [0.07, 0.0, DOOR_Z0], "swing_deg": 100.0, "swing_axis": "y"}

	# 环境动画（≤6）：吊扇 ×2（装于 2F 板下）
	fans.append({"pos": [5.2, 2.86, 0.6]})
	fans.append({"pos": [7.4, 2.86, -2.2]})


# ============================ 辅助 ============================

func _load_materials() -> void:
	var keys := [
		"concrete_plain", "wall_warm", "wall_brick", "wall_panel", "wood", "metal_dark",
		"metal_teal", "metal_orange", "door_dark", "rubber", "marking", "poster",
		"bulb_warm", "lamp_lens", "lit_warm", "lit_cool", "glass_dark", "roof",
		"pavement", "asphalt", "asphalt_wet", "sign_repair",
	]
	for k in keys:
		var path := "%s/%s.tres" % [MAT_DIR, k]
		if ResourceLoader.exists(path):
			mats[k] = load(path)
		else:
			push_warning("interior: 共享材质缺失 %s" % path)
	# 室内专属材质（内联，不进共享库）
	var wood_floor := StandardMaterial3D.new()
	wood_floor.albedo_color = Color(0.52, 0.38, 0.26)
	wood_floor.roughness = 0.72
	mats["wood_floor"] = wood_floor
	var rug := StandardMaterial3D.new()
	rug.albedo_color = Color(0.66, 0.36, 0.30)
	rug.roughness = 0.97
	mats["rug"] = rug
	# 门外光池（Backdrop 不烘焙、无实时光——路灯落地池必须自发光才可见）
	# v5 终验复盘：单层大光池被读作“平坦米色梯形”；改外池+更亮内芯两层伪衰减。
	var pool := StandardMaterial3D.new()
	pool.albedo_color = Color(0.55, 0.47, 0.36)
	pool.emission_enabled = true
	pool.emission = Color(1.0, 0.72, 0.42)
	pool.emission_energy_multiplier = 0.55
	pool.roughness = 0.42
	mats["pool_glow"] = pool
	var pool_core := StandardMaterial3D.new()
	pool_core.albedo_color = Color(0.62, 0.54, 0.42)
	pool_core.emission_enabled = true
	pool_core.emission = Color(1.0, 0.8, 0.52)
	pool_core.emission_energy_multiplier = 0.95
	pool_core.roughness = 0.36
	mats["pool_core"] = pool_core
	var sofa := StandardMaterial3D.new()
	sofa.albedo_color = Color(0.36, 0.44, 0.50)
	sofa.roughness = 0.95
	mats["sofa_fabric"] = sofa
	var bed := StandardMaterial3D.new()
	bed.albedo_color = Color(0.86, 0.66, 0.47)
	bed.roughness = 0.95
	mats["bed_sheet"] = bed
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.84, 0.80, 0.72)
	cloth.roughness = 0.95
	mats["cloth"] = cloth
	# _plant/行道树叶冠用（修复既有缺陷：原引用未定义键，盆栽面一直无材质）
	var plant := StandardMaterial3D.new()
	plant.albedo_color = Color(0.33, 0.46, 0.30)
	plant.roughness = 0.95
	mats["plant_green"] = plant
	var term := StandardMaterial3D.new()
	term.albedo_color = Color(0.06, 0.10, 0.12)
	term.emission_enabled = true
	term.emission = Color(0.30, 0.92, 0.86)
	term.emission_energy_multiplier = 1.6
	mats["terminal_screen"] = term
	var vending := StandardMaterial3D.new()
	vending.albedo_color = Color(0.10, 0.18, 0.20)
	vending.emission_enabled = true
	vending.emission = Color(0.35, 0.85, 0.80)
	vending.emission_energy_multiplier = 1.4
	mats["vending_panel"] = vending
	# 透明玻璃（不烘焙）；暮色微光——Flash 验收指出窗面近纯黑(1.2 修复：窗外无天光+暗街)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.62, 0.73, 0.82, 0.32)
	glass.roughness = 0.14
	glass.metallic = 0.1
	glass.emission_enabled = true
	glass.emission = Color(0.30, 0.38, 0.55)
	glass.emission_energy_multiplier = 0.5
	mats["glass_interior"] = glass


func _omni(pos: Vector3, color: Color, energy: float, range_m: float) -> Dictionary:
	return {"pos": pos, "color": color, "energy": energy, "range": range_m}


func _plant(mb: GL.MeshBuilder, base: Vector3, radius: float) -> void:
	mb.cylinder("wood", base, radius * 0.14, 0.3, 6, 0.8, 16.0)
	mb.bulb("plant_green", base + Vector3(0, 0.44, 0), radius * 0.5)
	mb.bulb("plant_green", base + Vector3(radius * 0.3, 0.6, -radius * 0.15), radius * 0.34)
	mb.bulb("plant_green", base + Vector3(-radius * 0.26, 0.55, radius * 0.2), radius * 0.3)


func _flat(mb: GL.MeshBuilder, key: String, center: Vector3, w: float, h: float) -> void:
	var uv2sz := Vector2(maxf(w, 0.1) * 26.0 / GL.ATLAS_PX, maxf(h, 0.1) * 26.0 / GL.ATLAS_PX)
	mb.quad(key, center + Vector3(-w / 2, 0, h / 2), center + Vector3(w / 2, 0, h / 2),
		center + Vector3(w / 2, 0, -h / 2), center + Vector3(-w / 2, 0, -h / 2), Vector3.UP,
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], uv2sz)


func _flat_upper(mb: GL.MeshBuilder, key: String, center: Vector3, w: float, h: float) -> void:
	_flat(mb, key, center, w, h)


func _flat_bd(mb: GL.MeshBuilder, key: String, center: Vector3, w: float, h: float) -> void:
	## Backdrop 专用：不烘焙（uv2=0）
	mb.quad(key, center + Vector3(-w / 2, 0, h / 2), center + Vector3(w / 2, 0, h / 2),
		center + Vector3(w / 2, 0, -h / 2), center + Vector3(-w / 2, 0, -h / 2), Vector3.UP,
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2())


func _save_spec() -> void:
	var excl: Array = []
	for b in exclusions:
		excl.append([b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	var walks: Array = []
	for b in walk_surfaces:
		walks.append([b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	var spec := {
		"schema_version": 1,
		"map_id": "m01_repair_interior",
		"display_name": "余晖维修·店内",
		"generated_scene": GEN_SCENE,
		"anchors": anchors,
		"default_anchor": "entry_view",
		"exclusions": excl,
		"camera_mode": "walk",
		"walk_surfaces": walks,
		"portals": portals,
		"door": door_spec,
		"bounds": [0.45, 1.5, -5.6, 13.15, 4.5, 11.2],
		"fans": fans,
		"flickers": flickers,
		"particles": [],
		"lighting_profile_id": "m01_interior_dusk_v12",
		"content_revision": "1.2.0",
		"requires_baked_lighting": true,
	}
	var f := FileAccess.open(GEN_SPEC, FileAccess.WRITE)
	if f == null:
		push_error("interior spec 写入失败")
		return
	f.store_string(JSON.stringify(spec, "  "))
	f.close()
	print("interior spec saved: anchors=", anchors.size(), " exclusions=", excl.size(),
		" walk_surfaces=", walks.size(), " portals=", portals.size())


func _set_all_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child != root:
			child.owner = root
		_set_all_owners(child, root)
