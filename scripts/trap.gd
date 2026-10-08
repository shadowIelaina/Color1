class_name Trap
extends Node2D
## 机关：周期性朝玩家（或固定方向）发射飞行物，供「冰墙挡弹」玩法使用。

@export var fire_interval := 2.0          # 发射间隔（秒）
@export var projectile_speed := 900.0     # 飞行物速度
@export var aim_at_player := true         # true=朝玩家当前位置瞄准；false=用 fixed_direction
@export var fixed_direction := Vector2.RIGHT

const PROJECTILE := preload("res://prefabs/items/interaction/projectile.tscn")

var _timer := 0.0


func _ready() -> void:
	_timer = fire_interval * 0.5   # 开局半拍后开火，给玩家反应时间


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = fire_interval
		_fire()


func _fire() -> void:
	var dir := _aim()
	var p := PROJECTILE.instantiate()
	p.setup(dir)
	p.speed = projectile_speed
	add_child(p)
	p.position = dir * 40.0   # 从炮口前发射（相对机关）


func _aim() -> Vector2:
	if aim_at_player:
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			return (player.global_position - global_position).normalized()
	return fixed_direction.normalized()
