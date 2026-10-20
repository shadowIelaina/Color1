class_name Boss
extends CharacterBody2D
## Boss 敌人（占位色块版）。缓慢移动的重型敌人，两种弹幕攻击 + 低血特殊机制：
##   · 红色环形弹幕：360° 均匀铺一圈红弹（可弹反），血量越低每圈弹数越多、间隔越短；
##   · 冰子弹（≤50% 血解锁）：先蓝色预警 + 锁定瞄准线，再沿锁定方向发射冰弹，命中冻结玩家；
##     血量越少发射越频繁（冷却在「半血值」与「濒死值」间插值）。
##   · 绿色回复：≤34% 血触发，变绿 3 秒后回血；期间可被附「蓝」→ 变青冲锋撞墙自伤。
##
## 阵营：加入 "enemy" 组并实现 take_damage()，被弹反回来的子弹会自动打它。
## 蓝色交互：Boss 加入专用 "boss_paint_target" 组，只实现 apply_boss_color()；
##   不进入解密的 "colorable" 契约，避免被元素扩散 / 导管 / 踏板误判。
## 青色机制：BossCyanCharge 独立实现，不调用解密「蓝×绿=青」的任何逻辑。
## 视觉：AnimatedSprite2D（Visual 子节点，红/蓝/绿/青待机 + 转换动画）+ SniperSight（蓝色狙击瞄准线）。
##
## 信号：health_changed(current, max_health) / died。供 HUD 血条订阅；也可读 health_snapshot()。

signal health_changed(current: float, max_health: float)
signal died
## 状态切换（CHASE / RING_CAST / ICE_CAST / HEAL / CYAN_CHARGE / STUNNED ...），供场景演出使用。
signal state_changed(state: int)
## 青色冲锋撞墙，供场地震屏 / 冲击特效使用。
signal charge_crashed

enum State { CHASE, RING_CAST, ICE_CAST, HEAL_WINDUP, HEAL, CYAN_CHARGE, STUNNED, DEAD }

const DepthSort := preload("res://scripts/depth_sort.gd")
const CyanCharge := preload("res://scripts/enemies/boss_cyan_charge.gd")
const SniperSightScript := preload("res://effects/sniper_sight/sniper_sight.gd")
const SniperShotScript := preload("res://effects/sniper_shot/sniper_shot.gd")

@export_group("属性")
@export var max_health := 24.0
## 被弹反子弹命中时扣除的最大生命比例（每颗默认 5%）。
@export_range(0.0, 1.0, 0.01) var reflected_bullet_damage_ratio := 0.05
@export_range(0.0, 4000.0, 1.0) var move_speed := 1150.0
## 点击命中半径（世界像素），用于「赋予颜色」判定。
@export_range(8.0, 1024.0, 1.0) var hit_radius := 150.0

@export_group("导航走位")
## 想与玩家保持的距离（世界像素）：近了后退、远了靠近。
@export var preferred_distance := 1320.0
## 开火前是否需要看得见玩家（掩体阻挡时改为绕侧，不隔墙放弹幕）。
@export var require_line_of_sight := true
## 死区：|当前距离 - 目标距离| 在此范围内视为「已就位」，改为横向漂移。
@export var distance_deadzone := 70.0
## 重新下发导航目标点的最小间隔（秒），避免每帧重算路径抖动。
@export var retarget_interval := 0.12
## 就位时的横向漂移速度（像素/秒），制造游斗感。
@export var drift_speed := 180.0
## 导航代理半径（≈ 本体半宽）。
@export var nav_radius := 130.0
## 到达「路径点 / 最终目标」的判定距离。
@export var nav_path_desired := 40.0
@export var nav_target_desired := 60.0

@export_group("被逼墙角")
## 想拉开距离却几乎动不了（被墙/障碍卡住）持续多久判定为「进墙角」。
@export var stuck_time := 0.5
## 进入墙角状态后，主动靠近玩家的最长持续时间（秒）。
@export var cornered_duration := 1.5
## 靠近到该距离即解除墙角状态（已贴到玩家身边，无需再靠）。
@export var corner_release_distance := 350.0

@export_group("红色扇形弹幕")
@export var ring_bullet_scene: PackedScene = preload("res://prefabs/boss/boss_fireball.tscn")
## 前摇（预警）时长：变红蓄力，之后铺一个扇形。
@export var ring_windup := 0.38
## 满血 → 濒死的发射间隔（秒），越少血越快。
@export var ring_interval_max := 2.3
@export var ring_interval_min := 1.2
## 满血 → 濒死扇形内的弹数。
@export_range(1, 48, 1) var ring_bullets_min := 8
@export_range(1, 48, 1) var ring_bullets_max := 12
## 扇形张角（度），以「朝玩家方向」为中心。
@export_range(10.0, 360.0, 1.0) var ring_arc_deg := 90.0
@export var ring_bullet_speed := 420.0
## 出膛半径（世界像素）。0 = 从 Boss 本体中心发射（生成时对本体加碰撞例外，见 _spawn_projectile）。
@export var ring_muzzle := 0.0

@export_group("子弹通用")
## Boss 子弹最大飞行距离（世界像素）：超过即消失。0 = 不限制。子弹从本体中心出膛，故≈离 Boss 的距离。
@export_range(0.0, 8000.0, 10.0) var bullet_max_range := 1800.0

