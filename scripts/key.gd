class_name Key
extends StatefulObject
## 钥匙：玩家碰到即拾取到 GameState.keys 背包，并在左上角记录一条消息。
## 1:1 钥匙门：key_id 唯一，对应一扇 Door / RoomDoor 的 required_key_id；开门时被消耗销毁。
## 结构：`Node2D` + `PickupArea`（Area2D）+ `Visual` 子节点（与 item_pickup 一致）。

@export var key_id: String = ""
## 提示里显示的钥匙名（留空则用 key_id）。
@export var key_name: String = ""

@onready var _pickup_area: Area2D = $PickupArea
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if key_id == "":
		key_id = name
	state_id = "key:" + key_id   # 与门/机关的 state_id 命名空间隔开，避免撞键
	GameState.register_key(key_id, key_name)
	_pickup_area.body_entered.connect(_on_body_entered)
	_refresh()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if GameState.has_key(key_id) or GameState.was_key_used(key_id):
		return
	GameState.add_key(key_id)
	GameState.item_collected.emit(key_id)
	GameState.notice.emit(KeyLock.pickup_message(_display_name()))
	_refresh()


## 持有中或已被用掉的钥匙都从世界里消失（不重刷）。
func _refresh() -> void:
	var gone := GameState.has_key(key_id) or GameState.was_key_used(key_id)
	if _visual is CanvasItem:
		_visual.visible = not gone
	_pickup_area.set_deferred("monitoring", not gone)


func _display_name() -> String:
	return key_name if key_name != "" else key_id


func save_state() -> Dictionary:
	return {}


func restore_state(_data: Dictionary) -> void:
	_refresh()
