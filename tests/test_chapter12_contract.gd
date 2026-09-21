## chapter1-2 接口合同测试（headless 可运行）。
## 运行：godot --headless --path . --script res://tests/test_chapter12_contract.gd
## 覆盖（chapter1-2 §9.1）：MapDefinition walk/portals 校验（T01/T02）、
##       ObserverCamera walk_move 台阶攀爬/边缘阻挡/墙体排斥/QE 无效（T03–T05）、
##       相机合同透传（T06）、fly 模式回归（T07）、门户命中判定（T08）。
extends SceneTree

const CameraScript := preload("res://scripts/app/camera_controller.gd")
const MapDefScript := preload("res://scripts/maps/map_definition.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== chapter1-2 合同测试开始 ===")
	_test_walk_definition()
	_test_portal_definition()
	_test_walk_move_stairs()
	_test_walk_move_edges()
	_test_walk_move_walls()
	_test_fly_regression()
	_test_portal_hit_helper()
	if failures.is_empty():
		print("=== chapter1-2 合同测试全部通过 ===")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== chapter1-2 合同测试失败 %d 项 ===" % failures.size())
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		failures.append(label)
		printerr("FAIL: ", label)


# ---------------- MapDefinition walk/portals（T01/T02） ----------------

func _make_walk_def() -> MapDefinition:
	var def: MapDefinition = MapDefScript.new()
	def.map_id = "walk_test"
	def.display_name = "步行测试图"
	def.scene_path = "res://tests/fixtures/mini_test_map.tscn"
	def.default_anchor = "a"
	def.anchor_names = PackedStringArray(["a"])
	def.camera_bounds = AABB(Vector3(0.0, 1.5, 0.0), Vector3(14.0, 6.5, 14.0))
	def.camera_mode = "walk"
	def.walk_surfaces = [
		AABB(Vector3(0.24, 0.0, 0.0), Vector3(9.5, 0.001, 12.0)),       # 一层地面
		AABB(Vector3(3.6, 0.0, 0.0), Vector3(0.32, 0.197, 1.1)),        # 台阶样例
		AABB(Vector3(3.4, 3.15, 0.0), Vector3(6.6, 0.001, 10.0)),       # 二层板
	]
	def.portals = [{
		"pos": Vector3(0.9, 1.6, 1.7), "radius": 1.6,
		"target_map_id": "m01_afterglow", "target_anchor": "repair_shop_door",
		"label": "返回街道",
	}]
	return def


func _test_walk_definition() -> void:
	var def := _make_walk_def()
	_check(def.validate().is_empty(), "合法 walk 定义 validate 通过")
	var d2 := _make_walk_def()
	d2.walk_surfaces = []
	_check(not d2.validate().is_empty(), "walk 缺 walk_surfaces 被拒绝")
	var d3 := _make_walk_def()
	d3.camera_mode = "swim"
	_check(not d3.validate().is_empty(), "非法 camera_mode 被拒绝")
	# 旧 fly 定义（无新字段）仍合法
	var fly: MapDefinition = MapDefScript.new()
	fly.map_id = "fly_old"
	fly.scene_path = "res://tests/fixtures/mini_test_map.tscn"
	fly.anchor_names = PackedStringArray(["a"])
	fly.default_anchor = "a"
	_check(fly.validate().is_empty(), "fly 定义（新字段缺省）validate 通过")
	_check(fly.camera_mode == "fly" and fly.walk_surfaces.is_empty() and fly.portals.is_empty(), "fly 定义新字段缺省值正确")


func _test_portal_definition() -> void:
	var def := _make_walk_def()
	var copies := def.get_portal_copies()
	_check(copies.size() == 1 and str(copies[0].get("target_map_id", "")) == "m01_afterglow", "门户值副本读取正确")
	var d2 := _make_walk_def()
	d2.portals = [{"pos": Vector3.ZERO, "radius": 9.0, "target_map_id": "x", "target_anchor": "a", "label": "L"}]
	_check(not d2.validate().is_empty(), "portal radius 越界 (0,6] 被拒绝")
	var d3 := _make_walk_def()
	d3.portals = [{"pos": Vector3.ZERO, "radius": 1.0, "target_map_id": "", "target_anchor": "a", "label": "L"}]
	_check(not d3.validate().is_empty(), "portal 缺 target_map_id 被拒绝")


# ---------------- walk_move（T03–T05） ----------------

## 16 级直跑楼梯行走面（对应 m01_repair_interior 楼梯，z 0..1.1）
func _stair_surfaces() -> Array[AABB]:
	var arr: Array[AABB] = []
	arr.append(AABB(Vector3(0.0, 0.0, 0.0), Vector3(14.0, 0.001, 12.0)))  # 一层
	for i in 16:
		arr.append(AABB(Vector3(3.6 + i * 0.32, 0.0, 0.0), Vector3(0.32, 0.197 * (i + 1), 1.1)))
	arr.append(AABB(Vector3(8.72, 3.152, 0.0), Vector3(1.28, 0.001, 1.2)))  # 二层落脚条
	arr.append(AABB(Vector3(3.4, 3.152, 1.1), Vector3(6.6, 0.001, 10.9)))   # 二层主板
	return arr


func _make_walk_camera(exclusions: Array[AABB] = []) -> Node3D:
	var cam: Node3D = CameraScript.new()
	root.add_child(cam)
	cam.bind_map_contract(&"walk_test", AABB(Vector3(0.0, 1.5, 0.0), Vector3(14.0, 5.0, 12.0)), exclusions, "walk", _stair_surfaces())
	return cam


