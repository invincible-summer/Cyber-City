## T13-22/T13-23 的 MapManager 只读 stub：只提供签名校验/快照用到的方法。
extends RefCounted


func get_current_map_id() -> StringName:
	return StringName(str(get_meta("stub_map_id", "m01_afterglow")))


func get_state_snapshot() -> Dictionary:
	return {
		"state": "READY",
		"map_id": str(get_meta("stub_map_id", "m01_afterglow")),
		"transaction_id": 0,
		"active_map_count": 1,
		"content_revision": "",
		"last_error": "",
	}
