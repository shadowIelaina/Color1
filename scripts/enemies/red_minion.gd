class_name RedMinion
extends CharacterBody2D
## Boss 召唤的小怪（红/蓝/绿共用本脚本，按导出值区分）。
##   · 移动锚点 anchor：player=围绕玩家距离带游走（红/蓝）；boss=围绕 Boss 游走（绿）。
##   · 周期性朝玩家发射子弹（可开启锁定预警线）；蓝怪子弹沿路径留冰晶。
##   · 被赋予 killed_by_element 对应颜色时被消灭；弹反子弹也能打死它。
##   · 绿怪：周期性在 Boss 周围召藤蔓 + 强制 Boss 回血。
##
## 阵营：加入 "enemy" 组并实现 take_damage()，被弹反回来的子弹会自动打它。
## 可上色：加入 "colorable" 组并实现 apply_color() 等契约。
## ⚠️ 不要定义 is_frozen()（player._water_at_mouse 会把带 is_frozen 的 colorable 误判成水格崩溃）。

## 死亡时发出一次（无论被蓝消灭还是被弹反打死），供召唤它的 Boss 挂扣血回调。
signal died

const Rules := preload("res://scripts/element/element_rules.gd")
const DepthSort := preload("res://scripts/depth_sort.gd")
const SniperSightScript := preload("res://effects/sniper_sight/sniper_sight.gd")
const SniperShotScript := preload("res://effects/sniper_shot/sniper_shot.gd")

@export_group("移动")
@export_range(0.0, 4000.0, 1.0) var move_speed := 1050.0
## 与玩家的距离带：近于此值后退，远于此值靠近，带内绕玩家左右前后游走。
@export_range(0.0, 4000.0, 1.0) var min_distance := 820.0
@export_range(0.0, 8000.0, 1.0) var max_distance := 980.0
## 重新下发导航目标点的最小间隔（秒）。
@export var retarget_interval := 0.25
@export var wander_interval := 1.6
@export var wander_range := 220.0
## 贴近玩家时的最低速度倍率（1 = 不减速）。
@export_range(0.0, 1.0, 0.05) var close_speed_scale := 0.45
## 后退目标保持时长（秒）：期间不反复改方向。
@export var retreat_hold_time := 0.8
## 导航代理半径 / 到达路径点·目标的判定距离。
@export var nav_radius := 90.0
@export var nav_path_desired := 24.0
@export var nav_target_desired := 40.0
## 开火前是否需要看得见玩家（掩体阻挡时绕侧，不隔墙射击）。
@export var require_line_of_sight := true

@export_group("子弹")
@export var bullet_scene: PackedScene = preload("res://prefabs/boss/boss_fireball.tscn")
@export_range(0.1, 10.0, 0.1) var fire_interval := 2.0
@export var bullet_speed := 380.0
## 单次发射的弹数（红怪扇形压制 / 蓝怪紧凑狙击）。
@export_range(1, 9, 1) var bullet_count := 1
## 多发时的扇形张角（度）。
@export_range(0.0, 90.0, 0.5) var bullet_spread_deg := 0.0
## 出膛半径（世界像素，需大于本体半径）。
@export var muzzle := 125.0
## 子弹整体缩放（小怪子弹小于 BOSS 子弹）。
@export var bullet_scale := 0.8
## 命中冻结时长（仅对带 freeze_duration 的子弹生效）。<0 = 用子弹自身默认值。
@export var bullet_freeze_duration := -1.0

@export_group("地面残留")
@export var trail_scene: PackedScene = preload("res://prefabs/boss/fire_trail.tscn")
## 残留类型：0 = 燃烧(掉血)，1 = 冰晶(减速)。
@export_enum("burn", "ice_crystal") var trail_kind := 0
@export_range(0.05, 5.0, 0.05) var trail_interval := 0.5
@export_range(0.2, 30.0, 0.1) var trail_lifetime := 6.0

@export_group("归属 / 克制")
## 召唤者用它统计组成（red/blue/green）。
@export var minion_type := "red"
## 被赋予该元素（颜色）时被消灭。红怪=freeze(蓝)，蓝怪=burn(红)，绿怪=freeze(蓝)。
@export var killed_by_element := "freeze"

@export_group("移动锚点")
## 围绕谁活动：player（红/蓝）或 boss（绿）。
@export_enum("player", "boss") var anchor := "player"
## anchor=boss 时，绕 Boss 活动的半径区间（世界像素）。
@export var anchor_radius_min := 200.0
@export var anchor_radius_max := 400.0

