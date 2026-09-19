## 统一地图根节点脚本。所有地图根节点必须使用本脚本并加入 active_map_root 组。
## 职责：暴露锚点变换、按画质档开关非烘焙内容、干净地停掉地图内动画。
class_name MapRoot
extends Node3D

## 环境动画子节点名列表（Ambient 下），卸载时统一停掉。
var _ambient: Node3D = null
var _tweens: Array[Tween] = []
var _quality_profile: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("active_map_root")


func _ready() -> void:
	_ambient = get_node_or_null("Ambient")
	_setup_ambient()


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
	var m := anchors.get_node_or_null(NodePath(anchor_name))
	return m is Marker3D


## 画质档应用。profile 由 SettingsManager 提供，包含：
## particles / probes / extra_lights / glow / detail_prop_range
func apply_quality(profile: Dictionary) -> void:
	_quality_profile = profile
	_apply_group_visibility("q_particle", bool(profile.get("particles", false)))
	_apply_group_visibility("q_extra_light", bool(profile.get("extra_lights", false)))
	_apply_group_visibility("q_probe", bool(profile.get("probes", false)))
	_apply_group_visibility("q_runtime_light", false)  # 烘焙灯运行期一律隐藏
	var env_node := get_node_or_null("Environment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		env_node.environment.glow_enabled = bool(profile.get("glow", false))
	var range_end: float = float(profile.get("detail_prop_range", 150.0))
	for node in get_tree().get_nodes_in_group("detail_props"):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).visibility_range_end = range_end
	if _ambient != null:
		_ambient.visible = true
		for child in _ambient.get_children():
			if child is GPUParticles3D:
				(child as GPUParticles3D).emitting = bool(profile.get("particles", false))


## 停止地图内全部动画与粒子（卸载前调用；幂等）。
func shutdown() -> void:
	for tw in _tweens:
		if tw is Tween and tw.is_valid():
			tw.kill()
	_tweens.clear()
	if _ambient != null:
		for child in _ambient.get_children():
			if child is GPUParticles3D:
				(child as GPUParticles3D).emitting = false
			elif child is AnimationPlayer:
				(child as AnimationPlayer).stop()
	set_process(false)


func register_tween(tw: Tween) -> void:
	_tweens.append(tw)


func _apply_group_visibility(group_name: String, visible_flag: bool) -> void:
	## 只处理本地图子树内的节点，避免误伤外壳。
	for node in get_tree().get_nodes_in_group(group_name):
		var n := node as Node3D
		if n != null and is_ancestor_of(n):
			n.visible = visible_flag


func _setup_ambient() -> void:
	## 少量可关闭环境动画：本地图最多 6 个动画节点、2 个局部粒子。
	if _ambient == null:
		return
	for child in _ambient.get_children():
		if child is GPUParticles3D:
			continue
		if child is MeshInstance3D and child.get_meta("anim_rotate", false):
			var axis: String = str(child.get_meta("anim_axis", "y"))
			var tw := create_tween().set_loops()
			tw.tween_property(child, "rotation:" + axis, TAU, float(child.get_meta("anim_speed", 4.0)))
			register_tween(tw)
		elif child is MeshInstance3D and child.get_meta("anim_flicker", false):
			var mat: Material = (child as MeshInstance3D).material_override
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var base_energy: float = sm.emission_energy_multiplier
				var tw := create_tween().set_loops()
				tw.tween_property(sm, "emission_energy_multiplier", base_energy * 0.35, 0.15).set_delay(randf_range(2.0, 5.0))
				tw.tween_property(sm, "emission_energy_multiplier", base_energy, 0.08).set_delay(0.35)
				register_tween(tw)
