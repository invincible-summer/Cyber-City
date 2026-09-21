## 地图定义：轻量数据资源，只保存字符串路径与边界数据。
## 禁止持有 PackedScene、材质或 lightmap 数据（AGENTS.md §6.1）。
## schema_version 2（chapter1-1 §6.3）：新增 content_revision / region_manifest_path /
## occlusion_enabled / bookmark_schema_version / capture_anchor_names / requires_baked_lighting。
## v1 文件读取时新字段自动落默认值；超过 2 的版本在 validate() 中明确拒绝。
## chapter1-2 §4 扩展（仍属 v2，缺省即旧语义）：camera_mode / walk_surfaces / portals。
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

# ---- chapter1-2 §4 扩展（向后兼容缺省） ----
## "fly"（默认，受限自由飞行）| "walk"（第一人称步行：重力贴合行走面、踏步上楼梯）。
@export var camera_mode: String = "fly"
## walk 模式可行走面：每个 AABB 的顶面 = 可立足面（XZ 含点判定）。fly 图留空。
@export var walk_surfaces: Array[AABB] = []
## 门户（门 + F 键切换地图）：{pos: Vector3, radius: float, target_map_id: String,
## target_anchor: String, label: String}。只存值，不持有节点。
@export var portals: Array[Dictionary] = []


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
	if camera_mode != "fly" and camera_mode != "walk":
		return "camera_mode 非法: %s（允许 fly/walk）" % camera_mode
	if camera_mode == "walk" and walk_surfaces.is_empty():
		return "walk 模式缺少 walk_surfaces"
	for i in walk_surfaces.size():
		var s: AABB = walk_surfaces[i]
		if s.size.x <= 0.0 or s.size.z <= 0.0 or s.size.y < 0.0:
			return "walk_surfaces 第 %d 项尺寸非法" % i
	for i in portals.size():
		var reason := _validate_portal(portals[i], i)
		if not reason.is_empty():
			return reason
	return ""


func _validate_portal(p: Dictionary, idx: int) -> String:
	if not p.has("pos") or not p["pos"] is Vector3:
		return "portals 第 %d 项缺少 pos(Vector3)" % idx
	if not p.has("radius") or not p["radius"] is float or float(p["radius"]) <= 0.0 or float(p["radius"]) > 6.0:
		return "portals 第 %d 项 radius 非法（允许 (0,6]）" % idx
	if str(p.get("target_map_id", "")).is_empty():
		return "portals 第 %d 项缺少 target_map_id" % idx
	if str(p.get("target_anchor", "")).is_empty():
		return "portals 第 %d 项缺少 target_anchor" % idx
	if str(p.get("label", "")).is_empty():
		return "portals 第 %d 项缺少 label" % idx
	return ""


## 门户值副本（供运行时轮询；不暴露内部引用）。
func get_portal_copies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in portals:
		out.append({
			"pos": (p.get("pos") as Vector3),
			"radius": float(p.get("radius", 1.5)),
			"target_map_id": str(p.get("target_map_id", "")),
			"target_anchor": str(p.get("target_anchor", "")),
			"label": str(p.get("label", "")),
		})
	return out
