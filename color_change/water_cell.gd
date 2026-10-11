class_name WaterCell
extends StaticBody2D
## 单个水格：初始为水。被赋予「蓝」(freeze) 后结冰——冰块填满格、可通行；吸收蓝色则冰融回水。
## 分深/浅水：深水（默认）阻挡玩家、需冻结成冰才能过；浅水（shallow=true）不挡路、可直接行走。
## 两者都能冻结，仅美术不同（浅水用更浅/半透明的贴图，让玩家区分）。
## 属于 "colorable" group，实现 contains_point / apply_color 契约，供玩家鼠标赋予。
## 平面 2D 视觉：水/冰都是一张平铺的格贴图（或纯色），无伪 2.5D 落差。

const Rules := preload("res://scripts/element/element_rules.gd")
const ICE_WALL_SCENE := preload("res://prefabs/items/interaction/ice_wall.tscn")
const ICE_GROWTH_SCENE := preload("res://prefabs/Ice_growth/ice_block.tscn")

## 格子边长（世界单位）。一格水 = 一格 tile（= HeightMap.CELL，256px）。
var cell_size := Vector2(HeightMap.CELL, HeightMap.CELL)

## 水 ↔ 冰切换的淡入淡出时长（秒）。
const FADE_TIME := 0.2

## 水面贴图（可选），为空时用纯色 water_color。
@export var water_texture: Texture2D
## 水面颜色（无贴图时）。
@export var water_color := Color(0.13, 0.48, 0.64)
## 冰块贴图（可选），为空时用纯色 ice_color。
@export var ice_texture: Texture2D
## 冰块颜色（无贴图时）。
@export var ice_color := Color(0.88, 0.95, 1.0)
## 冻结预览（半透明冰块提示）透明度。悬停未结冰水格、手里是蓝时，叠一个半透明冰块预览。
@export_range(0.0, 1.0, 0.05) var freeze_preview_alpha := 0.4
## 浅水：玩家可直接在上面行走（不挡路、可站）。深水（默认 false）：挡路、需冻结成冰才能过。
@export var shallow := false
## 是否由本 WaterCell 绘制基础水面。使用 TileMapLayer 贴图时设为 false，只保留碰撞和结冰。
@export var draw_water := true
## 结冰生长方向兜底值：拿不到玩家位置时（非玩家触发的结冰）固定用这个方向。
## 正常由玩家赋予时，生长方向 = 从玩家站立一侧向外（背离玩家），见 _pick_grow_dir。
@export var ice_grow_dir := Vector2.RIGHT
## 结冰生长时长（秒）。ice_growth 预制体默认 3.0 太慢，冻结取 0.6 左右更干脆。
@export var ice_grow_duration := 0.6

var _frozen := false
var _col: CollisionShape2D
var _water: Node2D   # 水面 Sprite2D / Polygon2D
var _ice: Node2D     # 冰 Sprite2D / Polygon2D
var _preview: Node2D # 冻结预览（半透明冰）
var _tween: Tween
var _ice_wall: Node = null       # 本格上生成的可融冰墙


func _ready() -> void:
	add_to_group("colorable")
	collision_mask = 0
	_build_collision()
	if draw_water:
		_build_water()
	_build_ice()
	_build_preview()
	_ice.visible = false
	_preview.visible = false
	if shallow:
		collision_layer = 0      # 浅水：不挡玩家，可直接行走
		_col.disabled = true
		HeightMap.set_walkable(global_position, true)
	else:
		collision_layer = 2      # 深水：阻挡玩家（玩家 mask 6 = 层 2+3）
		HeightMap.set_walkable(global_position, false)


## 点击命中：世界坐标点是否落在本格范围内。
func contains_point(world_pos: Vector2) -> bool:
	return Rect2(-cell_size * 0.5, cell_size).has_point(to_local(world_pos))