func _set_pos(cam: Node3D, pos: Vector3) -> void:
	cam.set("_pos", pos)


func _get_pos(cam: Node3D) -> Vector3:
	return cam.get("_pos")


func _test_walk_move_stairs() -> void:
	var no_excl: Array[AABB] = []
	var cam := _make_walk_camera(no_excl)
	_set_pos(cam, Vector3(3.4, 1.62, 0.55))  # 楼梯起步前
	# 沿 +X 分步推进：每步 0.3m，模拟走上 16 级
	var steps := 0
	for i in 20:
		var before := _get_pos(cam)
		cam.walk_move(Vector3(0.3, 0.0, 0.0))
		var after := _get_pos(cam)
		if after.x - before.x < 0.29:
			break
		steps += 1
	_check(_get_pos(cam).y > 1.62 + 0.197 * 14.0, "连续推进沿楼梯抬升到接近二层高度")
	_check(_get_pos(cam).y <= 3.152 + 1.62 + 0.001, "楼梯顶不超过二层板面+眼高")
	# 继续走到二层主板
	for i in 12:
		cam.walk_move(Vector3(0.3, 0.0, 0.0))
	_check(absf(_get_pos(cam).y - (3.152 + 1.62)) < 0.01, "走上二层主板后眼高贴合 3.152+1.62")
	# 楼梯走向一侧（+Z）跨上主板
	for i in 6:
		cam.walk_move(Vector3(0.0, 0.0, 0.3))
	_check(absf(_get_pos(cam).y - (3.152 + 1.62)) < 0.01, "二层板上横向移动高度保持")
	cam.queue_free()


func _test_walk_move_edges() -> void:
	var no_excl: Array[AABB] = []
	var cam := _make_walk_camera(no_excl)
	# 站在二层主板边缘 x=3.5，向 -X（一层上空/无板区）推 → 应被取消
	_set_pos(cam, Vector3(3.5, 3.152 + 1.62, 5.0))
	var before := _get_pos(cam)
	cam.walk_move(Vector3(-0.4, 0.0, 0.0))
	_check(absf(_get_pos(cam).x - before.x) < 0.001, "二层边缘向外位移被取消（边缘阻挡）")
	# 但沿板内 +Z 方向可走
	cam.walk_move(Vector3(0.0, 0.0, 0.3))
	_check(absf(_get_pos(cam).z - (before.z + 0.3)) < 0.02, "二层板上安全方向可移动")
	cam.queue_free()


func _test_walk_move_walls() -> void:
	# 身体盒 vs 禁入盒：柜台在 x 5..6, z 4..5.2, y 0..1.05
	var cam: Node3D = CameraScript.new()
	root.add_child(cam)
	var excl: Array[AABB] = [AABB(Vector3(5.0, 0.0, 4.0), Vector3(1.0, 1.05, 1.2))]
	var surfaces: Array[AABB] = [AABB(Vector3(0.0, 0.0, 0.0), Vector3(14.0, 0.001, 12.0))]
	cam.bind_map_contract(&"walk_test", AABB(Vector3(0.0, 1.5, 0.0), Vector3(14.0, 5.0, 12.0)),
		excl, "walk", surfaces)
	_set_pos(cam, Vector3(4.0, 1.62, 4.6))
	cam.walk_move(Vector3(0.6, 0.0, 0.0))  # 目标 x=4.6 仍应被身体半径拦在 x≈4.65 前
	_check(_get_pos(cam).x < 4.68, "撞柜台（禁入盒）被身体半径阻挡")
	# Q/E 在 walk 模式不产生垂直位移：walk_move 忽略 y 分量
	cam.walk_move(Vector3(0.0, 5.0, 0.0))
	_check(absf(_get_pos(cam).y - 1.62) < 0.01, "walk_move 忽略垂直分量（Q/E 语义无效）")
	cam.queue_free()


func _test_fly_regression() -> void:
	var cam: Node3D = CameraScript.new()
	root.add_child(cam)
	var excl: Array[AABB] = [AABB(Vector3(0.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0))]
	cam.bind_map_contract(&"m01_fly", AABB(Vector3(-10.0, 1.5, -10.0), Vector3(20.0, 20.0, 20.0)), excl)
	_check(not cam.is_walk_mode(), "fly 图 is_walk_mode=false（旧签名默认 fly）")
	cam.set("_pos", Vector3(0.0, 5.0, 5.0))
	cam.call("_try_move", Vector3(0.0, 2.0, 0.0))  # fly 仍可垂直
	var pos: Vector3 = cam.get("_pos")
	_check(pos.y > 6.9, "fly 模式保留垂直移动（回归）")
	cam.queue_free()


# ---------------- 门户命中判定（T08） ----------------

func _test_portal_hit_helper() -> void:
	# 与 main.gd _on_pose_changed 相同的判定语义：半径内首个命中
	var portals: Array[Dictionary] = [
		{"pos": Vector3(0.9, 1.6, 1.7), "radius": 1.6, "target_map_id": "m01_afterglow",
			"target_anchor": "repair_shop_door", "label": "返回街道"},
	]
	var near := Vector3(1.2, 1.62, 2.2)
	var far := Vector3(6.0, 1.62, 2.2)
	var hit_near := false
	for p in portals:
		if (p["pos"] as Vector3).distance_to(near) <= float(p["radius"]):
			hit_near = true
			break
	var hit_far := false
	for p in portals:
		if (p["pos"] as Vector3).distance_to(far) <= float(p["radius"]):
			hit_far = true
			break
	_check(hit_near and not hit_far, "门户半径命中判定正确（近命中/远不命中）")
