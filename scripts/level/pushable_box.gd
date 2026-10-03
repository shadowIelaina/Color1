class_name PushableBox
extends StatefulObject
## 可推箱：RigidBody2D 子节点承载物理与视觉，玩家可推动。位置会被保存/恢复。

@onready var _body: RigidBody2D = $Body


func _ready() -> void:
	super._ready()
	_body.gravity_scale = 0.0
	_body.lock_rotation = true


func save_state() -> Dictionary:
	return {"pos": _body.global_position}


func restore_state(data: Dictionary) -> void:
	if data.has("pos"):
		_body.global_position = data["pos"]
		_body.linear_velocity = Vector2.ZERO
