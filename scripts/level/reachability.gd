class_name Reachability
extends RefCounted
## BFS 可达性检查：根据关卡图（房间/门/钥匙）检测软锁。
## 状态 = (房间, 已持有钥匙集合)。锁门需要钥匙已在集合中才能通过。
## 注：开关/能力门默认视为「到达该房间即可解开」，不参与 BFS。

## 测试关卡图（与 room_a / room_b 对应），关卡策划需在此维护。
static func test_graph() -> Dictionary:
	return {
		"start": "room_a",
		"rooms": ["room_a", "room_b"],
		"doors": [
			{"from": "room_a", "to": "room_b", "key": ""},
			{"from": "room_b", "to": "room_a", "key": ""},
			{"from": "room_a", "to": "room_b", "key": "key_b"},
		],
		"keys": [
			{"room": "room_b", "key": "key_b"},
		],
	}


static func check(rooms: Array, doors: Array, keys: Array, start_room: String) -> Dictionary:
	var room_keys: Dictionary = {}
	for k in keys:
		var r: String = k.get("room", "")
		if not room_keys.has(r):
			room_keys[r] = []
		room_keys[r].append(k.get("key", ""))

	var doors_by_room: Dictionary = {}
	for d in doors:
		var f: String = d.get("from", "")
		if not doors_by_room.has(f):
			doors_by_room[f] = []
		doors_by_room[f].append(d)

	var queue: Array = [[start_room, {}]]
	var visited: Dictionary = {_key(start_room, {}): true}
	var reachable: Dictionary = {start_room: true}

	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		var room: String = cur[0]
		var held: Dictionary = (cur[1] as Dictionary).duplicate()

		# 到达房间后收集该房间内的钥匙
		if room_keys.has(room):
			for key in room_keys[room]:
				held[key] = true

		# 经过门（锁门需要已持有对应钥匙）
		if doors_by_room.has(room):
			for d in doors_by_room[room]:
				var need: String = d.get("key", "")
				if need != "" and not held.get(need, false):
					continue
				var to: String = d.get("to", "")
				if to == "":
					continue
				var sk := _key(to, held)
				if not visited.has(sk):
					visited[sk] = true
					queue.append([to, held.duplicate()])
				reachable[to] = true

	var unreachable: Array = []
	for r in rooms:
		if not reachable.has(r):
			unreachable.append(r)

	var unreachable_keys: Array = []
	for k in keys:
		if not reachable.has(k.get("room", "")):
			unreachable_keys.append(k.get("key", ""))

	return {
		"reachable_rooms": reachable.keys(),
		"unreachable_rooms": unreachable,
		"unreachable_keys": unreachable_keys,
		"has_softlock": not unreachable.is_empty() or not unreachable_keys.is_empty(),
	}


static func self_test() -> Dictionary:
	var g := test_graph()
	return check(g["rooms"], g["doors"], g["keys"], g["start"])


static func format_report(result: Dictionary) -> String:
	return "可达房间：%s\n不可达房间：%s\n不可达钥匙：%s\n存在软锁：%s" % [
		str(result["reachable_rooms"]),
		str(result["unreachable_rooms"]),
		str(result["unreachable_keys"]),
		"是" if result["has_softlock"] else "否",
	]


static func _key(room: String, held: Dictionary) -> String:
	var ks: Array = held.keys()
	ks.sort()
	return "%s|%s" % [room, str(ks)]