@export_group("锁定预警")
## 开火前锁定玩家的预警时长（秒）。0 = 不预警（直接射）。
@export var aim_lock_time := 0.0
@export var aim_line_length := 2200.0
@export var aim_line_color := Color(0.45, 0.75, 1.0, 0.9)
## 开火时是否播放狙击枪口光束（蓝怪使用）。
@export var sniper_shot_enabled := false

@export_group("弹道残留（子弹）")
## 子弹飞行路径留下的残留场景（留空则无）。
@export var bullet_trail_scene: PackedScene
@export_enum("burn", "ice_crystal") var bullet_trail_kind := 1
@export var bullet_trail_interval := 0.6

@export_group("藤蔓（绿怪）")
## 周期性召唤藤蔓：间隔（秒），0 = 不召。
@export var vine_summon_interval := 0.0
@export var vine_scene: PackedScene
@export_range(0, 8, 1) var vine_summon_count := 2
@export var vine_radius_min := 200.0
@export var vine_radius_max := 450.0

@export_group("命中冲撞（绿怪）")
## 命中致命色时的行为：die=直接死；charge=先打断 Boss 回血再变青冲撞。
@export_enum("die", "charge") var on_hit_behavior := "die"
@export var charge_speed := 1200.0
@export var charge_min_time := 0.15
@export var charge_max_time := 2.5
@export var charge_color := Color(0.3, 0.9, 0.95)
## 变青冲撞的瞬间对 Boss 施加的回血封锁（秒）。
@export var charge_heal_lock := 6.0

@export_group("属性")
@export var max_health := 3.0
@export var hit_radius := 96.0
## 接触相反元素残留后的熄灭时长（秒）。
@export_range(0.1, 30.0, 0.1) var extinguish_duration := 4.0

@export_group("视觉")
## 兼容旧场景属性；贴图版小怪实际使用 visual_tint 染色。
@export var body_color := Color(0.95, 0.3, 0.25)
## 贴图染色；保持白色表示使用原图颜色。
@export var visual_tint := Color.WHITE

@export_group("贴图状态")
## 被正确颜色定格时切换的贴图（留空则保持原贴图）。
@export var lock_texture: Texture2D
## 死亡淡出时切换的贴图（留空则保持原贴图）。
@export var death_texture: Texture2D
## 被相反残留熄灭时切换的贴图（留空则压暗当前贴图/色块）。
@export var extinguish_texture: Texture2D

var health := 0.0
var _player: Node2D
var _body: Node2D
var _body_base_scale := Vector2.ONE
var _default_tint := Color.WHITE
var _body_tint := Color.WHITE
var _default_texture: Texture2D
var _extinguished := false
var _extinguish_t := 0.0
var _fire_cd := 0.0
var _trail_cd := 0.0
var _wander_target := Vector2.ZERO
var _wander_timer := 0.0
var _retreating := false
var _retreat_target := Vector2.ZERO
var _retreat_timer := 0.0
var _agent: NavigationAgent2D
var _retarget_cd := 0.0
var _dead := false
var _stuck_ready := false
var _stuck_check_t := 0.0
var _stuck_t := 0.0
var _last_stuck_pos := Vector2.ZERO
var _rescue_cd := 0.0
var _vine_cd := 0.0
var _aiming := false
var _aim_t := 0.0
var _charging := false
var _charge_t := 0.0
var _charge_dir := Vector2.RIGHT
var _lock_dir := Vector2.RIGHT
var _sight: Node2D
var _paint_locked := false
var _paint_lock_t := 0.0
var _paint_lock_tween: Tween
var _los_blocked_t := 0.0
var _flank_target := Vector2.ZERO
var _flank_recalc := 0.0


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("minion")
	add_to_group("colorable")
	health = max_health
	collision_layer = 0
	collision_mask = 2   # 撞「障碍」层（墙/树），不挡玩家
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_body = get_node_or_null("Visual") as Node2D
	if _body != null:
		_body_base_scale = _body.scale
	if _body is Sprite2D:
		_default_texture = (_body as Sprite2D).texture
	if _body is Polygon2D:
		_default_tint = body_color
	else:
		_default_tint = visual_tint
	_body_tint = _default_tint
	_player = get_tree().get_first_node_in_group("player") as Node2D
	z_index = DepthSort.z_for(global_position.y)
	_apply_body_tint()
	_new_wander_target()
	_fire_cd = fire_interval * randf_range(0.5, 1.0)
	_agent = get_node_or_null("Nav") as NavigationAgent2D
	if _agent != null:
		_agent.radius = nav_radius
		_agent.path_desired_distance = nav_path_desired
		_agent.target_desired_distance = nav_target_desired
		_agent.max_speed = move_speed
		_agent.avoidance_enabled = true          # 与其它小怪互相避让，避免扎堆
		_agent.max_neighbors = 10
		_agent.time_horizon_agents = 1.0
		_agent.velocity_computed.connect(_on_velocity_computed)
	_vine_cd = vine_summon_interval
	if aim_lock_time > 0.0:
		_sight = SniperSightScript.new()
		_sight.name = "SniperSight"
		_sight.z_index = 5
		add_child(_sight)
		if _sight.has_method("configure"):
			_sight.call("configure", aim_line_color, aim_line_length)
		_sight.visible = false


