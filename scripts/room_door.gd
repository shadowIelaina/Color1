class_name RoomDoor
extends StaticBody2D
## 统一物理门（房与房之间，原地开门，不切场景）。
## - 默认挡路（层 2），开锁后取消碰撞 + 贴图淡出
## - unlock_options：锁条件 OR 列表（"kind:id"，kind ∈ key/item/switch/ability/element）
## - unlock_side：单向——非零时只有从该法线指向的一侧靠近才能开（出生点门）
## - 条件满足 + 站在可开侧 → 自动开门（锁存 + 持久化，离开大场景再回来保持开）
## 也可被 Goal（RoomEffects.unlock）直接 open() 解锁。
## 需要子节点：Visual（门贴图 CanvasItem）、Collision（矩形 CollisionShape2D）、
##            Trigger（Area2D，检测玩家靠近；可选，缺省则只能被程序 open()）。

@export var door_id: String = ""
@export var unlock_options: Array[String] = []   # 如 ["key:bronze", "item:torch"]
@export var unlock_side: Vector2 = Vector2.ZERO   # 单向：单位法线，指向可开侧
@export var starts_open := false
@export var consume_on_open := false             # 开门时是否消耗钥匙（道具/开关/能力/元素不消耗）
@export var open_fade := 0.3
@export var state_id: String = ""                # 持久化键，默认 = door_id

@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem
@onready var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
@onready var trigger: Area2D = get_node_or_null("Trigger") as Area2D

var is_open := false


func _ready() -> void:
	add_to_group("room_door")
	add_to_group("stateful")
	if door_id == "":
		door_id = name
	if state_id == "":
		state_id = door_id
	collision_layer = 2   # 挡玩家（玩家 collision_mask 含层 2）
	collision_mask = 0
	if trigger != null:
		trigger.collision_layer = 0
		trigger.collision_mask = 1   # 只检测玩家（层 1）
		trigger.body_entered.connect(_on_body_entered)
	if starts_open:
		_apply_open()


func _on_body_entered(body: Node) -> void:
	if is_open:
		return
	if not body.is_in_group("player"):
		return
	if not _on_unlock_side(body):
		GameState.hint.emit("这扇门只能从对面开启")
		return
	if not _conditions_met():
		GameState.hint.emit("门锁住了")
		return
	open()


## 开门：取消碰撞 + 门贴图淡出。幂等（只开一次）。
func open() -> void:
	if is_open:
		return
	is_open = true
	_apply_open()
	if consume_on_open:
		for opt in unlock_options:
			if GameState.consume_flag(opt):
				break
	GameState.gate_opened.emit(door_id)


## 锁条件是否满足（unlock_options 为空 = 无锁，直接可开）。
func _conditions_met() -> bool:
	if unlock_options.is_empty():
		return true
	for opt in unlock_options:
		if GameState.meets_flag(opt):
			return true
	return false


## 单向判定：玩家是否在可开的一侧。
func _on_unlock_side(body: Node) -> bool:
	if unlock_side == Vector2.ZERO:
		return true
	var dir: Vector2 = body.global_position - global_position
	return dir.dot(unlock_side) > 0.0


func _apply_open() -> void:
	if collision != null:
		collision.set_deferred("disabled", true)
	if trigger != null:
		trigger.set_deferred("monitoring", false)
	if visual != null:
		var t := create_tween()
		t.tween_property(visual, "modulate:a", 0.0, open_fade)


# —— 状态持久化（Room 进出场时统一 save/restore）——
func save_state() -> Dictionary:
	return {"is_open": is_open}


func restore_state(data: Dictionary) -> void:
	is_open = data.get("is_open", starts_open)
	if is_open:
		_apply_open()
