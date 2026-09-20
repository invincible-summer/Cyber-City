## 统一地图根节点脚本。所有地图根节点必须使用本脚本并加入 active_map_root 组。
## 职责（chapter1-1 §7.4）：暴露锚点/边界值、运行时合同校验、按画质档开关可选内容、
## 环境动画的状态快照与恢复、干净的失活流程（begin_deactivation 幂等）。
class_name MapRoot
extends Node3D

## 由 MapManager 注入；验证与快照恢复需要它。MapRoot 不据此持有场景资源。
var definition: MapDefinition = null

var _ambient: Node3D = null
var _tweens: Array[Tween] = []
var _quality_profile: Dictionary = {}
var _deactivated := false
## 环境动画登记表：[{id, node, kind:"rotate"/"flicker", tween, speed, base_energy, axis}]
var _ambient_items: Array[Dictionary] = []
## 粒子登记表：[{id, node, desired_emitting}]
var _ambient_particles: Array[Dictionary] = []
var _ambient_paused := false
var _ambient_fixed_time := -1.0


func _enter_tree() -> void:
	add_to_group("active_map_root")


func _ready() -> void:
	_ambient = get_node_or_null("Ambient")
	_setup_ambient()


# ============================ 合同校验 ============================

func validate_runtime_contract() -> PackedStringArray:
	## 返回错误列表；空列表表示通过。检查锚点、环境、bounds、烘焙数据与区域路径。
	var errors: PackedStringArray = []
	if definition == null:
		errors.append("缺少 MapDefinition 引用")
		return errors
	# 锚点唯一且可用
	var seen := {}
	for anchor_id in definition.anchor_names:
		var key := str(anchor_id)
		if seen.has(key):
			errors.append("锚点重复声明: %s" % key)
		seen[key] = true
		if not has_anchor(key):
			errors.append("缺少锚点: %s" % key)
	var anchors_node := get_node_or_null("CameraAnchors")
	if anchors_node != null:
		for child in anchors_node.get_children():
			if child is Marker3D and not seen.has(str(child.name)):
				errors.append("场景中存在未声明的锚点: %s" % child.name)
	# 环境数量恰好 1
	var env_count := _world_environment_count(self)
	if env_count != 1:
		errors.append("WorldEnvironment 数量为 %d（应为 1）" % env_count)
	# 边界
	if definition.camera_bounds.size.x <= 0.0 or definition.camera_bounds.size.y <= 0.0 or definition.camera_bounds.size.z <= 0.0:
		errors.append("camera_bounds 尺寸非法")
	# 烘焙数据
	if definition.requires_baked_lighting:
		var lm := _find_lightmap_gi(self)
		if lm == null:
			errors.append("requires_baked_lighting=true 但未找到 LightmapGI")
		elif lm.light_data == null:
			errors.append("LightmapGI 缺少 light_data（烘焙数据未就绪）")
	# 区域清单
	if not definition.region_manifest_path.is_empty() and not FileAccess.file_exists(definition.region_manifest_path):
		errors.append("region_manifest_path 不存在: %s" % definition.region_manifest_path)
	return errors


func _world_environment_count(node: Node) -> int:
	var count := 1 if node is WorldEnvironment else 0
	for child in node.get_children():
		count += _world_environment_count(child)
	return count


func _find_lightmap_gi(node: Node) -> LightmapGI:
	if node is LightmapGI:
		return node
	for child in node.get_children():
		var found := _find_lightmap_gi(child)
		if found != null:
			return found
	return null


# ============================ 锚点与边界 ============================

func get_anchor_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	if definition != null and not definition.anchor_names.is_empty():
		for a in definition.anchor_names:
			ids.append(StringName(str(a)))
		return ids
	# 无定义时回退场景枚举
	var anchors := get_node_or_null("CameraAnchors")
	if anchors != null:
		for child in anchors.get_children():
			if child is Marker3D:
				ids.append(StringName(child.name))
	return ids


