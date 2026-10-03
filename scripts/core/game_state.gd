extends Node
## 运行时全局状态（合并版）。
## 原有框架部分：当前房间、已解锁颜色、周数、通用 flags、存档打包/还原。
## 新增关卡玩法部分：房间元数据、钥匙背包、开关、能力（供机关脚本使用）。
## 全局单例：GameState，直接用 GameState.xxx 访问。

signal state_changed(key: String, value)

# —— 关卡玩法信号（供 HUD / 机关使用）——
signal item_collected(item_id: String)
signal key_added(key_id: String)
signal key_used(key_id: String)
signal gate_opened(gate_id: String)
signal hint(text: String)
signal room_state_changed(room_id: String)

# —— 框架原有状态 ——
var current_room_id: String = ""
var unlocked_colors: Array[String] = ["red"]
var week_count: int = 1
var flags: Dictionary = {}

# —— 关卡玩法状态 ——
var rooms: Dictionary = {}        # room_id -> RoomMeta
var inventory: Dictionary = {}    # key_id -> true（当前持有的钥匙）
var used_keys: Dictionary = {}    # key_id -> true（被消耗过，用于钥匙重刷）
var switches: Dictionary = {}     # switch_id -> bool
var abilities: Dictionary = {}    # ability_id -> bool
var current_room: Node = null

const ReachabilityScript = preload("res://scripts/level/reachability.gd")


## 重置关卡玩法状态（房间元数据/钥匙/开关/能力）。不动框架状态。
func reset() -> void:
	rooms.clear()
	inventory.clear()
	used_keys.clear()
	switches.clear()
	abilities.clear()
	current_room_id = ""
	current_room = null


# —— 框架原有：通用 flag ——
func set_flag(key: String, value) -> void:
	flags[key] = value
	_notify(key, value)


func get_flag(key: String, default = null):
	return flags.get(key, default)


## 把运行时状态打包成可存档的字典（含关卡玩法状态）。
func to_dict() -> Dictionary:
	var rooms_data: Dictionary = {}
	for id in rooms:
		rooms_data[id] = rooms[id].to_dict()
	return {
		"current_room_id": current_room_id,
		"unlocked_colors": unlocked_colors,
		"week_count": week_count,
		"flags": flags,
		"rooms": rooms_data,
		"inventory": inventory,
		"used_keys": used_keys,
		"switches": switches,
		"abilities": abilities,
	}


## 从存档字典还原运行时状态。
func from_dict(data: Dictionary) -> void:
	current_room_id = str(data.get("current_room_id", ""))
	week_count = int(data.get("week_count", 1))
	flags = data.get("flags", {}) as Dictionary
	inventory = data.get("inventory", {}) as Dictionary
	used_keys = data.get("used_keys", {}) as Dictionary
	switches = data.get("switches", {}) as Dictionary
	abilities = data.get("abilities", {}) as Dictionary

	unlocked_colors.clear()
	var loaded_colors = data.get("unlocked_colors", ["red"])
	if loaded_colors is Array:
		for c in loaded_colors:
			unlocked_colors.append(str(c))
	if unlocked_colors.is_empty():
		unlocked_colors.append("red")

	rooms.clear()
	var rooms_data = data.get("rooms", {})
	if rooms_data is Dictionary:
		for id in rooms_data:
			rooms[id] = RoomMeta.from_dict(rooms_data[id])


# —— 房间元数据 ——
func get_room_meta(room_id: String) -> RoomMeta:
	if not rooms.has(room_id):
		rooms[room_id] = RoomMeta.new()
	return rooms[room_id]


func mark_room_visited(room_id: String) -> void:
	get_room_meta(room_id).mark_visited()
	room_state_changed.emit(room_id)


func mark_room_cleared(room_id: String) -> void:
	get_room_meta(room_id).mark_cleared()
	room_state_changed.emit(room_id)


func add_item(room_id: String, item_id: String) -> void:
	get_room_meta(room_id).add_item(item_id)
	item_collected.emit(item_id)
	_notify("item:" + room_id + ":" + item_id, true)


func has_item(room_id: String, item_id: String) -> bool:
	return get_room_meta(room_id).has_item(item_id)


# —— 钥匙 ——
func add_key(key_id: String) -> void:
	if has_key(key_id):
		return
	inventory[key_id] = true
	key_added.emit(key_id)
	_notify("key:" + key_id, true)


func has_key(key_id: String) -> bool:
	return inventory.get(key_id, false) == true


## 消耗一把钥匙（返回是否成功）。used_keys 记录用于让钥匙节点重刷，防软锁。
func consume_key(key_id: String) -> bool:
	if not has_key(key_id):
		return false
	inventory.erase(key_id)
	used_keys[key_id] = true
	key_used.emit(key_id)
	_notify("key:" + key_id, false)
	return true


func was_key_used(key_id: String) -> bool:
	return used_keys.get(key_id, false) == true


# —— 开关 ——
func set_switch(switch_id: String, value: bool) -> void:
	switches[switch_id] = value
	_notify("switch:" + switch_id, value)


func is_switch_on(switch_id: String) -> bool:
	return switches.get(switch_id, false) == true


# —— 能力 ——
func set_ability(ability_id: String) -> void:
	abilities[ability_id] = true
	_notify("ability:" + ability_id, true)


func has_ability(ability_id: String) -> bool:
	return abilities.get(ability_id, false) == true


# —— 软锁检查（BFS，见 reachability.gd）——
func debug_reachability() -> String:
	var result = ReachabilityScript.self_test()
	var report: String = ReachabilityScript.format_report(result)
	print("[软锁检查]\n" + report)
	return report


func _notify(key: String, value) -> void:
	state_changed.emit(key, value)
	EventBus.emit("game_state_changed", {"key": key, "value": value})
