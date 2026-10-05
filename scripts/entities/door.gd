class_name Door
extends Area2D
## 门：玩家进入触发切房，可加锁（required_key_id）。

@export var door_id: String = ""
@export var target_scene: String = ""      # 目标房间 res:// 场景路径
@export var target_entrance: String = ""   # 目标房间的入口 id
@export var required_key_id: String = ""   # 非空 = 需要该钥匙
@export var consume_key: bool = false      # 是否消耗钥匙（false = 钥匙可复用）

@onready var _visual: Node2D = $Visual


func _ready() -> void:
	add_to_group("door")
	if door_id == "":
		door_id = name
	body_entered.connect(_on_body_entered)
	GameState.key_added.connect(_refresh_visual)
	GameState.key_used.connect(_refresh_visual)
	_refresh_visual()


func _on_body_entered(body: Node) -> void:
	if SceneManager.is_busy():
		return
	if not body.is_in_group("player"):
		return
	if _is_locked():
		GameState.hint.emit("门锁住了，需要钥匙：%s" % required_key_id)
		return
	_use()


func _is_locked() -> bool:
	return required_key_id != "" and not GameState.has_key(required_key_id)


func _use() -> void:
	if required_key_id != "" and consume_key:
		GameState.consume_key(required_key_id)
	GameState.gate_opened.emit(door_id)
	SceneManager.change_room(target_scene, target_entrance)


func _refresh_visual(_k: String = "") -> void:
	if _visual is CanvasItem:
		_visual.modulate = Color(0.9, 0.45, 0.45) if _is_locked() else Color(0.5, 0.85, 0.5)
