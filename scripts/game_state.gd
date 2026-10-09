extends Node
## GameState（Autoload 单例）：全局常驻状态。
## - 按房间 ID 保存 RoomMeta（进入/通关/收集/机关状态）
## - 钥匙背包 / 关键道具 / 开关 / 能力 / 元素
## - 广播全局信号（item_collected、gate_opened、hint 等）

signal item_collected(item_id: String)
signal key_added(key_id: String)
signal key_used(key_id: String)
signal prop_added(prop_id: String)
signal gate_opened(gate_id: String)
signal hint(text: String)
signal room_state_changed(room_id: String)

var rooms: Dictionary = {}        # room_id -> RoomMeta
var inventory: Dictionary = {}    # key_id -> true（当前持有的钥匙）
var used_keys: Dictionary = {}    # key_id -> true（被消耗过，用于钥匙重刷）
var switches: Dictionary = {}     # switch_id -> bool
var abilities: Dictionary = {}    # ability_id -> bool
var props: Dictionary = {}        # prop_id -> true（关键道具背包）
var elements: Dictionary = {}     # element_id -> count（由玩家 inventory 同步，供元素门）

var current_room_id: String = ""
var current_room: Node = null

const ReachabilityScript = preload("res://scripts/reachability.gd")


func reset() -> void:
	rooms.clear()
	inventory.clear()
	used_keys.clear()
	switches.clear()
	abilities.clear()
	props.clear()
	elements.clear()
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


# —— 关键道具（道具门条件）——
func add_prop(prop_id: String) -> void:
	if has_prop(prop_id):
		return
	props[prop_id] = true
	prop_added.emit(prop_id)


func has_prop(prop_id: String) -> bool:
	return props.get(prop_id, false) == true


# —— 元素（由玩家 inventory 同步，供「元素门」条件）——
func set_elements(e: Dictionary) -> void:
	elements = e


func has_element(element_id: String) -> bool:
	return int(elements.get(element_id, 0)) > 0


# —— 统一条件查询（门 / 闸 / 机关通用）——
func has_flag(kind: String, id: String) -> bool:
	match kind:
		"key":
			return has_key(id)
		"item":
			return has_prop(id)
		"switch":
			return is_switch_on(id)
		"ability":
			return has_ability(id)
		"element":
			return has_element(id)
		_:
			return false


## 解析 "kind:id" 并查询条件（供门的 unlock_options 使用）。
func meets_flag(spec: String) -> bool:
	var i := spec.find(":")
	if i <= 0:
		return false
	return has_flag(spec.substr(0, i), spec.substr(i + 1))


## 消耗一个条件里的可消耗项（当前只有钥匙可消耗；道具/开关/能力/元素不消耗）。
func consume_flag(spec: String) -> bool:
	var i := spec.find(":")
	if i <= 0:
		return false
	var kind := spec.substr(0, i)
	var id := spec.substr(i + 1)
	if kind == "key" and has_key(id):
		return consume_key(id)
	return false


# —— 作用域：节点是否属于当前大场景（切场景后把全局搜索限定在「当前关内」）——
func is_in_current_scene(node: Node) -> bool:
	if current_room == null or not is_instance_valid(current_room):
		return true   # 未启用切场景（单场景）或切换间隙：全部放行
	var cur: Node = node
	while cur != null:
		if cur == current_room:
			return true
		cur = cur.get_parent()
	return false


# —— 软锁检查（BFS，见 reachability.gd）——
func debug_reachability() -> String:
	var result = ReachabilityScript.self_test()
	var report: String = ReachabilityScript.format_report(result)
	print("[软锁检查]\n" + report)
	return report