func get_anchor_transform(anchor_name: String) -> Transform3D:
	## 返回锚点的全局变换副本；不把 Marker3D 引用交给外部长期持有。
	var anchors := get_node_or_null("CameraAnchors")
	if anchors == null:
		return Transform3D()
	var m := anchors.get_node_or_null(NodePath(anchor_name))
	if m is Marker3D:
		return (m as Marker3D).global_transform
	return Transform3D()


func has_anchor(anchor_name: String) -> bool:
	var anchors := get_node_or_null("CameraAnchors")
	if anchors == null:
		return false
	return anchors.get_node_or_null(NodePath(anchor_name)) is Marker3D


func get_anchor_pose(anchor_id: StringName) -> CameraPose:
	if not has_anchor(String(anchor_id)):
		return null
	var map_id: StringName = &"" if definition == null else StringName(definition.map_id)
	var pose := CameraPose.new()
	pose.map_id = map_id
	pose.anchor_id = anchor_id
	pose.transform = get_anchor_transform(String(anchor_id))
	return pose


func get_camera_bounds() -> AABB:
	if definition == null:
		return AABB()
	return definition.camera_bounds


func get_camera_exclusion_bounds() -> Array[AABB]:
	if definition == null:
		return []
	return definition.camera_exclusion_bounds.duplicate()


# ============================ 画质档应用 ============================

