extends Node2D
## Boss 测试场景：开局直接招募跟班，并随机布场（实心障碍 + 可上色岩石 + 种子箱）。
## 每次运行布局都不同：拒绝采样散布，保证互不重叠、且避开玩家/Boss 出生点。

const ObstacleScene := preload("res://prefabs/boss/obstacle.tscn")
const ColorableRockScene := preload("res://color_change/object.tscn")
const SeedScene := preload("res://prefabs/items/interaction/seed_container.tscn")

@export_group("场地")
## 竞技场内部半宽/半高（世界像素）。
@export var arena_half := Vector2(2800, 2200)
## 距墙留白，障碍不贴墙生成。
@export var wall_margin := 260.0
## 障碍之间 / 与清空区之间的最小间隙。
@export var spacing := 150.0

@export_group("障碍")
@export var obstacle_count := 20
@export var obstacle_scale_min := 0.9
@export var obstacle_scale_max := 3.0

@export_group("大型掩体")
## 玩家与 Boss 中间必出的中央掩体数量（形成掩体拉锯）。
@export_range(0, 5, 1) var center_cover_count := 4
## 围绕场地中圈额外分布的大型掩体柱。
@export_range(0, 12, 1) var pillar_count := 6
@export var pillar_scale_min := 2.4
@export var pillar_scale_max := 3.2
@export var pillar_radius_min := 900.0
@export var pillar_radius_max := 1650.0

@export_group("可上色岩石")
@export var colorable_rock_count := 4
@export var colorable_rock_scale_min := 4.0
@export var colorable_rock_scale_max := 6.0

@export_group("安全区")
## 玩家 / Boss 出生点周围此半径内不放任何东西。
@export var clear_radius := 560.0
@export var max_attempts := 1200

@export_group("导航烘焙")
## 导航代理半径（应≥ Boss 半宽≈130，通道会按此拓宽）。
@export var nav_agent_radius := 150.0
## 导航栅格尺寸（像素）。越小越精确、烘焙越慢。
@export var nav_cell_size := 24.0
## 外扩边界。
@export var nav_border_size := 0.0

## 已占位记录：[{ pos: Vector2, r: float }]。含出生点清空区 + 已放置物体。
var _placed: Array = []

@onready var companion: Node = $Companion
@onready var player: Node2D = $Player
@onready var boss: Node2D = $BossEncounter/Boss
@onready var nav_region: NavigationRegion2D = $NavRegion


func _ready() -> void:
	randomize()
	if companion != null:
		companion.set("state", 1)   # Companion.State.FOLLOWING（= 已招募）
	_build_layout()
	await _bake_navigation()


## 布局生成后，用「障碍层(2)的静态碰撞体」烘焙导航网格。
## 障碍是运行时随机摆放的，所以必须在 _build_layout() 之后烘焙。
func _bake_navigation() -> void:
	if nav_region == null:
		return
	var poly := NavigationPolygon.new()
	poly.agent_radius = nav_agent_radius
	poly.cell_size = nav_cell_size
	poly.border_size = nav_border_size
	poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	poly.parsed_collision_mask = 2   # 层 2 = 墙 / 障碍 / 可上色岩石
	# 可行走区域外框 = 墙的内侧（= arena_half）。
	var hx := arena_half.x
	var hy := arena_half.y
	poly.add_outline(PackedVector2Array([
		Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy),
	]))
	var src := NavigationMeshSourceGeometryData2D.new()
	NavigationServer2D.parse_source_geometry_data(poly, src, self)
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	nav_region.navigation_polygon = poly
	# 等导航服务器同步一帧，Agent 下一帧即可取到路径。
	await get_tree().physics_frame
	await get_tree().physics_frame


func _build_layout() -> void:
	_add_keepout(player.global_position, clear_radius)
	_add_keepout(boss.global_position, clear_radius)
	_place_center_covers()
	_place_pillars()
	_place_obstacles()
	_place_colorable_rocks()
	_place_seed()


func _add_keepout(pos: Vector2, r: float) -> void:
	_placed.append({"pos": pos, "r": r})


# —— 障碍 ——