## 被赋予颜色：目前只有「蓝」会让水结冰，其它颜色暂不处理。
## 返回是否真的生效（已结冰或非蓝都不生效），供玩家侧判断是否该消耗种子。
func apply_color(_c: Color, color_name: String = "", _from_pos: Vector2 = Vector2.INF) -> bool:
	if color_name != "蓝":
		return false
	if not _frozen:
		_freeze(_from_pos)
		return true
	# 已结冰：再点一下生成一块可融冰墙（消耗 1 蓝）。
	if _has_wall():
		return false
	_spawn_ice_wall()
	return true


## 是否已结冰。
func is_frozen() -> bool:
	return _frozen


## 是否当前带色：结冰 = 带蓝（可被吸收）。
func has_color() -> bool:
	return _frozen


## 吸收蓝色：冰融回水（重新挡路），玩家获得蓝。
func absorb_color() -> Dictionary:
	if not _frozen:
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	if _has_wall():
		return {"element": "", "color": Color.WHITE, "color_name": ""}  # 有冰墙先融墙再融水
	# 玩家正站在这块冰上时禁止吸收：否则冰一融化玩家就掉进水里。
	if _player_on_cell(get_tree().get_first_node_in_group("player")):
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	_frozen = false
	if not shallow:
		_col.set_deferred("disabled", false)  # 深水恢复碰撞 → 重新挡路
	_fade_to(_ice, _water)
	HeightMap.set_walkable(global_position, shallow)  # 深水不可站、浅水可站
	return {
		"element": "freeze",
		"color": Rules.config("freeze")["color"],
		"color_name": Rules.config("freeze")["color_name"],
	}


## 结冰：取消碰撞（可通行），冰块以「生长」效果浮现盖住水。
func _freeze(from_pos: Vector2 = Vector2.INF) -> void:
	_frozen = true
	_col.set_deferred("disabled", true)
	_reveal_ice(from_pos)
	if _water != null:
		_fade_out_visual(_water)
	HeightMap.set_walkable(global_position, true)   # 冰：可站


## 结冰视觉：有 ice_growth 预制体时播放「从边缘生长」效果；纯色兜底沿用淡入。
func _reveal_ice(from_pos: Vector2 = Vector2.INF) -> void:
	if _ice == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_ice.visible = true
	if _ice.has_method("start"):
		_ice.modulate.a = 1.0
		_ice.grow_dir = _pick_grow_dir(from_pos)
		_ice.start()
	else:
		_ice.modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(_ice, "modulate:a", 1.0, FADE_TIME)


## 结冰生长方向：从玩家站立的一侧向外生长（背离玩家），量化到四向。
## 生长前端沿 grow_dir 方向推进，所以取「背离玩家」的方向 = 冰从玩家那一侧开始长出去。
## 拿不到玩家位置（非玩家触发）时退回 ice_grow_dir 固定方向。
func _pick_grow_dir(from_pos: Vector2 = Vector2.INF) -> Vector2:
	var origin := from_pos
	if origin == Vector2.INF:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			return ice_grow_dir
		origin = player.global_position
	var to_player := origin - global_position
	if absf(to_player.x) >= absf(to_player.y):
		return Vector2.LEFT if to_player.x >= 0.0 else Vector2.RIGHT
	return Vector2.UP if to_player.y >= 0.0 else Vector2.DOWN


## 单方向淡出一个视觉（冻结时水面淡出）。
func _fade_out_visual(vis: Node2D) -> void:
	if vis == null:
		return
	var tw := create_tween()
	tw.tween_property(vis, "modulate:a", 0.0, FADE_TIME)
	tw.tween_callback(func():
		vis.visible = false
		vis.modulate.a = 1.0
	)


func _has_wall() -> bool:
	return _ice_wall != null and is_instance_valid(_ice_wall)


## 在结冰的水格上生成一块可融冰墙（消耗 1 蓝，见 apply_color）。
func _spawn_ice_wall() -> void:
	var wall := ICE_WALL_SCENE.instantiate()
	wall.position = Vector2.ZERO   # 本格中心
	wall.z_index = 1               # 盖在水格上方；点击优先级高于水格（吸收先融墙）
	add_child(wall)
	_ice_wall = wall