@export_group("冰子弹（半血解锁）")
@export var ice_scene: PackedScene = preload("res://prefabs/boss/boss_freeze_orb.tscn")
## 解锁阈值（血量比例）。
@export_range(0.0, 1.0, 0.01) var ice_unlock_ratio := 0.5
## 刚解锁时先等一会儿，避免半血瞬间立刻放冰。
@export var ice_unlock_delay := 1.6
## 蓝色预警（瞄准线锁定）时长。
@export var ice_windup := 0.6
## 刚解锁（半血）→ 濒死的发射间隔（秒）。
@export var ice_interval_half := 5.0
@export var ice_interval_min := 1.7
@export var ice_speed := 2400.0
@export var ice_duration := 3.0
## 冰弹最大飞行距离（世界像素）：0 = 不限制。独立于环形弹，保证狙击弹能跨越远距离。
@export_range(0.0, 20000.0, 10.0) var ice_max_range := 6000.0
## 出膛半径（世界像素）。0 = 从 Boss 本体中心发射（同环形弹）。
@export var ice_muzzle := 0.0
## 濒死时一次发射的冰弹数（扇形，中心对准锁定方向）。
@export_range(1, 5, 1) var ice_max_count := 2
@export var ice_spread_deg := 12.0
## 瞄准预警线长度（世界像素）；实际会被墙体截断。
@export var aim_line_length := 4000.0

@export_group("节奏")
## 每次出招后的全局小冷却，避免弹幕糊成一团。
@export var post_attack_lock := 0.25

@export_group("阶段召唤小怪")
## 三种小怪场景（红/蓝/绿）。默认指向 Boss 预制体自带的小怪，拖入新场景即可直接工作；
## 留空则对应阶段不召该类。
@export var red_minion_scene: PackedScene = preload("res://prefabs/boss/red_minion.tscn")
@export var blue_minion_scene: PackedScene = preload("res://prefabs/boss/blue_minion.tscn")
@export var green_minion_scene: PackedScene = preload("res://prefabs/boss/green_minion.tscn")
## 阶段血量分界：> phase1 → 2 红；≤ phase1 → 2 红 + 1 蓝；≤ phase2 → 2 蓝 + 1 绿。
@export_range(0.0, 1.0, 0.01) var minion_phase1_ratio := 0.5
@export_range(0.0, 1.0, 0.01) var minion_phase2_ratio := 0.30
## 召唤点围绕 Boss 的半径（世界像素）。
@export_range(0.0, 2000.0, 8.0) var minion_spawn_radius := 360.0
## 小怪逐只出现的间隔（秒）。0 = 瞬间全部出现。
@export_range(0.0, 5.0, 0.1) var minion_summon_stagger := 0.8
## 每只（Boss 召唤的）小怪阵亡时，Boss 损失的最大血量比例。
@export_range(0.0, 1.0, 0.01) var minion_death_damage_ratio := 0.1
## 绿怪阵亡时不扣血，改为打断 Boss 回血并封锁该时长（秒）。
@export var green_death_heal_lock := 6.0
## 小怪补充间隔（秒）。
@export var minion_respawn_interval := 6.0
## 血量降到该比例后，整场战斗不再召唤红色小怪（即使之后回血到 50% 以上）。
@export_range(0.0, 1.0, 0.01) var red_summon_lock_ratio := 0.20

@export_group("绿色回复")
@export_range(0.0, 1.0, 0.01) var heal_threshold := 0.34
## 回血前的空窗期（秒）：原地静止变绿蓄力，期间可被打断。
@export var heal_windup_time := 3.0
@export_range(0.0, 1.0, 0.01) var heal_fraction := 0.18
@export var heal_duration := 3.0
@export var heal_cooldown := 10.0

@export_group("青色冲锋（Boss 独立机制）")
## 触发色名：仅在绿色回复/蓄力期接受该颜色，且只走 Boss 专用入口。
@export var cyan_trigger_color_name := "蓝"
@export var charge_speed := 1500.0
@export var charge_max_time := 2.2
@export var charge_min_time := 0.15
@export_range(0.0, 1.0, 0.01) var charge_self_damage := 0.16
@export var charge_stun_time := 1.4

@export_group("视觉")
## 兼容旧场景属性：Boss 贴图已按颜色分套，实际外观由状态动画决定。
@export var body_color := Color(0.55, 0.22, 0.62)
@export var ring_telegraph_color := Color(1.0, 0.35, 0.25)
@export var ice_telegraph_color := Color(0.35, 0.6, 1.0)
@export var heal_color := Color(0.3, 0.85, 0.4)
@export var heal_windup_color := Color(0.55, 1.0, 0.6)
@export var cyan_color := Color(0.3, 0.9, 0.95)
@export var stun_color := Color(0.5, 0.5, 0.5)
@export var aim_line_color := Color(0.45, 0.75, 1.0, 0.9)

const BOSS_FX_SCALE := 3.9
const DEATH_ANIM := &"death"

const BODY_IDLE_ANIMS := {
	"red": &"idle_red",
	"blue": &"idle_blue",
	"green": &"idle_green",
	"cyan": &"idle_cyan",
}
const BODY_TRANSITION_ANIMS := {
	"blue": &"to_blue",
	"green": &"to_green",
	"cyan": &"to_cyan",
}

var health := 0.0

var _state := State.CHASE
var _player: Node2D
var _body: AnimatedSprite2D
var _body_base_scale := Vector2.ONE
var _body_color_state := ""
var _pending_idle_anim: StringName = &""
var _sight: Node2D
var _cyan := CyanCharge.new()
var _heal_pulse: Tween

var _ring_cd := 0.0
var _ice_cd := 0.0
var _heal_cd := 0.0
var _attack_lock := 0.0
var _state_t := 0.0
var _heal_left := 0.0

var _ice_enabled := false
var _ice_dir := Vector2.RIGHT

var _respawn_cd := 0.0
var _phase := -1
var _phase_change_cd := 0.0
var _red_summons_locked := false
var _adds: Array = []
var _summon_generation := 0
var _heal_lock_t := 0.0

