## M01「余晖街区」离线生成（制作阶段工具）—— chapter1-1 §6.1 生成层。
## 运行前置：纹理与招牌 PNG 已生成并导入（--headless --import）。
## 运行：godot --headless --path . --script res://tools/build_m01.gd
## 输出：maps/m01_afterglow/generated/map_generated.tscn（StaticGeometry/Props/Lighting）
##       + meshes/ + generated_spec.json（exclusions/灯位/环境件位置，供 assemble_m01 组装）
## 注意：本脚本不写 map.tscn / MapDefinition / 锚点 / Environment——那些由 tools/assemble_m01.gd 组合。
extends SceneTree

const GL := preload("res://tools/gen_lib.gd")
const MAP_DEF_SCRIPT := preload("res://scripts/maps/map_definition.gd")
const TEX := "res://assets/m01_afterglow/textures"
const MAT_DIR := "res://assets/m01_afterglow/materials"
const MESH_DIR := "res://maps/m01_afterglow/meshes"
const GENERATED_DIR := "res://maps/m01_afterglow/generated"
const GENERATED_SCENE := "res://maps/m01_afterglow/generated/map_generated.tscn"
const SPEC_PATH := "res://maps/m01_afterglow/generated/generated_spec.json"
const FIXTURE_SCENE := "res://tests/fixtures/mini_test_map.tscn"
const FIXTURE_DEF := "res://tests/fixtures/mini_test_map_definition.tres"

var mats := {}
var lights_spec: Array = []
var exclusions: Array[AABB] = []
var _rng := RandomNumberGenerator.new()

const KEYS := {
	"frame": "metal_dark", "glass": "glass_dark", "lit_warm": "lit_warm", "lit_cool": "lit_cool",
	"sill": "concrete_plain", "concrete": "concrete_plain", "metal": "metal_dark",
	"wood": "wood", "lamp": "metal_teal", "lens": "lamp_lens", "roof": "roof",
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_rng.seed = 730001
	DirAccess.make_dir_recursive_absolute(MAT_DIR)
	DirAccess.make_dir_recursive_absolute(MESH_DIR)
	DirAccess.make_dir_recursive_absolute(GENERATED_DIR)
	DirAccess.make_dir_recursive_absolute("res://maps/m01_afterglow/baked")
	_mk_materials()

	var root := _build_generated_root()
	_build_static_geometry(root)
	_build_props(root)
	_build_lighting(root)
	_build_backdrop_mesh()

	var err := ResourceSaver.save(_pack(root), GENERATED_SCENE)
	print("generated scene saved: ", err, " -> ", GENERATED_SCENE)
	_save_spec()
	_build_fixture()
	print("BUILD_DONE tris_est=", _total_tris)
	quit(0)


var _total_tris := 0


func _pack(root: Node) -> PackedScene:
	_set_all_owners(root, root)
	var ps := PackedScene.new()
	var result := ps.pack(root)
	if result != OK:
		push_error("pack 失败: %d" % result)
	return ps


func _set_all_owners(node: Node, root: Node) -> void:
	## 保存场景需要每个后代 owner 指向根。
	for child in node.get_children():
		if child != root:
			child.owner = root
			_set_all_owners(child, root)


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)


# ============================ 材质 ============================

func _mk_materials() -> void:
	mats["wall_bluegray"] = _tex_mat("wall_bluegray", 0.95)
	mats["wall_warm"] = _tex_mat("wall_warm", 0.93)
	mats["wall_panel"] = _tex_mat("wall_panel", 0.85)
	mats["wall_brick"] = _tex_mat("wall_brick", 0.95)
	mats["concrete_plain"] = _flat(Color(0.62, 0.59, 0.53), 1.0)
	mats["metal_dark"] = _flat(Color(0.22, 0.24, 0.27), 0.45, 0.75)
	mats["metal_teal"] = _flat(Color(0.3, 0.62, 0.6), 0.5, 0.3)
	mats["metal_orange"] = _flat(Color(0.82, 0.43, 0.33), 0.55, 0.3)
	mats["glass_dark"] = _flat(Color(0.15, 0.19, 0.25), 0.15, 0.15)
	mats["lit_warm"] = _emis(Color(0.98, 0.74, 0.45), Color(1.0, 0.74, 0.42), 2.2, 0.35)
	mats["lit_cool"] = _emis(Color(0.72, 0.81, 0.92), Color(0.68, 0.78, 0.9), 1.05, 0.3)
	mats["glass_shop"] = _emis(Color(0.5, 0.4, 0.28), Color(1.0, 0.75, 0.45), 0.55, 0.25)
	mats["interior_back"] = _tex_emis("interior_shelf", 0.9, 0.6)
	mats["asphalt"] = _tex_mat("asphalt", 0.96)
	mats["asphalt_patch"] = _tex_mat_dark("asphalt", 0.92, 0.0, Color(0.42, 0.44, 0.5), 0.0)
	mats["asphalt_wet"] = _tex_mat_dark("asphalt", 0.3, 0.22, Color(0.6, 0.64, 0.72), 0.3)
	mats["pavement"] = _tex_mat("pavement", 0.95)
	mats["plaza"] = _tex_mat("plaza_paving", 0.9)
	mats["alley"] = _tex_mat("alley_ground", 0.85)
	mats["roof"] = _tex_mat("roof_gravel", 1.0)
	mats["wood"] = _flat(Color(0.42, 0.29, 0.19), 0.8)
	mats["rubber"] = _flat(Color(0.09, 0.09, 0.1), 0.9)
	mats["marking"] = _flat(Color(0.72, 0.71, 0.66), 0.9)
	mats["steel_station"] = _flat(Color(0.4, 0.48, 0.54), 0.5, 0.55)
	mats["bulb_warm"] = _emis(Color(1.0, 0.78, 0.5), Color(1.0, 0.75, 0.45), 1.2, 0.5)
	(mats["bulb_warm"] as StandardMaterial3D).cull_disabled = true
	mats["wire"] = _flat(Color(0.09, 0.09, 0.1), 0.85)
	mats["ground_far"] = _tex_mat_dark("asphalt", 1.0, 0.0, Color(0.55, 0.6, 0.7), 0.0)
	mats["backdrop1"] = _tex_emis("backdrop_facade", 0.9, 0.4, Color(0.72, 0.8, 0.92))
	mats["backdrop2"] = _tex_emis("backdrop_facade", 0.9, 0.3, Color(0.85, 0.8, 0.9))
	mats["backdrop3"] = _tex_emis("backdrop_facade", 0.9, 0.55, Color(0.6, 0.7, 0.82))
	mats["poster"] = _tex_mat("poster", 0.9)
	mats["door_dark"] = _flat(Color(0.12, 0.13, 0.15), 0.6)
	mats["lamp_lens"] = _emis(Color(1.0, 0.82, 0.6), Color(1.0, 0.79, 0.55), 2.2, 0.5)
	(mats["lamp_lens"] as StandardMaterial3D).cull_disabled = true
	mats["sign_repair"] = _sign("signs/repair_main", 4.2)
	mats["sign_station"] = _sign("signs/station_main", 3.2)
	mats["sign_convenience"] = _sign("signs/convenience", 2.8)
	mats["sign_cafe"] = _sign("signs/cafe", 2.4)
	mats["sign_noodle"] = _sign("signs/noodle", 2.4)
	mats["sign_pharmacy"] = _sign("signs/pharmacy", 2.4)
	mats["sign_electronics"] = _sign("signs/electronics", 2.4)
	mats["sign_hotel_v"] = _sign("signs/hotel_v", 2.2)
	mats["sign_soda"] = _sign("signs/soda", 2.2)
	mats["sign_bar_v"] = _sign("signs/bar_v", 2.6)
	for k in mats:
		ResourceSaver.save(mats[k], "%s/%s.tres" % [MAT_DIR, k])