func _physics_process(delta: float) -> void:
	z_index = DepthSort.z_for(global_position.y)
	if _extinguished:
		_extinguish_t -= delta
		velocity = Vector2.ZERO
		if _agent != null:
			_agent.set_velocity(Vector2.ZERO)
		move_and_slide()
		if _extinguish_t <= 0.0:
			_recover_from_extinguish()
		return
	if _paint_locked:
		_tick_paint_lock(delta)
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _charging:
		_do_charge(delta)
		return
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_trail_cd = maxf(0.0, _trail_cd - delta)
	_flank_recalc = maxf(0.0, _flank_recalc - delta)
	if _aiming:
		velocity = Vector2.ZERO
		move_and_slide()
	else:
		_move(delta)
	_maybe_fire(delta)
	_maybe_drop_trail()
	_maybe_support(delta)
	_update_stuck(delta)


## 变青冲撞：直线冲刺，撞墙即死（像 Boss 的青色冲锋）。
func _do_charge(delta: float) -> void:
	velocity = _charge_dir * charge_speed
	move_and_slide()
	_charge_t += delta
	if _charge_t >= charge_min_time and get_slide_collision_count() > 0:
		_die()
		return
	if _charge_t >= charge_max_time:
		_charging = false
		_set_body_tint(_default_tint)


func _move(delta: float) -> void:
	_retarget_cd = maxf(_retarget_cd - delta, 0.0)
	var goal := _desired_goal(delta)
	var speed := _current_move_speed()
	if _agent == null:
		velocity = (goal - global_position).normalized() * speed
		move_and_slide()
		return
	if _retarget_cd <= 0.0:
		_retarget_cd = retarget_interval
		_agent.target_position = goal
	# 走导航路径（开启避让，多只小怪不会互相叠在一起）。
	_agent.set_velocity(_follow_dir() * speed)


## 贴近玩家时降低移动速度，避免贴脸高速来回抖动。
func _current_move_speed() -> float:
	if not _player_valid() or min_distance <= 0.0:
		return move_speed
	var dist := global_position.distance_to(_player.global_position)
	if dist >= min_distance * 1.15:
		return move_speed
	var t := clampf(inverse_lerp(min_distance * 0.9, min_distance * 1.15, dist), 0.0, 1.0)
	return move_speed * lerpf(close_speed_scale, 1.0, t)


## 依锚点选目标点：anchor=boss → 绕 Boss 游走；否则按与玩家的距离带。
func _desired_goal(delta: float) -> Vector2:
	if anchor == "boss":
		var boss := _boss()
		if boss != null and is_instance_valid(boss):
			_wander_timer -= delta
			if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 40.0:
				_new_wander_target()
			return _wander_target
	if _player_valid():
		if require_line_of_sight and not _has_los_to_player():
			_los_blocked_t += delta
			if _flank_target == Vector2.ZERO or _flank_recalc <= 0.0:
				_flank_target = _find_flank_target()
				_flank_recalc = 0.5
			if _los_blocked_t < 0.35:
				return _player.global_position
			return _flank_target
		_los_blocked_t = 0.0
		var to_player := _player.global_position - global_position
		var dist := to_player.length()
		# 后退滞回：进入后要退到更远才解除，避免在距离边界反复掉头。
		if dist < min_distance * 0.92:
			_retreating = true
		elif dist > min_distance * 1.12:
			_retreating = false
			_retreat_target = Vector2.ZERO
		if _retreating:
			_retreat_timer -= delta
			if (
				_retreat_target == Vector2.ZERO
				or _retreat_timer <= 0.0
				or global_position.distance_to(_retreat_target) < 50.0
			):
				var away := global_position - _player.global_position
				if away.length() < 1.0:
					away = Vector2.from_angle(randf() * TAU)
				_retreat_target = _snap_to_nav(
					_player.global_position + away.normalized() * (min_distance * 1.3)
				)
				_retreat_timer = retreat_hold_time
			return _retreat_target
		if distance_band_dir(dist, min_distance, max_distance) > 0:
			return _player.global_position
	# 带内 / 无玩家：随机漫游。
	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 24.0:
		_new_wander_target()
	return _wander_target


