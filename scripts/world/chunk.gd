class_name WorldChunk
extends TileMapLayer
## 一块 CHUNK_SIZE×CHUNK_SIZE 的世界：commit() 写 tile（source id = tile 类型）+ 特征子节点。
## 特征：森林 → 树 + 草/大草丛（现成 prefab）；雪原/沙漠 → 石头（rock.png 贴图，按 size 缩放）。

const DepthSort := preload("res://scripts/depth_sort.gd")
const TREE_SCENE := preload("res://prefabs/items/static prop/tree.tscn")
const GRASS_SCENE := preload("res://prefabs/items/static prop/grass_1.tscn")
const GRASS_BIG_SCENE := preload("res://prefabs/items/static prop/grass_big.tscn")
const ROCK_TEX := preload("res://art/else/rock.png")
const WaterCellScript := preload("res://color_change/water_cell.gd")
const ICE_TEX := preload("res://art/picture_boluo/冰块.png")
const Rules := preload("res://scripts/element/element_rules.gd")


var chunk_coord := Vector2i.ZERO
var _paint: TileMapLayer  # 全局地面颜料层引用（跨块持久，缓存自 ground_paint group）
var _controller: Node      # chunk_manager（地面颜料+行为节点的唯一所有者），缓存自 ground_controller group


## 只设置块坐标/贴图/位置（不生成内容），供后台线程提交后调用。
func setup_meta(c: Vector2i, tileset: TileSet) -> void:
	chunk_coord = c
	tile_set = tileset
	var chunk_px := WorldGenerator.CHUNK_SIZE * WorldTileset.TILE_PX
	position = Vector2(c.x * chunk_px, c.y * chunk_px)


## 把预生成的数据写成本块（主线程）。data = {tiles, atlas, features}。
func commit(data: Dictionary) -> void:
	var tiles: PackedInt32Array = data["tiles"] as PackedInt32Array
	var atlas: PackedInt32Array = data["atlas"] as PackedInt32Array
	for ly in WorldGenerator.CHUNK_SIZE:
		for lx in WorldGenerator.CHUNK_SIZE:
			var i := ly * WorldGenerator.CHUNK_SIZE + lx
			var a: int = atlas[i]
			var t: int = tiles[i]
			set_cell(Vector2i(lx, ly), t, Vector2i(a & 3, a >> 2))
			if t == WorldGenerator.Tile.WATER:
				_spawn_water_cell(lx, ly)
	var features: Array = data["features"] as Array
	for feat in features:
		_spawn_feature(
			feat["type"] as int,
			feat["x"] as float,
			feat["y"] as float,
			feat["size"] as float,
		)


## 同步一次性生成（旧入口，测试/调试用）。
func setup(c: Vector2i, tileset: TileSet, seed_val: int) -> void:
	setup_meta(c, tileset)
	commit(WorldGenerator.generate_chunk_data(seed_val, c.x, c.y))


## 给一格水挂 WaterCell：TileSet 负责画灰度基础水，WaterCell 负责碰撞/结冰/预览。
## draw_water=false（不重复画水）；shallow=false（深水，挡路，需冻结成冰才能过）。
## 冻结后叠 冰块.png 蓝冰——灰白世界里的第一个涌现色。
func _spawn_water_cell(lx: int, ly: int) -> void:
	var wc := WaterCellScript.new()
	wc.name = "Water_%d_%d" % [lx, ly]
	wc.position = map_to_local(Vector2i(lx, ly))
	wc.draw_water = false
	wc.shallow = false
	wc.ice_texture = ICE_TEX
	add_child(wc)


