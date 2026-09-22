## 受限自由观察摄影机（chapter1-1 §7.6 ObserverCamera 合同）。
## 右键拖动转向，WASD/QE 移动；整体 AABB + 建筑禁入 AABB（小步推进=等价连续检测）。
## 绑定地图合同后通过 CameraPose 值对象应用/校验位姿；不持有地图节点引用。
## chapter1-2 §4.2：walk 模式 = 第一人称步行（眼高贴合行走面、踏步上下楼梯、
## 边缘阻挡防坠落）；不引入物理引擎，全部由 walk_surfaces(AABB 顶面) 数据驱动。
extends Node3D

signal pose_changed(pose: CameraPose)
signal anchors_changed(anchor_names: PackedStringArray, default_anchor: String)

const BASE_SPEED := 3.0
const BOOST_SPEED := 9.0
const SPEED_MIN := 0.5
const SPEED_MAX := 15.0
const SENSITIVITY := 0.0025
const PITCH_LIMIT := deg_to_rad(80.0)
const EXCLUSION_STEP := 0.4  # 禁入 AABB 小步检查间距（米）
const EXCLUSION_INFLATE := 0.05
const POSE_EMIT_INTERVAL := 0.1  # pose_changed 最高约 10 Hz
# ---- walk 模式合同常量（chapter1-2 §4.2；MapRoot.CONTRACT_EYE_HEIGHT 成对维护） ----
const EYE_HEIGHT := 1.62
const WALK_SPEED := 2.2
const WALK_BOOST := 4.4
const WALK_STEP_UP := 0.30      # 单帧可自动登上的高差（楼梯 0.197 ✓）
const WALK_STEP_DOWN := 0.45    # 单帧可自动落下的高差（下楼 ✓）
const WALK_FOOT_MARGIN := 0.12  # 脚掌 XZ 容差（立足点略出檐仍算站得住）
const WALK_BODY_RADIUS := 0.35  # 身体半径（水平阻挡膨胀）
const WALK_BODY_HEIGHT := 1.75  # 身体高度（用于与家具禁入盒求交）

var camera: Camera3D
var enabled := true
var move_speed_scale := 1.0

var _yaw := 0.0
var _pitch := 0.0
var _pos := Vector3.ZERO
var _keys := {}                    # Key -> bool
var _bound_map_id: StringName = &""
var _bounds := AABB()
var _exclusions: Array[AABB] = []
var _walk_mode := false
var _walk_surfaces: Array[AABB] = []
var _anchor_poses: Dictionary = {}         # StringName -> CameraPose（由 main 从 MapManager 取值注入）
var _anchor_order: PackedStringArray = []
var _default_anchor: StringName = &""
var _last_emit_sec := 0.0
var _last_emit_pos := Vector3.INF


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.3
	camera.far = 700.0
	camera.rotation_order = EulerOrder.EULER_ORDER_YXZ
	camera.name = "ObservationCamera"
	add_child(camera)


# ============================ 地图合同 ============================

func bind_map_contract(map_id: StringName, bounds: AABB, exclusions: Array[AABB], camera_mode: String = "fly", walk_surfaces: Array[AABB] = []) -> void:
	## 复制边界数组，不持有地图。
	_bound_map_id = map_id
	_bounds = bounds
	_exclusions = exclusions.duplicate()
	_walk_mode = camera_mode == "walk"
	_walk_surfaces = walk_surfaces.duplicate()
	_anchor_poses = {}
	_anchor_order = PackedStringArray()
	_default_anchor = &""


func unbind_map() -> void:
	_bound_map_id = &""
	_bounds = AABB()
	_exclusions = []
	_walk_mode = false
	_walk_surfaces = []
	_anchor_poses = {}
	_anchor_order = PackedStringArray()
	_default_anchor = &""


func is_bound() -> bool:
	return _bound_map_id != &""


func is_walk_mode() -> bool:
	return _walk_mode


## 由组合根在 map_loaded 时注入锚点位姿值（StringName -> CameraPose），供数字键/默认机位使用。
func set_anchor_poses(poses: Dictionary, default_anchor: StringName) -> void:
	_anchor_poses = poses.duplicate()
	_default_anchor = default_anchor
	var names := PackedStringArray()
	for k in poses:
		names.append(String(k))
	_anchor_order = names
	anchors_changed.emit(names, String(default_anchor))


