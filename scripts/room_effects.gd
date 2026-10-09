class_name RoomEffects
extends RefCounted
## 房间通关效果的统一出口：开门 + HUD 反馈。
## 触发源（Goal 踩上、未来的 ColorGate 赋色 / 收集门等）都调用这里，
## 使「通关条件」可以随时换，而「通关后做什么」只改这一处。
## 触发源约定：满足自身条件后调 unlock(self, ids) + notify(self, is_final, did_unlock)。


## 打开 door_id 落在 ids 列表里的所有房间门（"room_door" group）。幂等（门只开一次）。
static func unlock(from: Node, ids: Array) -> void:
	if ids.is_empty():
		return
	for d in from.get_tree().get_nodes_in_group("room_door"):
		if not GameState.is_in_current_scene(d):
			continue
		if str(d.get("door_id")) in ids and d.has_method("open"):
			d.open()


## 通关反馈：is_final 显示「过关！」；否则提示「门已解锁」（或「目标达成」）。
static func notify(from: Node, is_final: bool, did_unlock: bool) -> void:
	var hud := from.get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if is_final:
		if hud.has_method("show_win"):
			hud.show_win()
	else:
		var msg := "门已解锁" if did_unlock else "目标达成"
		if hud.has_method("show_hint"):
			hud.show_hint(msg)
