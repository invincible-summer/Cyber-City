## CameraPose 值对象：相机姿态快照，不含 Node/Resource 引用（chapter1-1 §7.2）。
## JSON 序列化：位置 [x,y,z]、旋转归一化四元数 [x,y,z,w]；反序列化显式校验。
class_name CameraPose
extends RefCounted

const FOV_MIN := 20.0
const FOV_MAX := 100.0

var map_id: StringName = &""
var anchor_id: StringName = &""       # 固定机位 ID；自由机位为空
var transform: Transform3D = Transform3D()
var fov_deg: float = 60.0
var near_m: float = 0.3
var far_m: float = 700.0
var keep_aspect: int = 1              # Camera3D.KEEP_HEIGHT


static func from_camera(map_id: StringName, camera: Camera3D, anchor_id: StringName = &"") -> CameraPose:
	var p := CameraPose.new()
	p.map_id = map_id
	p.anchor_id = anchor_id
	p.transform = camera.global_transform
	p.fov_deg = camera.fov
	p.near_m = camera.near
	p.far_m = camera.far
	p.keep_aspect = camera.keep_aspect
	return p


func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	if map_id == &"":
		errors.append("map_id 为空")
	if not _vec3_finite(transform.origin):
		errors.append("位置含非有限数值")
	if not _basis_finite(transform.basis):
		errors.append("旋转基含非有限数值")
	if transform.basis.determinant() <= 0.0:
		errors.append("旋转基行列式非正（镜像或退化）")
	if not is_finite(fov_deg) or fov_deg < FOV_MIN or fov_deg > FOV_MAX:
		errors.append("FOV 超出允许范围: %s" % str(fov_deg))
	if not is_finite(near_m) or not is_finite(far_m) or near_m <= 0.0 or far_m <= near_m:
		errors.append("near/far 非法: %s / %s" % [str(near_m), str(far_m)])
	return errors


## 可序列化表示（书签 JSON / 截图元数据共用）。
func to_dict() -> Dictionary:
	var q := transform.basis.get_rotation_quaternion().normalized()
	return {
		"map_id": String(map_id),
		"anchor_id": String(anchor_id),
		"position": [transform.origin.x, transform.origin.y, transform.origin.z],
		"quaternion": [q.x, q.y, q.z, q.w],
		"fov_deg": fov_deg,
		"near_m": near_m,
		"far_m": far_m,
		"keep_aspect": keep_aspect,
	}


## 从 Dictionary 解析。任何字段缺失/非法返回 null（调用方提示"书签不存在或数据无效"）。
static func from_dict(data: Variant) -> CameraPose:
	if not data is Dictionary:
		return null
	var d: Dictionary = data
	var pose := CameraPose.new()
	pose.map_id = StringName(str(d.get("map_id", "")))
	pose.anchor_id = StringName(str(d.get("anchor_id", "")))
	var pos_v: Variant = d.get("position")
	var pos_v3: Variant = _parse_vec3(pos_v)
	if pos_v3 == null:
		return null
	var pos: Vector3 = pos_v3
	var quat_v: Variant = d.get("quaternion")
	if not quat_v is Array or (quat_v as Array).size() != 4:
		return null
	var comps: Array[float] = []
	for v in quat_v:
		var f := float(v)
		if not is_finite(f):
			return null
		comps.append(f)
	var quat := Quaternion(comps[0], comps[1], comps[2], comps[3])
	var qlen := quat.length()
	if not is_finite(qlen) or qlen < 0.9 or qlen > 1.1:
		return null  # 零四元数或明显非法长度拒绝
	quat = quat.normalized()
	pose.transform = Transform3D(Basis(quat), pos)
	pose.fov_deg = float(d.get("fov_deg", 60.0))
	pose.near_m = float(d.get("near_m", 0.3))
	pose.far_m = float(d.get("far_m", 700.0))
	pose.keep_aspect = int(d.get("keep_aspect", 1))
	if not pose.validate().is_empty():
		return null
	return pose


static func _parse_vec3(v: Variant) -> Variant:
	if not v is Array or (v as Array).size() != 3:
		return null
	var out := Vector3.ZERO
	for i in 3:
		var f := float(v[i])
		if not is_finite(f):
			return null
		out[i] = f
	return out


static func _vec3_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _basis_finite(b: Basis) -> bool:
	## 4.7.2 GDScript 不暴露 Basis.rows；用坐标轴向量逐项检查。
	return _vec3_finite(b.x) and _vec3_finite(b.y) and _vec3_finite(b.z)
