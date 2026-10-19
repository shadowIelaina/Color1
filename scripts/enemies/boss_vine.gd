class_name BossVine
extends StaticBody2D
## Boss（绿怪）召唤的藤蔓：层 2 真物理挡路，生长动画，寿命到收缩消失；可被红(burn)烧掉。
## ⚠️ 不要定义 is_frozen()（player._water_at_mouse 会把带 is_frozen 的 colorable 误判成水格崩溃）。

const Rules := preload("res://scripts/element/element_rules.gd")
const DepthSort := preload("res://scripts/depth_sort.gd")

@export var lifetime := 8.0
@export var grow_time := 0.3
@export_range(8.0, 256.0, 2.0) var hit_radius := 48.0

var _age := 0.0
var _dying := false

@onready var visual: Node2D = get_node_or_null("Visual")


func _ready() -> void:
	add_to_group("colorable")
	add_to_group("boss_vine")
	collision_layer = 2
	collision_mask = 0
	z_index = DepthSort.z_for(global_position.y)
	scale = Vector2(0.05, 0.05)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, grow_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_age += delta
	if _age >= lifetime:
		_despawn()


## 收缩消失。
func _despawn() -> void:
	if _dying:
		return
	_dying = true
	set_physics_process(false)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(0.05, 0.05), 0.25)
	t.tween_callback(queue_free)


# —— colorable 契约 ——

## 给红(burn) → 烧掉；其余无效。
func apply_color(_c: Color, color_name: String = "", _from_pos: Vector2 = Vector2.INF) -> bool:
	if Rules.element_for_color_name(color_name) == "burn":
		_despawn()
		return true
	return false


func has_color() -> bool:
	return false


func absorb_color() -> Dictionary:
	return {"element": "", "color": Color.WHITE, "color_name": ""}


func contains_point(world_pos: Vector2) -> bool:
	return global_position.distance_to(world_pos) <= hit_radius