var _agent: NavigationAgent2D
var _drift_dir := 1.0
var _retarget_cd := 0.0
var _last_pos := Vector2.ZERO
var _stuck_t := 0.0
var _cornered := false
var _cornered_t := 0.0
var _los_blocked_t := 0.0


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	# Boss 专用蓝色交互目标：不进入解密的 "colorable" 组，避免元素扩散/导管/踏板误伤。
	add_to_group("boss_paint_target")
	health = max_health
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_body = get_node_or_null("Visual") as AnimatedSprite2D
	if _body != null:
		_body_base_scale = _body.scale
		if not _body.animation_finished.is_connected(_on_body_animation_finished):
			_body.animation_finished.connect(_on_body_animation_finished)
	_player = get_tree().get_first_node_in_group("player") as Node2D
	z_index = DepthSort.z_for(global_position.y)
	_play_body_state("red")
	_sight = SniperSightScript.new()
	_sight.name = "SniperSight"
	_sight.z_index = 5
	add_child(_sight)
	if _sight.has_method("configure"):
		_sight.call("configure", aim_line_color, aim_line_length)
	_sight.visible = false
	_cyan.speed = charge_speed
	_cyan.min_time = charge_min_time
	_cyan.max_time = charge_max_time
	_cyan.self_damage_ratio = charge_self_damage
	_cyan.stun_time = charge_stun_time
	_ring_cd = 1.2   # 开场给玩家一点喘息，不要立刻铺弹幕
	_agent = get_node_or_null("Nav") as NavigationAgent2D
	if _agent != null:
		_agent.radius = nav_radius
		_agent.path_desired_distance = nav_path_desired
		_agent.target_desired_distance = nav_target_desired
		_agent.max_speed = move_speed
		_agent.avoidance_enabled = false   # 只用路径寻路；不参与 RVO，免得削弱冲锋速度
	_drift_dir = 1.0 if randf() < 0.5 else -1.0
	_last_pos = global_position
	_respawn_cd = minion_respawn_interval
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	z_index = DepthSort.z_for(global_position.y)
	_tick_timers(delta)
	match _state:
		State.CHASE:
			_do_chase(delta)
		State.RING_CAST:
			_do_ring_cast()
		State.ICE_CAST:
			_do_ice_cast()
		State.HEAL_WINDUP:
			_do_heal_windup()
		State.HEAL:
			_do_heal(delta)
		State.CYAN_CHARGE:
			_do_charge(delta)
		State.STUNNED:
			_do_stunned()


func _tick_timers(delta: float) -> void:
	_ring_cd = maxf(_ring_cd - delta, 0.0)
	_ice_cd = maxf(_ice_cd - delta, 0.0)
	_heal_cd = maxf(_heal_cd - delta, 0.0)
	_heal_lock_t = maxf(_heal_lock_t - delta, 0.0)
	_attack_lock = maxf(_attack_lock - delta, 0.0)
	_retarget_cd = maxf(_retarget_cd - delta, 0.0)
	_state_t += delta
	_phase_change_cd = maxf(_phase_change_cd - delta, 0.0)
	# 低血时解锁冰子弹（一次性，避免回血后重新解锁）。
	if not _ice_enabled and health > 0.0 and health <= max_health * ice_unlock_ratio:
		_ice_enabled = true
		_ice_cd = ice_unlock_delay
		GameState.notice.emit("Boss 解锁冰子弹！变蓝锁定你时快走")
	# 红色小怪封锁只在前两阶段生效；进入第三阶段后即使回血也永久保持封锁。
	if _red_summons_locked and _phase < 2 and health > max_health * red_summon_lock_ratio:
		_red_summons_locked = false
	if not _red_summons_locked and health > 0.0 and health <= max_health * red_summon_lock_ratio:
		_lock_red_summons()
	# 先按当前阶段校正召唤物，再补足当前阶段的缺口。
	_check_summons()
	_respawn_cd = maxf(_respawn_cd - delta, 0.0)
	if _respawn_cd <= 0.0:
		_respawn_cd = minion_respawn_interval
		_try_respawn()


## 阶段组成：>phase1 → 2 红；≤phase1 → 2 红 + 1 蓝；≤phase2 → 2 蓝 + 1 绿。
func _phase_for_health() -> int:
	var ratio := health / maxf(max_health, 0.01)
	if ratio <= minion_phase2_ratio:
		return 2
	if ratio <= minion_phase1_ratio:
		return 1
	return 0


## 某阶段的小怪组成：[{scene, type, count}]。
func _composition(p: int) -> Array:
	match p:
		1:
			return [
				{"scene": red_minion_scene, "type": "red", "count": 2},
				{"scene": blue_minion_scene, "type": "blue", "count": 1},
			]
		2:
			return [
				{"scene": blue_minion_scene, "type": "blue", "count": 2},
				{"scene": green_minion_scene, "type": "green", "count": 1},
			]
		_:
			return [{"scene": red_minion_scene, "type": "red", "count": 2}]


## 血线跨阶段（只升不降：一旦进某阶段就留场，避免被 Boss 回血挤掉）：无伤清旧再按新组成召唤。
func _check_summons() -> void:
	if not _nav_ready():
		return
	# 回血不会降阶段：始终停留在已经到达过的最高阶段。
	var p := maxi(_phase_for_health(), _phase)
	if p == _phase:
		return
	# 防止在阶段血线附近小幅回血/掉血导致反复清怪。
	if _phase != -1 and _phase_change_cd > 0.0:
		return
	_phase = p
	if p >= 2:
		_red_summons_locked = true
	_phase_change_cd = 0.8
	_clear_adds()
	var plan: Array = []
	var names: Array = []
	for entry in _composition(p):
		var type := str(entry["type"])
		var count := int(entry["count"])
		if not _can_summon(entry["scene"], type, count):
			continue
		var base_ang := randf() * TAU
		for i in count:
			plan.append({
				"scene": entry["scene"],
				"type": type,
				"angle": base_ang + TAU * float(i) / float(count),
			})
		names.append(type)
	_start_summon_plan(plan)
	if not names.is_empty():
		GameState.notice.emit("Boss 召唤：%s" % ", ".join(names))


