class_name Switch
extends Area2D
## 开关（压力板 / 拉杆）：玩家进入触发区即把 GameState 的 switch 置位，
## 供 unlock_options=["switch:<id>"] 的门/闸使用。
##
## 三种模式（用 toggle / one_shot 组合）：
##   toggle=true              拉杆：每次进入翻转开/关。
##   toggle=false, one_shot=true（默认）  锁存触发：进入一次即永久开。
##   toggle=false, one_shot=false          压力板：站上去开、离开即关。
##
## 需要（可选）子节点：Visual（开关贴图 CanvasItem，按 on/off 换色）。
## 碰撞盒用本节点自身的 CollisionShape2D，本节点只检测玩家（层 1）。

@export var switch_id: String = ""
@export var toggle := false
@export var one_shot := true
@export var starts_on := false
@export var on_color := Color(0.5, 0.9, 0.5)
@export var off_color := Color(0.7, 0.5, 0.4)

@onready var _visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

var _on := false


func _ready() -> void:
	add_to_group("switch")
	if switch_id == "":
		switch_id = name
	collision_layer = 0
	collision_mask = 1   # 只检测玩家（层 1）
	_on = GameState.is_switch_on(switch_id)
	if starts_on and not _on:
		_on = true
		GameState.set_switch(switch_id, true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_refresh()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if toggle:
		_commit(not _on)
	elif one_shot:
		if not _on:
			_commit(true)
	else:
		_commit(true)


## 压力板模式：离开即关。
func _on_body_exited(body: Node) -> void:
	if toggle or one_shot:
		return
	if body.is_in_group("player"):
		_commit(false)


func _commit(value: bool) -> void:
	if _on == value:
		return
	_on = value
	GameState.set_switch(switch_id, value)
	_refresh()


func _refresh() -> void:
	if _visual != null:
		_visual.modulate = on_color if _on else off_color