## 画质档应用。profile 由 QualityController 提供，包含：
## particles / probes / extra_lights / glow / detail_prop_range
## 关闭可选功能只改运行时状态，不改写磁盘资产或共享材质权威值。
func apply_quality(profile: Dictionary) -> Error:
	if profile.is_empty():
		return ERR_INVALID_PARAMETER
	_quality_profile = profile
	_apply_group_visibility("optional_particle", bool(profile.get("particles", false)))
	_apply_group_visibility("runtime_fill_light", bool(profile.get("extra_lights", false)))
	_apply_group_visibility("optional_probe", bool(profile.get("probes", false)))
	_apply_group_visibility("bake_only_light", false)  # 制作灯运行期一律隐藏（FIX-07）
	var env_node := get_node_or_null("Environment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		env_node.environment.glow_enabled = bool(profile.get("glow", false))
	var range_end: float = float(profile.get("detail_prop_range", 150.0))
	for node in get_tree().get_nodes_in_group("detail_props"):
		if node is GeometryInstance3D and is_ancestor_of(node):
			(node as GeometryInstance3D).visibility_range_end = range_end
	_apply_region_detail_ranges(range_end)
	for item in _ambient_particles:
		var p := item["node"] as GPUParticles3D
		if p != null and is_instance_valid(p):
			var desired: bool = bool(profile.get("particles", false))
			item["desired_emitting"] = desired
			p.emitting = desired and not _ambient_paused
	if _ambient != null:
		_ambient.visible = true
	return OK


## 区域小装饰可见距离（chapter1-1 §6.3）：只影响 region manifest 标记的 detail 根，
## 不控制建筑/地面/主要家具。迟滞由 visibility_range_end + begin margin 实现。
func _apply_region_detail_ranges(default_end: float) -> void:
	if definition == null or definition.region_manifest_path.is_empty():
		return
	var txt := FileAccess.get_file_as_string(definition.region_manifest_path)
	if txt.is_empty():
		return
	var parsed = JSON.parse_string(txt)
	if not parsed is Dictionary:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	for region in parsed.get("regions", []):
		if not region is Dictionary:
			continue
		var root_path: String = str(region.get("detail_root_path", ""))
		var root := get_node_or_null(root_path)
		if root == null:
			continue
		var end_m: float = float(region.get("balanced_detail_end_m", default_end))
		if _quality_profile.get("id", "eco") == "eco":
			end_m = float(region.get("eco_detail_end_m", default_end * 0.4))
		_set_detail_range_recursive(root, end_m, cam)


func _set_detail_range_recursive(node: Node, end_m: float, cam: Camera3D) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.visibility_range_end = end_m
		# 迟滞：begin 提前 5 米淡出边界，避免边界闪烁
		gi.visibility_range_begin = 0.0
	for child in node.get_children():
		_set_detail_range_recursive(child, end_m, cam)


func _apply_group_visibility(group_name: String, visible_flag: bool) -> void:
	## 只处理本地图子树内的节点，避免误伤外壳。
	for node in get_tree().get_nodes_in_group(group_name):
		var n := node as Node3D
		if n != null and is_ancestor_of(n):
			n.visible = visible_flag


# ============================ 环境动画：暂停 / 固定时间 / 快照 ============================

func _setup_ambient() -> void:
	## 少量可关闭环境动画：本地图最多 6 个动画节点、2 个局部粒子。
	if _ambient == null:
		return
	for child in _ambient.get_children():
		if child is GPUParticles3D:
			_ambient_particles.append({"id": String(_stable_id(child)), "node": child, "desired_emitting": false})
			child.add_to_group("optional_particle")
			child.emitting = false
		elif child is MeshInstance3D and child.get_meta("anim_rotate", false):
			var axis: String = str(child.get_meta("anim_axis", "y"))
			var speed: float = float(child.get_meta("anim_speed", 4.0))
			var tw := create_tween().set_loops()
			tw.tween_property(child, "rotation:" + axis, TAU, speed).from(0.0)
			_tweens.append(tw)
			_ambient_items.append({"id": String(_stable_id(child)), "node": child, "kind": "rotate", "tween": tw, "axis": axis, "speed": speed})
			child.add_to_group("ambient_animation")
		elif child is MeshInstance3D and child.get_meta("anim_flicker", false):
			var mat: Material = (child as MeshInstance3D).material_override
			var base_energy := 1.0
			if mat is StandardMaterial3D:
				base_energy = (mat as StandardMaterial3D).emission_energy_multiplier
			var tw := _create_flicker_tween(mat, base_energy)
			_tweens.append(tw)
			_ambient_items.append({"id": String(_stable_id(child)), "node": child, "kind": "flicker", "tween": tw, "material": mat, "base_energy": base_energy})
			child.add_to_group("ambient_animation")


func _create_flicker_tween(mat: Material, base_energy: float) -> Tween:
	var tw := create_tween().set_loops()
	tw.tween_property(mat, "emission_energy_multiplier", base_energy * 0.35, 0.15).set_delay(randf_range(2.0, 5.0))
	tw.tween_property(mat, "emission_energy_multiplier", base_energy, 0.08).set_delay(0.35)
	return tw


func _stable_id(node: Node) -> StringName:
	## 稳定 ID：从语义路径生成，不依赖遍历顺序编号。
	var path := String(node.get_path())
	# 场景实例化后路径含 MapSlot 等外壳前缀，截去地图根以上部分
	var root_path := String(get_path())
	if path.begins_with(root_path + "/"):
		path = path.substr(root_path.length() + 1)
	return StringName(path)


func set_ambient_paused(paused: bool) -> void:
	_ambient_paused = paused
	for item in _ambient_items:
		var tw: Tween = item.get("tween")
		if tw != null and tw.is_valid():
			if paused:
				tw.pause()
			elif _ambient_fixed_time < 0.0:
				tw.play()
	for item in _ambient_particles:
		var p := item["node"] as GPUParticles3D
		if p != null and is_instance_valid(p):
			p.emitting = bool(item.get("desired_emitting", false)) and not paused


## 固定采样时间：终止动画并落到确定状态（基准/截图对齐用）。
## seconds 之后的动画保持静止；恢复需 restore_ambient_state 或重新进入地图。
func set_ambient_time(seconds: float) -> void:
	_ambient_fixed_time = maxf(0.0, seconds)
	for item in _ambient_items:
		var tw: Tween = item.get("tween")
		if tw != null and tw.is_valid():
			tw.kill()
		var node: Node3D = item["node"]
		if not is_instance_valid(node):
			continue
		match str(item["kind"]):
			"rotate":
				var speed: float = item["speed"]
				node.rotation[str(item["axis"])] = fmod(seconds / maxf(0.01, speed), 1.0) * TAU
			"flicker":
				var mat: Material = item["material"]
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).emission_energy_multiplier = float(item["base_energy"])
	for item in _ambient_particles:
		var p := item["node"] as GPUParticles3D
		if p != null and is_instance_valid(p):
			p.emitting = false


