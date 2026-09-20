## 地图定义：轻量数据资源，只保存字符串路径与边界数据。
## 禁止持有 PackedScene、材质或 lightmap 数据（AGENTS.md §6.1）。
## schema_version 2（chapter1-1 §6.3）：新增 content_revision / region_manifest_path /
## occlusion_enabled / bookmark_schema_version / capture_anchor_names / requires_baked_lighting。
## v1 文件读取时新字段自动落默认值；超过 2 的版本在 validate() 中明确拒绝。
class_name MapDefinition
extends Resource

@export var schema_version: int = 2
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

# ---- v2 新增字段 ----
@export var content_revision: String = "1.0.0"
@export var region_manifest_path: String = ""
@export var occlusion_enabled: bool = true
@export var bookmark_schema_version: int = 1
## 仅当确有不同用途时填写；为空则回落 anchor_names（权威字段），不双份维护。
@export var capture_anchor_names: PackedStringArray = []
@export var requires_baked_lighting: bool = false


static func make_stub(id: String, display: String, scene: String, default_anchor_name: String) -> MapDefinition:
	var def := MapDefinition.new()
	def.map_id = id
	def.display_name = display
	def.scene_path = scene
	def.default_anchor = default_anchor_name
	return def


## 权威锚点列表 = anchor_names；capture 列表通过访问器回落，避免两份手工维护。
func get_capture_anchor_names() -> PackedStringArray:
	return capture_anchor_names if not capture_anchor_names.is_empty() else anchor_names


func validate() -> String:
	## 返回空字符串表示定义本身合法，否则返回可读原因。
	if schema_version < 1:
		return "schema_version 非法: %d" % schema_version
	if schema_version > 2:
		return "不支持的 schema_version: %d（本程序最高支持 2）" % schema_version
	if map_id.is_empty():
		return "map_id 为空"
	if scene_path.is_empty() or not scene_path.begins_with("res://"):
		return "scene_path 非法: %s" % scene_path
	if not default_anchor.is_empty() and not anchor_names.is_empty():
		if not anchor_names.has(default_anchor):
			return "default_anchor 不在 anchor_names 中"
	if camera_bounds.size.x <= 0.0 or camera_bounds.size.y <= 0.0 or camera_bounds.size.z <= 0.0:
		return "camera_bounds 尺寸非法: %s" % str(camera_bounds.size)
	for i in anchor_names.size():
		if str(anchor_names[i]).is_empty():
			return "anchor_names 第 %d 项为空" % i
	return ""
