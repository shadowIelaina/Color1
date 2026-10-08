class_name ColorableStatic
extends StaticBody2D
## 可上色静态体（带 "Visual" Sprite2D 贴图，如树/木条）：colorable_sprite 的「带碰撞」版本。
## 实现 colorable 契约（apply_color / absorb_color / has_color / contains_point），挂 ElementBehavior。
## 被赋予红则燃烧蔓延、烧尽后 Visual 碎裂并整体销毁（含碰撞）；赋予蓝则冻结。
## 上色/状态视觉反馈交给 ElementBehavior 的 VFX（火焰/冰霜）+ 烧尽碎裂，本脚本不接管贴图材质。

const Rules := preload("res://scripts/element/element_rules.gd")
const Behavior := preload("res://scripts/element/element_behavior.gd")

@onready var visual: Sprite2D = $Visual

var _behavior: Node2D


func _ready() -> void:
	add_to_group("colorable")
	_behavior = Behavior.new()
	_behavior.name = "ElementBehavior"
	add_child(_behavior)


func apply_color(c: Color, color_name: String = "", from_pos: Vector2 = Vector2.INF) -> bool:
	var element := Rules.element_for_color_name(color_name)
	if element != "":
		_behavior.call("apply", element)
	return true


func has_color() -> bool:
	return bool(_behavior.call("has_element"))


func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))


func absorb_color() -> Dictionary:
	var el := str(_behavior.call("current_element"))
	_behavior.call("clear")
	var cfg := Rules.config(el)
	return {
		"element": el,
		"color": cfg.get("color", Color.WHITE),
		"color_name": cfg.get("color_name", ""),
	}
