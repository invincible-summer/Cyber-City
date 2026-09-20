## 固定性能路线定义（chapter1-1 §8.3）。时间驱动、与帧率无关；
## 段间切镜，不跨楼插值。legacy_v1 与第一阶段 main.gd ROUTE_SEGMENTS 完全一致。
class_name PerfRoutes
extends RefCounted

const ROUTE_LEGACY := "legacy_v1"
const ROUTE_EXPANDED := "expanded_v11"

## 每段时长（秒）。legacy_v1 三段 60s；expanded_v11 六段各 10s。
const SEGMENT_SECONDS := {
	ROUTE_LEGACY: 20.0,
	ROUTE_EXPANDED: 10.0,
}

const ROUTES: Dictionary = {
	# legacy_v1：三段形状与第一阶段一致；第三段坐标修正——原 (18,12,-35)→(14,13,-38)
	# 在 E6 楼体内穿行（第一章潜在缺陷，目检确认），报告按"新建对照路线"标注。
	ROUTE_LEGACY: [
		{"p0": Vector3(-3, 1.7, 52), "p1": Vector3(-3, 1.7, 20), "look": Vector3(1, 8, -45), "name": "main_street"},
		{"p0": Vector3(15, 1.8, 31), "p1": Vector3(19, 2.0, 29), "look": Vector3(33, 2.5, 25), "name": "repair_shop"},
		{"p0": Vector3(3, 12, -32), "p1": Vector3(1, 13, -36), "look": Vector3(0, 10, -62), "name": "station_high"},
	],
	# expanded_v11 段序=主街/维修铺/生活广场/屋顶露台/站前广场/原站口高位
	ROUTE_EXPANDED: [
		{"p0": Vector3(-3, 1.7, 50), "p1": Vector3(-3, 1.8, 30), "look": Vector3(1, 8, -45), "name": "main_street"},
		{"p0": Vector3(14, 1.8, 32), "p1": Vector3(17, 2.0, 30), "look": Vector3(33, 2.5, 25), "name": "repair_shop"},
		{"p0": Vector3(-44, 2.0, 3), "p1": Vector3(-48, 2.0, 1), "look": Vector3(-64, 2.5, -2), "name": "service_court"},
		{"p0": Vector3(-56, 10.8, 2), "p1": Vector3(-59, 10.8, -2), "look": Vector3(10, 12, 30), "name": "roof_terrace"},
		{"p0": Vector3(34, 1.7, -82), "p1": Vector3(30, 1.7, -79.5), "look": Vector3(19, 6.5, -64), "name": "station_forecourt"},
		{"p0": Vector3(3, 12, -32), "p1": Vector3(1, 13, -36), "look": Vector3(0, 10, -62), "name": "station_high"},
	],
}


static func route_duration(route_id: String) -> float:
	var segments: Array = ROUTES.get(route_id, [])
	var sec: float = SEGMENT_SECONDS.get(route_id, 20.0)
	return sec * segments.size()


static func route_transform(route_id: String, t: float) -> Transform3D:
	var segments: Array = ROUTES.get(route_id, [])
	if segments.is_empty():
		return Transform3D(Basis(), Vector3(0, 2, 0))
	var total := route_duration(route_id)
	var tc := clampf(t, 0.0, total - 0.001)
	var seg_len: float = SEGMENT_SECONDS.get(route_id, 20.0)
	var seg := int(tc / seg_len)
	var local := (tc - seg * seg_len) / seg_len
	var s: Dictionary = segments[mini(seg, segments.size() - 1)]
	var pos: Vector3 = s["p0"].lerp(s["p1"], local)
	var xf := Transform3D(Basis(), pos)
	return xf.looking_at(s["look"], Vector3.UP)


static func segment_id(route_id: String, t: float) -> String:
	var segments: Array = ROUTES.get(route_id, [])
	if segments.is_empty():
		return ""
	var seg_len: float = SEGMENT_SECONDS.get(route_id, 20.0)
	var seg := int(clampf(t, 0.0, route_duration(route_id) - 0.001) / seg_len)
	return str(segments[mini(seg, segments.size() - 1)].get("name", str(seg)))
