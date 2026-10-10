class_name AbilityPickup
extends StatefulObject
## 能力拾取：玩家碰到即把该能力永久授予玩家（GameState.set_ability）。
## 供 unlock_options=["ability:<id>"] 的门/闸使用（如二段跳、冲刺、潜水）。
## 结构同 item_pickup.gd：需要 PickupArea（Area2D）与 Visual 子节点。

@export var ability_id: String = ""

@onready var _pickup_area: Area2D = $PickupArea
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if ability_id == "":
		ability_id = name
	_pickup_area.body_entered.connect(_on_body_entered)
	_refresh()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if GameState.has_ability(ability_id):
		return
	GameState.set_ability(ability_id)
	GameState.item_collected.emit(ability_id)
	_refresh()


func _refresh() -> void:
	var held := GameState.has_ability(ability_id)
	if _visual is CanvasItem:
		_visual.visible = not held
	_pickup_area.set_deferred("monitoring", not held)


func save_state() -> Dictionary:
	return {}


func restore_state(_data: Dictionary) -> void:
	_refresh()
