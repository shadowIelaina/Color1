class_name BirdAI
extends CharacterBody2D
## 小鸟简单移动 AI：左右巡逻，并随方向转向。
## 蓝色（stability 特性）→ 冻结不动；白色重置后恢复移动。

@export var speed := 60.0
@export var patrol_distance := 120.0

var _start_x := 0.0
var _moving_right := true

@onready var sprite: Sprite2D = $Sprite2D
@onready var colorable := $Sprite2D as Colorable


func _ready() -> void:
	_start_x = global_position.x
	_update_facing()


func _physics_process(delta: float) -> void:
	if colorable.traits.get("stability", false):
		return  # 蓝色 = 稳定 = 冻结

	var dir := Vector2.RIGHT if _moving_right else Vector2.LEFT
	velocity = dir * speed
	move_and_slide()
	_update_facing()

	if global_position.x >= _start_x + patrol_distance:
		_moving_right = false
	elif global_position.x <= _start_x - patrol_distance:
		_moving_right = true


## 按移动方向翻转贴图。假设 bird.png 默认朝右；若反了把 not _moving_right 改成 _moving_right。
func _update_facing() -> void:
	sprite.flip_h = not _moving_right
