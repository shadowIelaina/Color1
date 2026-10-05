class_name Room
extends Node2D
## 单个房间：承载门、机关、可收集物。
## 负责进出场标记、相机边界、Y 排序、状态保存与恢复（遍历 StatefulObject）。

@export var room_id: String = ""
@export var start_entrance: String = ""
@export var camera_limits: Rect2 = Rect2(-10000, -10000, 20000, 20000)
@export var y_sort_on := true


func _ready() -> void:
	add_to_group("room")
	y_sort_enabled = y_sort_on
	if room_id == "":
		room_id = name


## 进入房间：标记访问、应用相机边界、恢复机关状态。
func enter() -> void:
	GameState.current_room_id = room_id
	GameState.current_room = self
	GameState.mark_room_visited(room_id)
	_apply_camera_limits()
	restore_state()


## 退出房间：保存机关状态。
func exit() -> void:
	save_state()


## 查找本房间内 matching entrance_id 的入口位置。
func get_entrance_position(entrance_id: String) -> Vector2:
	if entrance_id == "":
		return Vector2.ZERO
	for e in get_tree().get_nodes_in_group("entrance"):
		if e.get("entrance_id") == entrance_id and e is Node2D and _is_descendant(e):
			return e.global_position
	var by_name := get_node_or_null(entrance_id)
	if by_name is Node2D:
		return by_name.global_position
	return Vector2.ZERO


func _is_descendant(node: Node) -> bool:
	var cur: Node = node
	while cur != null:
		if cur == self:
			return true
		cur = cur.get_parent()
	return false


# —— 状态保存 / 恢复（统一遍历 StatefulObject）——
func save_state() -> void:
	var meta := GameState.get_room_meta(room_id)
	for obj in _stateful_objects():
		if obj.has_method("save_state"):
			meta.stateful[obj.get("state_id")] = obj.save_state()


func restore_state() -> void:
	var meta := GameState.get_room_meta(room_id)
	for obj in _stateful_objects():
		if obj.has_method("restore_state"):
			var sid: String = obj.get("state_id")
			obj.restore_state(meta.stateful.get(sid, {}))


func _stateful_objects() -> Array:
	var result: Array = []
	for obj in get_tree().get_nodes_in_group("stateful"):
		if _is_descendant(obj):
			result.append(obj)
	return result


# —— 相机边界 ——
func _apply_camera_limits() -> void:
	var cam := _find_player_camera()
	if cam:
		cam.limit_left = int(camera_limits.position.x)
		cam.limit_top = int(camera_limits.position.y)
		cam.limit_right = int(camera_limits.end.x)
		cam.limit_bottom = int(camera_limits.end.y)


func _find_player_camera() -> Camera2D:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return null
	var cam := p.get_node_or_null("Camera")
	if cam is Camera2D:
		return cam
	for c in p.find_children("*", "Camera2D", true, false):
		return c
	return null
