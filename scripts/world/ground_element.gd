class_name GroundElement
extends Node2D
## 一格被泼色地面的「行为」宿主：挂 ElementBehavior，驱动红=燃烧(火+光照)、蓝=冻结(霜)。
## chunk_manager 在泼色时按格创建/复用，吸收时清除并释放。只给已泼色的稀疏格建节点，
## 不逐格铺（未泼色的格子没有节点，杜绝 WaterCell 式节点爆炸）。

const Behavior := preload("res://scripts/element/element_behavior.gd")

var element_id := ""
var _behavior: ElementBehavior


func _ready() -> void:
	_behavior = Behavior.new()
	_behavior.name = "ElementBehavior"
	_behavior.light_radius = 352.0
	add_child(_behavior)
	if element_id != "":
		_behavior.apply(element_id)


## 换元素 / 重新上色：先清旧行为再应用新元素。地面不可「摧毁」，故跳过 freeze×burn 的碎裂路径。
func apply(element: String) -> void:
	element_id = element
	if _behavior != null:
		_behavior.clear()
		_behavior.apply(element)


## 吸收时清除行为（火熄 / 霜消），随后由 chunk_manager 释放本节点。
func clear_behavior() -> void:
	if _behavior != null:
		_behavior.clear()