## 无伤清除全部召唤物（直接 queue_free，不发 died → 不触发 Boss 扣血）。
func _clear_adds() -> void:
	# 取消仍在逐只等待的旧召唤序列，避免清场后又冒出上一阶段的小怪。
	_summon_generation += 1
	for m in _all_boss_minions():
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			m.queue_free()
	_adds.clear()


## 低血后永久锁定红色小怪召唤，并清掉当前已经存在的红小怪。
func _lock_red_summons() -> void:
	if _red_summons_locked:
		return
	_red_summons_locked = true
	var kept: Array = []
	for m in _all_boss_minions():
		if str(m.get("minion_type")) == "red":
			m.queue_free()
		else:
			kept.append(m)
	_adds = kept


## 该类型/数量当前是否允许召唤（红怪可能已被永久封锁）。
func _can_summon(scene: PackedScene, type: String, count: int) -> bool:
	if _red_summons_locked and type == "red":
		return false
	return scene != null and count > 0


## 启动一段召唤计划：按顺序逐只出现，每只间隔 minion_summon_stagger。
func _start_summon_plan(plan: Array) -> void:
	if plan.is_empty():
		return
	var holder := get_parent()
	if holder == null:
		return
	# 新计划会取消上一段尚未完成的召唤，避免重叠刷怪。
	_summon_generation += 1
	_run_summon_plan(plan, _summon_generation, holder)


func _run_summon_plan(plan: Array, generation: int, holder: Node) -> void:
	for i in plan.size():
		if _state == State.DEAD or not is_inside_tree() or not is_instance_valid(holder):
			return
		if generation != _summon_generation:
			return
		var entry: Dictionary = plan[i]
		_spawn_minion(entry["scene"], str(entry["type"]), float(entry["angle"]), holder)
		if i < plan.size() - 1 and minion_summon_stagger > 0.0:
			await get_tree().create_timer(minion_summon_stagger).timeout


func _spawn_minion(scene: PackedScene, type: String, angle: float, holder: Node) -> void:
	if scene == null:
		return
	var m := scene.instantiate()
	holder.add_child(m)
	m.add_to_group("boss_minion")
	if m.get("minion_type") != null:
		m.set("minion_type", type)
	if m is Node2D:
		(m as Node2D).global_position = _spawn_pos(Vector2.from_angle(angle))
	_watch_minion(m)


## 召唤点：Boss 外一圈的方向点；吸附到导航网格上，避免落到墙外卡住。
func _spawn_pos(dir: Vector2) -> Vector2:
	var p := global_position + dir.normalized() * minion_spawn_radius
	if not _nav_ready():
		return p
	return NavigationServer2D.map_get_closest_point(get_world_2d().navigation_map, p)


## 监听一只召唤物（阵亡回调）；存活统计走 _alive_count 按需统计。
func _watch_minion(m: Node) -> void:
	_adds.append(m)
	if m.has_signal("died"):
		m.died.connect(_on_minion_died.bind(m))


## 当前存活且未失效的某类型小怪数（顺带清理失效引用）。
func _alive_count(type: String) -> int:
	var n := 0
	var kept := _all_boss_minions()
	for m in kept:
		if str(m.get("minion_type")) == type:
			n += 1
	_adds = kept
	return n


## 召唤的小怪阵亡：红/蓝扣血；绿怪不扣血，改为打断 Boss 回血。
func _on_minion_died(m: Node = null) -> void:
	if _state == State.DEAD:
		return
	var t := ""
	if m != null and is_instance_valid(m):
		t = str(m.get("minion_type"))
	if t == "green":
		interrupt_heal(green_death_heal_lock)
		GameState.notice.emit("绿怪阵亡，Boss 回血被打断！")
		return
	take_damage(max_health * minion_death_damage_ratio)
	GameState.notice.emit("小怪阵亡，Boss −%d%%" % int(round(minion_death_damage_ratio * 100.0)))


## 周期性把当前组成逐类补足到目标数（Boss 死后不再补）。
## 当前 Boss 召唤的全部小怪（列表 + 分组兜底，避免漏清）。
func _all_boss_minions() -> Array:
	var out: Array = []
	var seen := {}
	for m in _adds:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			seen[m] = true
			out.append(m)
	for m in get_tree().get_nodes_in_group("boss_minion"):
		if GameState.is_in_current_scene(m) and is_instance_valid(m) and not m.is_queued_for_deletion() and not seen.has(m):
			seen[m] = true
			out.append(m)
	return out


func _nav_ready() -> bool:
	var map := get_world_2d().navigation_map
	return map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0


func _try_respawn() -> void:
	if _state == State.DEAD or _phase < 0 or not _nav_ready():
		return
	var plan: Array = []
	for entry in _composition(_phase):
		var type := str(entry["type"])
		var target := int(entry["count"])
		var have := _alive_count(type)
		var count := target - have
		if not _can_summon(entry["scene"], type, count):
			continue
		var base_ang := randf() * TAU
		for i in count:
			plan.append({
				"scene": entry["scene"],
				"type": type,
				"angle": base_ang + TAU * float(i) / float(count),
			})
	_start_summon_plan(plan)


# —— 行为 ——

