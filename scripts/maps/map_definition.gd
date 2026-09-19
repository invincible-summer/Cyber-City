## 地图定义：轻量数据资源，只保存字符串路径与边界数据。
## 禁止持有 PackedScene、材质或 lightmap 数据（AGENTS.md §6.1）。
class_name MapDefinition
extends Resource

@export var schema_version: int = 1
@export var map_id: String = ""
@export var display_name: String = ""
@export var scene_path: String = ""
@export var preview_path: String = ""
@export var default_anchor: String = ""
@export var camera_bounds: AABB = AABB(Vector3(-50.0, 1.5, -70.0), Vector3(100.0, 22.5, 140.0))
@export var camera_exclusion_bounds: Array[AABB] = []
@export var anchor_names: PackedStringArray = []
@export var lighting_profile_id: String = ""
@export var available: bool = true


static func make_stub(id: String, display: String, scene: String, default_anchor_name: String) -> MapDefinition:
	var def := MapDefinition.new()
	def.map_id = id
	def.display_name = display
	def.scene_path = scene
	def.default_anchor = default_anchor_name
	return def


func validate() -> String:
	## 返回空字符串表示定义本身合法，否则返回可读原因。
	if map_id.is_empty():
		return "map_id 为空"
	if scene_path.is_empty() or not scene_path.begins_with("res://"):
		return "scene_path 非法: %s" % scene_path
	if not default_anchor.is_empty() and not anchor_names.is_empty():
		if not anchor_names.has(default_anchor):
			return "default_anchor 不在 anchor_names 中"
	return ""
