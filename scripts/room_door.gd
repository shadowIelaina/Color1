class_name RoomDoor
extends StaticBody2D
## 统一物理门（房与房之间，原地开门，不切场景）。
## - 默认挡路（层 2），开锁后取消碰撞 + 贴图淡出
## - required_key_id：1:1 钥匙门——需要对应钥匙，开门即消耗销毁（见 KeyLock）
## - unlock_options：非钥匙 OR 锁（"kind:id"，kind ∈ item/switch/ability/element）
## - unlock_side：单向——非零时只有从该法线指向的一侧靠近才能开（出生点门）
## - 条件满足 + 站在可开侧 → 自动开门（锁存 + 持久化，离开大场景再回来保持开）
## 也可被 Goal（RoomEffects.unlock）直接 open() 解锁。
## 需要子节点：Visual（门贴图 CanvasItem）、Collision（矩形 CollisionShape2D）、
##            Trigger（Area2D，检测玩家靠近；可选，缺省则只能被程序 open()）。

const Lock := preload("res://scripts/lock_condition.gd")

@export var door_id: String = ""
## 1:1 钥匙门：需要该 id 的钥匙，开门时钥匙被消耗销毁。留空 = 不用钥匙。
@export var required_key_id: String = ""
@export var unlock_options: Array[String] = []   # 如 ["item:torch", "switch:bridge"]
@export var unlock_side: Vector2 = Vector2.ZERO   # 单向：单位法线，指向可开侧
@export var starts_open := false
@export var open_fade := 0.3
@export var state_id: String = ""                # 持久化键，默认 = door_id
## 自动阻挡区域：阻挡碰撞尺寸 = Visual（橙点）宽高 × block_scale。Vector2.ZERO = 关闭（用场景里手动配的 Collision）。
## 点保持小、区域够大，防止玩家从门旁边绕过去。例：(4, 9) = 宽 4 倍点、高 9 倍点。
@export var block_scale: Vector2 = Vector2.ZERO
## 触发区外扩（世界像素，单边）：触发区 = 阻挡区四边各外扩 trigger_pad。
## 须 >0：大阻挡会把触发区包住，玩家先撞墙、进不了触发区就永远开不了门。
@export var trigger_pad: float = 0.0

@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem
@onready var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
@onready var trigger: Area2D = get_node_or_null("Trigger") as Area2D

var is_open := false

var _lock: Lock
var _key_lock: KeyLock


func _ready() -> void:
	add_to_group("room_door")
	add_to_group("stateful")
	if door_id == "":
		door_id = name
	if state_id == "":
		state_id = door_id
	_lock = Lock.new(unlock_options, unlock_side)
	_key_lock = KeyLock.new(required_key_id)
	collision_layer = 2   # 挡玩家（玩家 collision_mask 含层 2）
	collision_mask = 0
	if trigger != null:
		trigger.collision_layer = 0
		trigger.collision_mask = 1   # 只检测玩家（层 1）
		trigger.body_entered.connect(_on_body_entered)
	_apply_region()
	if starts_open:
		_apply_open()


func _on_body_entered(body: Node) -> void:
	if is_open:
		return
	if not body.is_in_group("player"):
		return
	if not _lock.on_unlock_side(body, global_position):
		GameState.hint.emit("这扇门只能从对面开启")
		return
	# 1:1 钥匙门优先。
	var key_result := _key_lock.try_unlock()
	if key_result == KeyLock.Result.NO_KEY:
		return
	if key_result == KeyLock.Result.UNLOCKED:
		open()
		return
	# 非钥匙锁 / 无锁。
	if not _lock.is_met():
		GameState.hint.emit("门锁住了")
		return
	open()


## 开门：取消碰撞 + 门贴图淡出。幂等（只开一次）。
func open() -> void:
	if is_open:
		return
	is_open = true
	_apply_open()
	GameState.gate_opened.emit(door_id)


## 自动区域：把阻挡碰撞设为「橙点(Visual)宽高 × block_scale」，触发区再外扩 trigger_pad。
## 新建 RectangleShape2D 再赋值（不原地改 shape.size），避免改到与其它节点共享的 SubResource。
func _apply_region() -> void:
	if block_scale == Vector2.ZERO:
		return
	var dot := _visual_size()
	if dot == Vector2.ZERO:
		return
	var block_size := dot * block_scale
	if collision != null:
		var rect := RectangleShape2D.new()
		rect.size = block_size
		collision.shape = rect
		collision.position = Vector2.ZERO
	if trigger != null and trigger_pad > 0.0:
		_resize_trigger(block_size + Vector2(trigger_pad, trigger_pad) * 2.0)


## 取 Visual（橙点）的宽高：Polygon2D 用多边形包围盒，Sprite2D 用贴图尺寸，均乘自身 scale。
func _visual_size() -> Vector2:
	if visual == null:
		return Vector2.ZERO
	if visual is Polygon2D:
		var poly := (visual as Polygon2D).polygon
		if poly.is_empty():
			return Vector2.ZERO
		var mn := poly[0]
		var mx := poly[0]
		for p in poly:
			mn = mn.min(p)
			mx = mx.max(p)
		return (mx - mn) * (visual as Polygon2D).scale
	if visual is Sprite2D:
		var spr := visual as Sprite2D
		if spr.texture != null:
			return spr.texture.get_size() * spr.scale
	return Vector2.ZERO


func _resize_trigger(size: Vector2) -> void:
	for c in trigger.get_children():
		if c is CollisionShape2D:
			var rect := RectangleShape2D.new()
			rect.size = size
			(c as CollisionShape2D).shape = rect
			(c as CollisionShape2D).position = Vector2.ZERO


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