## 与玩家保持 preferred_distance：距离超出死区就靠近/远离（交给导航绕障过去），
## 距离合适则横向漂移游斗。按冷却择招：冰弹 > 环形弹幕。
func _do_chase(delta: float) -> void:
	if not _player_valid():
		_steer(Vector2.ZERO)
		return
	if _heal_cd_ready():
		_enter(State.HEAL_WINDUP)
		return
	if require_line_of_sight and not _has_los_to_player():
		_los_blocked_t += delta
		_flank(delta)
		return
	_los_blocked_t = 0.0
	_kite(delta)
	if _attack_lock > 0.0:
		return
	if _ice_enabled and _ice_cd <= 0.0:
		_enter(State.ICE_CAST)
		return
	if _ring_cd <= 0.0:
		_enter(State.RING_CAST)


## 视线被掩体挡住：绕到玩家周围的另一个角度，而不是隔墙空放弹幕。
func _flank(delta: float) -> void:
	var to_boss := global_position - _player.global_position
	var dist := to_boss.length()
	_update_corner(delta, dist, true)
	if _cornered:
		if _retarget_cd <= 0.0:
			_retarget_cd = retarget_interval
			if _agent != null:
				_agent.target_position = _player.global_position
		_steer(_path_dir() * move_speed)
		return
	if _retarget_cd <= 0.0:
		_retarget_cd = retarget_interval
		if _agent != null:
			_agent.target_position = _flank_point()
	_steer(_path_dir() * move_speed)


## 在玩家周围找一个「有视线 + 导航可达」的绕侧点；找不到就朝玩家靠近。
func _flank_point() -> Vector2:
	var base_ang := (global_position - _player.global_position).angle()
	var offsets := [0.0, 35.0, -35.0, 70.0, -70.0, 105.0, -105.0, 140.0, -140.0, 180.0]
	for deg in offsets:
		var p := _player.global_position + Vector2.from_angle(base_ang + deg_to_rad(deg)) * preferred_distance
		p = _snap_to_nav(p)
		if _point_has_los(p, _player.global_position):
			return p
	return _player.global_position


func _has_los_to_player() -> bool:
	if not _player_valid():
		return false
	return _point_has_los(global_position, _player.global_position)


func _point_has_los(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 2)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


## 把绕侧点吸附到导航网格，避免目标落在墙体内部导致卡住。
func _snap_to_nav(p: Vector2) -> Vector2:
	if not _nav_ready():
		return p
	return NavigationServer2D.map_get_closest_point(get_world_2d().navigation_map, p)


## 距离保持走位：目标点 = 玩家位置 + 朝己方向 × preferred_distance。
## 同一公式：太远时目标点落在中间（靠近），太近时落在更外侧（远离）。
## 若被墙/障碍逼住、想动却动不了 → 进入「墙角」状态，改为主动靠近玩家脱困。
func _kite(delta: float) -> void:
	var to_boss := global_position - _player.global_position
	var dist := to_boss.length()
	var dir := to_boss / dist if dist > 0.001 else Vector2.RIGHT
	var offset := dist - preferred_distance
	var maintaining := absf(offset) > distance_deadzone

	_update_corner(delta, dist, maintaining)

	if _cornered:
		# 被逼墙角：放弃拉开距离，直接朝玩家靠，走出死角。
		if _retarget_cd <= 0.0:
			_retarget_cd = retarget_interval
			if _agent != null:
				_agent.target_position = _player.global_position
		_steer(_path_dir() * move_speed)
		return

	if maintaining:
		# 需要靠近/远离：把目标点交给导航，让它绕开障碍走过去。
		if _retarget_cd <= 0.0:
			_retarget_cd = retarget_interval
			if _agent != null:
				_agent.target_position = _player.global_position + dir * preferred_distance
		_steer(_path_dir() * move_speed)
	else:
		# 已就位：沿切向缓慢漂移，避免原地待机显得呆板。
		if randf() < delta * 0.5:
			_drift_dir = -_drift_dir
		_steer(dir.orthogonal() * _drift_dir * drift_speed)


## 墙角判定：正在拉开/追近距离、却撞到东西且几乎没挪动 → 累积计时；
## 超过 stuck_time 进入墙角状态，靠近到 corner_release_distance（或超时）后解除。
func _update_corner(delta: float, dist: float, maintaining: bool) -> void:
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position

	if _cornered:
		_cornered_t -= delta
		if dist <= corner_release_distance or _cornered_t <= 0.0:
			_cornered = false
			_stuck_t = 0.0
		return

	if maintaining and moved < move_speed * delta * 0.25:
		_stuck_t += delta
		if _stuck_t >= stuck_time:
			_cornered = true
			_cornered_t = cornered_duration
	else:
		_stuck_t = maxf(_stuck_t - delta * 2.0, 0.0)


## 沿导航路径的下一段方向；无路径/未就绪时退化为直线朝向导航目标点。
func _path_dir() -> Vector2:
	if _agent == null:
		return Vector2.ZERO
	var to_target := _agent.target_position - global_position
	if not _agent.is_navigation_finished():
		var d := _agent.get_next_path_position() - global_position
		if d.length() > 1.0:
			to_target = d
	if to_target.length() < 1.0:
		return Vector2.ZERO
	return to_target.normalized()


## 统一的移动出口：设定速度并 move_and_slide。
func _steer(v: Vector2) -> void:
	velocity = v
	move_and_slide()


func _do_ring_cast() -> void:
	_steer(Vector2.ZERO)
	if require_line_of_sight and not _has_los_to_player():
		_ring_cd = maxf(_ring_cd, 0.35)
		_enter(State.CHASE)
		return
	if _state_t < ring_windup:
		return
	_fire_ring()
	_ring_cd = _ring_interval()
	_attack_lock = post_attack_lock
	_enter(State.CHASE)


