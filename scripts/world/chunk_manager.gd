extends Node2D
## 流式加载：看玩家落在哪块，加载渲染半径内的块、卸载半径外的块。
## Phase 4：生成丢后台线程（WorkerThreadPool 纯函数），结果经 Mutex 保护字典回传主线程；
## 新块边缘淡入，避免跨块时突然出现。


@export var seed_value := 1337
@export var render_radius := 3       # 块数（以玩家块为中心）
@export var max_in_flight := 6       # 同时跑的后台生成任务上限
@export var fade_time := 0.25        # 新块淡入秒数

var _loaded := {}        # Vector2i -> WorldChunk（已提交可见）
var _pending: Array = [] # 待生成的块坐标
var _in_flight := {}     # Vector2i -> task_id（后台生成中）
var _wanted := {}        # 当前应加载的块集合
var _center := Vector2i(1 << 30, 1 << 30)
var _base: TileMapLayer  # 纯白底图，垫在所有 chunk 之下遮空隙
var _paint: TileMapLayer # 全局地面颜料层（绝对世界格坐标），叠在 chunk 之上、特征物之下
var _effects := {}        # Vector2i -> GroundElement（已泼色格的行为节点：火/霜）
var _effects_layer: Node2D

## 后台线程 → 主线程的结果交接：Mutex 保护。
var _mutex := Mutex.new()
var _results := {}       # Vector2i -> {tiles, features}

@onready var _player: Node2D = get_node("../Player") as Node2D


func _ready() -> void:
	add_to_group("ground_controller")
	_base = _make_base()
	add_child(_base)
	_paint = _make_paint()
	add_child(_paint)
	_effects_layer = _make_effects()
	add_child(_effects_layer)
	_ensure_player_on_land()
	_center = _player_chunk()
	_rebuild_wanted()


## 出生点校正：始终把玩家吸附到最近陆地块的中心。
## 不能只看脚下单格——玩家出生在 (0,0) 这种格角上时，脚部碰撞(128×41)会跨到相邻水格被推开。
## 直接吸附到陆地块中心（脚远小于 256 的格），保证开局不卡水。
func _ensure_player_on_land() -> void:
	var w: Vector2 = _player.global_position
	var tile := Vector2i(floori(w.x / WorldTileset.TILE_PX), floori(w.y / WorldTileset.TILE_PX))
	var land := WorldGenerator.find_land(seed_value, tile.x, tile.y)
	_player.global_position = Vector2(
		(land.x + 0.5) * WorldTileset.TILE_PX,
		(land.y + 0.5) * WorldTileset.TILE_PX,
	)


func _process(_delta: float) -> void:
	var pc := _player_chunk()
	if pc != _center:
		_center = pc
		_rebuild_wanted()
	_dispatch()
	_collect()


func _player_chunk() -> Vector2i:
	var w: Vector2 = _player.global_position
	var chunk_px := WorldGenerator.CHUNK_SIZE * WorldTileset.TILE_PX
	return Vector2i(floori(w.x / chunk_px), floori(w.y / chunk_px))


## 重建「该加载的块」清单：范围外的卸载，缺的进生成队列。
func _rebuild_wanted() -> void:
	_wanted.clear()
	for dy in range(-render_radius, render_radius + 1):
		for dx in range(-render_radius, render_radius + 1):
			_wanted[Vector2i(_center.x + dx, _center.y + dy)] = true
	for c in _loaded.keys():
		if not _wanted.has(c):
			_despawn(c)
	for c in _wanted.keys():
		if not _loaded.has(c) and not _pending.has(c) and not _in_flight.has(c):
			_pending.append(c)


## 把待生成块派到后台线程（纯函数，无线程共享状态）。
func _dispatch() -> void:
	while not _pending.is_empty() and _in_flight.size() < max_in_flight:
		var c: Vector2i = _pending.pop_back()
		var callable := _make_task.bind(seed_value, c.x, c.y)
		_in_flight[c] = WorkerThreadPool.add_task(callable)


## 收后台结果：完成的取出数据、提交成可见块并淡入。
func _collect() -> void:
	for c in _in_flight.keys():
		var task_id: int = _in_flight[c]
		if not WorkerThreadPool.is_task_completed(task_id):
			continue
		_in_flight.erase(c)
		var data := _take_result(c)
		if not data.is_empty() and _wanted.has(c) and not _loaded.has(c):
			_spawn(c, data)


## 后台线程体：只算纯静态生成，结果塞进锁保护的字典。
func _make_task(seed_val: int, cx: int, cy: int) -> void:
	var data := WorldGenerator.generate_chunk_data(seed_val, cx, cy)
	_mutex.lock()
	_results[Vector2i(cx, cy)] = data
	_mutex.unlock()


