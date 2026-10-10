class_name Reachability
extends RefCounted
## BFS 可达性检查：根据关卡图（房间/门）检测是否存在到不了的房间（软锁）。
## 注：道具/开关/能力/元素门默认视为「到达该房间即可解开」，不参与 BFS。

## 测试关卡图（与 level_1 / level_2 对应），关卡策划需在此维护。
static func test_graph() -> Dictionary:
	return {
		"start": "level_1",
		"rooms": ["level_1", "level_2"],
		"doors": [
			{"from": "level_1", "to": "level_2"},
			{"from": "level_2", "to": "level_1"},
		],
	}


static func check(rooms: Array, doors: Array, start_room: String) -> Dictionary:
	var doors_by_room: Dictionary = {}
	for d in doors:
		var f: String = d.get("from", "")
		if not doors_by_room.has(f):
			doors_by_room[f] = []
		doors_by_room[f].append(d)

	var queue: Array = [start_room]
	var reachable: Dictionary = {start_room: true}
	while not queue.is_empty():
		var room: String = queue.pop_front()
		if not doors_by_room.has(room):
			continue
		for d in doors_by_room[room]:
			var to: String = d.get("to", "")
			if to == "" or reachable.has(to):
				continue
			reachable[to] = true
			queue.append(to)

	var unreachable: Array = []
	for r in rooms:
		if not reachable.has(r):
			unreachable.append(r)

	return {
		"reachable_rooms": reachable.keys(),
		"unreachable_rooms": unreachable,
		"has_softlock": not unreachable.is_empty(),
	}


static func self_test() -> Dictionary:
	var g := test_graph()
	return check(g["rooms"], g["doors"], g["start"])


static func format_report(result: Dictionary) -> String:
	return "可达房间：%s\n不可达房间：%s\n存在软锁：%s" % [
		str(result["reachable_rooms"]),
		str(result["unreachable_rooms"]),
		"是" if result["has_softlock"] else "否",
	]
