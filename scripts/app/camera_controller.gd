## 受限自由观察摄影机：右键拖动转向，WASD/QE 移动，整体 AABB + 建筑禁入 AABB。
## 移动使用 delta，与帧率无关；机位切换只保存 Transform3D，不持有旧地图锚点。
extends Node3D

const BASE_SPEED := 3.0
const BOOST_SPEED := 9.0
const SPEED_MIN := 0.5
const SPEED_MAX := 15.0
const SENSITIVITY := 0.0025
const PITCH_LIMIT := deg_to_rad(80.0)
const EXCLUSION_STEP := 0.4  # 禁入 AABB 小步检查间距（米）

signal anchors_changed(anchor_names: PackedStringArray, default_anchor: String)

var camera: Camera3D
var enabled := true
var move_speed_scale := 1.0

var _yaw := 0.0
var _pitch := 0.0
var _pos := Vector3.ZERO
var _keys := {}                    # Key -> bool
var _bounds := AABB()
var _exclusions: Array[AABB] = []
var _anchor_transforms: Dictionary = {}  # name -> Transform3D
var _anchor_order: PackedStringArray = []
var _default_anchor := ""


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.3
	camera.far = 700.0
	camera.rotation_order = EulerOrder.EULER_ORDER_YXZ
	camera.name = "ObservationCamera"
	add_child(camera)


func set_map_data(bounds: AABB, exclusions: Array[AABB], anchor_names: PackedStringArray, default_anchor: String, anchor_transforms: Dictionary) -> void:
	_bounds = bounds
	_exclusions = exclusions.duplicate()
	_anchor_order = anchor_names
	_default_anchor = default_anchor
	_anchor_transforms = anchor_transforms
	anchors_changed.emit(anchor_names, default_anchor)


func clear_map_data() -> void:
	_bounds = AABB()
	_exclusions = []
	_anchor_transforms = {}
	_anchor_order = PackedStringArray()
	_default_anchor = ""


func go_to_anchor(anchor_name: String) -> bool:
	if not _anchor_transforms.has(anchor_name):
		return false
	var t: Transform3D = _anchor_transforms[anchor_name]
	_pos = t.origin
	var fwd := -t.basis.z
	_pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_yaw = atan2(-fwd.x, -fwd.z)
	_sync_transform()
	return true


func go_to_default_anchor() -> bool:
	return go_to_anchor(_default_anchor)


func get_camera_global_transform() -> Transform3D:
	return camera.global_transform


## 性能路线：直接以时间 t（秒）设置相机全局变换（0..60）。
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


func _process(delta: float) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
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
	if motion == Vector3.ZERO:
		return
	motion = motion.normalized() * speed * delta
	_try_move(motion)


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
