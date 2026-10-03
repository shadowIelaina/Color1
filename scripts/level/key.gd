class_name Key
extends StatefulObject
## 钥匙：玩家碰到即拾取到 GameState 背包。
## 若被消耗，重进房间后会重新出现（防软锁）。

@export var key_id: String = ""

@onready var _pickup_area: Area2D = $PickupArea
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if key_id == "":
		key_id = name
	_pickup_area.body_entered.connect(_on_body_entered)
	_refresh()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if GameState.has_key(key_id):
		return
	GameState.add_key(key_id)
	GameState.item_collected.emit(key_id)
	_refresh()


func _refresh() -> void:
	var held := GameState.has_key(key_id)
	if _visual is CanvasItem:
		_visual.visible = not held
	_pickup_area.set_deferred("monitoring", not held)


func save_state() -> Dictionary:
	return {}


func restore_state(_data: Dictionary) -> void:
	_refresh()