func _place_obstacles() -> void:
	for i in obstacle_count:
		var spot := _find_spot(obstacle_scale_min, obstacle_scale_max, 100.0)
		if spot.is_empty():
			continue
		var node := ObstacleScene.instantiate()
		node.name = "Obstacle_%d" % i
		node.position = spot["pos"]
		node.scale = Vector2.ONE * float(spot["scale"])
		add_child(node)
		_placed.append({"pos": spot["pos"], "r": float(spot["r"])})


# —— 中央掩体：放在玩家与 Boss 之间，保证有“躲与探头”的拉锯空间 ——

func _place_center_covers() -> void:
	var center := (player.global_position + boss.global_position) * 0.5
	var offsets := [
		Vector2(-900, 0),
		Vector2(900, 0),
		Vector2(-1300, 0),
		Vector2(1300, 0),
		Vector2.ZERO,
	]
	for i in mini(center_cover_count, offsets.size()):
		var pos: Vector2 = center + offsets[i]
		var scale := randf_range(2.2, 3.0)
		var r := 100.0 * scale
		if not _is_clear(pos, r):
			continue
		_spawn_cover(pos, scale, "CenterCover_%d" % i)


# —— 大型掩体柱：围场地中圈分布，增加可绕的柱子 ——

func _place_pillars() -> void:
	for i in pillar_count:
		var ang := TAU * float(i) / float(maxi(pillar_count, 1)) + randf_range(-0.18, 0.18)
		var placed := false
		for _attempt in 8:
			var pos := Vector2.from_angle(ang) * randf_range(pillar_radius_min, pillar_radius_max)
			var scale := randf_range(pillar_scale_min, pillar_scale_max)
			var r := 100.0 * scale
			if _is_clear(pos, r):
				_spawn_cover(pos, scale, "Pillar_%d" % i)
				placed = true
				break
			ang += 0.2
		if not placed:
			continue


func _spawn_cover(pos: Vector2, scale: float, node_name: String) -> void:
	var node := ObstacleScene.instantiate()
	node.name = node_name
	node.position = pos
	node.scale = Vector2.ONE * scale
	add_child(node)
	_placed.append({"pos": pos, "r": 100.0 * scale})


# —— 可上色岩石（实心，红+绿变黄后反火球）——

func _place_colorable_rocks() -> void:
	for i in colorable_rock_count:
		var spot := _find_spot(colorable_rock_scale_min, colorable_rock_scale_max, 30.0)
		if spot.is_empty():
			continue
		var scale: float = float(spot["scale"])
		var rock := ColorableRockScene.instantiate()
		rock.name = "ColorableRock_%d" % i
		rock.position = spot["pos"]
		rock.scale = Vector2.ONE * scale
		rock.collision_layer = 2                 # 变成实心障碍
		rock.reflect_radius = 60.0 * scale       # 反射范围随体型放大
		add_child(rock)
		_placed.append({"pos": spot["pos"], "r": float(spot["r"])})


# —— 种子箱 ——

func _place_seed() -> void:
	var spot := _find_spot(1.0, 1.0, 46.0)
	if spot.is_empty():
		return
	var seed := SeedScene.instantiate()
	seed.name = "SeedContainer"
	seed.position = spot["pos"]
	seed.burn_seeds = 6
	seed.freeze_seeds = 4
	seed.grow_seeds = 6
	add_child(seed)
	_placed.append({"pos": spot["pos"], "r": float(spot["r"])})


# —— 拒绝采样 ——

## 在场地内随机找一个不与任何已占位重叠的位置；失败返回空字典。
func _find_spot(scale_min: float, scale_max: float, r_base: float) -> Dictionary:
	var hx := arena_half.x - wall_margin
	var hy := arena_half.y - wall_margin
	for _i in max_attempts:
		var scale := randf_range(scale_min, scale_max)
		var r := r_base * scale
		var pos := Vector2(randf_range(-hx, hx), randf_range(-hy, hy))
		if _is_clear(pos, r):
			return {"pos": pos, "scale": scale, "r": r}
	return {}


func _is_clear(pos: Vector2, r: float) -> bool:
	for p in _placed:
		if pos.distance_to(p["pos"]) < r + float(p["r"]) + spacing:
			return false
	return true