func _has_los_to_player() -> bool:
	if not _player_valid():
		return false
	return _point_has_los(global_position, _player.global_position)


func _point_has_los(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 2)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


## 绕到玩家周围能看见它的位置；找不到就朝玩家靠。
func _find_flank_target() -> Vector2:
	var base_ang := (global_position - _player.global_position).angle()
	var radius := clampf(global_position.distance_to(_player.global_position), min_distance, max_distance)
	var offsets := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]
	for deg in offsets:
		var p := _player.global_position + Vector2.from_angle(base_ang + deg_to_rad(deg)) * radius
		p = _snap_to_nav(p)
		if _point_has_los(p, _player.global_position):
			return p
	return _player.global_position


func _snap_to_nav(p: Vector2) -> Vector2:
	var map := get_world_2d().navigation_map
	if map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0:
		return NavigationServer2D.map_get_closest_point(map, p)
	return p


## 卡住检测：先强制重寻路，持续卡住则救援传送到玩家附近的有效导航点。
func _update_stuck(delta: float) -> void:
	if _aiming or _charging or _extinguished or _paint_locked or _dead or not _player_valid():
		_stuck_ready = false
		_stuck_t = 0.0
		_stuck_check_t = 0.0
		return
	if not _stuck_ready:
		_stuck_ready = true
		_last_stuck_pos = global_position
		return
	_rescue_cd = maxf(0.0, _rescue_cd - delta)
	_stuck_check_t += delta
	if _stuck_check_t < 0.5:
		return
	var moved := global_position.distance_to(_last_stuck_pos)
	_last_stuck_pos = global_position
	var target := _agent.target_position if _agent != null else _player.global_position
	var wants_move := global_position.distance_to(target) > nav_target_desired + 24.0
	if moved < 10.0 and wants_move:
		_stuck_t += _stuck_check_t
	else:
		_stuck_t = 0.0
	_stuck_check_t = 0.0
	if _stuck_t >= 1.5:
		if _agent != null:
			_agent.target_position = _snap_to_nav(target)
		if _stuck_t >= 2.3 and _rescue_cd <= 0.0:
			_rescue_from_stuck()


func _rescue_from_stuck() -> void:
	if not _player_valid():
		return
	var angle := randf() * TAU
	var radius := clampf(randf_range(min_distance, max_distance), 400.0, 1600.0)
	var target := _snap_to_nav(_player.global_position + Vector2.from_angle(angle) * radius)
	if target.distance_to(_player.global_position) < 300.0:
		target = _snap_to_nav(_player.global_position + Vector2.from_angle(angle) * maxf(radius, 600.0))
	global_position = target
	velocity = Vector2.ZERO
	if _agent != null:
		_agent.target_position = _player.global_position
		_agent.set_velocity(Vector2.ZERO)
	_stuck_ready = true
	_stuck_t = 0.0
	_stuck_check_t = 0.0
	_last_stuck_pos = global_position
	_rescue_cd = 2.0
	_retreating = false
	_retreat_target = Vector2.ZERO


## 沿导航路径的下一段方向；无路径/未就绪时退化为直线朝向导航目标点。
func _follow_dir() -> Vector2:
	if _agent == null:
		return Vector2.ZERO
	var dir := _agent.target_position - global_position
	if not _agent.is_navigation_finished():
		var d := _agent.get_next_path_position() - global_position
		if d.length() > 1.0:
			dir = d
	if dir.length() < 1.0:
		return Vector2.ZERO
	return dir.normalized()


## 避让后的安全速度回调：应用速度并真正移动。
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if _paint_locked or _extinguished or _dead or _aiming:
		return
	velocity = safe_velocity
	move_and_slide()


