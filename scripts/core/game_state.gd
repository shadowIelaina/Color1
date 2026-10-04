extends Node
## GameState（Autoload 单例）：全局常驻状态。
## - 按房间 ID 保存 RoomMeta（进入/通关/收集/机关状态）
## - 钥匙背包 / 开关 / 能力
## - 广播全局信号（item_collected、gate_opened、hint 等）

signal item_collected(item_id: String)
signal key_added(key_id: String)
signal key_used(key_id: String)
signal gate_opened(gate_id: String)
signal hint(text: String)
signal room_state_changed(room_id: String)

var rooms: Dictionary = {}        # room_id -> RoomMeta
var inventory: Dictionary = {}    # key_id -> true（当前持有的钥匙）
var used_keys: Dictionary = {}    # key_id -> true（被消耗过，用于钥匙重刷）
var switches: Dictionary = {}     # switch_id -> bool
var abilities: Dictionary = {}    # ability_id -> bool

var current_room_id: String = ""
var current_room: Node = null

var unlocked_colors: Array[String] = ["red"]   # 已解锁颜色（颜色机制进度）

const ReachabilityScript = preload("res://scripts/rooms/reachability.gd")


func reset() -> void:
	rooms.clear()
	inventory.clear()
	used_keys.clear()
	switches.clear()
	abilities.clear()
	current_room_id = ""
	current_room = null


# —— 房间元数据 ——
func get_room_meta(room_id: String) -> RoomMeta:
	if not rooms.has(room_id):
		rooms[room_id] = RoomMeta.new()
	return rooms[room_id]


func mark_room_visited(room_id: String) -> void:
	get_room_meta(room_id).mark_visited()


func mark_room_cleared(room_id: String) -> void:
	get_room_meta(room_id).mark_cleared()


func add_item(room_id: String, item_id: String) -> void:
	get_room_meta(room_id).add_item(item_id)
	item_collected.emit(item_id)


func has_item(room_id: String, item_id: String) -> bool:
	return get_room_meta(room_id).has_item(item_id)


# —— 钥匙 ——
func add_key(key_id: String) -> void:
	if has_key(key_id):
		return
	inventory[key_id] = true
	key_added.emit(key_id)


func has_key(key_id: String) -> bool:
	return inventory.get(key_id, false) == true


## 消耗一把钥匙（返回是否成功）。used_keys 记录用于让钥匙节点重刷，防软锁。
func consume_key(key_id: String) -> bool:
	if not has_key(key_id):
		return false
	inventory.erase(key_id)
	used_keys[key_id] = true
	key_used.emit(key_id)
	return true


func was_key_used(key_id: String) -> bool:
	return used_keys.get(key_id, false) == true


# —— 开关 ——
func set_switch(switch_id: String, value: bool) -> void:
	switches[switch_id] = value


func is_switch_on(switch_id: String) -> bool:
	return switches.get(switch_id, false) == true


# —— 能力 ——
func set_ability(ability_id: String) -> void:
	abilities[ability_id] = true


func has_ability(ability_id: String) -> bool:
	return abilities.get(ability_id, false) == true


# —— 软锁检查（BFS，见 reachability.gd）——
func debug_reachability() -> String:
	var result = ReachabilityScript.self_test()
	var report: String = ReachabilityScript.format_report(result)
	print("[软锁检查]\n" + report)
	return report


## 打包成可存档字典。
func to_dict() -> Dictionary:
	var room_data := {}
	for room_id in rooms:
		var meta: RoomMeta = rooms[room_id]
		room_data[room_id] = meta.to_dict()
	return {
		"rooms": room_data,
		"inventory": inventory.duplicate(),
		"used_keys": used_keys.duplicate(),
		"switches": switches.duplicate(),
		"abilities": abilities.duplicate(),
		"current_room_id": current_room_id,
		"unlocked_colors": unlocked_colors.duplicate(),
	}


## 从存档字典还原。
func from_dict(data: Dictionary) -> void:
	reset()
	unlocked_colors.clear()
	var loaded_colors = data.get("unlocked_colors", ["red"])
	if loaded_colors is Array:
		for c in loaded_colors:
			unlocked_colors.append(str(c))
	if unlocked_colors.is_empty():
		unlocked_colors.append("red")

	current_room_id = str(data.get("current_room_id", ""))

	var room_data = data.get("rooms", {})
	if room_data is Dictionary:
		for room_id in room_data:
			rooms[room_id] = RoomMeta.from_dict(room_data[room_id])

	for key_id in data.get("inventory", {}):
		inventory[key_id] = true
	for key_id in data.get("used_keys", {}):
		used_keys[key_id] = true
	for sid in data.get("switches", {}):
		switches[sid] = bool(data["switches"][sid])
	for aid in data.get("abilities", {}):
		abilities[aid] = true
