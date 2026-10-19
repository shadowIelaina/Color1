extends Node
## GameState（Autoload 单例）：全局常驻状态。
## - 按房间 ID 保存 RoomMeta（进入/通关/收集/机关状态）
## - 钥匙 / 关键道具 / 开关 / 能力 / 元素
## - 广播全局信号（item_collected、key_added、gate_opened、hint 等）

signal item_collected(item_id: String)
signal key_added(key_id: String)
signal key_used(key_id: String)
signal prop_added(prop_id: String)
signal ability_added(ability_id: String)
signal switch_changed(switch_id: String, value: bool)
signal gate_opened(gate_id: String)
signal hint(text: String)
## 左上角短暂提示（拾取道具、门被解锁等）。HUD 连接它做顶部左侧的消息行。
signal notice(text: String)
## Boss 级警告横幅：标题 / 副标题 / 主题色 / 持续秒数（带倒计时）。HUD 连接它做居中横幅。
signal alert(title: String, subtitle: String, color: Color, duration: float)
## 立即收起当前 Boss 警告横幅（打断回血、Boss 死亡等）。
signal alert_cancelled
signal room_state_changed(room_id: String)

var rooms: Dictionary = {}        # room_id -> RoomMeta
var keys: Dictionary = {}         # key_id -> true（当前持有的钥匙）
var used_keys: Dictionary = {}    # key_id -> true（已被消耗过，钥匙不再刷新）
var key_names: Dictionary = {}    # key_id -> 显示名（供提示文案；由 Key 节点登记）
var switches: Dictionary = {}     # switch_id -> bool
var abilities: Dictionary = {}    # ability_id -> bool
var props: Dictionary = {}        # prop_id -> true（关键道具背包）
var elements: Dictionary = {}     # element_id -> count（由玩家 inventory 同步，供元素门）
## 已解锁的出口门（door_id -> true）。用于「锁定门解锁后重进此关仍保持开启」，避免重复触发。
var opened_gates: Dictionary = {}
## 本次游戏已开始播放的剧情，切关保留，reset 后清空。
var played_story: Dictionary = {}
## 小精灵一次性提示已播记录（hint_id -> true），切关保留，reset 后清空。
var hints: Dictionary = {}
var companion_recruited := false
var health_upgrades: Dictionary = {} # 道具唯一 id -> 增加的最大生命值
var health_upgrade_names: Dictionary = {}

var current_room_id: String = ""
var current_room: Node = null

## 存档点：角色最近一次到达的存档位置（场景路径 + 世界坐标）。
var checkpoint_scene: String = ""
var checkpoint_pos: Vector2 = Vector2.ZERO

const SAVE_PATH := "user://save.json"
## 主菜单请求的下一次启动方式。重建玩家和房间，避免继承预览状态。
var menu_launch_action := ""

const ReachabilityScript = preload("res://scripts/reachability.gd")


func reset() -> void:
	rooms.clear()
	keys.clear()
	used_keys.clear()
	key_names.clear()
	switches.clear()
	abilities.clear()
	props.clear()
	elements.clear()
	opened_gates.clear()
	played_story.clear()
	hints.clear()
	companion_recruited = false
	health_upgrades.clear()
	health_upgrade_names.clear()
	current_room_id = ""
	current_room = null
	checkpoint_scene = ""
	checkpoint_pos = Vector2.ZERO


# —— 存档 / 读档 ——
## 设置存档点（角色到达存档点时调用），并立即写盘。
func set_checkpoint(scene: String, pos: Vector2) -> void:
	checkpoint_scene = scene
	checkpoint_pos = pos
	save_game()


func has_checkpoint() -> bool:
	return checkpoint_scene != ""


## 序列化当前进度 + 存档点到 user://save.json。
func save_game() -> void:
	# 存档点也要抓取当前房间，不能只等离开房间时才记录容器剩余种子。
	if is_instance_valid(current_room) and current_room.has_method("save_state"):
		current_room.save_state()
	var seed_containers := {}
	for room_id in rooms:
		var containers := {}
		var meta: RoomMeta = rooms[room_id]
		for state_id in meta.stateful:
			var object_state: Dictionary = meta.stateful[state_id]
			if object_state.get("store") is Dictionary:
				containers[state_id] = object_state.duplicate(true)
		if not containers.is_empty():
			seed_containers[room_id] = containers
	# 飞行中预留的上色种子尚未作用到世界；存档应保留它们，避免读档丢种。
	var saved_elements := elements.duplicate()
	for companion in get_tree().get_nodes_in_group("companion"):
		if companion.has_method("reserved_elements"):
			var reserved: Dictionary = companion.reserved_elements()
			for element in reserved:
				saved_elements[element] = int(saved_elements.get(element, 0)) + int(reserved[element])
	var data := {
		"checkpoint_scene": checkpoint_scene,
		"checkpoint_pos": [checkpoint_pos.x, checkpoint_pos.y],
		"keys": keys,
		"used_keys": used_keys,
		"key_names": key_names,
		"switches": switches,
		"abilities": abilities,
		"props": props,
		"elements": saved_elements,
		"seed_containers": seed_containers,
		"opened_gates": opened_gates,
		"played_story": played_story,
		"hints": hints,
		"companion_recruited": companion_recruited,
		"health_upgrades": health_upgrades,
		"health_upgrade_names": health_upgrade_names,
	}
	# 确保 user:// 目录存在（首次运行时可能还没建）。
	if DirAccess.open("user://") == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://"))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入存档：%s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()


