class_name Room
extends Node2D
## 单个房间：承载门、机关、可收集物。
## 负责进出场标记、相机边界、Y 排序、状态保存与恢复（遍历 StatefulObject）。

const RuntimeNavBakerScript := preload("res://scripts/nav/runtime_nav_baker.gd")

@export var room_id: String = ""
@export var start_entrance: String = ""
@export var camera_limits: Rect2 = Rect2(-10000, -10000, 20000, 20000)
@export var y_sort_on := true

@export_group("运行时导航")
## 房间加载后自动按碰撞层 2 烘焙导航网格，供 Boss / 小怪绕障。
@export var auto_nav_bake := true
@export_range(8.0, 512.0, 1.0) var nav_agent_radius := 150.0
@export_range(8.0, 256.0, 1.0) var nav_cell_size := 64.0
@export_range(0.0, 2048.0, 8.0) var nav_bounds_margin := 256.0


func _ready() -> void:
	add_to_group("room")
	y_sort_enabled = y_sort_on
	if room_id == "":
		room_id = name
	if auto_nav_bake:
		_setup_runtime_nav.call_deferred()


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
		entrance_id = start_entrance if start_entrance != "" else "spawn"
	for e in get_tree().get_nodes_in_group("entrance"):
		if e.get("entrance_id") == entrance_id and e is Node2D and _is_descendant(e):
			return e.global_position
	var by_name := get_node_or_null(entrance_id)
	if by_name is Node2D:
		return by_name.global_position
	# 未配置或已改名的入口回到正式出生点，避免落在原点的机关内。
	if entrance_id != "spawn":
		return get_entrance_position("spawn")
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
	CameraLimits.apply(
		int(camera_limits.position.x),
		int(camera_limits.position.y),
		int(camera_limits.end.x),
		int(camera_limits.end.y)
	)


# —— 运行时导航烘焙 ——

## 房间加载后自动创建并烘焙导航区域；已有手放 NavigationRegion2D 时不重复烘焙。
func _setup_runtime_nav() -> void:
	if not is_inside_tree():
		return
	if _has_nav_region(self):
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var bounds := _nav_bounds()
	if bounds.size.x <= 1.0 or bounds.size.y <= 1.0:
		return
	var baker := RuntimeNavBakerScript.new()
	baker.name = "RuntimeNav"
	add_child(baker)
	baker.setup(self, bounds, nav_agent_radius, nav_cell_size, nav_bounds_margin)


func _has_nav_region(node: Node) -> bool:
	if node is NavigationRegion2D:
		return true
	for child in node.get_children():
		if _has_nav_region(child):
			return true
	return false


## 优先用 RoomZone 的房间矩形并集；没有分区时退回静态碰撞/地块包围盒。
func _nav_bounds() -> Rect2:
	var zones := _collect_room_zones(self, [])
	var zone_bounds := Rect2()
	var has_zone := false
	for zone in zones:
		var r: Rect2 = zone.call("get_rect")
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		if r.size.x > 100000.0 or r.size.y > 100000.0:
			continue
		if not has_zone:
			zone_bounds = r
			has_zone = true
		else:
			zone_bounds = zone_bounds.merge(r)
	if has_zone:
		return zone_bounds

	var acc: Array = [Rect2(), false]
	_collect_collision_bounds(self, acc)
	if bool(acc[1]):
		return acc[0]
	return Rect2()


func _collect_room_zones(node: Node, out: Array) -> Array:
	if node != self and node is RoomZone:
		out.append(node)
	for child in node.get_children():
		_collect_room_zones(child, out)
	return out


func _collect_collision_bounds(node: Node, acc: Array) -> void:
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		var used := layer.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var corners: Array[Vector2] = [
				layer.to_global(layer.map_to_local(used.position)),
				layer.to_global(layer.map_to_local(Vector2i(used.end.x, used.position.y))),
				layer.to_global(layer.map_to_local(used.end)),
				layer.to_global(layer.map_to_local(Vector2i(used.position.x, used.end.y))),
			]
			_merge_bounds(acc, _rect_from_points(corners))
	elif node is CollisionObject2D:
		var body := node as CollisionObject2D
		if (body.collision_layer & 2) != 0:
			for child in body.get_children():
				if child is CollisionShape2D:
					var col := child as CollisionShape2D
					if col.shape != null:
						_merge_bounds(acc, _shape_world_rect(col))
				elif child is CollisionPolygon2D:
					var poly := child as CollisionPolygon2D
					var pts: Array[Vector2] = []
					for p in poly.polygon:
						pts.append(poly.to_global(p))
					if not pts.is_empty():
						_merge_bounds(acc, _rect_from_points(pts))
	for child in node.get_children():
		_collect_collision_bounds(child, acc)


func _shape_world_rect(col: CollisionShape2D) -> Rect2:
	var r: Rect2 = col.shape.get_rect()
	var pts: Array[Vector2] = [
		col.to_global(r.position),
		col.to_global(Vector2(r.end.x, r.position.y)),
		col.to_global(r.end),
		col.to_global(Vector2(r.position.x, r.end.y)),
	]
	return _rect_from_points(pts)


func _rect_from_points(pts: Array[Vector2]) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for i in range(1, pts.size()):
		r = r.expand(pts[i])
	return r


func _merge_bounds(acc: Array, r: Rect2) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	if not bool(acc[1]):
		acc[0] = r
		acc[1] = true
	else:
		acc[0] = (acc[0] as Rect2).merge(r)
