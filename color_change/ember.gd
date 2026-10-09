class_name Ember
extends StaticBody2D
## 火种（余烬）：开局已被赋予红色并挡住玩家。玩家吸收其红色后，火种熄灭（破碎）、获得红并放行。
## 红色（燃烧）的初始种子来源，对标 ice_block.gd 的红色版本。

const Rules := preload("res://scripts/element/element_rules.gd")
const SHATTER := preload("res://effects/shatter/shatter.gd")

## 熄灭动画结束后销毁本节点（秒）。
@export var shatter_delay := 1.4

## 吸收后返还的红色数量。默认 3（红色种子闸门），对标 ice_block 的蓝色种子闸门。
@export var seed_amount := 3

@onready var visual: Sprite2D = $Visual
@onready var collision: CollisionShape2D = $Collision

var _has_red := true


func _ready() -> void:
	add_to_group("colorable")


func has_color() -> bool:
	return _has_red


## 点击命中：世界坐标点是否落在 Visual 贴图矩形内。
func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))


## 吸收红色：返回元素信息，同时火种熄灭放行。
func absorb_color() -> Dictionary:
	if not _has_red:
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	_has_red = false
	_break()
	return {
		"element": "burn",
		"color": Rules.config("burn")["color"],
		"color_name": Rules.config("burn")["color_name"],
		"amount": seed_amount,
	}


## 熄灭并放行：先移除碰撞（立刻可通行），再播破碎动画，最后销毁。
func _break() -> void:
	collision.set_deferred("disabled", true)
	var shatter := SHATTER.new()
	shatter.target = visual
	shatter.loop = false
	shatter.seed_value = randf() * 100.0
	add_child(shatter)
	shatter.shatter()
	get_tree().create_timer(shatter_delay).timeout.connect(queue_free)