## 校验磁盘数据；失败不修改内存，也不覆盖原文件。
func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	if parsed == null or not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	var containers: Variant = d.get("seed_containers", {})
	if not containers is Dictionary:
		return {}
	for room_states in containers.values():
		if not room_states is Dictionary:
			return {}
		for container in room_states.values():
			if not container is Dictionary or not container.get("store") is Dictionary or not container.get("frozen", false) is bool:
				return {}
			for count in container.store.values():
				if not (count is float or count is int) or not is_finite(float(count)) or count < 0:
					return {}
	if d.has("companion_recruited") and not d.companion_recruited is bool:
		return {}
	var scene: Variant = d.get("checkpoint_scene", "")
	var position: Variant = d.get("checkpoint_pos", [])
	if not scene is String or not scene.begins_with("res://") or not scene.ends_with(".tscn") or not ResourceLoader.exists(scene, "PackedScene"):
		return {}
	if not position is Array or position.size() != 2:
		return {}
	for coordinate in position:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):
			return {}
	for key in ["keys", "used_keys", "key_names", "switches", "abilities", "props", "elements", "opened_gates", "played_story", "hints", "health_upgrades", "health_upgrade_names"]:
		if not d.get(key, {}) is Dictionary:
			return {}
	for key in ["elements", "health_upgrades"]:
		for value in d.get(key, {}).values():
			if not (value is int or value is float) or not is_finite(float(value)) or value < 0:
				return {}
	return d


## 检查可继续的存档，不改内存进度；缺失、损坏、场景已删除均返回 false。
func has_valid_save() -> bool:
	return not _read_save().is_empty()


## 从有效存档恢复进度；先清理上一局的房间元数据。
func load_game() -> bool:
	var d := _read_save()
	if d.is_empty():
		return false
	reset()
	checkpoint_scene = str(d.get("checkpoint_scene", ""))
	var pos_arr: Array = d.get("checkpoint_pos", [0.0, 0.0])
	checkpoint_pos = Vector2(float(pos_arr[0]), float(pos_arr[1]))
	keys = d.get("keys", {})
	used_keys = d.get("used_keys", {})
	key_names = d.get("key_names", {})
	switches = d.get("switches", {})
	abilities = d.get("abilities", {})
	props = d.get("props", {})
	elements = d.get("elements", {})
	opened_gates = d.get("opened_gates", {})
	played_story = d.get("played_story", {})
	hints = d.get("hints", {})
	# 旧存档无此字段：后续关卡或已获得元素说明已完成跟班教学。
	companion_recruited = bool(d.get("companion_recruited", checkpoint_scene != "res://scenes/level_1.tscn" or not elements.is_empty()))
	health_upgrades = d.get("health_upgrades", {})
	health_upgrade_names = d.get("health_upgrade_names", {})
	# 仅补齐有限种子容器；其他机关仍沿用现有房间临时状态机制。
	for room_id in d.get("seed_containers", {}):
		var meta := get_room_meta(str(room_id))
		var containers: Dictionary = d.seed_containers[room_id]
		for state_id in containers:
			meta.stateful[state_id] = containers[state_id].duplicate(true)
	return true


## 开始新游戏：清空进度、清掉存档点、删除存档文件。
func new_game() -> void:
	reset()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## 继续游戏：读取存档，返回是否有可用存档。
func continue_game() -> bool:
	return load_game()


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


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


# —— 钥匙（1:1 钥匙门：一把钥匙开一扇门，开门时消耗销毁）——
## 由 Key 节点在 _ready 登记显示名，供门 / 提示文案查询。
func register_key(key_id: String, key_name: String = "") -> void:
	key_names[key_id] = key_name if key_name != "" else key_id


## 钥匙显示名（未登记则回退为 id）。
func key_display(key_id: String) -> String:
	return str(key_names.get(key_id, key_id))


## 拾取一把钥匙（幂等）。
func add_key(key_id: String) -> void:
	if has_key(key_id):
		return
	keys[key_id] = true
	key_added.emit(key_id)


func has_key(key_id: String) -> bool:
	return keys.get(key_id, false) == true


## 消耗（销毁）一把钥匙：从持有中移除并记录已用（防重刷）。返回是否成功。
func consume_key(key_id: String) -> bool:
	if not has_key(key_id):
		return false
	keys.erase(key_id)
	used_keys[key_id] = true
	key_used.emit(key_id)
	return true


func was_key_used(key_id: String) -> bool:
	return used_keys.get(key_id, false) == true


## 当前持有的钥匙 id（排序，供 HUD 显示）。
func held_key_ids() -> Array[String]:
	var out: Array[String] = []
	for k in keys:
		if keys[k] == true:
			out.append(str(k))
	out.sort()
	return out


# —— 开关 ——
func set_switch(switch_id: String, value: bool) -> void:
	switches[switch_id] = value
	switch_changed.emit(switch_id, value)


func is_switch_on(switch_id: String) -> bool:
	return switches.get(switch_id, false) == true


# —— 能力 ——
func set_ability(ability_id: String) -> void:
	if has_ability(ability_id):
		return
	abilities[ability_id] = true
	ability_added.emit(ability_id)


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


# —— 出口门解锁记录（锁定门解锁后保持开启，避免重复触发）——
func mark_gate_opened(gate_id: String) -> void:
	opened_gates[gate_id] = true


func is_gate_opened(gate_id: String) -> bool:
	return opened_gates.get(gate_id, false) == true


# —— 统一条件查询（门 / 闸 / 机关通用）——
func has_flag(kind: String, id: String) -> bool:
	match kind:
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
