class_name Lever
extends StatefulObject
## 拉杆/开关：玩家走过触发切换，写入 GameState.switches，驱动 Gate(switch) 开关。

@export var lever_id: String = ""
@export var starts_on: bool = false

var is_on: bool = false

@onready var _interact_area: Area2D = $InteractArea
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if lever_id == "":
		lever_id = name
	if not GameState.switches.has(lever_id):
		GameState.switches[lever_id] = starts_on
	is_on = GameState.switches[lever_id]
	_apply_visual()
	_interact_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		toggle()


func toggle() -> void:
	is_on = not is_on
	GameState.set_switch(lever_id, is_on)
	_apply_visual()


func _apply_visual() -> void:
	if _visual is CanvasItem:
		_visual.modulate = Color(0.4, 1.0, 0.4) if is_on else Color(0.85, 0.85, 0.85)


func save_state() -> Dictionary:
	return {"is_on": is_on}


func restore_state(data: Dictionary) -> void:
	is_on = data.get("is_on", starts_on)
	GameState.set_switch(lever_id, is_on)
	_apply_visual()
