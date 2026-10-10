class_name PushableBox
extends StatefulObject
## 可推箱：CharacterBody2D 子节点承载物理与视觉，玩家可推动。位置会被保存/恢复。

const DepthSort := preload("res://scripts/depth_sort.gd")

@onready var _body: CharacterBody2D = $Body


func _ready() -> void:
	super._ready()


## 箱子可被推动，位置会变，故每帧按脚底 Y 重算 z_index（高障碍物遮挡玩家）。
func _physics_process(_delta: float) -> void:
	_body.z_index = DepthSort.z_for(_body.global_position.y)


func save_state() -> Dictionary:
	return {"pos": _body.global_position}


func restore_state(data: Dictionary) -> void:
	if data.has("pos"):
		_body.global_position = data["pos"]
		_body.velocity = Vector2.ZERO