func _new_wander_target() -> void:
	if anchor == "boss":
		var boss := _boss()
		if boss != null and is_instance_valid(boss):
			_wander_target = boss.global_position + Vector2.from_angle(randf() * TAU) * randf_range(anchor_radius_min, anchor_radius_max)
			_wander_timer = wander_interval * randf_range(0.7, 1.3)
			return
	if _player_valid():
		# 在当前方位附近取点，避免每次重选都穿过玩家、造成来回跑。
		var base_ang := (global_position - _player.global_position).angle()
		var ang := base_ang + randf_range(-PI * 0.6, PI * 0.6)
		var r := randf_range(min_distance, max_distance)
		_wander_target = _player.global_position + Vector2.from_angle(ang) * r
	else:
		_wander_target = global_position + Vector2.from_angle(randf() * TAU) * randf_range(40.0, wander_range)
	_wander_timer = wander_interval * randf_range(0.7, 1.3)


## 距离带决策（纯逻辑，供单测）：1 = 太远靠近，-1 = 太近后退，0 = 在带内。
static func distance_band_dir(dist: float, min_dist: float, max_dist: float) -> int:
	if dist > max_dist:
		return 1
	if dist < min_dist:
		return -1
	return 0


# —— 开火 / 留痕 ——

func _maybe_fire(delta: float) -> void:
	if bullet_scene == null or not _player_valid():
		return
	if require_line_of_sight and not _has_los_to_player():
		if _aiming:
			_aiming = false
			_hide_aim_line()
		_fire_cd = maxf(_fire_cd, 0.2)
		return
	if _aiming:
		_aim_t -= delta
		_update_aim_line()
		if _aim_t <= 0.0:
			_aiming = false
			_hide_aim_line()
			_fire_cd = fire_interval
			_spawn_bullet(_lock_dir)
		return
	if _fire_cd > 0.0:
		return
	if aim_lock_time > 0.0:
		_aiming = true
		_aim_t = aim_lock_time
		_lock_dir = _dir_to_player()
		_update_aim_line()
	else:
		_fire_cd = fire_interval
		_spawn_bullet(_dir_to_player())


func _dir_to_player() -> Vector2:
	var d := global_position.direction_to(_player.global_position)
	return d if d != Vector2.ZERO else Vector2.RIGHT


func _update_aim_line() -> void:
	if _sight == null:
		return
	_sight.call("show_sight", _lock_dir, aim_line_length)
	if _sight.has_method("set_locked"):
		_sight.call("set_locked", _aim_t <= 0.15)


func _hide_aim_line() -> void:
	if _sight != null:
		if _sight.has_method("hide_sight"):
			_sight.call("hide_sight")
		else:
			_sight.visible = false


func _spawn_bullet(dir: Vector2) -> void:
	var holder := get_parent()
	if holder == null:
		return
	var base := dir.normalized()
	if base == Vector2.ZERO:
		base = Vector2.RIGHT
	if sniper_shot_enabled:
		_spawn_sniper_flash(holder, base)
	var count := maxi(bullet_count, 1)
	var spread := deg_to_rad(bullet_spread_deg)
	for i in count:
		var ang := 0.0
		if count > 1:
			ang = spread * (float(i) / float(count - 1) - 0.5)
		var d := base.rotated(ang)
		var b := bullet_scene.instantiate()
		holder.add_child(b)
		if b is Node2D:
			(b as Node2D).scale = Vector2(bullet_scale, bullet_scale)
			(b as Node2D).global_position = global_position + d * muzzle
		if b.has_method("setup"):
			b.call("setup", d, "enemy")
		if b.get("speed") != null:
			b.set("speed", bullet_speed)
		if bullet_freeze_duration >= 0.0 and b.get("freeze_duration") != null:
			b.set("freeze_duration", bullet_freeze_duration)
		if bullet_trail_scene != null and b is ParryProjectile:
			b.trail_scene = bullet_trail_scene
			b.trail_kind = bullet_trail_kind
			b.trail_interval = bullet_trail_interval


func _spawn_sniper_flash(holder: Node, dir: Vector2) -> void:
	var flash := SniperShotScript.new()
	holder.add_child(flash)
	flash.global_position = global_position + dir * muzzle
	if flash.has_method("setup"):
		flash.call("setup", dir, aim_line_color, 1600.0)