func _spawn_feature(type: int, x: float, y: float, size: float) -> void:
	var pos := Vector2(x, y) * float(WorldTileset.TILE_PX)
	match type:
		WorldGenerator.Feature.TREE:
			var tree: Node2D = TREE_SCENE.instantiate() as Node2D
			tree.position = pos
			# tree.tscn 内 Visual 缩放只有 0.074（树贴图 1024×1024），主游戏里每棵树都 scale=16。
			# 这里不加缩放就只有 ~76px，比 256px 的 tile 还小 → 补上 16× 与主游戏一致。
			tree.scale = Vector2(16.0, 16.0)
			add_child(tree)
			_register_grid_object(tree, "树")
		WorldGenerator.Feature.ROCK:
			var rock := Interactable.new()
			rock.material_id = "stone"
			rock.grid_label = "石头"
			rock.position = pos
			var rock_sprite := Sprite2D.new()
			rock_sprite.name = "Visual"
			rock_sprite.texture = ROCK_TEX
			# rock.png 只有 16×16；size 是 0.8~1.3 的变异，×16 后约 1 tile 大小。
			rock_sprite.scale = Vector2(size, size) * 16.0
			rock.add_child(rock_sprite)
			add_child(rock)
		WorldGenerator.Feature.GRASS:
			# grass_1.tscn 本身已带正确尺寸（Area2D，含踩踏弯曲 shader），无需再缩放。
			# 包进 Interactable：草获得可互动（泼色/吸收）+ 按物质(grass)反应，同时保留踩踏弯曲。
			var grass := Interactable.new()
			grass.material_id = "grass"
			grass.grid_label = "草"
			grass.position = pos
			grass.visual_offset = Vector2(-13, -137)  # grass_1.tscn 的 MeshInstance2D 贴图中心偏移
			grass.add_child(GRASS_SCENE.instantiate() as Node2D)
			add_child(grass)
		WorldGenerator.Feature.GRASS_BIG:
			var grass_big := Interactable.new()
			grass_big.material_id = "grass"
			grass_big.grid_label = "大草丛"
			grass_big.position = pos
			grass_big.visual_offset = Vector2(-6, -155)  # grass_big.tscn 的 MeshInstance2D 贴图中心偏移
			grass_big.add_child(GRASS_BIG_SCENE.instantiate() as Node2D)
			add_child(grass_big)


## 登记成「网格对象」：进 grid_object group，标记显示名 + 占地格数。
## 占地默认 1×1；建筑/大树这类多格物品写 Vector2i(w,h)，悬停高亮与提示按此展开。
func _register_grid_object(obj: Node2D, label: String) -> void:
	obj.add_to_group("grid_object")
	obj.set_meta("grid_label", label)
	obj.set_meta("footprint", Vector2i(1, 1))


func _ready() -> void:
	add_to_group("colorable")
	_paint = get_tree().get_first_node_in_group("ground_paint") as TileMapLayer
	_controller = get_tree().get_first_node_in_group("ground_controller")


## 点击命中：只让「陆地格」可命中（水格归 WaterCell 管，避免冲突）。
func contains_point(world_pos: Vector2) -> bool:
	var src := get_cell_source_id(local_to_map(to_local(world_pos)))
	return src != -1 and src != WorldGenerator.Tile.WATER


## 泼色：把鼠标下这格陆地染成选中元素对应的颜料。吃 1 种子（玩家侧扣）。
func apply_color(_c: Color, color_name: String = "", _from_pos: Vector2 = Vector2.INF) -> bool:
	var el := Rules.element_for_color_name(color_name)
	if el == "" or _controller == null:
		return false
	_controller.call("paint_tile", _world_tile_under_mouse(), el)
	return true


## 吸收：抹掉鼠标下这格的颜料，返还元素（净零搬动语义）。
func absorb_color() -> Dictionary:
	if _paint == null:
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	var world := _world_tile_under_mouse()
	var src := _paint.get_cell_source_id(world)
	if src == -1:
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	var el := WorldTileset.paint_element(src)
	_controller.call("erase_paint", world)
	var cfg := Rules.config(el)
	return {
		"element": el,
		"color": cfg.get("color", Color.WHITE),
		"color_name": cfg.get("color_name", ""),
	}


## 是否带色：鼠标下这格是否已泼色（可被吸收）。
func has_color() -> bool:
	return _paint != null and _paint.get_cell_source_id(_world_tile_under_mouse()) != -1


## 鼠标世界坐标 → 绝对世界格坐标。
func _world_tile_under_mouse() -> Vector2i:
	var mp := get_global_mouse_position()
	return Vector2i(floori(mp.x / WorldTileset.TILE_PX), floori(mp.y / WorldTileset.TILE_PX))