func _do_ice_cast() -> void:
	_steer(Vector2.ZERO)
	if require_line_of_sight and not _has_los_to_player():
		_ice_cd = maxf(_ice_cd, 0.55)
		_enter(State.CHASE)
		return
	_update_aim_line()
	if _state_t < ice_windup:
		return
	_fire_ice()
	_ice_cd = _ice_interval()
	_attack_lock = post_attack_lock
	_enter(State.CHASE)


## 绿色回复开始：变绿 + 登记可被附蓝（apply_boss_color 仅在 HEAL 态生效）。
func _start_heal() -> void:
	_heal_left = max_health * heal_fraction
	_enter(State.HEAL)
	GameState.alert.emit("BOSS 正在回复", "用蓝色打断它", heal_color, heal_duration)


## 回血空窗期：原地静止、变绿蓄力，满 heal_windup_time 才开始真正回血；期间可被打断。
func _do_heal_windup() -> void:
	_steer(Vector2.ZERO)
	if _state_t >= heal_windup_time:
		_start_heal()


func _do_heal(delta: float) -> void:
	_steer(Vector2.ZERO)
	# 回血期间「可打红色环弹、禁止蓝色冰弹」：只走环形弹幕冷却，绝不进入 ICE_CAST。
	if _ring_cd <= 0.0:
		_fire_ring()
		_ring_cd = _ring_interval()
	var total := maxf(max_health * heal_fraction, 0.01)
	var rate := total / maxf(heal_duration, 0.01)
	var healed := minf(rate * delta, _heal_left)
	health = minf(health + healed, max_health)
	_heal_left -= healed
	health_changed.emit(health, max_health)
	if _heal_left <= 0.0 or _state_t >= heal_duration:
		_heal_cd = heal_cooldown
		_enter(State.CHASE)


## 打断回血（供绿共鸣石调用）：立即退出 HEAL，并封锁回血 lock_time 秒。
func interrupt_heal(lock_time: float = 0.0) -> void:
	if _state == State.DEAD:
		return
	var was_healing := _state == State.HEAL or _state == State.HEAL_WINDUP
	if was_healing:
		_heal_left = 0.0
		_enter(State.CHASE)
		GameState.alert_cancelled.emit()
	_heal_lock_t = maxf(_heal_lock_t, lock_time)
	_heal_cd = maxf(_heal_cd, lock_time)
	if was_healing:
		GameState.notice.emit("Boss 回血被打断！")


## 强制进入回血（供绿小怪调用）；回血封锁期内无效。
func force_heal() -> void:
	if _state == State.DEAD or _state == State.HEAL or _heal_lock_t > 0.0:
		return
	_heal_cd = 0.0
	_start_heal()


## 进入青色冲锋（由玩家附蓝触发）：朝「远离赋予来源」方向冲刺，撞墙自伤。
## 方向/计时/撞墙判定全部交给 BossCyanCharge，本函数只负责切状态和提示。
func _enter_cyan_charge(from_pos: Vector2) -> void:
	_cyan.start(global_position, from_pos, _aim_dir())
	_enter(State.CYAN_CHARGE)
	GameState.alert.emit("青色冲锋！", "躲开冲锋路线，引它撞墙", cyan_color, 1.4)


func _do_charge(delta: float) -> void:
	_steer(_cyan.direction * _cyan.speed)
	var outcome := _cyan.tick(delta, get_slide_collision_count())
	if outcome == CyanCharge.Outcome.CRASHED:
		_charge_crash()
		return
	if outcome == CyanCharge.Outcome.FINISHED:
		_enter(State.CHASE)


## 撞墙：按最大血比例自伤 + 眩晕；并把回复推后，避免连环刷回复。
func _charge_crash() -> void:
	AudioManager.play_event("boss_wall")
	charge_crashed.emit()
	health = maxf(health - max_health * _cyan.self_damage_ratio, 0.0)
	health_changed.emit(health, max_health)
	_flash()
	velocity = Vector2.ZERO
	if health <= 0.0:
		_die()
		return
	_heal_cd = maxf(_heal_cd, heal_cooldown)
	_enter(State.STUNNED)


func _do_stunned() -> void:
	_steer(Vector2.ZERO)
	if _state_t >= _cyan.stun_time:
		_enter(State.CHASE)


# —— 攻击 · 频率设计 ——

## 全局难度 0（满血）~ 1（濒死）：驱动环形弹幕的密度与节奏。
func _difficulty() -> float:
	return clampf(1.0 - health / maxf(max_health, 0.01), 0.0, 1.0)


## 环形弹幕间隔：随血量降低从 ring_interval_max 压到 ring_interval_min。
func _ring_interval() -> float:
	return lerpf(ring_interval_max, ring_interval_min, _difficulty())


## 每圈弹数：随血量降低从 ring_bullets_min 增到 ring_bullets_max。
func _ring_bullet_count() -> int:
	return int(round(lerpf(float(ring_bullets_min), float(ring_bullets_max), _difficulty())))


## 冰弹间隔：半血解锁时为 ice_interval_half，濒死压到 ice_interval_min。
func _ice_interval() -> float:
	var hp := health / maxf(max_health, 0.01)
	var t := clampf((ice_unlock_ratio - hp) / maxf(ice_unlock_ratio, 0.01), 0.0, 1.0)
	return lerpf(ice_interval_half, ice_interval_min, t)


## 濒死时冰弹改成小扇形连发（1 → ice_max_count）。
func _ice_count() -> int:
	return int(round(lerpf(1.0, float(ice_max_count), _difficulty())))