func _maybe_drop_trail() -> void:
	if _trail_cd > 0.0 or trail_scene == null:
		return
	_trail_cd = trail_interval
	var holder := get_parent()
	if holder == null:
		return
	var h := trail_scene.instantiate()
	h.set("kind", trail_kind)
	h.set("lifetime", trail_lifetime)
	holder.add_child(h)
	if h is Node2D:
		(h as Node2D).global_position = global_position


## 绿怪支援：周期性在（玩家/Boss）周围召唤藤蔓阻挡。
func _maybe_support(delta: float) -> void:
	if vine_summon_interval > 0.0 and vine_scene != null:
		_vine_cd = maxf(0.0, _vine_cd - delta)
		if _vine_cd <= 0.0:
			_vine_cd = vine_summon_interval
			_summon_vines()


## 在玩家周围随机召唤若干藤蔓。
func _summon_vines() -> void:
	var center := _vine_center()
	var holder := get_parent()
	if center == null or holder == null:
		return
	for i in vine_summon_count:
		var v := vine_scene.instantiate()
		holder.add_child(v)
		if v is Node2D:
			var ang := randf() * TAU
			var r := randf_range(vine_radius_min, vine_radius_max)
			(v as Node2D).global_position = center.global_position + Vector2.from_angle(ang) * r


## 藤蔓的生成中心：只允许围绕玩家生成，不再围绕 BOSS。
func _vine_center() -> Node2D:
	return _player if _player_valid() else null


func _boss() -> Node2D:
	return get_tree().get_first_node_in_group("boss") as Node2D


# —— 受伤 / 死亡 ——

func take_damage(amount: float = 1.0) -> void:
	if _dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_flash()
	if health <= 0.0:
		_die()


## 供 Boss 死亡时统一清场调用。
func kill() -> void:
	_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	_extinguished = false
	_extinguish_t = 0.0
	set_physics_process(false)
	release_paint_lock()
	_set_body_tint(_default_tint)
	_set_body_texture(death_texture)
	collision_layer = 0
	collision_mask = 0
	_hide_aim_line()
	died.emit()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_callback(queue_free)


# —— 被正确颜色指引时定格 ——

## 玩家用「克制它的颜色」发起攻击时调用：立刻停止移动/开火，方便跟班落到它身上。
## 颜色不匹配或正在冲撞时返回 false，不改变小怪行为。
func lock_for_paint(color_name: String, duration := 1.4) -> bool:
	if _dead or _charging:
		return false
	if _extinguished:
		_recover_from_extinguish()
	var element := Rules.element_for_color_name(color_name)
	if element == "" or element != killed_by_element:
		return false
	var element_color: Color = Rules.config(element).get("color", body_color)
	if _paint_locked:
		_paint_lock_t = maxf(_paint_lock_t, duration)
		return true
	_paint_locked = true
	_paint_lock_t = maxf(duration, 0.1)
	velocity = Vector2.ZERO
	if _agent != null:
		_agent.set_velocity(Vector2.ZERO)
	_hide_aim_line()
	_play_lock_visual(element_color)
	return true


func release_paint_lock() -> void:
	var was_locked := _paint_locked
	_paint_locked = false
	_paint_lock_t = 0.0
	if _paint_lock_tween != null and _paint_lock_tween.is_valid():
		_paint_lock_tween.kill()
	_paint_lock_tween = null
	if was_locked and _body != null:
		_set_body_texture(_default_texture)
		_set_body_tint(_default_tint)
		_body.scale = _body_base_scale


func is_paint_locked() -> bool:
	return _paint_locked


func _tick_paint_lock(delta: float) -> void:
	_paint_lock_t -= delta
	if _paint_lock_t <= 0.0:
		release_paint_lock()