func get_ambient_state() -> Dictionary:
	var items: Array = []
	for item in _ambient_items:
		var entry := {
			"id": str(item["id"]),
			"kind": str(item["kind"]),
			"playing": _ambient_fixed_time < 0.0 and not _ambient_paused,
		}
		var node: Node3D = item["node"]
		if node != null and is_instance_valid(node):
			match str(item["kind"]):
				"rotate":
					var speed: float = item["speed"]
					entry["time_sec"] = fmod(float(node.rotation[str(item["axis"])]), TAU) / TAU * speed
				"flicker":
					entry["time_sec"] = 0.0
		items.append(entry)
	var emitters: Array = []
	for item in _ambient_particles:
		var p := item["node"] as GPUParticles3D
		if p != null and is_instance_valid(p):
			emitters.append({"id": str(item["id"]), "emitting": p.emitting})
	var map_id: String = definition.map_id if definition != null else ""
	return {"map_id": map_id, "items": items, "emitters": emitters}


func restore_ambient_state(snapshot: Dictionary) -> Error:
	if snapshot.is_empty():
		return ERR_INVALID_PARAMETER
	var my_map_id: String = definition.map_id if definition != null else ""
	if str(snapshot.get("map_id", "")) != my_map_id:
		push_warning("MapRoot: 环境快照属于地图 %s，拒绝恢复到 %s" % [str(snapshot.get("map_id", "")), my_map_id])
		return ERR_INVALID_PARAMETER
	_ambient_fixed_time = -1.0
	var by_id := {}
	for item in _ambient_items:
		by_id[str(item["id"])] = item
	var restored_any := false
	for entry in snapshot.get("items", []):
		if not entry is Dictionary:
			continue
		var id := str(entry.get("id", ""))
		if not by_id.has(id):
			continue  # 缺失对象：跳过并继续恢复其余项
		var item: Dictionary = by_id[id]
		var old_tw: Tween = item.get("tween")
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
		if bool(entry.get("playing", true)):
			var tw: Tween
			match str(item["kind"]):
				"rotate":
					tw = create_tween().set_loops()
					tw.tween_property(item["node"], "rotation:" + str(item["axis"]), TAU, float(item["speed"])).from(0.0)
				"flicker":
					tw = _create_flicker_tween(item["material"], float(item["base_energy"]))
			item["tween"] = tw
			if not _tweens.has(tw):
				_tweens.append(tw)
			restored_any = true
	for emitter in snapshot.get("emitters", []):
		if not emitter is Dictionary:
			continue
		for item in _ambient_particles:
			if str(item["id"]) == str(emitter.get("id", "")):
				var p := item["node"] as GPUParticles3D
				if p != null and is_instance_valid(p):
					item["desired_emitting"] = bool(emitter.get("emitting", false))
					p.emitting = item["desired_emitting"] and not _ambient_paused
					restored_any = true
	return OK if restored_any or not snapshot.get("items", []).is_empty() else ERR_INVALID_PARAMETER


func register_tween(tw: Tween) -> void:
	_tweens.append(tw)


# ============================ 失活 ============================

## 卸载前调用（幂等）：停止地图内 Timer/Tween/动画/粒子/音频，
## 不清空仍被其他系统使用的全局资源缓存。
func begin_deactivation() -> void:
	if _deactivated:
		return
	_deactivated = true
	for tw in _tweens:
		if tw is Tween and tw.is_valid():
			tw.kill()
	_tweens.clear()
	for item in _ambient_items:
		item["tween"] = null
	if _ambient != null:
		for child in _ambient.get_children():
			if child is GPUParticles3D:
				(child as GPUParticles3D).emitting = false
			elif child is AnimationPlayer:
				(child as AnimationPlayer).stop()
			elif child is AudioStreamPlayer3D:
				(child as AudioStreamPlayer3D).stop()
	for child in get_children():
		_stop_timers_recursive(child)
	set_process(false)
	set_physics_process(false)


func _stop_timers_recursive(node: Node) -> void:
	if node is Timer:
		(node as Timer).stop()
	for child in node.get_children():
		_stop_timers_recursive(child)