func get_pose() -> CameraPose:
	if _bound_map_id == &"":
		return null
	return CameraPose.from_camera(_bound_map_id, camera, _current_anchor_id())


func _current_anchor_id() -> StringName:
	for k in _anchor_poses:
		var pose: CameraPose = _anchor_poses[k]
		if pose != null and pose.transform.origin.distance_to(camera.global_transform.origin) < 0.6:
			return k
	return &""


func validate_pose(pose: CameraPose) -> PackedStringArray:
	var errors: PackedStringArray = []
	if pose == null:
		return PackedStringArray(["pose 为 null"])
	if _bound_map_id == &"":
		errors.append("相机未绑定地图")
	if pose.map_id != _bound_map_id:
		errors.append("地图不匹配: %s != %s" % [pose.map_id, _bound_map_id])
	errors.append_array(pose.validate())
	# 边界（小容差：锚点/书签允许贴合边缘）
	if errors.is_empty() and _bounds.size.length() > 0.001:
		var o := pose.transform.origin
		var eps := 0.25
		if o.x < _bounds.position.x - eps or o.x > _bounds.position.x + _bounds.size.x + eps \
				or o.y < _bounds.position.y - eps or o.y > _bounds.position.y + _bounds.size.y + eps \
				or o.z < _bounds.position.z - eps or o.z > _bounds.position.z + _bounds.size.z + eps:
			errors.append("位置超出地图边界: %s" % str(o))
		for box in _exclusions:
			var inflated := (box as AABB).grow(EXCLUSION_INFLATE)
			if inflated.has_point(o):
				errors.append("位置位于禁入体积内: %s" % str(o))
				break
	return errors


## 应用位姿。无效返回错误并保持原位，不默默跳到地图中心。
func apply_pose(pose: CameraPose, immediate: bool = true) -> Error:
	var errors := validate_pose(pose)
	if not errors.is_empty():
		push_warning("ObserverCamera: 拒绝位姿 %s" % "; ".join(errors))
		return ERR_INVALID_PARAMETER
	if not immediate:
		# 仅固定机位默认 immediate；平滑路径只能沿已验证的小范围路线，暂不实现补间。
		immediate = true
	_pos = pose.transform.origin
	var fwd := -pose.transform.basis.z
	_pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_yaw = atan2(-fwd.x, -fwd.z)
	camera.fov = clampf(pose.fov_deg, CameraPose.FOV_MIN, CameraPose.FOV_MAX)
	_sync_transform()
	return OK


func set_input_enabled(flag: bool) -> void:
	enabled = flag


# ============================ 兼容适配（现有调用方） ============================

## 兼容适配：旧 set_map_data —— main.gd 已迁移到 bind_map_contract + set_anchor_poses。
func set_map_data(bounds: AABB, exclusions: Array[AABB], anchor_names: PackedStringArray, default_anchor: String, anchor_transforms: Dictionary) -> void:
	bind_map_contract(&"unknown_map", bounds, exclusions)
	var poses := {}
	for anchor in anchor_names:
		var p := CameraPose.new()
		p.map_id = &"unknown_map"
		p.anchor_id = StringName(anchor)
		p.transform = anchor_transforms.get(anchor, Transform3D())
		poses[StringName(anchor)] = p
	set_anchor_poses(poses, StringName(default_anchor))


func clear_map_data() -> void:
	unbind_map()


func go_to_anchor(anchor_name: String) -> bool:
	var key := StringName(anchor_name)
	if not _anchor_poses.has(key):
		return false
	return apply_pose(_anchor_poses[key], true) == OK


## §14.1 公开锚点接口：外部（Main/UI/自动化）禁止直接读 _anchor_order。
func get_anchor_order() -> PackedStringArray:
	return _anchor_order.duplicate()


## §14.2 数字键 1–9 统一入口：index 在当前锚点数组内 → 切换；超界 no-op。
func go_to_anchor_index(index: int) -> bool:
	if index < 0 or index >= _anchor_order.size():
		return false
	return go_to_anchor(_anchor_order[index])


func go_to_default_anchor() -> bool:
	if _default_anchor == &"":
		return false
	return go_to_anchor(String(_default_anchor))


func get_camera_global_transform() -> Transform3D:
	return camera.global_transform