func _play_lock_visual(lock_color: Color) -> void:
	if _body == null:
		return
	_set_body_texture(lock_texture)
	# 色块直接显示玩家赋予的颜色；贴图小怪保持原图并轻微提亮。
	if _body is Polygon2D:
		_set_body_visual(lock_color)
	else:
		_set_body_visual(_body_tint.lightened(0.45))
	_body.scale = _body_base_scale
	if not is_inside_tree():
		return
	_paint_lock_tween = create_tween().set_loops()
	_paint_lock_tween.tween_property(_body, "scale", _body_base_scale * Vector2(1.08, 0.94), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_paint_lock_tween.tween_property(_body, "scale", _body_base_scale, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# —— colorable 契约 ——

## 命中致命色：on_hit_behavior=die 直接死；charge 先打断 Boss 回血再变青冲撞。
func apply_color(_c: Color, color_name: String = "", from_pos: Vector2 = Vector2.INF) -> bool:
	if _dead or _charging:
		return false
	var element := Rules.element_for_color_name(color_name)
	if element == "" or element != killed_by_element:
		return false
	if on_hit_behavior == "charge":
		_start_charge(from_pos)
	else:
		_die()
	return true


## 变青冲撞起手：打断 Boss 回血 + 变青 + 朝远离来源方向冲刺。
func _start_charge(from_pos: Vector2) -> void:
	if _extinguished:
		_recover_from_extinguish()
	release_paint_lock()
	_charging = true
	_charge_t = 0.0
	var away := global_position - from_pos
	if from_pos != Vector2.INF and away.length() > 1.0:
		_charge_dir = away.normalized()
	elif _player_valid():
		_charge_dir = _dir_to_player()
	else:
		_charge_dir = Vector2.RIGHT
	_set_body_tint(charge_color)
	_hide_aim_line()
	var boss := _boss()
	if boss != null and boss.has_method("interrupt_heal"):
		boss.call("interrupt_heal", charge_heal_lock)
	GameState.notice.emit("绿怪变青冲撞！让它撞墙")


func has_color() -> bool:
	return false


func absorb_color() -> Dictionary:
	return {"element": "", "color": Color.WHITE, "color_name": ""}


func contains_point(world_pos: Vector2) -> bool:
	return global_position.distance_to(world_pos) <= hit_radius


func _player_valid() -> bool:
	return _player != null and is_instance_valid(_player)


# —— 残留熄灭 ——

## 接触相反元素残留：红怪怕冰，蓝/绿怪怕火。
## 熄灭期间停止移动/开火/召唤，重复接触刷新时长。
func extinguish_from_hazard(element_id: String) -> bool:
	if _dead or _paint_locked:
		return false
	var weak_element := "freeze" if minion_type == "red" else "burn"
	if element_id != weak_element:
		return false
	if _charging:
		_charging = false
		_charge_t = 0.0
		_set_body_tint(_default_tint)
	if _extinguished:
		_extinguish_t = maxf(_extinguish_t, extinguish_duration)
		return true
	_extinguished = true
	_extinguish_t = extinguish_duration
	velocity = Vector2.ZERO
	if _agent != null:
		_agent.set_velocity(Vector2.ZERO)
	_aiming = false
	_hide_aim_line()
	_show_extinguished_visual()
	return true


func _recover_from_extinguish() -> void:
	if not _extinguished:
		return
	_extinguished = false
	_extinguish_t = 0.0
	_set_body_texture(_default_texture)
	_set_body_tint(_default_tint)
	_fire_cd = maxf(_fire_cd, 0.4)


func _show_extinguished_visual() -> void:
	if _body == null:
		return
	if _body is Sprite2D:
		if extinguish_texture != null:
			(_body as Sprite2D).texture = extinguish_texture
			_body.self_modulate = Color.WHITE
		else:
			_body.self_modulate = Color(0.55, 0.55, 0.6, 1.0)
	else:
		_set_body_visual(_default_tint.darkened(0.65))


# —— 视觉 ——

## 切换小怪贴图状态（定格 / 死亡）；留空则保持不变。
func _set_body_texture(tex: Texture2D) -> void:
	if tex == null or not (_body is Sprite2D):
		return
	(_body as Sprite2D).texture = tex


## 设置当前基础染色（冲锋变青 / 恢复默认时使用）。
func _set_body_tint(c: Color) -> void:
	_body_tint = c
	_apply_body_tint()


## 把染色写到视觉节点：Sprite2D 用 self_modulate，旧 Polygon2D 用 color。
func _apply_body_tint() -> void:
	if _body == null:
		return
	_set_body_visual(_body_tint)


func _set_body_visual(c: Color) -> void:
	if _body == null:
		return
	if _body is Polygon2D:
		(_body as Polygon2D).color = c
	else:
		_body.self_modulate = c


func _flash() -> void:
	if _body == null:
		return
	_body.self_modulate = Color(2.0, 2.0, 2.0, 1.0)
	var restore := Color.WHITE if _body is Polygon2D else _body_tint
	var t := create_tween()
	t.tween_property(_body, "self_modulate", restore, 0.25)
