class_name StatefulObject
extends Node2D
## 可持久化物体基类：子类实现 save_state() / restore_state()。
## Room 会在进出场时统一保存/恢复这些物体。
## 物理节点（碰撞/检测）建议放在子节点，本体只负责逻辑与视觉。

@export var state_id: String = ""


func _ready() -> void:
	add_to_group("stateful")
	if state_id == "":
		state_id = name


func save_state() -> Dictionary:
	return {}


func restore_state(_data: Dictionary) -> void:
	pass
