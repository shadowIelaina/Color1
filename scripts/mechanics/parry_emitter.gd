class_name ParryEmitter
extends CharacterBody2D
const DepthSort := preload("res://scripts/depth_sort.gd")
signal projectile_fired(projectile: Node)
## 弹幕发射怪（示例 / 测试用）：周期性朝玩家发射 ParryProjectile，可选沿直线走位。
##
## 它自己在 "enemy" 组里并带 take_damage，因此被弹反回来的子弹命中会掉血直至销毁——
## 演示「弹反 → 反打」的完整闭环，也可作为接入自己敌人的用法示例。
##
## 行走模式（move_speed > 0 时生效）：
##   · travel ≠ ZERO → 在「起点 ↔ 起点+travel」之间往复；
##   · travel = ZERO → 沿 move_direction 直线走。
##   两种情况撞到障碍层（collision_layer=2 的墙 / 方块）都会折返。
##
## 视觉：idle_texture 待机；开火前先切 windup_texture 做「攻击前摇」，过后再切回待机。
##
## 公共 API：fire() -> Node（手动发射一发，返回子弹节点）。

@export_group("发射")
@export var projectile_scene: PackedScene = preload("res://scenes/parry_projectile.tscn")
@export_range(0.1, 10.0, 0.1) var fire_interval := 1.6
## true = 瞄准玩家；false = 沿 fire_direction 直线发射。
@export var aim_at_player := true
@export var fire_direction := Vector2.RIGHT
## 出膛点相对发射器的前向偏移（像素，避免子弹一出生就撞到自己）。
@export var muzzle_offset := 96.0
@export var projectile_speed := 420.0
@export_range(1, 50, 1) var max_health := 2
## 玩家在此距离内才发射；0 = 不限制距离（始终发射）。
@export_range(0.0, 20000.0, 16.0) var activate_radius := 4096.0

@export_group("行走")
## 行走速度；0 = 原地不动（默认，旧关卡行为不变）。
@export_range(0.0, 2000.0, 1.0) var move_speed := 0.0
## 未设 travel 时的直线行走方向。
@export var move_direction := Vector2.LEFT
## 往复终点相对起点的偏移（Vector2.ZERO = 不设距离终点，沿 move_direction 直线走）。
@export var travel := Vector2.ZERO
## 撞到障碍层（墙 / 方块）时是否折返。
@export var bounce_on_wall := true
## 行走时按方向水平翻转贴图。
@export var flip_visual := true

@export_group("视觉")
@export var idle_texture: Texture2D
@export var windup_texture: Texture2D
## 攻击前摇时长（秒）：开火前先亮 windup_texture，之后发射并切回待机。
@export_range(0.0, 2.0, 0.01) var windup_time := 0.18

var health := 0

var _t := 0.0
var _windup := 0.0
var _player: Node2D
var _origin := Vector2.ZERO
var _target := Vector2.ZERO
var _dir := Vector2.LEFT
var _travel_dist := 0.0

@onready var visual: Node2D = get_node_or_null("Visual")


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("parry_emitter")
	z_index = DepthSort.z_for(global_position.y)
	health = max_health
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_t = fire_interval   # 进场立刻先来一发，方便观察
	if idle_texture == null and visual is Sprite2D:
		idle_texture = (visual as Sprite2D).texture   # 未指定则用场景里摆好的贴图
	_origin = global_position
	if travel.length() > 0.0:
		_dir = travel.normalized()
		_travel_dist = travel.length()
		_target = _origin + travel
	elif move_direction != Vector2.ZERO:
		_dir = move_direction.normalized()
	_apply_texture(idle_texture)
	_refresh_flip()


func _physics_process(delta: float) -> void:
	_patrol(delta)
	z_index = DepthSort.z_for(global_position.y)
	_tick_fire(delta)


# —— 行走 ——
func _patrol(delta: float) -> void:
	if move_speed <= 0.0:
		return
	if _travel_dist > 0.0:
		var to := _target - global_position
		if to.length() <= move_speed * delta:
			global_position = _target
			_reverse()
			return
		_dir = to.normalized()
	velocity = _dir * move_speed
	move_and_slide()
	if bounce_on_wall and get_slide_collision_count() > 0:
		_reverse()
	_refresh_flip()


## 折返：有 travel 时交换两端点，否则原地掉头。
func _reverse() -> void:
	if _travel_dist > 0.0:
		var tmp := _origin
		_origin = _target
		_target = tmp
		_dir = (_target - global_position).normalized()
	else:
		_dir = -_dir
	_refresh_flip()


func _refresh_flip() -> void:
	if flip_visual and visual is Sprite2D:
		(visual as Sprite2D).flip_h = _dir.x < 0.0


# —— 发射 ——
func _tick_fire(delta: float) -> void:
	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			fire()
			_apply_texture(idle_texture)
		return
	if not _player_in_range():
		return
	_t += delta
	if _t < fire_interval:
		return
	_t = 0.0
	if windup_texture != null and windup_time > 0.0:
		_apply_texture(windup_texture)
		_windup = windup_time
		return
	fire()


## 玩家是否在激活半径内（距离不足时暂停发射，不累计冷却）。
func _player_in_range() -> bool:
	if activate_radius <= 0.0:
		return true
	if _player == null or not is_instance_valid(_player):
		return false
	return global_position.distance_to(_player.global_position) <= activate_radius


## 发射一发子弹，返回子弹节点（发射失败返回 null）。
func fire() -> Node:
	if projectile_scene == null:
		return null
	var dir := fire_direction
	if aim_at_player and _player != null and is_instance_valid(_player):
		dir = global_position.direction_to(_player.global_position)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var proj := projectile_scene.instantiate()
	var holder := get_parent()
	if holder == null:
		proj.queue_free()
		return null
	holder.add_child(proj)
	if proj.has_method("set_source_body"):
		proj.set_source_body(self)
	if proj is Node2D:
		(proj as Node2D).global_position = global_position + dir.normalized() * muzzle_offset
		# 飞行弹体置于地面物体深度带之上，暗房遮罩之下。
		proj.z_as_relative = false
		proj.z_index = 4001
	if proj.has_method("setup"):
		proj.call("setup", dir, "enemy")
		proj.set("speed", projectile_speed)
	projectile_fired.emit(proj)
	return proj


func take_damage(amount: float = 1.0) -> void:
	health -= int(round(amount))
	_flash()
	if health <= 0:
		queue_free()


func _apply_texture(tex: Texture2D) -> void:
	if visual is Sprite2D and tex != null:
		(visual as Sprite2D).texture = tex


func _flash() -> void:
	if visual is Sprite2D:
		var s := visual as Sprite2D
		var base := s.self_modulate
		s.self_modulate = Color(1.4, 1.4, 1.4, 1.0)
		var t := create_tween()
		t.tween_property(s, "self_modulate", base, 0.25)
	elif visual is Polygon2D:
		var p := visual as Polygon2D
		var base := p.color
		p.color = Color(1.4, 1.4, 1.4, 1.0)
		var t := create_tween()
		t.tween_property(p, "color", base, 0.25)
