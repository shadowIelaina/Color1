extends StaticBody2D
## 三色神殿方尖碑：固定颜色符文 + 石身染色 + 顶部光晕/晶石。

const DepthSort := preload("res://scripts/depth_sort.gd")
const STONE_BASE := Color(0.2, 0.19, 0.25, 1.0)
const TOP_BASE := Color(0.34, 0.32, 0.4, 1.0)

@export var glow_color := Color(0.95, 0.3, 0.22, 1.0)
@export var z_offset := 0

@onready var stone: Polygon2D = get_node_or_null("Visual") as Polygon2D
@onready var cap: Polygon2D = get_node_or_null("Top") as Polygon2D
@onready var glow: Polygon2D = get_node_or_null("Glow") as Polygon2D
@onready var halo: Polygon2D = get_node_or_null("Halo") as Polygon2D
@onready var crystal: Polygon2D = get_node_or_null("Crystal") as Polygon2D

var _tween: Tween
var _halo_pulse: Tween


func _ready() -> void:
	z_index = DepthSort.z_for(global_position.y) + z_offset
	set_active(false, true)


## 由 boss_arena 在阶段切换时调用：激活的方尖碑明显发光，未激活也保留可辨识的底色。
func set_active(active: bool, instant := false) -> void:
	var blend := 0.55 if active else 0.3
	var stone_color := STONE_BASE.lerp(glow_color, blend)
	var cap_color := TOP_BASE.lerp(glow_color, blend * 0.75)
	var glow_alpha := 1.0 if active else 0.45
	var halo_alpha := 0.65 if active else 0.22
	var crystal_alpha := 1.0 if active else 0.7

	if glow != null:
		glow.color = glow_color
	if halo != null:
		halo.color = glow_color
	if crystal != null:
		crystal.color = glow_color.lightened(0.2)

	if instant:
		if stone != null:
			stone.color = stone_color
		if cap != null:
			cap.color = cap_color
		if glow != null:
			glow.modulate.a = glow_alpha
		if halo != null:
			halo.modulate.a = halo_alpha
			halo.scale = Vector2.ONE
		if crystal != null:
			crystal.modulate.a = crystal_alpha
		_stop_halo_pulse()
		if active:
			_start_halo_pulse()
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	if stone != null:
		_tween.tween_property(stone, "color", stone_color, 0.4)
	if cap != null:
		_tween.tween_property(cap, "color", cap_color, 0.4)
	if glow != null:
		_tween.tween_property(glow, "modulate:a", glow_alpha, 0.4)
	if halo != null:
		_tween.tween_property(halo, "modulate:a", halo_alpha, 0.4)
	if crystal != null:
		_tween.tween_property(crystal, "modulate:a", crystal_alpha, 0.4)

	if active:
		_start_halo_pulse()
	else:
		_stop_halo_pulse()


func _start_halo_pulse() -> void:
	if _halo_pulse != null and _halo_pulse.is_valid():
		_halo_pulse.kill()
	if halo == null:
		return
	halo.scale = Vector2.ONE
	_halo_pulse = create_tween().set_loops()
	_halo_pulse.tween_property(halo, "scale", Vector2(1.15, 1.15), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_halo_pulse.tween_property(halo, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_halo_pulse() -> void:
	if _halo_pulse != null and _halo_pulse.is_valid():
		_halo_pulse.kill()
	if halo != null:
		halo.scale = Vector2.ONE