func _tex_mat(name: String, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("%s/%s.png" % [TEX, name])
	m.roughness = rough
	return m


func _tex_mat_dark(name: String, rough: float, metallic: float, tint: Color, _unused: float = 0.0) -> StandardMaterial3D:
	var m := _tex_mat(name, rough)
	m.albedo_color = tint
	m.metallic = metallic
	return m


func _flat(color: Color, rough: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


func _emis(albedo: Color, emission: Color, energy: float, rough: float) -> StandardMaterial3D:
	var m := _flat(albedo, rough)
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m


func _tex_emis(name: String, rough: float, energy: float, tint: Color = Color(1, 1, 1)) -> StandardMaterial3D:
	var m := _tex_mat(name, rough)
	m.albedo_color = tint
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = energy
	return m


func _sign(rel: String, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("%s/%s.png" % [TEX, rel])
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = energy
	return m


# ============================ 场景结构 ============================

func _node3d(name: String, parent: Node) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	return n


func _build_generated_root() -> Node3D:
	## 生成层根：只含参与烘焙的静态内容与灯光；不挂 MapRoot/环境/锚点。
	var root := Node3D.new()
	root.name = "M01Generated"
	return root


func _build_static_geometry(root: Node3D) -> void:
	# 普通容器：真正的 LightmapGI 由 assemble_m01 挂在 map.tscn 根部，
	# 生成层内部不得再嵌 LightmapGI（嵌套会劫持子树网格的光照采样）。
	var lm := Node3D.new()
	lm.name = "BakedWorld"
	root.add_child(lm)
	var sg := _node3d("StaticGeometry", lm)
	var mb := GL.MeshBuilder.new()

	_ground_and_street(mb)
	for spec in _building_specs():
		_building(mb, spec)
	_repair_shop(mb)
	_station(mb)

	var mesh := mb.commit(mats, "%s/baked_static.res" % MESH_DIR, Vector2i(2048, 2048))
	_total_tris += mb.tri_count()
	print("static: tris=", mb.tri_count(), " surf=", mesh.get_surface_count(), " uv2_used=%.3f uv2_max_y=%.3f overflow=%d" % [mb.packer.utilization(), mb.packer.max_y(), mb.packer.overflow_count])
	if mb.packer.overflow_count > 0:
		print("overflow sizes (w×h in 1/1000 UV): ", mb.packer.overflow_report())
	var mi := MeshInstance3D.new()
	mi.name = "BakedStatic"
	mi.mesh = mesh
	sg.add_child(mi)
	_add_occluders(sg)
	_own(sg, root)
	exclusions.append_array(_exclusion_list())


func _build_props(root: Node3D) -> void:
	var lm := root.get_node("BakedWorld")
	var props := _node3d("Props", lm)
	var mb := GL.MeshBuilder.new()
	_street_furniture(mb)
	_alley_props(mb)
	_plaza_props(mb)
	_station_area_props(mb)
	var mesh := mb.commit(mats, "%s/baked_props.res" % MESH_DIR, Vector2i(512, 512))
	_total_tris += mb.tri_count()
	print("props: tris=", mb.tri_count(), " surf=", mesh.get_surface_count())
	var mi := MeshInstance3D.new()
	mi.name = "BakedProps"
	mi.mesh = mesh
	mi.add_to_group("detail_props")
	mi.set_meta("node_groups", PackedStringArray(["detail_props"]))
	props.add_child(mi)
	_own(props, root)


# ============================ 地面与街道 ============================

func _ground_and_street(mb: GL.MeshBuilder) -> void:
	# 主街（含桥下延伸到 z=-66）
	mb.box("asphalt", Vector3(-6, 0, -66), Vector3(6, 0.02, 60), 1.0 / 7.0, 22.0, 4)
	# 两侧人行道 + 路缘
	mb.box("pavement", Vector3(-11, 0, -60), Vector3(-6.3, 0.15, 60), 1.0 / 2.4, 20.0)
	mb.box("pavement", Vector3(6.3, 0, -60), Vector3(11, 0.15, 60), 1.0 / 2.4, 20.0)
	mb.box("concrete_plain", Vector3(-6.3, 0.02, -60), Vector3(-6.0, 0.17, 60), 0.5, 20.0)
	mb.box("concrete_plain", Vector3(6.0, 0.02, -60), Vector3(6.3, 0.17, 60), 0.5, 20.0)
	# 站前小广场
	mb.box("pavement", Vector3(-12, 0, -60), Vector3(12, 0.15, -51), 1.0 / 2.4, 20.0)
	# 修理铺前广场
	mb.box("plaza", Vector3(12, 0.15, 15), Vector3(33, 0.17, 38), 1.0 / 9.6, 22.0)
	mb.box("pavement", Vector3(11, 0, 15), Vector3(12, 0.16, 38), 1.0 / 2.4, 20.0)
	# 侧巷地面（略低）
	mb.box("alley", Vector3(-45, 0, -6), Vector3(-12, 0.1, 6), 1.0 / 4.0, 20.0)
	# 雨后湿区
	_wet_patch(mb, Vector3(-2.5, 0.035, -20), 3.6, 6.5)
	_wet_patch(mb, Vector3(2.8, 0.035, 9), 2.6, 4.2)
	_wet_patch(mb, Vector3(-26, 0.115, -1), 3.0, 2.0)
	# 道路修补（沥青补丁 + 接缝，1.1 精修）
	for rp in [{"c": Vector3(-1.8, 0.03, 8.0), "w": 3.4, "h": 5.5}, {"c": Vector3(2.2, 0.03, -33.0), "w": 4.2, "h": 6.0}, {"c": Vector3(-2.0, 0.03, 38.0), "w": 3.0, "h": 4.0}]:
		var r: Dictionary = rp
		var c: Vector3 = r["c"]
		var rw: float = r["w"]
		var rh: float = r["h"]
		var patch_uv := Vector2(rw * 16.0 / GL.ATLAS_PX, rh * 16.0 / GL.ATLAS_PX)
		mb.quad("asphalt_patch", c + Vector3(-rw / 2, 0, rh / 2), c + Vector3(rw / 2, 0, rh / 2), c + Vector3(rw / 2, 0, -rh / 2), c + Vector3(-rw / 2, 0, -rh / 2), Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], patch_uv)
		# 接缝线（两侧）
		mb.box("marking", Vector3(c.x - rw / 2 - 0.06, 0.045, c.z - rh / 2), Vector3(c.x - rw / 2 + 0.06, 0.055, c.z + rh / 2), 0.8, 16.0)
		mb.box("marking", Vector3(c.x + rw / 2 - 0.06, 0.045, c.z - rh / 2), Vector3(c.x + rw / 2 + 0.06, 0.055, c.z + rh / 2), 0.8, 16.0)
	# 标线
	_markings(mb)
	# 井盖
	for p in [Vector2(1.5, -12), Vector2(-3.5, 22), Vector2(2.5, -44)]:
		mb.cylinder("metal_dark", Vector3(p.x, 0.02, p.y), 0.42, 0.025, 10, 0.8, 18.0)
	# 排水沟篦子（路缘边）
	for z in [-38.0, -6.0, 26.0]:
		mb.box("metal_dark", Vector3(5.55, 0.02, z - 0.5), Vector3(5.95, 0.08, z + 0.5), 0.8, 18.0)
		mb.box("metal_dark", Vector3(-5.95, 0.02, z - 0.5), Vector3(-5.55, 0.08, z + 0.5), 0.8, 18.0)


func _wet_patch(mb: GL.MeshBuilder, center: Vector3, w: float, h: float) -> void:
	var uv2sz := Vector2(w * 20.0 / GL.ATLAS_PX, h * 20.0 / GL.ATLAS_PX)
	mb.quad("asphalt_wet", center + Vector3(-w / 2, 0, h / 2), center + Vector3(w / 2, 0, h / 2), center + Vector3(w / 2, 0, -h / 2), center + Vector3(-w / 2, 0, -h / 2), Vector3.UP, [Vector2(0, 0), Vector2(w / 12.0, 0), Vector2(w / 12.0, h / 12.0), Vector2(0, h / 12.0)], uv2sz)


func _markings(mb: GL.MeshBuilder) -> void:
	# 中心虚线
	var z := -56.0
	while z < 56.0:
		_flat_quad(mb, "marking", Vector3(-0.09, 0.055, z), 0.18, 3.0)
		z += 6.0
	# 边线
	_flat_quad(mb, "marking", Vector3(-5.45, 0.055, 0), 0.12, 114.0)
	_flat_quad(mb, "marking", Vector3(5.45, 0.055, 0), 0.12, 114.0)
	# 人行横道（广场口与站前）
	for cz in [14.0, -53.0]:
		var x := -4.6
		while x < 4.6:
			_flat_quad(mb, "marking", Vector3(x, 0.055, cz), 0.62, 3.4)
			x += 1.4
	# 站前停止线
	_flat_quad(mb, "marking", Vector3(0, 0.055, -50.6), 10.6, 0.35)


func _flat_quad(mb: GL.MeshBuilder, key: String, center: Vector3, w: float, h: float) -> void:
	var uv2sz := Vector2(maxf(w, 0.1) * 16.0 / GL.ATLAS_PX, maxf(h, 0.1) * 16.0 / GL.ATLAS_PX)
	mb.quad(key, center + Vector3(-w / 2, 0, h / 2), center + Vector3(w / 2, 0, h / 2), center + Vector3(w / 2, 0, -h / 2), center + Vector3(-w / 2, 0, -h / 2), Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], uv2sz)


# ============================ 建筑 ============================

func _building_specs() -> Array[Dictionary]:
	return [
		# 西侧楼群（front +x，临街面 x=-12）
		{"id": "W1", "x0": -30, "z0": 40, "x1": -12, "z1": 57, "h": 15, "wall": "wall_bluegray", "pattern": "grid", "floor_h": 3.0, "bay": 3.1, "win_w": 1.35, "win_h": 1.6, "front": "+x", "balcony": [1, 3], "seed": 1101, "shop": {"a0": 44, "a1": 52, "mat": "sign_soda", "awning": true, "depth": 3.0}},
		{"id": "W2", "x0": -26, "z0": 22, "x1": -12, "z1": 39, "h": 11.5, "wall": "wall_warm", "pattern": "grid", "floor_h": 3.1, "bay": 3.2, "win_w": 1.5, "win_h": 1.7, "front": "+x", "seed": 1102, "shop": {"a0": 24, "a1": 36, "mat": "sign_convenience", "awning": true, "depth": 3.5}},
		{"id": "W3", "x0": -34, "z0": 6, "x1": -12, "z1": 20, "h": 18, "wall": "wall_panel", "pattern": "grid", "floor_h": 3.0, "bay": 3.4, "win_w": 1.6, "win_h": 1.7, "front": "+x", "seed": 1103, "tall": true, "shop": {"a0": 9, "a1": 15, "mat": "sign_cafe", "awning": true, "depth": 3.0}},
		# 侧巷 z -6..6
		{"id": "W5", "x0": -24, "z0": -22, "x1": -12, "z1": -6, "h": 9.5, "wall": "wall_brick", "pattern": "grid", "floor_h": 3.1, "bay": 2.8, "win_w": 1.25, "win_h": 1.55, "front": "+x", "seed": 1105, "shop": {"a0": -20.5, "a1": -14.5, "mat": "sign_noodle", "awning": true, "depth": 2.8}, "shop2": {"a0": -13.5, "a1": -7.5, "mat": "sign_electronics", "awning": false, "depth": 2.6}},
		{"id": "W6", "x0": -38, "z0": -40, "x1": -12, "z1": -24, "h": 24, "wall": "wall_bluegray", "pattern": "grid", "floor_h": 3.0, "bay": 3.3, "win_w": 1.4, "win_h": 1.6, "front": "+x", "seed": 1106, "tall": true, "tank": true},
		{"id": "W7", "x0": -28, "z0": -54, "x1": -12, "z1": -40, "h": 13, "wall": "wall_warm", "pattern": "grid", "floor_h": 3.2, "bay": 3.0, "win_w": 1.4, "win_h": 1.6, "front": "+x", "seed": 1107},
		# 东侧楼群（front -x，临街面 x=12）
		{"id": "E1", "x0": 12, "z0": 42, "x1": 27, "z1": 57, "h": 10, "wall": "wall_warm", "pattern": "grid", "floor_h": 3.2, "bay": 3.0, "win_w": 1.45, "win_h": 1.65, "front": "-x", "seed": 1201, "shop": {"a0": 44, "a1": 54, "mat": "sign_cafe", "awning": true, "depth": 3.2}},
		{"id": "E3", "x0": 12, "z0": 2, "x1": 26, "z1": 13, "h": 14, "wall": "wall_bluegray", "pattern": "grid", "floor_h": 3.0, "bay": 3.1, "win_w": 1.4, "win_h": 1.6, "front": "-x", "balcony": [2], "seed": 1203, "shop": {"a0": 4, "a1": 10, "mat": "sign_soda", "awning": false, "depth": 2.8}},
		{"id": "E4", "x0": 12, "z0": -13, "x1": 30, "z1": 0, "h": 20, "wall": "wall_panel", "pattern": "band", "floor_h": 3.3, "bay": 3.0, "win_w": 1.5, "win_h": 1.5, "front": "-x", "seed": 1204, "tall": true, "trim": true},
		{"id": "E5", "x0": 12, "z0": -28, "x1": 24, "z1": -15, "h": 8.5, "wall": "wall_brick", "pattern": "grid", "floor_h": 3.1, "bay": 2.9, "win_w": 1.3, "win_h": 1.55, "front": "-x", "seed": 1205, "shop": {"a0": -26, "a1": -21, "mat": "sign_pharmacy", "awning": false, "depth": 2.6}, "vsign": {"a": -18, "mat": "sign_hotel_v"}},
		{"id": "E6", "x0": 12, "z0": -46, "x1": 34, "z1": -30, "h": 26, "wall": "wall_bluegray", "pattern": "band", "floor_h": 3.2, "bay": 3.4, "win_w": 1.6, "win_h": 1.5, "front": "-x", "seed": 1206, "tall": true},
		{"id": "E7", "x0": 12, "z0": -56, "x1": 25, "z1": -48, "h": 12, "wall": "wall_warm", "pattern": "grid", "floor_h": 3.0, "bay": 3.0, "win_w": 1.35, "win_h": 1.55, "front": "-x", "seed": 1207},
	]


func _building(mb: GL.MeshBuilder, spec: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var x0: float = spec["x0"]; var x1: float = spec["x1"]
	var z0: float = spec["z0"]; var z1: float = spec["z1"]
	var h: float = spec["h"]
	var wall: String = spec["wall"]
	# 主体（无底面）
	mb.box(wall, Vector3(x0, 0, z0), Vector3(x1, h, z1), 1.0 / 3.0, 26.0, GL.FACE_NO_BOTTOM)
	# 基座
	mb.box("concrete_plain", Vector3(x0 - 0.04, 0, z0 - 0.04), Vector3(x1 + 0.04, 0.55, z1 + 0.04), 0.55, 24.0, GL.FACE_NO_BOTTOM)
	# 楼顶
	GL.roof_kit(mb, x0, z0, x1, z1, h, rng, {"parapet": "concrete_plain", "roof": "roof", "metal": "metal_dark"}, bool(spec.get("tall", false)))
	if spec.get("tank", false):
		mb.cylinder("metal_dark", Vector3((x0 + x1) / 2 + 1.5, h + 0.75, (z0 + z1) / 2), 1.15, 2.0, 12, 0.4, 16.0)
	# 角部装饰条（E4）
	if spec.get("trim", false):
		mb.box("metal_teal", Vector3(x0 - 0.06, 0.55, z0 - 0.06), Vector3(x0 + 0.18, h, z0 + 0.18), 0.8, 22.0)
		mb.box("metal_teal", Vector3(x1 - 0.18, 0.55, z1 - 0.18), Vector3(x1 + 0.06, h, z1 + 0.06), 0.8, 22.0)

	# 店面（临街面）
	var front: String = spec.get("front", "+x")
	var shop: Dictionary = spec.get("shop", {})
	if not shop.is_empty():
		_shopfront(mb, front, spec, shop, rng)
	var shop2: Dictionary = spec.get("shop2", {})
	if not shop2.is_empty():
		_shopfront(mb, front, spec, shop2, rng)
	var vsign: Dictionary = spec.get("vsign", {})
	if not vsign.is_empty():
		_vertical_sign(mb, front, spec, vsign)

	# 窗户：临街面 + 两个侧面
	_windows_for_face(mb, spec, front, true, rng)
	for side in _sides_of(front):
		_windows_for_face(mb, spec, side, false, rng)
	_windows_for_face(mb, spec, _back_of(front), false, rng)

	exclusions.append(AABB(Vector3(x0 - 0.3, 0, z0 - 0.3), Vector3(x1 - x0 + 0.6, h + 0.5, z1 - z0 + 0.6)))


func _sides_of(front: String) -> Array[String]:
	return ["+z", "-z"] if front.length() == 2 and (front[1] == "x") else ["+x", "-x"]


func _back_of(front: String) -> String:
	if front == "+x": return "-x"
	if front == "-x": return "+x"
	if front == "+z": return "-z"
	return "+z"


func _face_params(spec: Dictionary, face: String, is_front: bool) -> Array:
	## 返回 [axis, wall_c, out_dir, a0, a1]
	var x0: float = spec["x0"]; var x1: float = spec["x1"]
	var z0: float = spec["z0"]; var z1: float = spec["z1"]
	match face:
		"+x": return ["x", x1, 1, z0, z1]
		"-x": return ["x", x0, -1, z0, z1]
		"+z": return ["z", z1, 1, x0, x1]
		"-z": return ["z", z0, -1, x0, x1]
	return ["x", x1, 1, z0, z1]


func _windows_for_face(mb: GL.MeshBuilder, spec: Dictionary, face: String, is_front: bool, rng: RandomNumberGenerator) -> void:
	var p := _face_params(spec, face, is_front)
	var axis: String = p[0]
	var wall_c: float = p[1]
	var out_dir: int = p[2]
	var a0: float = p[3] + 0.5
	var a1: float = p[4] - 0.5
	var h: float = spec["h"]
	var has_shop := is_front and not (spec.get("shop", {}) as Dictionary).is_empty()
	var base_y := 3.9 if has_shop else 0.95
	var pattern: String = spec.get("pattern", "grid")
	if pattern == "band" and is_front:
		_band_windows(mb, axis, wall_c, out_dir, a0, a1, base_y, h - 0.7, spec, rng)
		return
	# grid：逐层逐开间
	var y := base_y
	var floor_idx := 0
	while y + float(spec["win_h"]) + 0.45 <= h - 0.6:
		var a := a0 + float(spec["bay"]) * 0.5
		var bay_idx := 0
		while a + float(spec["win_w"]) * 0.5 + 0.2 <= a1:
			var r := rng.randf()
			var lit := 0
			if r < 0.3:
				lit = 1
			elif r < 0.38:
				lit = 2
			if r >= 0.9:
				# 固定配置差异：关闭的遮板窗（约 10%），打破机械规律
				var sh_in := wall_c + out_dir * 0.02
				var sh_out := wall_c + out_dir * 0.1
				_strip(mb, "metal_teal", axis, minf(sh_in, sh_out), maxf(sh_in, sh_out), a - float(spec["win_w"]) * 0.5 - 0.06, a + float(spec["win_w"]) * 0.5 + 0.06, y - 0.06, y + float(spec["win_h"]) + 0.06)
			else:
				GL.window_unit(mb, axis, wall_c, out_dir, a, y, float(spec["win_w"]), float(spec["win_h"]), KEYS, lit)
			var balcony: Array = spec.get("balcony", [])
			if balcony.has(floor_idx) and bay_idx % 2 == 0 and is_front:
				GL.balcony(mb, axis, wall_c, out_dir, a - float(spec["bay"]) * 0.55, a + float(spec["bay"]) * 0.55, y - 0.05, 1.15, KEYS)
			a += float(spec["bay"])
			bay_idx += 1
		y += float(spec["floor_h"])
		floor_idx += 1


func _band_windows(mb: GL.MeshBuilder, axis: String, wall_c: float, out_dir: int, a0: float, a1: float, y_base: float, y_top: float, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	## 水平带窗：每层一条连续玻璃带，分段亮暗。
	var floor_h: float = spec["floor_h"]
	var win_h: float = 1.45
	var y := y_base
	while y + win_h + 0.5 <= y_top:
		# 上沿窗框带与下沿墙带
		var f_in := wall_c + out_dir * -0.03
		var f_out := wall_c + out_dir * 0.05
		_strip(mb, "metal_dark", axis, minf(f_in, f_out), maxf(f_in, f_out), a0 - 0.3, a1 + 0.3, y - 0.12, y)
		_strip(mb, "metal_dark", axis, minf(f_in, f_out), maxf(f_in, f_out), a0 - 0.3, a1 + 0.3, y + win_h, y + win_h + 0.12)
		# 分段玻璃
		var seg := 2.3
		var a := a0
		while a < a1:
			var w := minf(seg, a1 - a)
			var r := rng.randf()
			var key := "glass_dark"
			if r < 0.26:
				key = "lit_warm"
			elif r < 0.33:
				key = "lit_cool"
			var glass_off := wall_c + out_dir * -0.06
			var uv2sz := Vector2(w * 26.0 / GL.ATLAS_PX, win_h * 26.0 / GL.ATLAS_PX)
			_quad_axis(mb, key, axis, glass_off, a, a + w, y, y + win_h, out_dir, uv2sz)
			# 竖框
			if a > a0:
				_strip(mb, "metal_dark", axis, minf(f_in, f_out), maxf(f_in, f_out), a - 0.06, a + 0.06, y, y + win_h)
			a += w
		y += floor_h


func _strip(mb: GL.MeshBuilder, key: String, axis: String, c0: float, c1: float, a0: float, a1: float, y0: float, y1: float) -> void:
	## 沿墙面薄条（box_between 内部处理角点顺序）。
	if axis == "x":
		mb.box_between(key, Vector3(c0, y0, a0), Vector3(c1, y1, a1), 0.5, 22.0)
	else:
		mb.box_between(key, Vector3(a0, y0, c0), Vector3(a1, y1, c1), 0.5, 22.0)


func _quad_axis(mb: GL.MeshBuilder, key: String, axis: String, c: float, a0: float, a1: float, y0: float, y1: float, out_dir: int, uv2sz: Vector2) -> void:
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


func _shopfront(mb: GL.MeshBuilder, front: String, spec: Dictionary, shop: Dictionary, rng: RandomNumberGenerator) -> void:
	var p := _face_params(spec, front, true)
	var axis: String = p[0]
	var wall_c: float = p[1]
	var out_dir: int = p[2]
	var a0: float = shop["a0"]
	var a1: float = shop["a1"]
	var depth: float = shop.get("depth", 3.0)
	var sign_mat: String = shop["mat"]
	var uv01 := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	# 踢脚墙
	_strip(mb, "concrete_plain", axis, wall_c, wall_c + out_dir * 0.02, a0, a1, 0.0, 0.45)
	# 橱窗玻璃（内凹 0.08）
	var glass_c := wall_c + out_dir * -0.08
	var uv2sz := Vector2((a1 - a0) * 26.0 / GL.ATLAS_PX, 2.6 * 26.0 / GL.ATLAS_PX)
	_quad_axis(mb, "glass_shop", axis, glass_c, a0 + 0.15, a1 - 0.15, 0.45, 3.05, out_dir, uv2sz)
	# 橱窗竖框
	var n_mid := int((a1 - a0) / 2.2)
	for i in n_mid + 1:
		var a := a0 + (a1 - a0) * float(i) / maxf(1.0, float(n_mid))
		_strip(mb, "metal_dark", axis, wall_c + out_dir * -0.06, wall_c + out_dir * 0.04, a - 0.045, a + 0.045, 0.45, 3.05)
	# 店内背景盒
	var back_c := wall_c + out_dir * -depth
	var intface_uv2 := Vector2((a1 - a0) * 20.0 / GL.ATLAS_PX, 2.8 * 20.0 / GL.ATLAS_PX)
	_quad_axis(mb, "interior_back", axis, back_c, a0, a1, 0.1, 3.0, out_dir, intface_uv2)
	_strip(mb, "door_dark", axis, wall_c + out_dir * -depth, wall_c + out_dir * -depth + out_dir * -0.06, a0 - 0.05, a1 + 0.05, 0.0, 3.15)
	_strip(mb, "door_dark", axis, wall_c + out_dir * -depth, wall_c, a0 - 0.05, a0 + 0.05, 0.0, 3.15)
	_strip(mb, "door_dark", axis, wall_c + out_dir * -depth, wall_c, a1 - 0.05, a1 + 0.05, 0.0, 3.15)
	_strip(mb, "door_dark", axis, wall_c + out_dir * -depth, wall_c, a0, a1, 3.15, 3.3)
	_strip(mb, "wood", axis, wall_c + out_dir * -depth, wall_c, a0, a1, 0.0, 0.12)
	# 货架与柜台剪影
	var shelf_n := int((a1 - a0) / 2.0)
	for i in shelf_n:
		var sa := a0 + 0.8 + i * 2.0
		if sa + 0.8 < a1:
			_strip(mb, "wood", axis, wall_c + out_dir * -0.55, wall_c + out_dir * -0.15, sa, sa + 0.75, 0.7, 2.4)
			_strip(mb, "wood", axis, wall_c + out_dir * -depth + out_dir * 0.3, wall_c + out_dir * -depth + out_dir * 0.7, sa, sa + 1.5, 0.55, 1.05)
	# 招牌盒 + 发光面
	var sign_y0 := 3.35
	var sign_y1 := 4.15
	var s_in := wall_c + out_dir * 0.0
	var s_out := wall_c + out_dir * 0.35
	_strip(mb, "metal_dark", axis, minf(s_in, s_out), maxf(s_in, s_out), a0 - 0.25, a1 + 0.25, sign_y0, sign_y1)
	var signface_uv2 := Vector2((a1 - a0) * 18.0 / GL.ATLAS_PX, (sign_y1 - sign_y0) * 18.0 / GL.ATLAS_PX)
	_quad_axis(mb, sign_mat, axis, s_out + out_dir * 0.01, a0 - 0.1, a1 + 0.1, sign_y0 + 0.08, sign_y1 - 0.08, out_dir, signface_uv2)
	var light_pos := Vector3(wall_c + out_dir * -1.2, 1.9, (a0 + a1) / 2) if axis == "x" else Vector3((a0 + a1) / 2, 1.9, wall_c + out_dir * -1.2)
	lights_spec.append(_omni(light_pos, Color(1, 0.72, 0.45), 4.0, 8.0))
	# 雨棚
	if shop.get("awning", false):
		var aw_out := wall_c + out_dir * 1.5
		_strip(mb, "metal_teal", axis, wall_c + out_dir * 0.05, aw_out, a0 - 0.1, a1 + 0.1, 3.18, 3.42)
		for s in [0.2, 0.8]:
			var aa := lerpf(a0, a1, s)
			_strip(mb, "metal_dark", axis, wall_c + out_dir * 1.2, wall_c + out_dir * 1.45, aa - 0.03, aa + 0.03, 2.55, 3.2)
	# 门（一侧）
	var door_a := a1 - 0.9
	var door_uv2 := Vector2(0.9 * 22.0 / GL.ATLAS_PX, 2.3 * 22.0 / GL.ATLAS_PX)
	_quad_axis(mb, "door_dark", axis, wall_c + out_dir * -0.05, door_a, door_a + 0.9, 0.0, 2.4, out_dir, door_uv2)


func _vertical_sign(mb: GL.MeshBuilder, front: String, spec: Dictionary, vsign: Dictionary) -> void:
	var p := _face_params(spec, front, true)
	var axis: String = p[0]
	var wall_c: float = p[1]
	var out_dir: int = p[2]
	var a: float = vsign["a"]
	var mat_key: String = vsign["mat"]
	# 竖招牌：0.75 宽 × 3.2 高，从 3.4 挂到 6.6
	var s_out := wall_c + out_dir * 0.55
	if axis == "x":
		mb.box("metal_dark", Vector3(minf(wall_c, s_out), 3.4, a - 0.38), Vector3(maxf(wall_c, s_out), 6.6, a + 0.38), 0.5, 18.0)
		var uv2sz := Vector2(0.7 * 18.0 / GL.ATLAS_PX, 3.1 * 18.0 / GL.ATLAS_PX)
		var face_c := s_out + out_dir * 0.01
		_quad_axis(mb, mat_key, "x", face_c, a - 0.34, a + 0.34, 3.45, 6.55, out_dir, uv2sz)
	else:
		mb.box("metal_dark", Vector3(a - 0.38, 3.4, minf(wall_c, s_out)), Vector3(a + 0.38, 6.6, maxf(wall_c, s_out)), 0.5, 18.0)
		var uv2sz := Vector2(0.7 * 18.0 / GL.ATLAS_PX, 3.1 * 18.0 / GL.ATLAS_PX)
		var face_c := s_out + out_dir * 0.01
		_quad_axis(mb, mat_key, "z", face_c, a - 0.34, a + 0.34, 3.45, 6.55, out_dir, uv2sz)
	lights_spec.append(_omni(Vector3(a, 5.0, wall_c + out_dir * 1.2) if axis == "z" else Vector3(wall_c + out_dir * 1.2, 5.0, a), Color(0.9, 0.7, 0.85), 1.1, 3.0))


func _omni(pos: Vector3, color: Color, energy: float, range_m: float) -> Dictionary:
	return {"pos": pos, "color": color, "energy": energy, "range": range_m}


# ============================ 修理铺（主角近景） ============================

func _repair_shop(mb: GL.MeshBuilder) -> void:
	# 建筑 x 33..44, z 18..36, h 8；店面朝 -x（面向广场）
	var x0 := 33.0; var x1 := 44.0; var z0 := 18.0; var z1 := 36.0; var h := 8.0
	mb.box("wall_warm", Vector3(x0, 0, z0), Vector3(x1, h, z1), 1.0 / 3.0, 26.0, GL.FACE_NO_BOTTOM)
	mb.box("concrete_plain", Vector3(x0 - 0.04, 0, z0 - 0.04), Vector3(x1 + 0.04, 0.5, z1 + 0.04), 0.55, 24.0, GL.FACE_NO_BOTTOM)
	GL.roof_kit(mb, x0, z0, x1, z1, h, _rng, {"parapet": "concrete_plain", "roof": "roof", "metal": "metal_dark"}, false)
	# 大橱窗 z 20..30.5，卷帘门 z 31.5..35
	var glass_c := x0 - 0.08
	var uv2sz := Vector2(10.5 * 26.0 / GL.ATLAS_PX, 3.4 * 26.0 / GL.ATLAS_PX)
	_quad_axis(mb, "glass_shop", "x", glass_c, 20.2, 30.4, 0.45, 3.85, -1, uv2sz)
	for i in 5:
		var a := 20.2 + i * 2.55
		_strip(mb, "metal_dark", "x", x0 - 0.06, x0 + 0.04, a - 0.045, a + 0.045, 0.45, 3.85)
	_strip(mb, "metal_dark", "x", x0 - 0.06, x0 + 0.04, 20.2, 30.5, 3.85, 4.0)
	# 卷帘门（水平条纹盒 + 纹理条）
	mb.box("metal_dark", Vector3(x0 - 0.06, 0, 31.3), Vector3(x0 + 0.1, 4.2, 35.3), 0.9, 22.0)
	for yy in range(1, 5):
		_strip(mb, "metal_teal", "x", x0 - 0.07, x0 - 0.02, 31.3, 35.3, float(yy), float(yy) + 0.12)
	# 卷帘门导轨（1.1 近景）
	mb.box("metal_dark", Vector3(x0 - 0.12, 0, 31.15), Vector3(x0 + 0.02, 4.3, 31.35), 0.8, 18.0)
	mb.box("metal_dark", Vector3(x0 - 0.12, 0, 35.25), Vector3(x0 + 0.02, 4.3, 35.45), 0.8, 18.0)
	# 门口近景件：灭火器 + 油桶 ×2 + 灭火器箱
	mb.cylinder("metal_orange", Vector3(x0 - 0.35, 0.55, 30.6), 0.09, 0.85, 8, 0.7, 16.0)
	mb.box("metal_orange", Vector3(x0 - 0.42, 1.05, 30.5), Vector3(x0 - 0.28, 1.14, 30.7), 0.8, 14.0)
	mb.box("metal_dark", Vector3(x0 - 0.5, 0.85, 30.45), Vector3(x0 - 0.2, 1.25, 30.75), 0.7, 14.0)
	for i in 2:
		mb.cylinder("metal_teal", Vector3(x0 - 0.6, 0.47 + i * 0.0, 32.4 + i * 0.75), 0.29, 0.94, 10, 0.55, 18.0)
	# 店内：深处工作台/货架/轮胎
	var back_c := x0 + 4.6
	var int_uv2 := Vector2(14.0 * 20.0 / GL.ATLAS_PX, 3.9 * 20.0 / GL.ATLAS_PX)
	_quad_axis(mb, "interior_back", "x", back_c, z0 + 0.5, z1 - 0.5, 0.1, 4.0, -1, int_uv2)
	mb.box("door_dark", Vector3(x0, 0, z0 - 0.05), Vector3(back_c, 0.12, z0 + 0.05), 0.6, 20.0)
	mb.box("door_dark", Vector3(x0, 0, z1 - 0.05), Vector3(back_c, 0.12, z1 + 0.05), 0.6, 20.0)
	mb.box("door_dark", Vector3(x0, 4.0, z0), Vector3(back_c, 4.15, z1), 0.6, 20.0)
	mb.box("door_dark", Vector3(back_c - 0.06, 0, z0), Vector3(back_c, 4.15, z1), 0.6, 20.0)
	# 工作台（橱窗后）
	mb.box("wood", Vector3(x0 + 0.8, 0.9, 21.5), Vector3(x0 + 1.9, 1.05, 29.5), 0.6, 22.0)
	mb.box("metal_dark", Vector3(x0 + 0.85, 0, 21.6), Vector3(x0 + 0.95, 0.9, 21.9), 0.7, 18.0)
	mb.box("metal_dark", Vector3(x0 + 1.75, 0, 29.1), Vector3(x0 + 1.85, 0.9, 29.4), 0.7, 18.0)
	# 工具架（背墙上）
	for i in 3:
		mb.box("wood", Vector3(back_c - 0.7, 1.3 + i * 0.9, 24.0), Vector3(back_c - 0.15, 1.42 + i * 0.9, 31.0), 0.6, 20.0)
	# 轮胎堆（店内一角 + 门外）
	for i in 3:
		mb.cylinder("rubber", Vector3(x0 + 3.2, 0.12 + i * 0.38, 34.6), 0.55, 0.32, 12, 0.9, 18.0)
	# 主招牌（双层大字 + 厚雨棚）
	var s_out := x0 - 0.5
	mb.box("metal_dark", Vector3(s_out - 0.12, 4.35, 19.2), Vector3(x0 + 0.1, 5.75, 35.8), 0.5, 20.0)
	var sign_uv2 := Vector2(15.0 * 18.0 / GL.ATLAS_PX, 1.2 * 18.0 / GL.ATLAS_PX)
	_quad_axis(mb, "sign_repair", "x", s_out - 0.13, 19.6, 35.4, 4.5, 5.6, -1, sign_uv2)
	# 厚雨棚（金属 + 底面）
	mb.box("metal_orange", Vector3(x0 - 2.4, 4.05, 19.4), Vector3(x0 + 0.05, 4.4, 35.6), 0.5, 22.0)
	mb.box("metal_dark", Vector3(x0 - 2.3, 3.85, 19.5), Vector3(x0 - 2.15, 4.05, 35.5), 0.6, 20.0)
	for s in [0.15, 0.5, 0.85]:
		var zz := lerpf(19.8, 35.2, s)
		mb.box("metal_dark", Vector3(x0 - 2.25, 3.0, zz - 0.03), Vector3(x0 - 2.1, 4.05, zz + 0.03), 0.7, 18.0)
	# 店内暖光 + 招牌光（小空间低能量，避免漫反射裁剪成整片白）
	lights_spec.append(_omni(Vector3(x0 + 1.5, 2.6, 25.5), Color(1, 0.78, 0.5), 2.2, 10.0))
	lights_spec.append(_omni(Vector3(x0 + 1.2, 2.6, 33.0), Color(1, 0.72, 0.45), 1.8, 9.0))
	lights_spec.append(_omni(Vector3(x0 - 1.2, 4.9, 27.5), Color(1, 0.68, 0.4), 2.2, 8.0))
	exclusions.append(AABB(Vector3(x0 - 2.5, 0, z0 - 0.3), Vector3(x1 - x0 + 2.8, h + 0.5, z1 - z0 + 0.6)))


# ============================ 高架站口 ============================

func _station(mb: GL.MeshBuilder) -> void:
	# 双柱 + 桥面 + 轨道 + 站台 + 站名牌 + 楼梯；街道在 z=-60 收束
	var pyl := "concrete_plain"
	var steel := "steel_station"
	# 柱（两侧）
	mb.box(pyl, Vector3(-15.0, 0, -66.5), Vector3(-12.6, 10.4, -62.5), 0.5, 22.0)
	mb.box(pyl, Vector3(12.6, 0, -66.5), Vector3(15.0, 10.4, -62.5), 0.5, 22.0)
	# 横梁与桥面板
	mb.box(steel, Vector3(-20, 9.9, -66.8), Vector3(26, 10.6, -59.6), 0.6, 22.0)
	mb.box(pyl, Vector3(-20, 10.6, -66.5), Vector3(26, 11.3, -59.9), 0.5, 22.0)
	# 轨道（东西向延伸出画面）
	mb.box("metal_dark", Vector3(-150, 11.3, -64.6), Vector3(150, 11.44, -61.2), 0.8, 10.0)
	mb.box("steel_station", Vector3(-150, 11.44, -64.2), Vector3(150, 11.58, -64.0), 0.7, 8.0)
	mb.box("steel_station", Vector3(-150, 11.44, -61.8), Vector3(150, 11.58, -61.6), 0.7, 8.0)
	# 站台（南侧条 + 栏杆）
	mb.box(pyl, Vector3(-20, 11.3, -61.4), Vector3(26, 11.55, -59.9), 0.5, 20.0)
	for i in 24:
		var px := -19.5 + i * 1.9
		mb.box("metal_dark", Vector3(px, 11.55, -60.15), Vector3(px + 0.06, 12.45, -60.05), 0.8, 14.0)
	mb.box("metal_teal", Vector3(-20, 12.35, -60.2), Vector3(26, 12.5, -60.0), 0.7, 14.0)
	# 顶部雨棚
	mb.box(steel, Vector3(-20, 13.6, -65.5), Vector3(26, 13.9, -59.5), 0.6, 18.0)
	for i in 6:
		var cx := -18.0 + i * 8.5
		mb.box("metal_dark", Vector3(cx - 0.09, 12.9, -64.5), Vector3(cx + 0.09, 13.6, -64.3), 0.7, 14.0)
	# 站名牌（悬挂，朝南面向街道）
	mb.box("metal_dark", Vector3(-3.4, 8.6, -60.18), Vector3(3.4, 10.0, -60.02), 0.5, 20.0)
	var uv2sz := Vector2(6.4 * 20.0 / GL.ATLAS_PX, 1.3 * 20.0 / GL.ATLAS_PX)
	var uv01 := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	mb.quad("sign_station", Vector3(3.25, 8.75, -60.2), Vector3(-3.25, 8.75, -60.2), Vector3(-3.25, 9.9, -60.2), Vector3(3.25, 9.9, -60.2), Vector3(0, 0, -1), uv01, uv2sz)
	for sx in [-2.4, 2.4]:
		mb.box("metal_dark", Vector3(sx - 0.04, 10.0, -60.1), Vector3(sx + 0.04, 10.6, -60.05), 0.7, 14.0)
	lights_spec.append(_omni(Vector3(0, 8.2, -59.0), Color(0.5, 0.88, 0.85), 2.6, 8.0))
	# 侧墙收束街道尽头（留中间通道的栏杆）
	mb.box("concrete_plain", Vector3(-12.2, 0, -60.6), Vector3(-6.0, 3.6, -60.0), 0.55, 22.0)
	mb.box("concrete_plain", Vector3(6.0, 0, -60.6), Vector3(12.2, 3.6, -60.0), 0.55, 22.0)
	mb.box("metal_dark", Vector3(-6.0, 0.6, -60.35), Vector3(6.0, 1.05, -60.15), 0.8, 18.0)
	for i in 7:
		var bx := -5.5 + i * 1.8
		mb.box("metal_dark", Vector3(bx - 0.04, 0.15, -60.35), Vector3(bx + 0.04, 1.05, -60.15), 0.8, 14.0)
	# 楼梯（东侧双跑：低位南北两段 + 顶部连平台）
	var sh := "concrete_plain"
	for i in 12:
		# 第一跑：x 15.5→24.5 上升至 y≈5.3，z 带 -58.9..-57.1
		mb.box(sh, Vector3(15.5 + i * 0.75, 0.15 + i * 0.43, -58.9), Vector3(15.5 + (i + 1) * 0.75 + 0.1, 0.15 + i * 0.43 + 0.14, -57.1), 0.5, 20.0)
		# 第二跑：x 24.5→15.5 继续上升至 y≈10.4，z 带 -61.0..-59.2
		mb.box(sh, Vector3(24.5 - (i + 1) * 0.75, 5.35 + i * 0.43, -61.0), Vector3(24.5 - i * 0.75 + 0.1, 5.35 + i * 0.43 + 0.14, -59.2), 0.5, 20.0)
	# 顶部小平台接站台
	mb.box(sh, Vector3(13.6, 10.35, -61.2), Vector3(17.0, 10.5, -58.9), 0.5, 20.0)
	# 梯段侧栏板（低墙）
	mb.box("concrete_plain", Vector3(15.3, 0, -57.25), Vector3(24.8, 5.4, -57.1), 0.5, 18.0)
	mb.box("concrete_plain", Vector3(15.3, 5.3, -61.15), Vector3(24.8, 10.6, -61.0), 0.5, 18.0)
	# 站牌小灯（实时补光在 Lighting 中）
	exclusions.append(AABB(Vector3(-15.3, 0, -66.8), Vector3(2.7, 10.6, 4.4)))
	exclusions.append(AABB(Vector3(12.3, 0, -66.8), Vector3(2.7, 10.6, 4.4)))
	exclusions.append(AABB(Vector3(-20.3, 9.8, -67.1), Vector3(46.6, 4.2, 7.6)))
	exclusions.append(AABB(Vector3(13.3, 0, -61.4), Vector3(12.2, 10.7, 4.4)))
	exclusions.append(AABB(Vector3(-12.5, 0, -60.9), Vector3(25.0, 3.8, 1.0)))


func _exclusion_list() -> Array[AABB]:
	# 建筑体积已在 _building 中收集；这里补背景遮挡不需要（相机边界限制）
	return []


# ============================ 道具 ============================

func _street_furniture(mb: GL.MeshBuilder) -> void:
	# 路灯（两侧交错）
	for i in 6:
		var z := -45.0 + i * 18.0
		if absf(z - 13.5) < 3.0 or absf(z + 53.0) < 3.0:
			continue  # 避开横道
		var west := i % 2 == 0
		var head := GL.streetlight(mb, -8.6 if west else 8.6, z, 1 if west else -1, 0, KEYS)
		lights_spec.append(_omni(head, Color(1, 0.78, 0.52), 5.5, 11.0))
	# 电杆（东便道，北半段）
	for z in [-46.0, -26.0, -6.0]:
		mb.cylinder("wood", Vector3(9.8, 0.15, z), 0.13, 7.2, 8, 0.6, 20.0)
		mb.box("wood", Vector3(8.9, 6.6, z - 0.06), Vector3(10.7, 6.78, z + 0.06), 0.7, 18.0)
		mb.box("wood", Vector3(9.2, 5.9, z - 0.05), Vector3(10.4, 6.05, z + 0.05), 0.7, 18.0)
		# 绝缘子
		for ix in [9.1, 10.5]:
			mb.cylinder("metal_dark", Vector3(ix, 6.78, z), 0.05, 0.22, 6, 0.8, 12.0)
	# 街道小品
	GL.bench(mb, -8.8, 24.0, PI / 2, KEYS)
	GL.bench(mb, 8.8, -20.0, -PI / 2, KEYS)
	# 垃圾桶
	for pos in [Vector3(-9.2, 0.15, 33.0), Vector3(9.2, 0.15, -33.0)]:
		mb.cylinder("metal_dark", pos, 0.34, 0.85, 10, 0.7, 20.0)
	# 消防栓
	mb.cylinder("metal_orange", Vector3(7.2, 0.15, 2.0), 0.11, 0.62, 8, 0.7, 20.0)
	mb.cylinder("metal_orange", Vector3(7.2, 0.72, 2.0), 0.09, 0.12, 8, 0.7, 16.0)
	# 便利店外：配送箱与手推车
	for i in 3:
		mb.box("wood", Vector3(-9.0, 0.15 + i * 0.42, 37.3), Vector3(-8.3, 0.55 + i * 0.42, 38.0), 0.7, 22.0)
	mb.box("metal_dark", Vector3(-9.6, 0.15, 38.3), Vector3(-8.4, 0.95, 39.4), 0.7, 20.0)
	mb.box("wood", Vector3(-9.5, 0.95, 38.4), Vector3(-8.5, 1.0, 39.3), 0.7, 20.0)


func _alley_props(mb: GL.MeshBuilder) -> void:
	# 墙上空调 ×4（南北墙）
	var fan_poss: Array[Vector3] = []
	fan_poss.append(GL.ac_unit(mb, Vector3(-18, 3.4, 5.4), Vector3(0, 0, 1), KEYS))
	fan_poss.append(GL.ac_unit(mb, Vector3(-30, 2.6, 5.4), Vector3(0, 0, 1), KEYS))
	fan_poss.append(GL.ac_unit(mb, Vector3(-24, 3.8, -5.4), Vector3(0, 0, -1), KEYS))
	fan_poss.append(GL.ac_unit(mb, Vector3(-38, 2.8, -5.4), Vector3(0, 0, -1), KEYS))
	# 竖向落水管（1.1：起止支架）
	for x in [-13.0, -21.0, -33.0, -43.0]:
		mb.cylinder("metal_dark", Vector3(x, 0.1, 5.7), 0.07, 9.4, 6, 0.8, 14.0)
		# 顶部弯头 + 底部排水口 + 中部支架
		mb.box("metal_dark", Vector3(x - 0.16, 9.4, 5.55), Vector3(x + 0.16, 9.56, 5.85), 0.8, 14.0)
		mb.box("metal_dark", Vector3(x - 0.12, 0.02, 5.58), Vector3(x + 0.12, 0.14, 5.82), 0.8, 14.0)
		mb.box("metal_dark", Vector3(x - 0.11, 4.6, 5.62), Vector3(x + 0.11, 4.72, 5.78), 0.8, 12.0)
	# 电表箱 ×3（墙面半嵌入盒体）
	for mp in [Vector3(-15.5, 1.4, 5.82), Vector3(-28.5, 1.5, 5.82), Vector3(-36.0, 1.35, -5.82)]:
		mb.box("metal_teal", mp + Vector3(-0.25, 0, -0.06), mp + Vector3(0.25, 1.3, 0.06), 0.7, 16.0)
	# 海报（贴巷道两侧墙面）
	var poster_uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for pd in [{"p": Vector3(-16.5, 1.7, 5.86), "n": 1}, {"p": Vector3(-27.5, 1.4, 5.86), "n": 1}, {"p": Vector3(-35.2, 1.9, -5.86), "n": -1}]:
		var uv2sz := Vector2(0.9 * 20.0 / GL.ATLAS_PX, 1.3 * 20.0 / GL.ATLAS_PX)
		var p: Vector3 = pd["p"]
		var nd: int = pd["n"]
		if nd > 0:
			mb.quad("poster", p + Vector3(-0.45, -0.65, 0), p + Vector3(0.45, -0.65, 0), p + Vector3(0.45, 0.65, 0), p + Vector3(-0.45, 0.65, 0), Vector3(0, 0, 1), poster_uv, uv2sz)
		else:
			mb.quad("poster", p + Vector3(0.45, -0.65, 0), p + Vector3(-0.45, -0.65, 0), p + Vector3(-0.45, 0.65, 0), p + Vector3(0.45, 0.65, 0), Vector3(0, 0, -1), poster_uv, uv2sz)
	# 杂物箱与轮胎
	mb.box("wood", Vector3(-41.5, 0.1, -3.4), Vector3(-40.6, 0.9, -2.5), 0.7, 20.0)
	mb.box("wood", Vector3(-41.2, 0.9, -3.2), Vector3(-40.9, 1.2, -2.8), 0.7, 20.0)
	for i in 2:
		mb.cylinder("rubber", Vector3(-14.2, 0.22 + i * 0.38, -4.8), 0.5, 0.32, 12, 0.9, 16.0)
	# 巷尾已开放连通生活广场（1.1：移除原栅栏门，由 authored 层拱门承接空间转换）
	# 巷内小灯（罩灯）
	mb.box("metal_dark", Vector3(-21.5, 3.6, 5.7), Vector3(-21.1, 3.9, 6.05), 0.8, 16.0)
	lights_spec.append(_omni(Vector3(-21.3, 3.3, 5.6), Color(1, 0.8, 0.55), 1.8, 5.0))
	_fan_positions = fan_poss


var _fan_positions: Array[Vector3] = []


func _plaza_props(mb: GL.MeshBuilder) -> void:
	# 工具车（修理铺门前）
	mb.box("metal_teal", Vector3(29.5, 0.17, 23.0), Vector3(31.1, 1.05, 24.4), 0.7, 22.0)
	mb.box("metal_dark", Vector3(29.6, 1.05, 23.1), Vector3(31.0, 1.35, 24.3), 0.7, 20.0)
	mb.cylinder("rubber", Vector3(29.8, 0.17, 24.4), 0.16, 0.34, 8, 0.8, 16.0)
	mb.cylinder("rubber", Vector3(30.8, 0.17, 24.4), 0.16, 0.34, 8, 0.8, 16.0)
	# 门外轮胎堆（Flash 验收 1.2：从 (30.6,33.5) 移到门南侧——原位恰在 repair_shop_door
	# 锚点到行人小门的视线上，近距巨物遮挡门户；也避开门扇向街开启的扫掠区）
	for i in 3:
		mb.cylinder("rubber", Vector3(30.9, 0.19 + i * 0.36, 34.9), 0.52, 0.3, 12, 0.9, 18.0)
	# 长椅 ×2 + 花坛
	GL.bench(mb, 18.5, 20.5, PI / 2, KEYS)
	GL.bench(mb, 18.5, 33.5, PI / 2, KEYS)
	for pd in [Vector3(24.5, 0.17, 20.0), Vector3(16.5, 0.17, 27.0)]:
		mb.box("concrete_plain", pd + Vector3(-0.8, 0, -0.8), pd + Vector3(0.8, 0.55, 0.8), 0.6, 20.0)
		mb.box("metal_dark", pd + Vector3(-0.7, 0.5, -0.7), pd + Vector3(0.7, 0.62, 0.7), 0.7, 18.0)
	# 街边围桩（广场临街一侧）
	for i in 5:
		mb.cylinder("metal_dark", Vector3(12.6, 0.17, 17.5 + i * 4.5), 0.09, 0.75, 8, 0.8, 16.0)
	# 串灯（广场上方，单段横跨，避开维修铺机位正前）
	_string_lights(mb, Vector3(13.5, 5.0, 19.5), Vector3(31.5, 5.0, 32.5), 0.5)
	# 咖啡外摆（E1 门前，属于街边但用同一网格）
	GL.bench(mb, 14.2, 46.0, -PI / 2, KEYS)
	mb.box("wood", Vector3(13.6, 0.15, 45.2), Vector3(14.1, 0.72, 45.7), 0.7, 20.0)
	# 广场一角路灯（矮，暖）
	mb.cylinder("metal_dark", Vector3(14.0, 0.17, 36.5), 0.06, 3.2, 8, 0.6, 18.0)
	lights_spec.append(_omni(Vector3(14.0, 3.0, 36.5), Color(1, 0.74, 0.48), 2.4, 6.5))
	lights_spec.append(_omni(Vector3(22.0, 3.4, 26.0), Color(1, 0.68, 0.44), 2.0, 10.0))


func _string_lights(mb: GL.MeshBuilder, p0: Vector3, p1: Vector3, sag: float) -> void:
	var n := 13
	var prev := p0
	for i in range(1, n + 1):
		var t := float(i) / n
		var pos := p0.lerp(p1, t) + Vector3.DOWN * (sag * 4.0 * t * (1.0 - t))
		# 灯泡
		mb.bulb("bulb_warm", pos + Vector3.DOWN * 0.1, 0.045)
		# 拉线段
		var mid := (prev + pos) / 2.0
		var length := prev.distance_to(pos)
		mb.box_between("wire", mid - Vector3(length / 2, 0.012, 0.012), mid + Vector3(length / 2, 0.012, 0.012), 0.9, 8.0)
		prev = pos


func _station_area_props(mb: GL.MeshBuilder) -> void:
	# 站前：指示牌与候车椅
	mb.box("metal_dark", Vector3(-7.5, 0.15, -56.5), Vector3(-7.3, 2.8, -56.3), 0.7, 18.0)
	mb.box("metal_teal", Vector3(-8.3, 2.5, -56.6), Vector3(-6.5, 2.9, -56.2), 0.7, 16.0)
	GL.bench(mb, -8.5, -54.5, 0, KEYS)
	# 导流柱
	for i in 4:
		mb.cylinder("metal_teal", Vector3(-4.5 + i * 3.0, 0.15, -51.8), 0.08, 0.7, 8, 0.8, 14.0)


# ============================ 灯光与环境 ============================

func _build_lighting(root: Node3D) -> void:
	var lm := root.get_node("BakedWorld")
	var lighting := _node3d("Lighting", lm)
	# 黄昏低角度主光（BAKE_STATIC → 只进 lightmap；天空取自它）
	var sun := DirectionalLight3D.new()
	sun.name = "DuskSun"
	sun.light_color = Color(1.0, 0.71, 0.5)
	sun.light_energy = 2.9
	sun.light_bake_mode = Light3D.BAKE_STATIC
	sun.transform = Transform3D(Basis(), Vector3.ZERO).looking_at(Vector3(0.52, -0.16, 0.4).normalized(), Vector3.UP)
	sun.set_meta("node_groups", PackedStringArray(["bake_only_light"]))
	lighting.add_child(sun)
	# 烘焙灯（运行时隐藏）
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
	# 均衡档补光（≤2，无阴影）
	var extra1 := OmniLight3D.new()
	extra1.position = Vector3(30.8, 2.4, 25.8)
	extra1.light_color = Color(1, 0.76, 0.5)
	extra1.light_energy = 2.2
	extra1.omni_range = 5.5
	extra1.shadow_enabled = false
	extra1.visible = false
	extra1.add_to_group("runtime_fill_light")
	extra1.set_meta("node_groups", PackedStringArray(["runtime_fill_light"]))
	lighting.add_child(extra1)
	var extra2 := OmniLight3D.new()
	extra2.position = Vector3(21.0, 2.6, -57.5)
	extra2.light_color = Color(0.6, 0.85, 0.9)
	extra2.light_energy = 1.6
	extra2.omni_range = 7.0
	extra2.shadow_enabled = false
	extra2.visible = false
	extra2.add_to_group("runtime_fill_light")
	extra2.set_meta("node_groups", PackedStringArray(["runtime_fill_light"]))
	lighting.add_child(extra2)
	# 均衡档反射探针（≤2，Once）
	var probe1 := ReflectionProbe.new()
	probe1.position = Vector3(22, 2.2, 26)
	probe1.size = Vector3(18, 6, 18)
	probe1.update_mode = ReflectionProbe.UPDATE_ONCE
	probe1.visible = false
	probe1.add_to_group("optional_probe")
	probe1.set_meta("node_groups", PackedStringArray(["optional_probe"]))
	lighting.add_child(probe1)
	var probe2 := ReflectionProbe.new()
	probe2.position = Vector3(0, 3.5, -18)
	probe2.size = Vector3(24, 7, 30)
	probe2.update_mode = ReflectionProbe.UPDATE_ONCE
	probe2.visible = false
	probe2.add_to_group("optional_probe")
	probe2.set_meta("node_groups", PackedStringArray(["optional_probe"]))
	lighting.add_child(probe2)
	_own(lighting, root)


func _build_backdrop_mesh() -> void:
	## 远景天际线网格：只产出 mesh 资源；节点由 assemble_m01 放置在 BakedWorld 之外。
	var mb := GL.MeshBuilder.new()
	# 远景塔楼环（不烘焙：px_per_m=0）
	var rng := RandomNumberGenerator.new()
	rng.seed = 99001
	var specs: Array[Dictionary] = []
	var angles: Array[float] = []
	for i in 22:
		angles.append(-165.0 + i * (330.0 / 22.0) + rng.randf_range(-4.0, 4.0))
	for ang in angles:
		var rad := deg_to_rad(ang)
		var dist := rng.randf_range(95.0, 165.0)
		var w := rng.randf_range(12.0, 26.0)
		var d := rng.randf_range(12.0, 26.0)
		var h := rng.randf_range(18.0, 64.0)
		var cx := cos(rad) * dist
		var cz := sin(rad) * dist
		# 塔楼沿切向朝向
		var rot := rad + PI / 2
		var ex := absf(cos(rot)) * w / 2 + absf(sin(rot)) * d / 2
		var ez := absf(sin(rot)) * w / 2 + absf(cos(rot)) * d / 2
		var key := "backdrop%d" % (1 + (rng.randi() % 3))
		mb.box(key, Vector3(cx - ex, 0, cz - ez), Vector3(cx + ex, h, cz + ez), 1.0 / 12.0, 0.0, GL.FACE_NO_BOTTOM)
	# 信号塔（西北远处）
	var tx := -98.0
	var tz := -112.0
	mb.box("metal_dark", Vector3(tx - 1.2, 0, tz - 1.2), Vector3(tx - 0.6, 44, tz - 0.6), 0.8, 0.0)
	mb.box("metal_dark", Vector3(tx + 0.6, 0, tz + 0.6), Vector3(tx + 1.2, 44, tz + 1.2), 0.8, 0.0)
	mb.box("metal_dark", Vector3(tx - 1.2, 0, tz + 0.6), Vector3(tx - 0.6, 44, tz + 1.2), 0.8, 0.0)
	mb.box("metal_dark", Vector3(tx + 0.6, 0, tz - 1.2), Vector3(tx + 1.2, 44, tz - 0.6), 0.8, 0.0)
	for i in 8:
		var yy := 3.5 + i * 5.0
		mb.box("metal_dark", Vector3(tx - 1.2, yy, tz - 1.2), Vector3(tx + 1.2, yy + 0.18, tz + 1.2), 0.8, 0.0, 4)
	mb.box("metal_dark", Vector3(tx - 2.6, 42.0, tz - 0.05), Vector3(tx + 2.6, 42.2, tz + 0.05), 0.8, 0.0)
	mb.cylinder("metal_dark", Vector3(tx, 44, tz), 0.08, 5.0, 6, 0.8, 0.0, false)
	mb.bulb("bulb_warm", Vector3(tx, 48.6, tz), 0.5)
	# 大地面（不烘焙）
	mb.box("ground_far", Vector3(-260, -0.06, -260), Vector3(260, -0.04, 260), 1.0 / 36.0, 0.0, 4)
	var mesh := mb.commit(mats, "%s/backdrop.res" % MESH_DIR, Vector2i(64, 64))
	_total_tris += mb.tri_count()
	print("backdrop: tris=", mb.tri_count())


# ============================ 生成规格（供 assemble_m01 组装） ============================

func _save_spec() -> void:
	## 输出生成层规格 JSON：禁入体积、灯位、环境件位置。assemble 据此组合最终地图。
	var excl: Array = []
	for b in exclusions:
		excl.append([b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	var spec := {
		"schema_version": 1,
		"generated_scene": GENERATED_SCENE,
		"backdrop_mesh": "%s/backdrop.res" % MESH_DIR,
		"exclusions": excl,
		"fan_positions": [
			[_fan_positions[0].x, _fan_positions[0].y, _fan_positions[0].z] if _fan_positions.size() > 0 else [-18.0, 3.4, 5.75],
			[36.5, 4.6, 17.72],
		],
		"flickers": [
			{"mat_key": "sign_bar_v", "pos": [-12.35, 4.3, -1.2], "size": [0.8, 2.6], "rot_y": 90.0},
			{"mat_key": "sign_electronics", "pos": [-11.63, 3.75, -10.5], "size": [6.1, 0.62], "rot_y": 90.0},
		],
		"particles": [[-30.5, 0.3, -2.0], [38.5, 8.35, 23.5]],
		"camera_bounds": [-50.0, 1.5, -70.0, 100.0, 22.5, 140.0],
		"anchors": {
			"street_view": {"pos": [-3, 1.7, 52], "look": [1, 8, -45]},
			"repair_shop_view": {"pos": [15, 1.8, 31], "look": [33, 2.5, 25]},
			# 1.1 正式新姿态：原 (18,12,-35) 落在 E6 楼体禁入体积内（第一章缺陷），移至街道上空
			"station_view": {"pos": [2, 13, -30], "look": [0, 10, -62]},
		},
	}
	var f := FileAccess.open(SPEC_PATH, FileAccess.WRITE)
	if f == null:
		push_error("spec 写入失败")
		return
	f.store_string(JSON.stringify(spec, "  "))
	f.close()
	print("spec saved: ", SPEC_PATH)


# ============================ 遮挡体 ============================

func _add_occluders(parent: Node3D) -> void:
	if not ClassDB.class_exists("BoxOccluder"):
		print("BoxOccluder 不可用，跳过遮挡体")
		return
	for spec in _building_specs():
		var occ := OccluderInstance3D.new()
		occ.name = "Occ_%s" % spec["id"]
		var box = ClassDB.instantiate("BoxOccluder")
		box.size = Vector3(float(spec["x1"]) - float(spec["x0"]), float(spec["h"]), float(spec["z1"]) - float(spec["z0"]))
		occ.occluder = box
		occ.position = Vector3((float(spec["x0"]) + float(spec["x1"])) / 2, float(spec["h"]) / 2, (float(spec["z0"]) + float(spec["z1"])) / 2)
		parent.add_child(occ)


# ============================ 测试地图 ============================

func _build_fixture() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures")
	var root := Node3D.new()
	root.name = "MiniTestMap"
	root.set_script(load("res://scripts/maps/map_root.gd"))
	var mb := GL.MeshBuilder.new()
	mb.box("concrete_plain", Vector3(-12, 0, -12), Vector3(12, 0.2, 12), 0.4, 20.0)
	mb.box("wall_warm", Vector3(-4, 0.2, -6), Vector3(4, 4.0, -4), 0.4, 20.0)
	var mesh := mb.commit(mats, "res://tests/fixtures/mini_test_map_mesh.res", Vector2i(256, 256))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	var we := WorldEnvironment.new()
	we.name = "Environment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.24, 0.3)
	we.environment = env
	root.add_child(we)
	var anchors := _node3d("CameraAnchors", root)
	var test_anchor := Marker3D.new()
	test_anchor.name = "test_anchor"
	test_anchor.transform = Transform3D(Basis(), Vector3(8, 2, 8)).looking_at(Vector3(0, 2, 0), Vector3.UP)
	anchors.add_child(test_anchor)
	_own(mi, root)
	_own(we, root)
	_own(anchors, root)
	ResourceSaver.save(_pack(root), FIXTURE_SCENE)
	var def := MAP_DEF_SCRIPT.new()
	def.map_id = "test_mini_map"
	def.display_name = "极小测试地图（不进生产注册表）"
	def.scene_path = FIXTURE_SCENE
	def.default_anchor = "test_anchor"
	def.anchor_names = PackedStringArray(["test_anchor"])
	def.camera_bounds = AABB(Vector3(-10, 1.5, -10), Vector3(20, 8, 20))
	def.lighting_profile_id = "none"
	def.available = true
	ResourceSaver.save(def, FIXTURE_DEF)
	print("fixture saved")
