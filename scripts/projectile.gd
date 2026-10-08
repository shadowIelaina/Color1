class_name Projectile
extends CharacterBody2D
## 机关发射的飞行物：沿 direction 直线飞行，撞到实体（层 2 墙/层 3 箱）或玩家即销毁。
## 撞玩家 = 把玩家沿飞行方向击退（MVP 占位「受伤」，后续可接伤害/HP）。

@export var speed := 900.0
@export var lifetime := 5.0

var direction := Vector2.RIGHT
var _age := 0.0


func setup(dir: Vector2) -> void:
	direction = dir.normalized()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var col := move_and_collide(direction * speed * delta)
	if col == null:
		return
	var collider := col.get_collider()
	if collider != null and collider.is_in_group("player"):
		_hit_player(collider)
	else:
		_blocked()
	queue_free()


func _hit_player(player: Node) -> void:
	if player.has_method("knockback"):
		player.call("knockback", direction, 600.0)


func _blocked() -> void:
	pass   # MVP：撞墙直接销毁（被冰墙/树挡住即成功挡住）
