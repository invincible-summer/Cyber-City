## 受限自由观察摄影机（chapter1-1 §7.6 ObserverCamera 合同）。
## 右键拖动转向，WASD/QE 移动；整体 AABB + 建筑禁入 AABB（小步推进=等价连续检测）。
## 绑定地图合同后通过 CameraPose 值对象应用/校验位姿；不持有地图节点引用。
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

func bind_map_contract(map_id: StringName, bounds: AABB, exclusions: Array[AABB]) -> void:
	## 复制边界数组，不持有地图。
	_bound_map_id = map_id
	_bounds = bounds
	_exclusions = exclusions.duplicate()
	_anchor_poses = {}
	_anchor_order = PackedStringArray()
	_default_anchor = &""


func unbind_map() -> void:
	_bound_map_id = &""
	_bounds = AABB()
	_exclusions = []
	_anchor_poses = {}
	_anchor_order = PackedStringArray()
	_default_anchor = &""


func is_bound() -> bool:
	return _bound_map_id != &""


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
			motion = motion.normalized() * speed * _delta
			_try_move(motion)
	# pose_changed 节流发布：有变化且距上次 ≥0.1s；静止不重复
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_emit_sec >= POSE_EMIT_INTERVAL and _pos != _last_emit_pos:
		_last_emit_sec = now
		_last_emit_pos = _pos
		pose_changed.emit(get_pose())


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
