class_name ParryProjectile
extends CharacterBody2D
## 可弹反子弹：直线飞行，命中「敌对阵营」实体造成伤害与击退；被 Parry 弹反后反向、归属翻转。
##
## 阵营用 source_group 表示（默认 "enemy"，即攻击玩家）。被弹反时 source_group 变为弹反者所属阵营
## （弹反者是玩家 → "player"），于是它转而伤害敌人——「弹反」天然变成「反打」。
##
## 组 "parryable_projectile" 让 Parry 组件发现它（parryable 为真时自动加入）。
##
## 公共 API：
##   setup(direction, source_group := "enemy")  初始化朝向 / 阵营
##   can_parry() -> bool                        现在能否被弹反
##   parry(deflect_dir, parrier) -> bool        由 Parry 调用：反弹（反向 + 归属翻转 + 提速）
##   is_parried() -> bool
## 信号：parried(direction) / hit(target)

signal parried(direction: Vector2)
signal hit(target: Node)

const CoverImpactScript := preload("res://effects/cover_impact/cover_impact.gd")

@export_group("飞行")
@export var speed := 900.0
@export var lifetime := 6.0
@export var direction := Vector2.RIGHT
## 最大飞行距离（世界像素）：超过即消失。0 = 不限制（由 lifetime 决定）。
@export_range(0.0, 8000.0, 10.0) var max_distance := 0.0

@export_group("弹道残留")
## 沿飞行路径周期性留下的地面危险物场景（留空则不留）。
@export var trail_scene: PackedScene
## 残留类型（透传给 GroundHazard.kind）：0 = 燃烧(掉血)，1 = 冰晶(减速)。
@export_enum("burn", "ice_crystal") var trail_kind := 1
## 留痕间隔（秒）。
@export var trail_interval := 0.6
## 残留存活时长（秒）。<0 = 用场景默认值。
@export var trail_lifetime := -1.0

@export_group("命中")
@export var damage := 1.0
@export var knockback_strength := 600.0

@export_group("弹反")
## 是否可被弹反（加入 "parryable_projectile" 组）。
@export var parryable := true
## 反弹后速度倍率。
@export var reflect_speed_scale := 1.2
## 是否只能被弹反一次。
@export var single_parry := true

## 当前阵营：谁发射的（"enemy" / "player" / 自定义组名）。
var source_group := "enemy"

@onready var visual: Node2D = get_node_or_null("Visual")

var _age := 0.0
var _parried := false
var _traveled := 0.0
var _trail_cd := 0.0


func _ready() -> void:
	if parryable:
		add_to_group("parryable_projectile")
	_trail_cd = trail_interval
	_update_visual_rotation()


## 初始化。from 为发射者阵营组名（默认 "enemy"）。
func setup(dir: Vector2, from: String = "enemy") -> void:
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	source_group = from
	_update_visual_rotation()


func is_parried() -> bool:
	return _parried


func can_parry() -> bool:
	return parryable and not (_parried and single_parry)


## 由 Parry 调用：沿 deflect_dir 反弹，归属翻转为弹反者阵营。
func parry(deflect_dir: Vector2, parrier: Node) -> bool:
	if not can_parry():
		return false
	_parried = true
	direction = deflect_dir.normalized() if deflect_dir != Vector2.ZERO else -direction
	speed *= reflect_speed_scale
	source_group = _faction_of(parrier)
	_age = 0.0
	_traveled = 0.0
	# 归属翻转后不再命中「玩家层」（层 1），避免刚弹反就被自己挡住。
	set_collision_mask_value(1, source_group != "player")
	_update_visual_rotation()
	_on_parried_visual()
	parried.emit(direction)
	return true


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var col := move_and_collide(direction * speed * delta)
	_traveled += speed * delta
	if col != null:
		_resolve_hit(col.get_collider())
		_spawn_cover_impact(col)
		queue_free()
		return
	if max_distance > 0.0 and _traveled >= max_distance:
		queue_free()
		return
	_maybe_drop_trail(delta)


## 沿飞行路径周期性留下地面残留（如蓝弹留冰晶）。
func _maybe_drop_trail(delta: float) -> void:
	if trail_scene == null:
		return
	_trail_cd -= delta
	if _trail_cd > 0.0:
		return
	_trail_cd = maxf(trail_interval, 0.05)
	var holder := get_parent()
	if holder == null:
		return
	var h := trail_scene.instantiate()
	if h.get("kind") != null:
		h.set("kind", trail_kind)
	if trail_lifetime >= 0.0 and h.get("lifetime") != null:
		h.set("lifetime", trail_lifetime)
	holder.add_child(h)
	if h is Node2D:
		(h as Node2D).global_position = global_position


func _resolve_hit(collider: Node) -> void:
	if collider == null:
		return
	if collider.is_in_group(source_group):
		return   # 同阵营：不造成伤害
	if _parried and collider.has_method("take_reflected_damage"):
		collider.call("take_reflected_damage")
		hit.emit(collider)
	elif collider.has_method("take_damage"):
		collider.call("take_damage", damage)
		hit.emit(collider)
	if collider.has_method("knockback"):
		collider.call("knockback", direction, knockback_strength)


## 撞到墙/掩体（碰撞层 2）时生成火花；命中玩家/敌人不生成。
func _spawn_cover_impact(col: KinematicCollision2D) -> void:
	var collider := col.get_collider()
	if not (collider is CollisionObject2D):
		return
	if ((collider as CollisionObject2D).collision_layer & 2) == 0:
		return
	var holder := get_parent()
	if holder == null:
		return
	var fx := CoverImpactScript.new()
	holder.add_child(fx)
	fx.global_position = col.get_position()
	if fx.has_method("setup"):
		fx.call("setup", direction)


func _faction_of(node: Node) -> String:
	if node != null:
		if node.is_in_group("player"):
			return "player"
		if node.is_in_group("enemy"):
			return "enemy"
	return "player"


func _on_parried_visual() -> void:
	var gold := Color(1.0, 0.9, 0.35, 1.0)
	if visual is Polygon2D:
		(visual as Polygon2D).color = gold
	elif visual is Sprite2D:
		(visual as Sprite2D).self_modulate = gold


## 让视觉朝向飞行方向（只转视觉，不影响圆形碰撞与移动）。
func _update_visual_rotation() -> void:
	if visual != null:
		visual.rotation = direction.angle()
