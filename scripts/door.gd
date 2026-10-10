class_name Door
extends Area2D
## 大场景出口传送门：玩家进入即传送到目标场景的目标入口。
## 解锁方式（每扇门选一种）：
##   - required_key_id：1:1 钥匙门——需要对应钥匙，开门即消耗销毁（见 KeyLock）。
##   - unlock_options：非钥匙 OR 锁（item/switch/ability/element），满足即永久。
##   两者都留空 = 纯传送点，踩上即切场景；同时配置时钥匙优先。
## 解锁记录写入 GameState.opened_gates：解锁后重进此关仍是开的（防重复判定/软锁）。

const Lock := preload("res://scripts/lock_condition.gd")

@export var door_id: String = ""
@export var target_scene: String = ""      # 目标大场景 res:// 场景路径
@export var target_entrance: String = ""   # 目标场景的入口 id
## 1:1 钥匙门：需要该 id 的钥匙，开门时钥匙被消耗销毁。留空 = 不用钥匙。
@export var required_key_id: String = ""
@export var unlock_options: Array[String] = []   # 非钥匙 OR 锁（"kind:id"）
@export var unlock_side: Vector2 = Vector2.ZERO
## 「门被解锁了」提示后到切场景的延迟（秒），让玩家看到提示。
@export var unlock_delay := 0.8

@onready var _visual: Node2D = get_node_or_null("Visual") as Node2D

var _lock: Lock
var _key_lock: KeyLock
var _using := false


func _ready() -> void:
	add_to_group("door")
	if door_id == "":
		door_id = name
	_lock = Lock.new(unlock_options, unlock_side)
	_key_lock = KeyLock.new(required_key_id)
	body_entered.connect(_on_body_entered)
	GameState.key_added.connect(_refresh_visual)
	GameState.key_used.connect(_refresh_visual)
	GameState.prop_added.connect(_refresh_visual)
	GameState.ability_added.connect(_refresh_visual)
	GameState.switch_changed.connect(_refresh_visual)
	_refresh_visual()


func _on_body_entered(body: Node) -> void:
	if _using or SceneManager.is_busy():
		return
	if not body.is_in_group("player"):
		return
	# 已解锁过 → 直接传送，不再需要满足条件。
	if GameState.is_gate_opened(door_id):
		_teleport()
		return
	if not _lock.on_unlock_side(body, global_position):
		GameState.hint.emit("这扇门只能从对面开启")
		return
	# 1:1 钥匙门优先。
	var key_result := _key_lock.try_unlock()
	if key_result == KeyLock.Result.NO_KEY:
		return
	if key_result == KeyLock.Result.UNLOCKED:
		_unlock_and_pass(false)   # 钥匙的「使用」消息已由 KeyLock 发出
		return
	# 非钥匙锁 / 无锁。
	if unlock_options.is_empty():
		_teleport()
		return
	if not _lock.is_met():
		GameState.hint.emit("门锁住了")
		return
	_unlock_and_pass(true)


## 解锁：记录已开 → （可选）提示 → 延迟 → 传送。
func _unlock_and_pass(announce: bool) -> void:
	_using = true
	GameState.mark_gate_opened(door_id)
	GameState.gate_opened.emit(door_id)
	if announce:
		GameState.notice.emit("门被解锁了")
	_fade_open()
	await get_tree().create_timer(unlock_delay).timeout
	_teleport()


func _teleport() -> void:
	SceneManager.change_room(target_scene, target_entrance)


## 锁定状态用明暗微调表达：可开时正常，未满足时整体调暗。
func _refresh_visual(_a = null, _b = null) -> void:
	if not (_visual is CanvasItem):
		return
	var openable := GameState.is_gate_opened(door_id) or _lock.is_met()
	if not openable and required_key_id != "":
		openable = GameState.has_key(required_key_id)
	_visual.modulate = Color(1, 1, 1, 1) if openable else Color(0.55, 0.55, 0.55, 1)


func _fade_open() -> void:
	if _visual is CanvasItem:
		var t := create_tween()
		t.tween_property(_visual, "modulate:a", 0.2, 0.3)
