class_name RuntimeNavBaker
extends NavigationRegion2D
## 运行时导航烘焙组件：房间加载后按碰撞层 2（墙/障碍）烘焙一块 NavigationPolygon。
## 与 boss_test 的做法一致，但可复用于任何场景 / 房间。
##
## 用法：
##   var baker := RuntimeNavBaker.new()
##   add_child(baker)
##   baker.setup(self, world_rect, 150.0, 64.0)
##
## 也可以直接拖进场景，然后在 ready 前调用 setup() 指定范围。

@export var collision_mask := 2
@export_range(8.0, 512.0, 1.0) var agent_radius := 150.0
@export_range(8.0, 256.0, 1.0) var cell_size := 64.0
@export_range(0.0, 2048.0, 8.0) var border_size := 0.0
@export_range(0.0, 400000.0, 100.0) var max_bake_extent := 80000.0

signal baked

var source_root: Node
var bake_bounds := Rect2()
var last_bake_ms := 0
var _baked := false
var _baking := false


func setup(
	root: Node, bounds: Rect2, radius := 150.0, cell := 64.0, margin := 256.0
) -> void:
	source_root = root
	bake_bounds = bounds.grow(margin)
	agent_radius = radius
	cell_size = cell
	if is_inside_tree():
		_schedule_bake()
	else:
		ready.connect(_schedule_bake, CONNECT_ONE_SHOT)


func _schedule_bake() -> void:
	if _baking:
		return
	_baking = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	bake_now()


func bake_now() -> void:
	if _baked:
		return
	if source_root == null or not is_instance_valid(source_root):
		source_root = get_parent()
	if source_root == null or not is_instance_valid(source_root):
		return
	if bake_bounds.size.x <= 1.0 or bake_bounds.size.y <= 1.0:
		return
	var bounds := _clamp_bounds(bake_bounds)
	if bounds.size.x <= 1.0 or bounds.size.y <= 1.0:
		return

	top_level = true
	global_position = Vector2.ZERO
	global_rotation = 0.0
	global_scale = Vector2.ONE

	var poly := NavigationPolygon.new()
	poly.agent_radius = agent_radius
	poly.cell_size = cell_size
	poly.border_size = border_size
	poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	poly.parsed_collision_mask = collision_mask
	poly.add_outline(PackedVector2Array([
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
	]))

	var started := Time.get_ticks_msec()
	var source := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(poly, source, source_root)
	NavigationServer2D.bake_from_source_geometry_data(poly, source)
	last_bake_ms = Time.get_ticks_msec() - started
	navigation_polygon = poly
	# 运行时新烘焙的 region 需要等它真正进入 NavigationServer 的 map 后再同步一次。
	_sync_to_server.call_deferred()
	_baked = true
	baked.emit()


## 延迟到 region 已注册进 map 后再把多边形推给 NavigationServer。
func _sync_to_server() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var map := get_navigation_map()
	if not map.is_valid():
		return
	NavigationServer2D.region_set_map(get_rid(), map)
	NavigationServer2D.region_set_enabled(get_rid(), true)
	NavigationServer2D.region_set_navigation_polygon(get_rid(), navigation_polygon)
	NavigationServer2D.map_set_active(map, true)
	NavigationServer2D.map_force_update(map)


func is_baked() -> bool:
	return _baked


func _clamp_bounds(r: Rect2) -> Rect2:
	var size := Vector2(
		minf(r.size.x, max_bake_extent),
		minf(r.size.y, max_bake_extent)
	)
	return Rect2(r.get_center() - size * 0.5, size)
