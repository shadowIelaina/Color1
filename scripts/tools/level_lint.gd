@tool
extends EditorScript
## 关卡体检（lint）：一键检查当前编辑的大场景（关）的接线正确性。
##
## 用法：在 FileSystem 面板选中本脚本 → 右键 → Run（或 Ctrl+Shift+X）。
## 结果输出到编辑器「输出」面板。
##
## 检查项：
##   1. Door（切关出口）：target_scene 空/文件不存在、target_entrance 空/目标场景无此入口
##   2. Goal：unlock_door_ids 指向不存在的 RoomDoor.door_id（同场景）
##   3. RoomDoor：door_id 空/重复；无锁、无玩家触发区、又无 Goal 引用时可能永远打不开
##   4. Entrance：entrance_id 空/重复
##   5. unlock_options 格式："kind:id"，kind ∈ key/item/switch/ability/element
##   6. RoomZone：缺矩形碰撞盒 / 被缩放 / 被旋转
##   7. 场景整体：无入口、无 Goal（提示级）

const VALID_KINDS: Array[String] = ["key", "item", "switch", "ability", "element"]

var _errors := 0
var _warnings := 0
var _infos := 0


func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		printerr("[关卡体检] 没有打开的关卡场景，请先打开 scenes/level_*.tscn。")
		return

	print("==== 关卡体检：%s ====" % String(root.name))

	var all: Array[Node] = []
	_flatten(root, all)

	var doors: Array[Door] = []
	var room_doors: Array[RoomDoor] = []
	var goals: Array[Goal] = []
	var entrances: Array[Entrance] = []
	var keys: Array[Key] = []
	var items: Array[ItemPickup] = []
	var zones: Array[RoomZone] = []
	for n in all:
		if n is Door:
			doors.append(n as Door)
		if n is RoomDoor:
			room_doors.append(n as RoomDoor)
		if n is Goal:
			goals.append(n as Goal)
		if n is Entrance:
			entrances.append(n as Entrance)
		if n is Key:
			keys.append(n as Key)
		if n is ItemPickup:
			items.append(n as ItemPickup)
		if n is RoomZone:
			zones.append(n as RoomZone)

	_check_doors(doors)
	_check_room_doors(room_doors, goals)
	_check_goals(goals, room_doors)
	_check_entrances(entrances)
	_check_zones(zones)
	_check_scene(entrances, goals)
	_check_unlock_options(doors, room_doors, keys, items)

	print("==== 体检结束：%d 错误 / %d 警告 / %d 提示 ====" % [_errors, _warnings, _infos])