func _take_result(c: Vector2i) -> Dictionary:
	_mutex.lock()
	var data: Dictionary = _results.get(c, {})
	_results.erase(c)
	_mutex.unlock()
	return data


func _spawn(c: Vector2i, data: Dictionary) -> void:
	_fill_base(c)
	var chunk := WorldChunk.new()
	chunk.setup_meta(c, WorldTileset.get_tileset())
	add_child(chunk)
	chunk.commit(data)
	_loaded[c] = chunk
	_fade_in(chunk)


func _despawn(c: Vector2i) -> void:
	var chunk: Node = _loaded[c]
	_loaded.erase(c)
	chunk.queue_free()
	_erase_base(c)


## 新块从透明淡入，远处「浮出来」而非突然出现。
func _fade_in(chunk: WorldChunk) -> void:
	chunk.modulate = Color(1, 1, 1, 0)
	var tw := chunk.create_tween()
	tw.tween_property(chunk, "modulate:a", 1.0, fade_time)


## 纯白底图层，z_index 压到最底，遮住贴图透明角落的空隙。
func _make_base() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "WhiteBase"
	layer.z_index = -3
	layer.tile_set = WorldTileset.get_base_tileset()
	return layer


## 全局地面颜料层：z_index=1（高于地面 chunk 的 0，低于特征物/玩家的 y 排序 z）。
## 用绝对世界格坐标，独立于 chunk 生命周期——块卸载后颜料仍在（跨块持久）。
func _make_paint() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "GroundPaint"
	layer.z_index = 1
	layer.tile_set = WorldTileset.get_paint_tileset()
	layer.add_to_group("ground_paint")
	return layer


## 地面行为层：被泼色的格在这里各挂一个 GroundElement（火/霜）。z=2 高于颜料(1)、低于特征物 y 排序。
func _make_effects() -> Node2D:
	var layer := Node2D.new()
	layer.name = "GroundEffects"
	layer.z_index = 2
	return layer


## 泼色：把绝对世界格 world 染成 element 对应的颜料，并起一个行为节点（火/霜）。未知元素不落笔。
func paint_tile(world: Vector2i, element: String) -> void:
	var src := WorldTileset.paint_source_id(element)
	if src < 0:
		return
	_paint.set_cell(world, src, Vector2i(0, 0))
	_spawn_or_update_effect(world, element)


## 擦掉某格的颜料与行为（吸收）。
func erase_paint(world: Vector2i) -> void:
	_paint.erase_cell(world)
	_remove_effect(world)


## 某格的颜料 source id（-1 = 未泼色）。
func paint_source_at(world: Vector2i) -> int:
	return _paint.get_cell_source_id(world)


## 给格 world 起/刷新行为节点：已存在则换元素，否则新建并定位到格中心。
func _spawn_or_update_effect(world: Vector2i, element: String) -> void:
	if _effects.has(world):
		var fx: GroundElement = _effects[world]
		fx.apply(element)
		return
	var fx := GroundElement.new()
	fx.element_id = element
	fx.position = Vector2(world.x + 0.5, world.y + 0.5) * float(WorldTileset.TILE_PX)
	_effects_layer.add_child(fx)
	_effects[world] = fx


## 吸收时清掉行为节点（火熄/霜消）并释放。
func _remove_effect(world: Vector2i) -> void:
	if not _effects.has(world):
		return
	var fx: GroundElement = _effects[world]
	_effects.erase(world)
	fx.clear_behavior()
	fx.queue_free()


## 块加载时把底图对应格刷白（绝对格坐标，与 chunk 世界位置对齐）。
func _fill_base(c: Vector2i) -> void:
	var bx := c.x * WorldGenerator.CHUNK_SIZE
	var by := c.y * WorldGenerator.CHUNK_SIZE
	for ly in WorldGenerator.CHUNK_SIZE:
		for lx in WorldGenerator.CHUNK_SIZE:
			_base.set_cell(Vector2i(bx + lx, by + ly), 0, Vector2i(0, 0))


## 块卸载时擦掉底图对应格，避免底图白格无限累积。
func _erase_base(c: Vector2i) -> void:
	var bx := c.x * WorldGenerator.CHUNK_SIZE
	var by := c.y * WorldGenerator.CHUNK_SIZE
	for ly in WorldGenerator.CHUNK_SIZE:
		for lx in WorldGenerator.CHUNK_SIZE:
			_base.erase_cell(Vector2i(bx + lx, by + ly))