## 朝玩家方向铺一个扇形（ring_arc_deg 张角），逼玩家走位躲开。
func _fire_ring() -> void:
	if ring_bullet_scene == null:
		return
	var count := maxi(_ring_bullet_count(), 1)
	var base := _aim_dir()
	var arc := deg_to_rad(ring_arc_deg)
	for i in count:
		var ang := 0.0
		if count > 1:
			ang = arc * (float(i) / float(count - 1) - 0.5)
		_spawn_projectile(ring_bullet_scene, base.rotated(ang), ring_bullet_speed, ring_muzzle)


## 沿「预警时锁定的方向」发射冰弹（锁定后方向固定，玩家靠走位躲开）。
func _fire_ice() -> void:
	if ice_scene == null:
		return
	AudioManager.play_event("blue_shoot")
	var count := maxi(_ice_count(), 1)
	var base := _ice_dir if _ice_dir != Vector2.ZERO else Vector2.RIGHT
	_spawn_sniper_flash(base)
	for i in count:
		var ang := 0.0
		if count > 1:
			ang = deg_to_rad(ice_spread_deg) * (float(i) - float(count - 1) * 0.5)
		_spawn_projectile(
			ice_scene, base.rotated(ang), ice_speed, ice_muzzle, ice_duration, ice_max_range
		)


## 进入冰弹预警：锁定当前朝玩家方向，亮出狙击瞄准线（之后不再追踪）。
func _begin_ice_aim() -> void:
	_ice_dir = _aim_dir()
	_update_aim_line()
	GameState.notice.emit("蓝色狙击锁定！离开瞄准线")


func _update_aim_line() -> void:
	if _sight == null:
		return
	_sight.call("show_sight", _ice_dir, aim_line_length)
	if _sight.has_method("set_locked"):
		_sight.call("set_locked", _state_t >= ice_windup - 0.15)


func _hide_aim_line() -> void:
	if _sight != null:
		if _sight.has_method("hide_sight"):
			_sight.call("hide_sight")
		else:
			_sight.visible = false


## 狙击开火瞬间的枪口光束。
func _spawn_sniper_flash(dir: Vector2) -> void:
	var holder := get_parent()
	if holder == null:
		return
	var flash := SniperShotScript.new()
	holder.add_child(flash)
	flash.global_position = global_position
	if flash.has_method("setup"):
		flash.call("setup", dir, ice_telegraph_color, minf(aim_line_length, 2200.0))


# —— 发射 ——

## 生成一枚投射物（复用 ParryProjectile 契约：可被黄色场景物 / 玩家弹反）。
func _spawn_projectile(
	scene: PackedScene,
	dir: Vector2,
	speed: float,
	muzzle: float,
	freeze_dur: float = -1.0,
	max_range: float = -1.0
) -> Node:
	if scene == null:
		return null
	var proj := scene.instantiate()
	var holder := get_parent()
	if holder == null:
		proj.queue_free()
		return null
	holder.add_child(proj)
	# 子弹从本体中心出膛：与本体互相忽略，避免一出生就撞到自己被销毁。
	if proj is CollisionObject2D:
		(proj as CollisionObject2D).add_collision_exception_with(self)
	var d := dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	if proj is Node2D:
		(proj as Node2D).global_position = global_position + d * muzzle
	if proj.has_method("setup"):
		proj.call("setup", d, "enemy")
	if proj.get("speed") != null:
		proj.set("speed", speed)
	var limit := max_range if max_range >= 0.0 else bullet_max_range
	if limit > 0.0 and proj.get("max_distance") != null:
		proj.set("max_distance", limit)
	if freeze_dur >= 0.0 and proj.get("freeze_duration") != null:
		proj.set("freeze_duration", freeze_dur)
	return proj


func _aim_dir() -> Vector2:
	if _player_valid():
		var d := global_position.direction_to(_player.global_position)
		if d != Vector2.ZERO:
			return d
	return Vector2.RIGHT


func _player_valid() -> bool:
	return _player != null and is_instance_valid(_player)


func _heal_cd_ready() -> bool:
	return _heal_cd <= 0.0 and _heal_lock_t <= 0.0 and health > 0.0 and health <= max_health * heal_threshold


# —— 状态切换 ——

func _enter(s: int) -> void:
	_state = s
	state_changed.emit(s)
	_state_t = 0.0
	_stop_heal_pulse()
	_set_body_modulate(Color.WHITE)
	match s:
		State.CHASE:
			_play_body_state("red")
			_hide_aim_line()
		State.RING_CAST:
			_play_body_state("red")
			_hide_aim_line()
		State.ICE_CAST:
			_play_body_state("blue")
			_begin_ice_aim()
		State.HEAL_WINDUP:
			_play_body_state("green")
			_hide_aim_line()
			_start_heal_pulse()
			_spawn_pulse_ring(heal_windup_color, 120.0, 360.0, heal_windup_time)
			GameState.alert.emit(
				"BOSS 准备回复",
				"%d 秒后开始回血 · 用蓝色打断" % int(round(heal_windup_time)),
				heal_windup_color,
				heal_windup_time
			)
		State.HEAL:
			AudioManager.play_event("boss_heal")
			_play_body_state("green")
			_hide_aim_line()
			_start_heal_pulse()
			_spawn_pulse_ring(heal_color, 110.0, 320.0, heal_duration)
		State.CYAN_CHARGE:
			_play_body_state("cyan")
			_hide_aim_line()
			_spawn_pulse_ring(cyan_color, 100.0, 320.0, 0.5)
		State.STUNNED:
			_play_body_state("cyan")
			_set_body_modulate(stun_color)
			_hide_aim_line()
		_:
			pass


# —— 受伤 / 死亡 ——

func take_damage(amount: float = 1.0) -> void:
	if _state == State.DEAD or amount <= 0.0:
		return
	AudioManager.play_event("boss_hit")
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_flash()
	if health <= 0.0:
		_die()


