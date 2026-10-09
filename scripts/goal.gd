class_name Goal
extends Area2D
## 目标（「踩上即通关」这一种触发源）：玩家踏入即触发通关效果。
## 放在需要靠颜色解谜才能到达的位置。
##
## 通关效果统一走 RoomEffects（开门 + HUD 反馈）；本脚本只负责「踩上」这个条件。
## 以后换通关标准（元素门/收集门）时，写一个新触发源、调同样的 RoomEffects 即可。

signal reached

## 触发后要解锁的门 id 列表（对应 RoomDoor.door_id，可多扇 → 支持分叉/多出口）。留空则不解锁门。
@export var unlock_door_ids: Array[String] = []
## 是否为最后一间房的目标：true 显示「过关！」；false 显示「门已解锁」提示。
@export var is_final := false

@onready var visual: Node2D = $Visual

var _reached := false
var _pulse := 0.0


func _ready() -> void:
	add_to_group("goal")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_pulse += delta
	var s := 1.0 + 0.08 * sin(_pulse * 3.0)
	visual.scale = Vector2(s, s)


func _on_body_entered(body: Node) -> void:
	if _reached:
		return
	if not body.is_in_group("player"):
		return
	_reached = true
	reached.emit()
	RoomEffects.unlock(self, unlock_door_ids)
	RoomEffects.notify(self, is_final, not unlock_door_ids.is_empty())