func _flatten(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for c in n.get_children():
		_flatten(c, out)


# —— 1. 切关出口 Door ——
func _check_doors(doors: Array[Door]) -> void:
	for d in doors:
		var label := _path(d)
		if d.target_scene == "":
			_err("%s：target_scene 为空，无法切关" % label)
		elif not ResourceLoader.exists(d.target_scene):
			_err("%s：target_scene 文件不存在：%s" % [label, d.target_scene])
		elif d.target_entrance == "":
			_err("%s：target_entrance 为空" % label)
		elif not _scene_has_entrance(d.target_scene, d.target_entrance):
			_err("%s：目标场景 %s 里找不到 entrance_id=%s" % [label, d.target_scene, d.target_entrance])
		if d.required_key_id != "":
			_info("%s：使用了旧字段 required_key_id（等价 key:%s），建议改用 unlock_options" % [label, d.required_key_id])


## 目标场景里是否存在指定 entrance_id 的入口（加载目标场景临时实例扫描）。
func _scene_has_entrance(scene_path: String, entrance_id: String) -> bool:
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return false
	var inst := ps.instantiate()
	var found := false
	var stack: Array[Node] = [inst]
	var i := 0
	while i < stack.size():
		var n: Node = stack[i]
		i += 1
		if n is Entrance and (n as Entrance).entrance_id == entrance_id:
			found = true
			break
		for c in n.get_children():
			stack.append(c)
	inst.free()
	return found


# —— 2. 房与房门 RoomDoor ——
func _check_room_doors(room_doors: Array[RoomDoor], goals: Array[Goal]) -> void:
	var seen: Dictionary = {}
	var referenced: Dictionary = {}
	for g in goals:
		for did in g.unlock_door_ids:
			referenced[did] = true
	for r in room_doors:
		var label := _path(r)
		var did: String = r.door_id
		if did == "":
			_warn("%s：door_id 为空，将回退为节点名「%s」" % [label, String(r.name)])
			continue
		if seen.has(did):
			_err("%s：door_id「%s」与另一扇门重复" % [label, did])
		seen[did] = true
		if not referenced.has(did):
			if r.unlock_options.is_empty() and r.get_node_or_null("Trigger") == null:
				_warn("%s：无锁、无玩家触发区、且无 Goal 引用，可能永远无法打开" % label)
			else:
				_info("%s：无 Goal 引用（可能是玩家触发/程序开门，确认是否有意）" % label)


# —— 3. 触发源 Goal ——
func _check_goals(goals: Array[Goal], room_doors: Array[RoomDoor]) -> void:
	var ids: Dictionary = {}
	for r in room_doors:
		ids[r.door_id] = true
	for g in goals:
		for did in g.unlock_door_ids:
			if not ids.has(did):
				_err("%s：unlock_door_ids 引用了不存在的 door_id「%s」" % [_path(g), did])


# —— 4. 入口 Entrance ——
func _check_entrances(entrances: Array[Entrance]) -> void:
	var seen: Dictionary = {}
	for e in entrances:
		var eid: String = e.entrance_id
		if eid == "":
			_warn("%s：entrance_id 为空，将回退为节点名「%s」" % [_path(e), String(e.name)])
			continue
		if seen.has(eid):
			_err("%s：entrance_id「%s」重复" % [_path(e), eid])
		seen[eid] = true


# —— 6. 房分区 RoomZone ——
func _check_zones(zones: Array[RoomZone]) -> void:
	for z in zones:
		var label := _path(z)
		if z.scale != Vector2.ONE:
			_err("%s：RoomZone 被缩放（%s），相机边界会算错" % [label, str(z.scale)])
		if z.rotation != 0.0:
			_err("%s：RoomZone 被旋转，相机边界会算错" % label)
		var has_rect := false
		for c in z.get_children():
			if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
				has_rect = true
				break
		if not has_rect:
			_err("%s：缺矩形 CollisionShape2D，无法算相机边界" % label)


# —— 7. 场景整体 ——
func _check_scene(entrances: Array[Entrance], goals: Array[Goal]) -> void:
	if entrances.is_empty():
		_warn("场景里没有任何 Entrance，玩家无法出生")
	else:
		var has_spawn := false
		for e in entrances:
			if e.entrance_id == "spawn":
				has_spawn = true
				break
		if not has_spawn:
			_info("没有 entrance_id=「spawn」的入口（默认出生点约定）")
	if goals.is_empty():
		_info("场景里没有 Goal（若以 Door 切关为出口则正常）")


# —— 5. 锁条件 unlock_options ——
func _check_unlock_options(doors: Array[Door], room_doors: Array[RoomDoor], keys: Array[Key], items: Array[ItemPickup]) -> void:
	var key_ids: Dictionary = {}
	for k in keys:
		key_ids[k.key_id] = true
	var prop_ids: Dictionary = {}
	for it in items:
		prop_ids[it.prop_id] = true
	for d in doors:
		_check_opts(_path(d), d.unlock_options, key_ids, prop_ids)
	for r in room_doors:
		_check_opts(_path(r), r.unlock_options, key_ids, prop_ids)


func _check_opts(label: String, opts: Array[String], key_ids: Dictionary, prop_ids: Dictionary) -> void:
	for opt in opts:
		var i := opt.find(":")
		if i <= 0:
			_err("%s：锁条件「%s」格式错误，应为「kind:id」" % [label, opt])
			continue
		var kind := opt.substr(0, i)
		var id := opt.substr(i + 1)
		if not VALID_KINDS.has(kind):
			_err("%s：锁条件「%s」的 kind「%s」非法，应为 key/item/switch/ability/element" % [label, opt, kind])
		elif id == "":
			_err("%s：锁条件「%s」的 id 为空" % [label, opt])
		elif kind == "key" and not key_ids.has(id):
			_info("%s：锁条件「%s」引用的钥匙在本场景找不到（可能在其他场景）" % [label, opt])
		elif kind == "item" and not prop_ids.has(id):
			_info("%s：锁条件「%s」引用的道具在本场景找不到（可能在其他场景）" % [label, opt])


# —— 输出辅助 ——
func _path(n: Node) -> String:
	var result := String(n.name)
	var p := n.get_parent()
	while p != null:
		result = String(p.name) + "/" + result
		p = p.get_parent()
	return result


func _err(msg: String) -> void:
	_errors += 1
	print("  [错误] " + msg)


func _warn(msg: String) -> void:
	_warnings += 1
	print("  [警告] " + msg)


func _info(msg: String) -> void:
	_infos += 1
	print("  [提示] " + msg)
