class_name ItemPickup
extends StatefulObject
## 关键道具：玩家碰到即拾取到 GameState.props 背包（供「道具门」条件使用）。
## 结构仿 key.gd：需要 PickupArea（Area2D）与 Visual 子节点。

@export var prop_id: String = ""

@onready var _pickup_area: Area2D = $PickupArea
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if prop_id == "":
		prop_id = name
	_pickup_area.body_entered.connect(_on_body_entered)
	_refresh()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if GameState.has_prop(prop_id):
		return
	GameState.add_prop(prop_id)
	GameState.item_collected.emit(prop_id)
	_refresh()


func _refresh() -> void:
	var held := GameState.has_prop(prop_id)
	if _visual is CanvasItem:
		_visual.visible = not held
	_pickup_area.set_deferred("monitoring", not held)


func save_state() -> Dictionary:
	return {}


func restore_state(_data: Dictionary) -> void:
	_refresh()