## 淡入淡出：把 from 视觉淡出、to 视觉淡入。快速反复切换时会有轻微跳变，可接受。
func _fade_to(from_vis: Node2D, to_vis: Node2D) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if from_vis != null:
		_tween.tween_property(from_vis, "modulate:a", 0.0, FADE_TIME)
	if to_vis != null:
		to_vis.modulate.a = 0.0
		to_vis.visible = true
		_tween.tween_property(to_vis, "modulate:a", 1.0, FADE_TIME)
	_tween.chain().tween_callback(func():
		if from_vis != null:
			from_vis.visible = false
			from_vis.modulate.a = 1.0
	)


## 玩家是否正站在本格（脚底在本格范围内）。用于「玩家站在冰上时禁止吸收」，
## 避免冰融化把玩家坑进水里。
func _player_on_cell(player: Node) -> bool:
	if player == null or not (player is Node2D):
		return false
	return Rect2(-cell_size * 0.5, cell_size).has_point(to_local((player as Node2D).global_position))


func _build_collision() -> void:
	var shape := RectangleShape2D.new()
	shape.size = cell_size
	_col = CollisionShape2D.new()
	_col.name = "Collision"
	_col.shape = shape
	add_child(_col)


## 构建水/冰视觉：优先贴图（Sprite2D，缩放到一格），否则纯色（Polygon2D）。
func _make_visual(vis_name: String, texture: Texture2D, color: Color) -> Node2D:
	if texture != null:
		var s := Sprite2D.new()
		s.name = vis_name
		s.centered = true
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.texture = texture
		var ts := texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			s.scale = cell_size / ts
		return s
	var p := Polygon2D.new()
	p.name = vis_name
	var ext := cell_size * 0.5 + Vector2(0.5, 0.5)  # 相邻格轻微重叠消除接缝
	p.polygon = PackedVector2Array([
		Vector2(-ext.x, -ext.y), Vector2(ext.x, -ext.y),
		Vector2(ext.x, ext.y), Vector2(-ext.x, ext.y),
	])
	p.color = color
	return p


func _build_water() -> void:
	_water = _make_visual("Water", water_texture, water_color)
	add_child(_water)


func _build_ice() -> void:
	if ice_texture != null:
		_build_ice_growth()
	else:
		_ice = _make_visual("Ice", null, ice_color)
		add_child(_ice)


## 用 ice_growth 预制体构建冰视觉：冻结时从边缘生长浮现（shader 进度 + 边缘粒子）。
func _build_ice_growth() -> void:
	var ice := ICE_GROWTH_SCENE.instantiate()
	ice.name = "Ice"
	ice.auto_start = false               # 先不生长，等结冰时再 start()
	ice.grow_dir = ice_grow_dir
	ice.grow_duration = ice_grow_duration
	var sprite := ice.get_node("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = ice_texture
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var ts := ice_texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			sprite.scale = cell_size / ts   # 与 _make_visual 一致：缩到一格
		# 关键：预制体的 sub_resource 在所有实例间共享。若不复制，多个冰格会共用同一份
		# ShaderMaterial，后结冰的格子改 progress/grow_dir 会把已结冰格子的生长动画重播一遍。
		if sprite.material is ShaderMaterial:
			sprite.material = (sprite.material as ShaderMaterial).duplicate()
	var particles := ice.get_node("GPUParticles2D") as GPUParticles2D
	if particles != null and particles.process_material is ParticleProcessMaterial:
		particles.process_material = (particles.process_material as ParticleProcessMaterial).duplicate()
	_ice = ice
	add_child(ice)


func _build_preview() -> void:
	_preview = _make_visual("FreezePreview", ice_texture, ice_color)
	_preview.modulate = Color(1, 1, 1, freeze_preview_alpha)
	_preview.visible = false
	add_child(_preview)


## 显示/隐藏冻结预览（半透明冰块）。
func set_freeze_preview(value: bool) -> void:
	if _preview != null:
		_preview.visible = value
