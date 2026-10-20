class_name ItemPickup
extends StatefulObject
## 关键道具：玩家碰到即拾取到 GameState.props 背包（供「道具门」条件使用）。
## 结构：`Node2D` + `PickupArea`（Area2D）+ `Visual` 子节点。

@export var prop_id: String = ""
## 收集页显示名称与图标；图标留空时自动使用 Visual 的贴图。
@export var item_name: String = ""
## 拾取纸签下方的说明；生命道具留空时自动显示增加的生命值。
@export_multiline var item_description: String = ""
@export var inventory_icon: Texture2D

@onready var _pickup_area: Area2D = $PickupArea
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if prop_id == "":
		prop_id = name
	preload("res://scripts/pickup_presentation.gd").register_item("prop", prop_id, item_name if item_name != "" else str(name), _visual, inventory_icon)
	_pickup_area.body_entered.connect(_on_body_entered)
	_refresh()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if GameState.has_prop(prop_id):
		return
	GameState.add_prop(prop_id)
	GameState.item_collected.emit(prop_id)
	preload("res://scripts/pickup_presentation.gd").announce("prop", prop_id, item_description if item_description != "" else "已收好")
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
