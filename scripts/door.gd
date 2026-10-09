class_name Door
extends Area2D
## 大场景出口门：玩家进入触发切场景（SceneManager.change_room），可加锁。
## 与 RoomDoor（原地开物理门）不同：本门开门 = 切到目标大场景。
## 锁条件复用统一模型：unlock_options（OR 列表）+ unlock_side（单向）。
## 兼容旧字段：required_key_id / consume_key（等价 ["key:<id>"]）。

@export var door_id: String = ""
@export var target_scene: String = ""      # 目标大场景 res:// 场景路径
@export var target_entrance: String = ""   # 目标场景的入口 id
@export var unlock_options: Array[String] = []   # 锁条件 OR 列表（"kind:id"）
@export var unlock_side: Vector2 = Vector2.ZERO
@export var required_key_id: String = ""   # 旧字段：非空 = 需要该钥匙
@export var consume_key: bool = false      # 旧字段：是否消耗钥匙

@onready var _visual: Node2D = get_node_or_null("Visual") as Node2D


func _ready() -> void:
	add_to_group("door")
	if door_id == "":
		door_id = name
	body_entered.connect(_on_body_entered)
	GameState.key_added.connect(_refresh_visual)
	GameState.key_used.connect(_refresh_visual)
	GameState.prop_added.connect(_refresh_visual)
	_refresh_visual()


func _on_body_entered(body: Node) -> void:
	if SceneManager.is_busy():
		return
	if not body.is_in_group("player"):
		return
	if not _on_unlock_side(body):
		GameState.hint.emit("这扇门只能从对面开启")
		return
	if not _conditions_met():
		GameState.hint.emit("门锁住了")
		return
	_use()


## 生效的锁条件：优先 unlock_options，其次旧字段 required_key_id。
func _effective_options() -> Array[String]:
	if not unlock_options.is_empty():
		return unlock_options
	if required_key_id != "":
		return ["key:" + required_key_id]
	return []


func _conditions_met() -> bool:
	var opts := _effective_options()
	if opts.is_empty():
		return true
	for opt in opts:
		if GameState.meets_flag(opt):
			return true
	return false


func _on_unlock_side(body: Node) -> bool:
	if unlock_side == Vector2.ZERO:
		return true
	var dir: Vector2 = body.global_position - global_position
	return dir.dot(unlock_side) > 0.0


func _use() -> void:
	if consume_key:
		if required_key_id != "":
			GameState.consume_key(required_key_id)
		else:
			for opt in unlock_options:
				if GameState.consume_flag(opt):
					break
	GameState.gate_opened.emit(door_id)
	SceneManager.change_room(target_scene, target_entrance)


func _refresh_visual(_k: String = "") -> void:
	if _visual is CanvasItem:
		_visual.modulate = Color(0.9, 0.45, 0.45) if not _conditions_met() else Color(0.5, 0.85, 0.5)