## 性能路线：直接以时间 t（秒）设置相机全局变换（0..60）。受信路线，不做校验。
func set_route_transform(t: Transform3D) -> void:
	_pos = t.origin
	var fwd := -t.basis.z
	_pitch = asin(clampf(fwd.y, -1.0, 1.0))
	_yaw = atan2(-fwd.x, -fwd.z)
	_sync_transform()


func _ready() -> void:
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not enabled:
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_apply_look(event.relative)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)
	elif event is InputEventMouseButton:
		_handle_wheel(event)


func _apply_look(relative: Vector2) -> void:
	_yaw -= relative.x * SENSITIVITY
	_pitch -= relative.y * SENSITIVITY
	_pitch = clampf(_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	_sync_transform()


func _handle_wheel(event: InputEventMouseButton) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		move_speed_scale = clampf(move_speed_scale * 1.25, SPEED_MIN / BASE_SPEED, SPEED_MAX / BASE_SPEED)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		move_speed_scale = clampf(move_speed_scale * 0.8, SPEED_MIN / BASE_SPEED, SPEED_MAX / BASE_SPEED)


func handle_key(event: InputEventKey) -> void:
	## 由 Main 统一分发按键，避免与 UI 冲突。
	if event.pressed:
		_keys[event.keycode] = true
	else:
		_keys.erase(event.keycode)


func _process(_delta: float) -> void:
	if enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _walk_mode:
			_process_walk(_delta)
		else:
			_process_fly(_delta)
	# pose_changed 节流发布：有变化且距上次 ≥0.1s；静止不重复
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_emit_sec >= POSE_EMIT_INTERVAL and _pos != _last_emit_pos:
		_last_emit_sec = now
		_last_emit_pos = _pos
		pose_changed.emit(get_pose())


func _process_fly(delta: float) -> void:
	var speed := BASE_SPEED * move_speed_scale
	if _keys.get(KEY_SHIFT, false):
		speed = BOOST_SPEED * clampf(move_speed_scale, 0.5, 1.6)
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var motion := Vector3.ZERO
	if _keys.get(KEY_W, false):
		motion += forward
	if _keys.get(KEY_S, false):
		motion -= forward
	if _keys.get(KEY_D, false):
		motion += right
	if _keys.get(KEY_A, false):
		motion -= right
	if _keys.get(KEY_E, false):
		motion += Vector3.UP
	if _keys.get(KEY_Q, false):
		motion -= Vector3.UP
	if motion != Vector3.ZERO:
		motion = motion.normalized() * speed * delta
		_try_move(motion)


# ============================ walk 模式（chapter1-2 §4.2） ============================

func _process_walk(delta: float) -> void:
	var speed := WALK_SPEED * move_speed_scale
	if _keys.get(KEY_SHIFT, false):
		speed = WALK_BOOST * clampf(move_speed_scale, 0.5, 1.6)
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var motion := Vector3.ZERO
	if _keys.get(KEY_W, false):
		motion += forward
	if _keys.get(KEY_S, false):
		motion -= forward
	if _keys.get(KEY_D, false):
		motion += right
	if _keys.get(KEY_A, false):
		motion -= right
	# Q/E 在 walk 模式无效（不飞行）
	if motion != Vector3.ZERO:
		motion = motion.normalized() * speed * delta
		walk_move(motion)


## 步行位移（可测试入口）：水平排斥（身体盒 vs 禁入 AABB，小步推进）+ 地面贴合。
## 拟落点无地面或高差超出 [STEP_DOWN, STEP_UP] → 取消本帧水平位移（边缘阻挡）。
func walk_move(motion: Vector3) -> void:
	if not _walk_mode or motion.length() < 0.0001:
		_sync_transform()
		return
	var start := _pos
	var target := start + Vector3(motion.x, 0.0, motion.z)
	# 整体边界
	if _bounds.size.length() > 0.001:
		target.x = clampf(target.x, _bounds.position.x, _bounds.position.x + _bounds.size.x)
		target.z = clampf(target.z, _bounds.position.z, _bounds.position.z + _bounds.size.z)
	# 身体盒扫掠：小步推进，撞到禁入盒即停在之前
	target = _sweep_body(start, target)
	if target.x == start.x and target.z == start.z:
		_snap_to_ground()
		_sync_transform()
		return
	# 地面贴合 / 边缘阻挡
	var feet := start.y - EYE_HEIGHT
	var ground := _ground_top_at(target.x, target.z, feet)
	if ground == -INF:
		target = start  # 无立足面：取消位移
	elif feet - ground > WALK_STEP_DOWN:
		target = start  # 落差过大（楼梯井/二层边缘外）：取消位移
	else:
		_pos = Vector3(target.x, ground + EYE_HEIGHT, target.z)
		_sync_transform()
		return
	_snap_to_ground()
	_sync_transform()


func _snap_to_ground() -> void:
	## 原地把眼高贴合到当前立足面（处理地面数据微调后的悬空）。
	var ground := _ground_top_at(_pos.x, _pos.z, _pos.y - EYE_HEIGHT)
	if ground != -INF and absf(ground + EYE_HEIGHT - _pos.y) <= WALK_STEP_DOWN:
		_pos.y = ground + EYE_HEIGHT


func _sweep_body(from: Vector3, to: Vector3) -> Vector3:
	## 沿水平段小步推进；身体盒 = (x±r, feet+0.05..feet+1.75, z±r) 与禁入盒求交即停。
	if _exclusions.is_empty():
		return to
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	if dist < 0.0001:
		return from
	var feet := from.y - EYE_HEIGHT
	var steps := maxi(1, ceili(dist / 0.2))
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var px := lerpf(from.x, to.x, t)
		var pz := lerpf(from.z, to.z, t)
		var body := AABB(Vector3(px - WALK_BODY_RADIUS, feet + 0.05, pz - WALK_BODY_RADIUS),
				Vector3(WALK_BODY_RADIUS * 2.0, WALK_BODY_HEIGHT, WALK_BODY_RADIUS * 2.0))
		var blocked := false
		for box in _exclusions:
			if body.intersects(box as AABB):
				blocked = true
				break
		if blocked:
			var prev_t := float(i - 1) / float(steps)
			return Vector3(lerpf(from.x, to.x, prev_t), from.y, lerpf(from.z, to.z, prev_t))
	return to


## 立足面查询：XZ 含点（外扩 FOOT_MARGIN）且 top ≤ feet+STEP_UP 的最高顶面；无则 -INF。
func _ground_top_at(x: float, z: float, feet: float) -> float:
	var best := -INF
	for s in _walk_surfaces:
		var box: AABB = s.grow(0.0)
		var xz := AABB(Vector3(box.position.x - WALK_FOOT_MARGIN, box.position.y, box.position.z - WALK_FOOT_MARGIN),
				Vector3(box.size.x + WALK_FOOT_MARGIN * 2.0, box.size.y, box.size.z + WALK_FOOT_MARGIN * 2.0))
		if xz.has_point(Vector3(x, box.position.y, z)):
			var top := box.position.y + box.size.y
			if top <= feet + WALK_STEP_UP and top > best:
				best = top
	return best


func _try_move(motion: Vector3) -> void:
	var target := _pos + motion
	# 整体边界（无地图数据时不夹持）
	if _bounds.size.length() > 0.001:
		target.x = clampf(target.x, _bounds.position.x, _bounds.position.x + _bounds.size.x)
		target.y = clampf(target.y, _bounds.position.y, _bounds.position.y + _bounds.size.y)
		target.z = clampf(target.z, _bounds.position.z, _bounds.position.z + _bounds.size.z)
	# 禁入 AABB：小步推进，拒绝进入楼体
	if _exclusions.is_empty():
		_pos = target
		_sync_transform()
		return
	var dist := target.distance_to(_pos)
	if dist < 0.001:
		_sync_transform()
		return
	var dir := (target - _pos).normalized()
	var travelled := 0.0
	var probe := _pos
	while travelled < dist:
		var step_len: float = minf(EXCLUSION_STEP, dist - travelled)
		var next := probe + dir * step_len
		var blocked := false
		for box in _exclusions:
			if box is AABB:
				var b: AABB = box
				var start_inside := b.has_point(_pos)
				var next_inside := b.has_point(next)
				if next_inside and not start_inside:
					blocked = true
					break
		if blocked:
			break
		probe = next
		travelled += step_len
	_pos = probe
	_sync_transform()


func _sync_transform() -> void:
	camera.position = _pos
	camera.rotation = Vector3(_pitch, _yaw, 0.0)