## 被弹反子弹命中：按最大生命比例扣血（每颗默认 5%）。
func take_reflected_damage() -> void:
	take_damage(max_health * reflected_bullet_damage_ratio)


## 回复血量（供绿色小怪等调用）。不超过上限，死亡后无效。
func heal(amount: float) -> void:
	if _state == State.DEAD or amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func _die() -> void:
	_state = State.DEAD
	_cyan.stop()
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	_stop_heal_pulse()
	_hide_aim_line()
	GameState.alert_cancelled.emit()
	_kill_all_minions()
	died.emit()
	_pending_idle_anim = &""
	var has_death := _body != null and _body.sprite_frames != null and _body.sprite_frames.has_animation(DEATH_ANIM)
	if has_death:
		_body.modulate = Color.WHITE
		_body.self_modulate = Color.WHITE
		_body.play(DEATH_ANIM)
		await _body.animation_finished
		if not is_inside_tree():
			return
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free)


## Boss 阵亡：让全部召唤物一起消失，并清掉它们留下的藤蔓/地面残留。
func _kill_all_minions() -> void:
	var seen := {}
	for m in _adds:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			seen[m.get_instance_id()] = true
			_kill_minion_node(m)
	_adds.clear()
	for m in get_tree().get_nodes_in_group("minion"):
		if not GameState.is_in_current_scene(m):
			continue
		if m.is_queued_for_deletion() or seen.has(m.get_instance_id()):
			continue
		_kill_minion_node(m)
	for v in get_tree().get_nodes_in_group("boss_vine"):
		if GameState.is_in_current_scene(v) and v.has_method("_despawn"):
			v.call("_despawn")
	for h in get_tree().get_nodes_in_group("ice_crystal"):
		if GameState.is_in_current_scene(h):
			h.queue_free()
	for h in get_tree().get_nodes_in_group("burn_trail"):
		if GameState.is_in_current_scene(h):
			h.queue_free()


func _kill_minion_node(m: Node) -> void:
	if m == null or not is_instance_valid(m):
		return
	if m.has_method("kill"):
		m.call("kill")
	else:
		m.queue_free()


func health_snapshot() -> Dictionary:
	return {"health": health, "max_health": max_health}


# —— Boss 专用蓝色交互（不走解密 colorable 契约）——

## 仅在绿色回复/空窗期接受「蓝」→ 触发 Boss 独立青色冲锋。
## 返回 true 表示消耗玩家 1 颗蓝；其余情况 false（跟班会退还种子）。
func apply_boss_color(
	_c: Color, color_name: String = "", from_pos: Vector2 = Vector2.INF
) -> bool:
	if _state != State.HEAL and _state != State.HEAL_WINDUP:
		return false
	if color_name != cyan_trigger_color_name:
		return false
	_enter_cyan_charge(from_pos)
	return true


## 鼠标命中判定（Boss 专用目标组使用）。
func contains_point(world_pos: Vector2) -> bool:
	return global_position.distance_to(world_pos) <= hit_radius


# —— 视觉 ——

## 切换到某套颜色待机；蓝/绿/青先播一次 4 帧转换动画，再循环对应待机。
func _play_body_state(kind: String) -> void:
	if _body == null:
		return
	if kind == _body_color_state:
		return
	_body_color_state = kind
	var idle: StringName = BODY_IDLE_ANIMS.get(kind, &"idle_red")
	var transition: StringName = BODY_TRANSITION_ANIMS.get(kind, &"")
	if transition != &"" and _body.sprite_frames != null and _body.sprite_frames.has_animation(transition):
		_pending_idle_anim = idle
		_body.play(transition)
	else:
		_pending_idle_anim = &""
		_body.play(idle)


func _on_body_animation_finished() -> void:
	if _pending_idle_anim == &"":
		return
	var next := _pending_idle_anim
	_pending_idle_anim = &""
	if _body != null:
		_body.play(next)


func _set_body_modulate(c: Color) -> void:
	if _body != null:
		_body.modulate = c


## 蓄力/回复期间让本体轻微呼吸缩放。
func _start_heal_pulse() -> void:
	if _body == null:
		return
	_stop_heal_pulse()
	var large := _body_base_scale * 1.06
	_heal_pulse = create_tween().set_loops()
	_heal_pulse.tween_property(_body, "scale", large, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_heal_pulse.tween_property(_body, "scale", _body_base_scale, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_heal_pulse() -> void:
	if _heal_pulse != null and _heal_pulse.is_valid():
		_heal_pulse.kill()
	_heal_pulse = null
	if _body != null:
		_body.scale = _body_base_scale


## 一圈向外扩散并淡出的充能环（绿色回复 / 青色冲锋用）。
func _spawn_pulse_ring(c: Color, from_radius: float, to_radius: float, duration: float) -> void:
	var ring := Line2D.new()
	ring.width = 12.0
	ring.default_color = Color(c.r, c.g, c.b, 0.75)
	ring.z_index = 2
	var fx_from := from_radius * BOSS_FX_SCALE
	var fx_to := to_radius * BOSS_FX_SCALE
	ring.points = _circle_points(fx_from, 48)
	add_child(ring)
	var t := create_tween()
	t.set_parallel(true)
	var grow := fx_to / maxf(fx_from, 1.0)
	t.tween_property(ring, "scale", Vector2.ONE * grow, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(ring.queue_free)


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		pts.append(Vector2.from_angle(TAU * float(i) / float(segments)) * radius)
	return pts


func _flash() -> void:
	if _body == null:
		return
	_body.self_modulate = Color(2.0, 2.0, 2.0, 1.0)
	var t := create_tween()
	t.tween_property(_body, "self_modulate", Color.WHITE, 0.25)
