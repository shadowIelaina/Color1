class_name Trap
extends Area2D
## 铁球机关：在两个设定点之间来回滚动，玩家碰到就掉血。
## 点 A = 节点自身 position（关卡里摆放的位置）；点 B = position + travel。
## speed 匀速往返；碰到玩家按 damage 扣血（受击无敌由 Player.take_damage 内部处理）。

const DepthSort := preload("res://scripts/depth_sort.gd")

@export var travel := Vector2(400, 0)   # 点 B 相对点 A 的偏移（世界像素）
@export var speed := 400.0               # 往返速度（像素/秒）
@export var damage := 1                  # 玩家碰到一次的伤害

var _origin := Vector2.ZERO
var _going_to_b := true
var _ball_radius := 60.0


func _ready() -> void:
	_origin = position
	var collision := $CollisionShape2D as CollisionShape2D
	if collision != null:
		var circle := collision.shape as CircleShape2D
		if circle != null:
			_ball_radius = circle.radius
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var dest := _origin + travel if _going_to_b else _origin
	position = position.move_toward(dest, speed * delta)
	if position == dest:
		_going_to_b = not _going_to_b
	# 深度排序：铁球按底部（脚底）Y 定 z，与玩家/树一致，玩家走到球后（北）侧会被球挡住。
	z_index = DepthSort.z_for(global_position.y + _ball_radius)


func _on_body_entered(body: Node2D) -> void:
	if body != null and body.is_in_group("player") and body.has_method("take_damage"):
		body.call("take_damage", damage)
