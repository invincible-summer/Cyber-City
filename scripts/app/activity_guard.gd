## 轻量活动互斥（chapter1-1 §7.8）：map_transition / capture / benchmark
## 任一时刻至多一个持有者。空闲 try_begin 返回 >0 token，忙碌返回 0。
## 持有者内部的相机切换/设置覆盖不得再次申请同一锁。
class_name ActivityGuard
extends RefCounted

const KIND_MAP_TRANSITION := &"map_transition"
const KIND_CAPTURE := &"capture"
const KIND_BENCHMARK := &"benchmark"
const KINDS: Array[StringName] = [KIND_MAP_TRANSITION, KIND_CAPTURE, KIND_BENCHMARK]

var _active_kind: StringName = &""
var _active_token: int = 0
var _next_token: int = 1


func try_begin(kind: StringName) -> int:
	if not KINDS.has(kind):
		return 0
	if _active_kind != &"":
		return 0
	_active_kind = kind
	_active_token = _next_token
	_next_token += 1
	return _active_token


func end(token: int) -> Error:
	if token <= 0:
		return ERR_INVALID_PARAMETER
	if _active_token == 0 or token != _active_token:
		return ERR_INVALID_PARAMETER
	_active_token = 0
	_active_kind = &""
	return OK


func get_active_kind() -> StringName:
	return _active_kind


func is_busy() -> bool:
	return _active_kind != &""


## 进程退出等场景的兜底释放（正常路径应使用 end）。
func force_release() -> void:
	_active_kind = &""
	_active_token = 0
