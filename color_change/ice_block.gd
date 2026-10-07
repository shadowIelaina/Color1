class_name IceBlock
extends StaticBody2D
## 冰块闸门：开局已被赋予蓝色并挡住玩家。玩家吸收其蓝色后，冰块破碎、获得蓝并放行。

const Rules := preload("res://scripts/element/element_rules.gd")
const SHATTER := preload("res://effects/shatter/shatter.gd")

## 破碎动画结束后销毁本节点（秒）。
@export var shatter_delay := 1.4

@onready var visual: Sprite2D = $Visual
@onready var collision: CollisionShape2D = $Collision

var _has_blue := true


func _ready() -> void:
	add_to_group("colorable")


func has_color() -> bool:
	return _has_blue


## 点击命中：世界坐标点是否落在 Visual 贴图矩形内。
func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))


## 吸收蓝色：返回元素信息，同时冰块破碎放行。
func absorb_color() -> Dictionary:
	if not _has_blue:
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	_has_blue = false
	_break()
	return {
		"element": "freeze",
		"color": Rules.config("freeze")["color"],
		"color_name": Rules.config("freeze")["color_name"],
	}


## 破碎并放行：先移除碰撞（立刻可通行），再播破碎动画，最后销毁。
func _break() -> void:
	collision.set_deferred("disabled", true)
	var shatter := SHATTER.new()
	shatter.target = visual
	shatter.loop = false
	shatter.seed_value = randf() * 100.0
	add_child(shatter)
	shatter.shatter()
	get_tree().create_timer(shatter_delay).timeout.connect(queue_free)
