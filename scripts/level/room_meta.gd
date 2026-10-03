class_name RoomMeta
extends RefCounted
## 单个房间的持久化元数据：进入/通关/收集/机关状态。
## 由 GameState 按房间 ID 保存，切房后仍然保留（常驻内存）。

var is_visited: bool = false
var is_cleared: bool = false
var collected_items: Dictionary = {}  # item_id -> true
var stateful: Dictionary = {}         # state_id -> 保存的数据（字典）


func mark_visited() -> void:
	is_visited = true


func mark_cleared() -> void:
	is_cleared = true


func add_item(item_id: String) -> void:
	collected_items[item_id] = true


func has_item(item_id: String) -> bool:
	return collected_items.get(item_id, false) == true


func to_dict() -> Dictionary:
	return {
		"is_visited": is_visited,
		"is_cleared": is_cleared,
		"collected_items": collected_items.duplicate(),
		"stateful": stateful.duplicate(true),
	}


static func from_dict(data: Dictionary) -> RoomMeta:
	var meta := RoomMeta.new()
	meta.is_visited = data.get("is_visited", false)
	meta.is_cleared = data.get("is_cleared", false)
	meta.collected_items = data.get("collected_items", {})
	meta.stateful = data.get("stateful", {})
	return meta
