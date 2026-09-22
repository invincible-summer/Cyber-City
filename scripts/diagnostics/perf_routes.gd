## 固定性能路线定义（chapter1-3 §10.2 ROUTE_SPECS 单一数据结构）。
## 时间驱动、与帧率无关；段间切镜，不跨楼插值。每条路线声明适用 map_id，
## BenchmarkRunner.start_run 校验 route_map_id == 当前 READY 地图（§10.4）。
## interior_v13（§10.3）：60 秒四段各 15 秒——entry/workbench/gallery/dining，
## 使用已通过的最终机位空间（同 interior 四锚点间小位移），不穿墙、不跨层插值。
class_name PerfRoutes
extends RefCounted

const ROUTE_LEGACY := "legacy_v1"
const ROUTE_EXPANDED := "expanded_v11"
const ROUTE_INTERIOR := "interior_v13"

const ROUTE_SPECS: Dictionary = {
	# legacy_v1：三段形状与第一阶段一致；第三段坐标修正——原 (18,12,-35)→(14,13,-38)
	# 在 E6 楼体内穿行（第一章潜在缺陷，目检确认），报告按"新建对照路线"标注。
	ROUTE_LEGACY: {
		"map_id": "m01_afterglow",
		"segment_seconds": 20.0,
		"segments": [
			{"p0": Vector3(-3, 1.7, 52), "p1": Vector3(-3, 1.7, 20), "look": Vector3(1, 8, -45), "name": "main_street"},
			{"p0": Vector3(15, 1.8, 31), "p1": Vector3(19, 2.0, 29), "look": Vector3(33, 2.5, 25), "name": "repair_shop"},
			{"p0": Vector3(3, 12, -32), "p1": Vector3(1, 13, -36), "look": Vector3(0, 10, -62), "name": "station_high"},
		],
	},
	# expanded_v11 段序=主街/维修铺/生活广场/屋顶露台/站前广场/原站口高位
	ROUTE_EXPANDED: {
		"map_id": "m01_afterglow",
		"segment_seconds": 10.0,
		"segments": [
			{"p0": Vector3(-3, 1.7, 50), "p1": Vector3(-3, 1.8, 30), "look": Vector3(1, 8, -45), "name": "main_street"},
			{"p0": Vector3(14, 1.8, 32), "p1": Vector3(17, 2.0, 30), "look": Vector3(33, 2.5, 25), "name": "repair_shop"},
			{"p0": Vector3(-44, 2.0, 3), "p1": Vector3(-48, 2.0, 1), "look": Vector3(-64, 2.5, -2), "name": "service_court"},
			{"p0": Vector3(-56, 10.8, 2), "p1": Vector3(-59, 10.8, -2), "look": Vector3(10, 12, 30), "name": "roof_terrace"},
			{"p0": Vector3(34, 1.7, -82), "p1": Vector3(30, 1.7, -79.5), "look": Vector3(19, 6.5, -64), "name": "station_forecourt"},
			{"p0": Vector3(3, 12, -32), "p1": Vector3(1, 13, -36), "look": Vector3(0, 10, -62), "name": "station_high"},
		],
	},
	# interior_v13：店内固定小位移（一层入口/工位、二层橱窗/餐区），同层不跨楼插值
	ROUTE_INTERIOR: {
		"map_id": "m01_repair_interior",
		"segment_seconds": 15.0,
		"segments": [
			{"p0": Vector3(1.7, 1.62, 1.8), "p1": Vector3(2.4, 1.62, 0.6), "look": Vector3(6, 1.45, -1), "name": "entry"},
			{"p0": Vector3(2.7, 1.62, -3.3), "p1": Vector3(3.4, 1.62, -2.4), "look": Vector3(1.4, 1.35, -5.5), "name": "workbench"},
			{"p0": Vector3(3.6, 4.77, -0.93), "p1": Vector3(3.6, 4.77, -1.6), "look": Vector3(0.7, 2.34, -0.93), "name": "gallery"},
			{"p0": Vector3(7.8, 4.77, -1.4), "p1": Vector3(7.4, 4.77, -2.0), "look": Vector3(1.2, 4.35, -2.2), "name": "dining"},
		],
	},
}


static func has_route(route_id: String) -> bool:
	return ROUTE_SPECS.has(route_id)


static func route_map_id(route_id: String) -> String:
	return str(ROUTE_SPECS.get(route_id, {}).get("map_id", ""))


static func route_duration(route_id: String) -> float:
	var spec: Dictionary = ROUTE_SPECS.get(route_id, {})
	var segments: Array = spec.get("segments", [])
	return float(spec.get("segment_seconds", 20.0)) * segments.size()


static func route_transform(route_id: String, t: float) -> Transform3D:
	var spec: Dictionary = ROUTE_SPECS.get(route_id, {})
	var segments: Array = spec.get("segments", [])
	if segments.is_empty():
		return Transform3D(Basis(), Vector3(0, 2, 0))
	var total := route_duration(route_id)
	var tc := clampf(t, 0.0, total - 0.001)
	var seg_len: float = float(spec.get("segment_seconds", 20.0))
	var seg := int(tc / seg_len)
	var local := (tc - seg * seg_len) / seg_len
	var s: Dictionary = segments[mini(seg, segments.size() - 1)]
	var pos: Vector3 = s["p0"].lerp(s["p1"], local)
	var xf := Transform3D(Basis(), pos)
	return xf.looking_at(s["look"], Vector3.UP)


static func segment_id(route_id: String, t: float) -> String:
	var spec: Dictionary = ROUTE_SPECS.get(route_id, {})
	var segments: Array = spec.get("segments", [])
	if segments.is_empty():
		return ""
	var seg_len: float = float(spec.get("segment_seconds", 20.0))
	var seg := int(clampf(t, 0.0, route_duration(route_id) - 0.001) / seg_len)
	return str(segments[mini(seg, segments.size() - 1)].get("name", str(seg)))
