class_name Player
extends CharacterBody2D

## 变色玩法：换色时发出，供 HUD 更新显示。
signal color_changed(new_color: Color, color_name: String)
## 颜色库/选中变化时发出，供 HUD 显示整套调色盘与当前选中。
signal inventory_changed(inventory: Dictionary, selected_element: String)
## 血量变化（current / max）。HUD 据此刷新红心。
signal health_changed(health: float, max_health: int)
## 血量归零死亡（重生由 Player 自行处理，这里只广播，供音效/演出等监听）。
signal died

## 角色控制器：2D 场景下的 2.5D 俯视（3/4）角色。
## 白盒阶段只做移动、朝向和动画状态机，不包含碰撞玩法逻辑。

enum State {
	IDLE,
	WALK,
	RUN,
	JUMP,
	ROTATE,
	HIT,
}

@export_group("Movement")
@export_range(0.0, 20000.0, 1.0) var walk_speed := 1500.0
@export_range(0.0, 30000.0, 1.0) var run_speed := 2400.0
## 起步加速度（像素/秒²）：越大越快达到全速。
@export_range(0.0, 40000.0, 100.0) var accel := 9000.0
## 松手后的减速度（像素/秒²）：越大刹车越干脆。
@export_range(0.0, 40000.0, 100.0) var decel := 14000.0

@export_group("Jump")
@export_range(0.0, 200.0, 1.0) var jump_height := 12.0
@export_range(0.05, 2.0, 0.05) var jump_duration := 0.45

@export_group("Rotate")
@export_range(0.05, 2.0, 0.05) var rotate_duration := 0.5

@export_group("Visual")
@export_range(0.01, 32.0, 0.001) var pixel_scale := 0.28
@export var animation_frames: SpriteFrames

@export_group("Interact")
@export_range(8.0, 4096.0, 1.0) var interact_range := 1024.0
## 红/蓝上色成功后，以落点为中心清除对应残留的半径（世界像素）。
@export_range(0.0, 4000.0, 50.0) var element_purge_radius := 800.0

@export_group("Light")
## 玩家自带微光半径（世界像素，256px ≈ 1 格）。暗房里照亮自身周围；相机 zoom 0.25，太小在屏幕上根本看不见。
@export_range(8.0, 4096.0, 8.0) var light_radius := 384.0

@export_group("Water Flow")
## 水流推力（像素/秒）。流向由脚下浅水格子的流向标记决定（见 flow_marker_spawner.gd）。
@export_range(0.0, 2000.0, 1.0) var flow_strength := 600.0

@export_group("Health")
## 最大血量（红心数）。初始 1 颗心；后续可加「心之容器」提高上限。
@export_range(1, 20, 1) var max_health := 1
## 屏幕像素；设为 0 可关闭受击镜头震动。
@export_range(0.0, 12.0, 0.5) var hit_shake_pixels := 3.0
@export var hit_gamepad_vibration := true

@export_group("Testing")
## 测试用：开启后玩家永久持有 红/蓝/绿 三色（消耗不减少），方便自由试玩各机制。
@export var infinite_elements := false
## 测试模式下的初始持有量（仅用于 HUD 显示，不参与扣除）。
@export var infinite_amount := 999

const FOOTPRINT_RADIUS := 64.0
const OUTLINE_SHADER := preload("res://shaders/outline_colorful.gdshader")
const Rules := preload("res://scripts/element/element_rules.gd")
const DepthSort := preload("res://scripts/depth_sort.gd")
## 水格碰撞层（water_cell.gd 里 collision_layer=2）。站在水里时临时忽略这层，让玩家能在水里走动。
const WATER_COLLISION_LAYER := 2
## 高清图脚底距画布中心的帧像素（1294×1626 画布，脚底 bbox 底≈1518，中心 813 → 705）。
const FEET_FRAME_OFFSET := 705.0
## 影子压扁比例（y = x × 这个）。原像素图 shadow scale (16, 7.2) → 0.45。
const SHADOW_FLATTEN := 0.45
## 受击后无敌时长（毫秒），防止机关连发瞬间秒杀。
const INVINCIBLE_MS := 1000
## 受击动画时长（秒），需与受击动画实际时长对齐（12 帧 ÷ speed）。
const HIT_DURATION := 1.0

## 4 方向（屏幕坐标，y 向下）：下、左、上、右。
const DIRS: Array[Vector2] = [
	Vector2(0, 1),
	Vector2(-1, 0),
	Vector2(0, -1),
	Vector2(1, 0),
]

## 素材里实际画的 4 个方向。左右各有独立素材，不再用 flip_h 镜像。
const DIR_NAMES: Array[String] = ["down", "left", "up", "right"]

var state: int = State.IDLE
var facing: int = 0
## 当前选中元素对应的颜色/名称（供 HUD 与描边显示）。
var selected_color := Color.WHITE
var selected_color_name := "无"
## 颜色库：玩家持有的元素种子（元素 id -> 数量）。种子守恒：只能从世界色源吸收获得。
var _inventory: Dictionary = {}
## 当前选中、用于「赋予」的元素 id；空 = 未持有任何元素。
var _selected_element := ""

var _jump_t := 1.0
var _rotate_t := 0.0
## 贴图基准偏移（帧像素，会被 sprite.scale 一起缩放）。高清图本身已居中，置 0 即可。
var _base_sprite_offset := Vector2.ZERO
var _outline_material: ShaderMaterial
var _highlighted: Node = null
var _highlight_outline: Sprite2D = null
var _range_indicator: RangeIndicator = null   # 工作圈节点（_setup_range_indicator 拿到，每帧同步 active）
var _freeze_preview_water: Node = null   # 当前显示冻结预览的水格
var _freeze_preview_on := false          # 预览当前是否开启（含「手里是蓝」这一条件）
var _base_collision_mask := 0    # 场景里配好的碰撞掩码（含水层）
var _in_water := false           # 是否正站在水里（不可站水格）→ 临时忽略水层碰撞以便踩水
var _knockback_vel := Vector2.ZERO   # 被飞行物命中时的击退速度（逐帧衰减）
var _move_vel := Vector2.ZERO        # 输入产生的平滑移动速度（加减速用）
var opening_input_locked := false
## 只登记玩家实际赋予成功的目标，避免回收关卡原有的种子源。
var _placed_colors: Dictionary = {}
const COLOR_WHEEL_HINT := "tutorial_color_wheel"
const COLOR_QUANTITY_HINT := "tutorial_color_quantity"
var _color_quantity_hint_delay := -1.0
var _color_tutorial_wait := 0.0
var _color_wheel_hint_delay := -1.0
var _dialogue_active := false        # 对话中禁止玩家移动
var health := 1.0
var _invincible_until := 0
var _hit_t := 0.0   # 受击动画计时
var _hit_feedback: Node
var _action_input_guard_until := 0
var _frozen := false        # 被冰冻（Boss 蓝弹）：禁止移动，需用红色解冻
var _freeze_t := 0.0        # 冰冻剩余时间（超时兜底自动解冻）
var _slow_t := 0.0          # 减速剩余时间（冰晶等地表）：不禁止移动，只是变慢
var _slow_factor := 1.0     # 减速系数（1 = 不减速，越小越慢）

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var collision: CollisionShape2D = $Collision
@onready var shadow: CharacterShadow = $Shadow


func _ready() -> void:
	_hit_feedback = preload("res://scripts/hit_feedback.gd").new()
	add_child(_hit_feedback)
	add_to_group("player")
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	for bonus in GameState.health_upgrades.values():
		max_health += int(bonus)
	health = float(max_health)
	_base_collision_mask = collision_mask
	_register_input_actions()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(pixel_scale, pixel_scale)
	# 脚底对齐玩家原点：画布居中，脚底在中心下方 FEET_FRAME_OFFSET 帧像素。
	sprite.position.y = -FEET_FRAME_OFFSET * pixel_scale
	# 影子跟随玩家尺寸（宽同玩家、高按比例压扁），只改 pixel_scale 就整体联动。
	shadow.set_rest_scale(Vector2(pixel_scale, pixel_scale * SHADOW_FLATTEN))
	var shape := collision.shape as CircleShape2D
	if shape:
		shape.radius = FOOTPRINT_RADIUS * pixel_scale
	sprite.sprite_frames = animation_frames if animation_frames != null else _build_sprite_frames()
	sprite.offset = _base_sprite_offset
	_apply_animation()
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_inventory = GameState.elements.duplicate()
	for element in _held_elements():
		_remember_acquired_color(str(element))
	var saved_elements := _held_elements()
	_select_element(str(saved_elements[0]) if not saved_elements.is_empty() else "")
	_seed_infinite_elements()
	_setup_light()
	_setup_range_indicator()


## 测试模式：直接把红/蓝/绿塞进颜色库（HUD 显示 infinite_amount），供自由试玩。
func _seed_infinite_elements() -> void:
	if not infinite_elements:
		return
	_inventory = {"burn": infinite_amount, "freeze": infinite_amount, "grow": infinite_amount}
	_select_element("burn")


func _on_dialogue_started(_resource: DialogueResource) -> void:
	_dialogue_active = true


func _on_dialogue_ended(_resource: DialogueResource) -> void:
	_dialogue_active = false


## 玩家自带微光：黑暗房间里照亮自身周围（遮罩挖洞；亮房里遮罩全透明，无影响）。
func _setup_light() -> void:
	var l := LightSource.new()
	l.radius = light_radius
	add_child(l)


## 工作圈可视化：以玩家为圆心、interact_range 为半径的 q 版虚线圆（跟班能飞到的范围）。
## 优先复用场景里预设的 RangeIndicator 子节点（虚线样式可在 Inspector 调）；没有则动态补一个。
func _setup_range_indicator() -> void:
	var ring := get_node_or_null("RangeIndicator") as RangeIndicator
	if ring == null:
		ring = RangeIndicator.new()
		ring.name = "RangeIndicator"
		add_child(ring)
	ring.radius = interact_range
	_range_indicator = ring


func _physics_process(delta: float) -> void:
	if opening_input_locked:
		velocity = Vector2.ZERO
		_move_vel = Vector2.ZERO
		return
	if _frozen:
		_process_frozen(delta)
		return
	_tick_slow(delta)
	if _range_indicator != null:
		_range_indicator.active = _companion_recruited()
	_handle_color_input()
	_update_highlight()
	_update_water_preview()
	_update_water_wade()
	_knockback_vel = _knockback_vel.move_toward(Vector2.ZERO, 2500.0 * delta)
	# 水流推力：脚下浅水格的流向标记（HeightMap）非 0 时被冲走；结冰那格不推。
	var flow_vel := Vector2.ZERO
	var flow_dir := HeightMap.flow_at(global_position)
	if flow_dir != 0 and not _on_frozen_ice():
		flow_vel = _flow_vector(flow_dir) * flow_strength
	# 深度排序：按脚底世界 Y 更新 z_index，让玩家被南侧的树/岩石正确遮挡。
	z_index = DepthSort.z_for(global_position.y)

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _dialogue_active:
		input = Vector2.ZERO
	var running := Input.is_action_pressed("run")

	if state == State.HIT:
		_hit_t += delta
		if _hit_t >= HIT_DURATION:
			state = State.IDLE
			_apply_animation()
		velocity = _knockback_vel + flow_vel   # 受击时保留击退/水流，但不响应输入
		move_and_slide()
		return

	if state == State.ROTATE:
		_move_vel = Vector2.ZERO
		velocity = Vector2.ZERO
		_rotate_t += delta
		if _rotate_t >= rotate_duration:
			state = State.IDLE
			sprite.offset = _base_sprite_offset
			_apply_animation()
		move_and_slide()
		return

	if state == State.JUMP:
		_jump_t += delta / jump_duration
		var jump_speed := (run_speed if running else walk_speed) * _speed_scale()
		_move_vel = _move_vel.move_toward(input * jump_speed, accel * delta)
		velocity = _move_vel
		if input != Vector2.ZERO:
			facing = _dir_from_input(input)
		if _jump_t >= 1.0:
			_jump_t = 1.0
			state = State.IDLE
		_update_hop_visual()
		_apply_animation()
		velocity += _knockback_vel
		velocity += flow_vel
		move_and_slide()
		_push_boxes(input, delta)
		return

	if Input.is_action_just_pressed("rotate"):
		_start_rotate()
		return

	if Input.is_action_just_pressed("jump"):
		_start_jump()
		return

	var speed := (run_speed if running else walk_speed) * _speed_scale()
	var target_vel := input * speed if input != Vector2.ZERO else Vector2.ZERO
	var rate := accel if input != Vector2.ZERO else decel
	_move_vel = _move_vel.move_toward(target_vel, rate * delta)
	velocity = _move_vel
	if input != Vector2.ZERO:
		facing = _dir_from_input(input)
		state = State.RUN if running else State.WALK
	elif _move_vel.length() > 20.0:
		state = State.RUN if _move_vel.length() > walk_speed * _speed_scale() * 0.75 else State.WALK
	else:
		state = State.IDLE

	sprite.offset = _base_sprite_offset
	_apply_animation()
	velocity += _knockback_vel
	velocity += flow_vel
	move_and_slide()
	_push_boxes(input, delta)


func _start_jump() -> void:
	state = State.JUMP
	_jump_t = 0.0
	_apply_animation()


func _start_rotate() -> void:
	state = State.ROTATE
	_rotate_t = 0.0
	velocity = Vector2.ZERO
	_apply_animation()


func _update_hop_visual() -> void:
	var height := sin(_jump_t * PI) * jump_height
	sprite.offset = Vector2(_base_sprite_offset.x, _base_sprite_offset.y - height)


## 被飞行物命中：沿 dir 方向给一个短促击退（velocity 逐帧衰减，见 _physics_process 顶部）。
func knockback(dir: Vector2, strength := 700.0) -> void:
	_knockback_vel = dir.normalized() * strength


## 冰冻（Boss 蓝弹命中）：冻结期间禁止移动/交互，需选中红色并左键消耗 1 颗红种子解冻；
## duration 为超时兜底（到点自动解冻）。重复命中取较长的剩余时间。
func freeze(duration := 3.0) -> void:
	if health <= 0.0:
		return
	_freeze_t = maxf(_freeze_t, duration)
	if _frozen:
		return
	_frozen = true
	state = State.IDLE
	_move_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	_knockback_vel = Vector2.ZERO
	sprite.modulate = Color(0.55, 0.75, 1.5, 1.0)
	sprite.play("idle_down")
	GameState.notice.emit("被冰冻！选中红色并左键解冻")


## 解除冰冻，恢复正常控制与配色。
func unfreeze() -> void:
	if not _frozen:
		return
	_frozen = false
	_freeze_t = 0.0
	sprite.modulate = Color.WHITE
	_apply_animation()


func is_frozen_status() -> bool:
	return _frozen


## 减速（冰晶等地表）：不禁止移动，只是移动速度乘 factor；重复触发取更慢的系数与更长的剩余时间。
func slow(factor := 0.5, duration := 1.0) -> void:
	if health <= 0.0:
		return
	factor = clampf(factor, 0.05, 1.0)
	if _slow_t > 0.0:
		_slow_factor = minf(_slow_factor, factor)
		_slow_t = maxf(_slow_t, duration)
	else:
		_slow_factor = factor
		_slow_t = duration


func is_slowed() -> bool:
	return _slow_t > 0.0


## 每帧衰减减速计时；到点恢复。
func _tick_slow(delta: float) -> void:
	if _slow_t > 0.0:
		_slow_t = maxf(0.0, _slow_t - delta)
		if _slow_t <= 0.0:
			_slow_factor = 1.0


## 当前移动速度倍率（减速中 < 1）。
func _speed_scale() -> float:
	return _slow_factor if _slow_t > 0.0 else 1.0


## 冻结期间每帧处理：倒计时 + 红色解冻输入 + 保留击退位移。
func _process_frozen(delta: float) -> void:
	_knockback_vel = _knockback_vel.move_toward(Vector2.ZERO, 2500.0 * delta)
	_freeze_t -= delta
	# 左键 + 选中红 → 消耗 1 颗红种子立刻破冰。
	if Input.is_action_just_pressed("interact") and _selected_element == "burn":
		if _consume_element("burn", 1):
			unfreeze()
			GameState.notice.emit("红色解冻！")
			return
	if _freeze_t <= 0.0:
		unfreeze()
		return
	velocity = _knockback_vel
	move_and_slide()


## 直接扣掉指定元素种子（不要求处于选中态）；不足返回 false。
func _consume_element(element: String, amount: int = 1) -> bool:
	if element == "" or amount <= 0:
		return false
	if infinite_elements:
		return true
	var have := int(_inventory.get(element, 0))
	if have < amount:
		return false
	_inventory[element] = have - amount
	if int(_inventory[element]) <= 0:
		_inventory.erase(element)
	_notify_inventory()
	return true


## 受击：进入 HIT 状态并播一次受击动画（只播一次，HIT 分支里不再每帧重播）。
## 受击素材只有左右两套：朝左用左侧受击，其余（右/下/上）先用右边受击兜底。
func _start_hit() -> void:
	state = State.HIT
	_hit_t = 0.0
	_move_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	sprite.play("hit_left" if facing == 1 else "hit_right")


## 流向编号 → 方向向量（屏幕坐标）。1=右 2=下 3=左 4=上，其它=无。
func _flow_vector(dir: int) -> Vector2:
	match dir:
		1:
			return Vector2.RIGHT
		2:
			return Vector2.DOWN
		3:
			return Vector2.LEFT
		4:
			return Vector2.UP
		_:
			return Vector2.ZERO


## 脚下那格是不是已结冰的浅水（WaterCell.is_frozen()）。结冰后水流不推人。
func _on_frozen_ice() -> bool:
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("is_frozen") or not obj.has_method("contains_point"):
			continue
		if not bool(obj.call("is_frozen")):
			continue
		if bool(obj.call("contains_point", global_position)):
			return true
	return false


## 受伤：扣血并广播 health_changed。受击后有短暂无敌，防止机关连发瞬间秒杀。
func take_damage(amount: float = 1.0) -> void:
	if amount <= 0:
		return
	if Time.get_ticks_msec() < _invincible_until:
		return
	_invincible_until = Time.get_ticks_msec() + INVINCIBLE_MS
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_start_hit()
	_hit_feedback.play(sprite, hit_shake_pixels, hit_gamepad_vibration)
	if health <= 0.0:
		_die()


## 死亡：广播 died，然后回出生点重生（满血 + 短暂无敌）。
func _die() -> void:
	died.emit()
	GameState.notice.emit("你死了")
	_respawn()


## 重生：回到当前房间出生点，恢复满血并给略长一点的无敌时间。
func _respawn() -> void:
	var companion := _companion()
	if is_instance_valid(companion): companion.cancel_orders()
	unfreeze()
	_slow_t = 0.0
	_slow_factor = 1.0
	health = float(max_health)
	_move_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	_knockback_vel = Vector2.ZERO
	global_position = _spawn_position()
	reclaim_placed_colors()
	state = State.IDLE
	_apply_animation()
	if is_instance_valid(companion) and GameState.companion_recruited:
		companion.restore_following()
	_invincible_until = Time.get_ticks_msec() + INVINCIBLE_MS * 2
	health_changed.emit(health, max_health)


## 出生点：当前房间的 "spawn" 入口位置（约定每个房间都有 entrance_id=spawn）。
func _spawn_position() -> Vector2:
	# 有存档点且存档点就在当前场景 → 优先复活到存档点。
	if GameState.has_checkpoint() and GameState.checkpoint_scene == SceneManager.current_room_scene:
		if is_safe_respawn_position(GameState.checkpoint_pos):
			return GameState.checkpoint_pos
	var room := GameState.current_room as Room
	if room == null:
		return global_position  # 兜底：不知道出生点就原地满血复活
	return room.get_entrance_position("spawn")


## 存档位置必须是稳定地面，不能依赖即将收回的冰面或藤桥。
func is_safe_respawn_position(pos: Vector2) -> bool:
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj): continue
		if obj is WaterCell and (obj.contains_point(pos) or obj.contains_point(pos + collision.position)): return false
	var shape := get_node_or_null("Collision") as CollisionShape2D
	if shape == null or shape.shape == null: return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.transform.origin += pos - global_position
	query.collision_mask = 6
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func register_placed_color(target: Node) -> void:
	if infinite_elements or not is_instance_valid(target): return
	if not target.has_method("absorb_color") or not target.has_method("has_color") or not target.has_color(): return
	var id := target.get_instance_id()
	var count := int(_placed_colors.get(id, {}).get("count", 0))
	_placed_colors[id] = {"target": weakref(target), "count": count + 1}


## 普通吸收同步扣除登记；混色一次吸收会清空目标，并自行返还两色。
func settle_placed_absorption(target: Node, info: Dictionary) -> void:
	var id := target.get_instance_id()
	if not _placed_colors.has(id): return
	if not target.has_color():
		_placed_colors.erase(id)
	elif str(info.get("element", "")) != "":
		_placed_colors[id].count -= 1
		if _placed_colors[id].count <= 0: _placed_colors.erase(id)


func reclaim_placed_colors() -> void:
	var companion := _companion()
	if is_instance_valid(companion): companion.cancel_orders()
	var entries := _placed_colors.values()
	_placed_colors.clear() # 先清账，防止回调或重复返回造成重复领取。
	for entry in entries:
		var target: Node = entry.target.get_ref()
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		for i in int(entry.count):
			if not target.has_color(): break
			var info: Dictionary
			if target.has_method("reclaim_placed_color"):
				info = target.reclaim_placed_color()
			else:
				info = target.absorb_color()
			var element := str(info.get("element", ""))
			if element == "": break
			receive_element(element, int(info.get("amount", 1)))


func return_to_checkpoint() -> bool:
	if opening_input_locked or StoryDirector.is_busy() or SceneManager.is_busy(): return false
	_respawn()
	if GameState.has_checkpoint() and GameState.checkpoint_scene != SceneManager.current_room_scene:
		SceneManager.resume_from_checkpoint()
	GameState.notice.emit("已返回存档点，放置的颜色已收回" if GameState.has_checkpoint() else "已返回出生点，放置的颜色已收回")
	return true


## 供 HUD 在连接信号前读取当前血量快照。
func health_snapshot() -> Dictionary:
	return {"health": health, "max_health": max_health}


## 永久容器：本次游戏跨关/死亡保留，每件唯一道具只增加一次。
func acquire_heart_container(item_id: String, amount: int = 1) -> bool:
	if item_id == "" or amount <= 0 or GameState.has_prop(item_id) or GameState.health_upgrades.has(item_id):
		return false
	GameState.health_upgrades[item_id] = amount
	max_health += amount
	health = minf(health + float(amount), float(max_health))
	GameState.add_prop(item_id)
	GameState.item_collected.emit(item_id)
	health_changed.emit(health, max_health)
	return true


## 站在水里（不可站水格）时，临时忽略水层碰撞，让玩家能在水里走动（踩水）；
## 爬回岸/冰（可站）后恢复碰撞。这样「掉进水里」后能挪动，而不是被困在一格里。
func _update_water_wade() -> void:
	# 用碰撞盒中心采样，而不是玩家节点原点。玩家碰撞盒相对原点有偏移，
	# 否则从不同方向进入水格时，进水/出水判定会不一致，导致卡死。
	var sample_pos := global_position + collision.position
	var in_water := not HeightMap.is_walkable(sample_pos)
	if in_water == _in_water:
		return
	_in_water = in_water
	collision_mask = (_base_collision_mask & ~WATER_COLLISION_LAYER) if in_water else _base_collision_mask


## 推动接触到的可推箱（PushableBody）。
## 仅当玩家朝箱子方向推（被箱子挡住）时，才沿玩家前进方向推动箱子；
## 只是贴着箱子滑过去（速度与表面平行）不会推动它。
func _push_boxes(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	dir = dir.normalized()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body is PhysicsBody2D and body.has_method("push"):
			var into := -col.get_normal()   # 指向箱子内部（被挡住的推入方向）
			if dir.dot(into) > 0.3:
				body.push(dir, delta)


func _apply_animation() -> void:
	sprite.flip_h = false  # 左右各有独立素材，不再镜像
	if state == State.HIT:
		sprite.play("hit_left" if facing == 1 else "hit_right")
		return
	# 目前只有 4 方向的 walk 与朝下的 idle 动画；run/jump/rotate 暂复用，后续补。
	if state == State.IDLE or state == State.ROTATE:
		sprite.play("idle_down")
	else:
		sprite.play("walk_%s" % DIR_NAMES[facing])


func _dir_from_input(v: Vector2) -> int:
	var n := v.normalized()
	var best := 0
	var best_dot := -2.0
	for i in range(DIRS.size()):
		var d := n.dot(DIRS[i])
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _handle_color_input() -> void:
	if Time.get_ticks_msec() < _action_input_guard_until: return
	if Input.is_action_just_pressed("absorb"):
		_absorb()
	if Input.is_action_just_pressed("interact"):
		_interact()
	if Input.is_action_just_pressed("cycle_color_up"):
		_cycle_selection(1)
	if Input.is_action_just_pressed("cycle_color_down"):
		_cycle_selection(-1)


## 暂停菜单鼠标点击返回时，避免同一次点击透传为场景上色。
func suppress_action_input() -> void:
	_action_input_guard_until = Time.get_ticks_msec() + 120


## 当前选中元素的颜色（未选中时为白）。
func _color_of(element_id: String) -> Color:
	return Rules.config(element_id).get("color", Color.WHITE)


## 当前选中元素的颜色名（未选中时为「无」）。
func _color_name_of(element_id: String) -> String:
	return str(Rules.config(element_id).get("color_name", ""))


## 更新选中元素：同步描边颜色 + 发射 UI 信号。
func _select_element(element_id: String) -> void:
	if is_node_ready() and element_id != "" and element_id != _selected_element:
		AudioManager.play_ui_select()
	_selected_element = element_id
	selected_color = _color_of(element_id)
	selected_color_name = _color_name_of(element_id) if element_id != "" else "无"
	# 描边改用彩虹 shader，颜色不再随选中元素变化，无需设置 outline_color。
	color_changed.emit(selected_color, selected_color_name)
	inventory_changed.emit(_inventory, _selected_element)
	GameState.set_elements(_inventory.duplicate())


## 仅数量变化（选中不变）时刷新 UI。
func _notify_inventory() -> void:
	inventory_changed.emit(_inventory, _selected_element)
	GameState.set_elements(_inventory.duplicate())


## 供 HUD 在连接前读取颜色库快照。
func palette_snapshot() -> Dictionary:
	return {"inventory": _inventory.duplicate(), "selected": _selected_element}


## 颜色库里按固定顺序（burn→freeze→grow）列出持有中的元素，用于滚轮循环。
func _held_elements() -> Array:
	var order := ["burn", "freeze", "grow"]
	var out: Array = []
	for el in order:
		if int(_inventory.get(el, 0)) > 0:
			out.append(el)
	for el in _inventory:
		if int(_inventory[el]) > 0 and not out.has(el):
			out.append(el)
	return out


## 滚轮在颜色库中循环切换选中元素。dir = +1 下一个 / -1 上一个。
func _cycle_selection(dir: int) -> void:
	var held := _held_elements()
	if held.is_empty():
		return
	var idx := held.find(_selected_element)
	if idx == -1:
		idx = 0
	else:
		idx = posmod(idx + dir, held.size())
	_select_element(held[idx])


## 吸收：让跟班飞过去从鼠标指向的带色物体抽走元素，带回后入库（种子守恒）。
## 跟班跟随之后才有交互：未招募直接不做。
func _absorb() -> void:
	if not _companion_recruited():
		return
	var target := _colored_at_mouse()
	if target == null:
		return
	var companion := _companion()
	companion.call("absorb", target)


## 左键：优先让跟班飞过去开宝箱；鼠标下没有宝箱时，回落到赋予（上色）。跟班跟随之后才有交互。
func _interact() -> void:
	if not _companion_recruited():
		return
	var target := _altar_at_mouse()
	if target == null:
		target = _chest_at_mouse()
	if target != null:
		_companion().call("interact", target)
		return
	_grant()


## 组 "companion" 里的跟班（本项目只有一个）。
func _companion() -> Node:
	var nodes := get_tree().get_nodes_in_group("companion")
	if nodes.is_empty():
		return null
	return nodes[0]


## 跟班是否已招募（跟随之后玩家才有上色/吸收/高亮等交互能力）。
func _companion_recruited() -> bool:
	var companion := _companion()
	return companion != null and bool(companion.call("is_recruited"))


## 跟班吸收带回的种子入库（吸收成功后由跟班回调）。
## 首次获得某种颜色时自动选中它：既让色轮在第一次得色时直接亮出，
## 也在之后新拿到一种没持有过的颜色时把色轮切到该色。
func receive_element(element: String, amount: int) -> void:
	if amount <= 0 or element == "":
		return
	var had_before := int(_inventory.get(element, 0)) > 0
	_inventory[element] = int(_inventory.get(element, 0)) + amount
	_remember_acquired_color(element)
	if not had_before:
		_select_element(element)
	else:
		_notify_inventory()


## 上色失败或目标返还元素时，退回预留的种子。
func refund_element(element: String, amount: int) -> void:
	if amount <= 0 or element == "":
		return
	_inventory[element] = int(_inventory.get(element, 0)) + amount
	_remember_acquired_color(element)
	_notify_inventory()


## 记录曾获得的颜色：第一种全部用出去后，拿到第二种仍要提示。
func _remember_acquired_color(element: String) -> void:
	if infinite_elements or element not in ["burn", "freeze", "grow"]: return
	GameState.hints["tutorial_color_seen_" + element] = true
	if not GameState.hints.has(COLOR_QUANTITY_HINT) and _color_quantity_hint_delay < 0.0:
		_color_quantity_hint_delay = 0.5
	if GameState.hints.has(COLOR_WHEEL_HINT): return
	var count := 0
	for color in ["burn", "freeze", "grow"]:
		if GameState.hints.has("tutorial_color_seen_" + color): count += 1
	if count >= 2 and _color_wheel_hint_delay < 0.0:
		_color_wheel_hint_delay = 0.5


func _process(delta: float) -> void:
	if _color_tutorial_wait > 0.0:
		_color_tutorial_wait -= delta
		return
	if _color_quantity_hint_delay >= 0.0:
		if StoryDirector.is_busy() or SceneManager.is_busy() or opening_input_locked:
			_color_quantity_hint_delay = 0.5
			return
		_color_quantity_hint_delay -= delta
		if _color_quantity_hint_delay <= 0.0:
			_color_quantity_hint_delay = -1.0
			GameState.hints[COLOR_QUANTITY_HINT] = true
			GameState.tutorial_notice.emit("颜色种子数量有限，赋予一次消耗一颗。\n右键吸收可以收回；返回存档点会回收已放置的颜色。", 6.0)
			_color_tutorial_wait = 6.7
		return
	if _color_wheel_hint_delay < 0.0: return
	# 让拾取反馈和相关对白先结束，避免滚轮教学被盖住或立刻覆盖。
	if StoryDirector.is_busy() or SceneManager.is_busy() or opening_input_locked:
		_color_wheel_hint_delay = 0.5
		return
	_color_wheel_hint_delay -= delta
	if _color_wheel_hint_delay <= 0.0:
		_color_wheel_hint_delay = -1.0
		if GameState.hints.has(COLOR_WHEEL_HINT): return
		GameState.hints[COLOR_WHEEL_HINT] = true
		GameState.notice.emit("已获得两种颜色！滚动鼠标滚轮，可以切换当前颜色。")


## 敌人（焰虱）碰到玩家时抢走库存种子——种子守恒的反向操作。抢到返回 true，抢不到返回 false。
func steal_element(element: String, amount: int = 1) -> bool:
	if amount <= 0 or element == "":
		return false
	var have := int(_inventory.get(element, 0))
	if have <= 0:
		return false
	_inventory[element] = have - amount
	if int(_inventory[element]) <= 0:
		_inventory.erase(element)
	_notify_inventory()
	return true


## 赋予：让跟班飞过去把当前选中的元素种到鼠标指向的可上色物体（种子守恒）。
## 跟班跟随之后才有交互：先预留种子，到场执行；取消/失败退回。
func _grant() -> void:
	if _selected_element == "" or not _companion_recruited():
		return
	if not infinite_elements and int(_inventory.get(_selected_element, 0)) <= 0:
		return
	var target := _grantable_at_mouse()
	if target == null:
		return
	var element := _selected_element
	var cfg := Rules.config(element)
	var companion := _companion()
	# 先预留种子；队列替换、目标失效或上色失败由跟班退回，拒绝接单则立即退回。
	_consume_selected()
	if not bool(companion.call("paint", target, cfg.get("color", Color.WHITE), cfg.get("color_name", ""), element)):
		refund_element(element, 1)


## 红/蓝上色成功后，以落点为中心清除对应残留：
## 红 → 藤蔓 + 冰晶；蓝 → 火焰痕迹。
func purge_element_hazards(element_id: String, center: Vector2) -> void:
	if element_id == "burn":
		_purge_nodes("boss_vine", "_despawn", center)
		_purge_nodes("ice_crystal", "extinguish", center)
	elif element_id == "freeze":
		_purge_nodes("burn_trail", "extinguish", center)


func _purge_nodes(group: String, method: String, center: Vector2) -> void:
	for n in get_tree().get_nodes_in_group(group):
		if not GameState.is_in_current_scene(n):
			continue
		var n2d := n as Node2D
		if n2d == null or n2d.is_queued_for_deletion():
			continue
		if n2d.global_position.distance_to(center) > element_purge_radius:
			continue
		if n.has_method(method):
			n.call(method)


## 扣掉当前选中元素的一颗种子；扣光后保留选中色，由玩家手动切换。
func _consume_selected() -> void:
	if _selected_element == "":
		return
	if infinite_elements:
		_notify_inventory()
		return
	if int(_inventory.get(_selected_element, 0)) <= 0:
		return
	_inventory[_selected_element] = int(_inventory[_selected_element]) - 1
	if int(_inventory[_selected_element]) <= 0:
		_inventory.erase(_selected_element)
	_notify_inventory()


## 鼠标当前指向、尚未激活的圣坛（工作圈内，重叠时取 z_index 最高/最上层）。
func _altar_at_mouse() -> Node:
	var mp := get_global_mouse_position()
	if global_position.distance_to(mp) > interact_range:
		return null
	var best: Node = null
	var best_z := -INF
	for obj in get_tree().get_nodes_in_group("altar"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("contains_point"):
			continue
		if bool(obj.get("is_open")):
			continue
		if not bool(obj.call("contains_point", mp)):
			continue
		var z := float(obj.get("z_index"))
		if z >= best_z:
			best_z = z
			best = obj
	return best


## 鼠标当前指向、且未开启的宝箱（工作圈内，重叠时取 z_index 最高/最上层）。
func _chest_at_mouse() -> Node:
	var mp := get_global_mouse_position()
	if global_position.distance_to(mp) > interact_range:
		return null   # 工作圈之外：鼠标指示无效
	var best: Node = null
	var best_z := -INF
	for obj in get_tree().get_nodes_in_group("chest"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("contains_point"):
			continue
		if bool(obj.get("is_open")):
			continue
		if not bool(obj.call("contains_point", mp)):
			continue
		var z := float(obj.get("z_index"))
		if z >= best_z:
			best_z = z
			best = obj
	return best


## 鼠标当前指向的可上色目标：解密用的 "colorable" + Boss 专用 "boss_paint_target"
## （重叠时取 z_index 最高/最上层）。
func _colorable_at_mouse() -> Node:
	var mp := get_global_mouse_position()
	if global_position.distance_to(mp) > interact_range:
		return null   # 工作圈之外：鼠标指示无效
	var best: Node = null
	var best_z := -INF
	for group in ["colorable", "boss_paint_target"]:
		for obj in get_tree().get_nodes_in_group(group):
			if not GameState.is_in_current_scene(obj):
				continue
			if not obj.has_method("contains_point"):
				continue
			if not bool(obj.call("contains_point", mp)):
				continue
			var z := float(obj.get("z_index"))
			if z >= best_z:
				best_z = z
				best = obj
	return best


## 鼠标下、且当前带颜色（可被吸收）的物体。
func _colored_at_mouse() -> Node:
	var t := _colorable_at_mouse()
	if t != null and t.has_method("absorb_color") and t.has_method("has_color") and bool(t.call("has_color")):
		return t
	return null


## 鼠标下、且能上色（可被赋予）的物体。
func _grantable_at_mouse() -> Node:
	var t := _colorable_at_mouse()
	if t != null and (t.has_method("apply_color") or t.has_method("apply_boss_color")):
		return t
	return null


## 给鼠标指向的可交互物体加描边提示，目标变化时自动切换。
## 优先级：带色（可吸收/溶解）> 可赋予（可上色）。这样手里攥着颜色时，
## 鼠标下的冰/带色物仍提示「可吸收」，而不是误导成「可赋予」。
## 跟班跟随之后才有交互：未招募时不做任何悬停高亮。
func _update_highlight() -> void:
	if not _companion_recruited():
		_clear_highlight()
		return
	var target := _colored_at_mouse()
	if target == null and _selected_element != "":
		target = _grantable_at_mouse()
	if target == null:
		target = _altar_at_mouse()
	if target == _highlighted:
		return
	_clear_highlight()
	if target != null:
		_highlighted = target
		AudioManager.play_ui_hover()
		_add_outline(target)


func _add_outline(target: Node) -> void:
	var sprite := _outline_sprite(target)
	if sprite == null:
		return
	_highlight_outline = Sprite2D.new()
	_highlight_outline.texture = sprite.texture
	_highlight_outline.centered = sprite.centered
	_highlight_outline.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_highlight_outline.material = _outline_material
	sprite.add_child(_highlight_outline)


## 取画描边要挂的 Sprite2D：目标本身是 Sprite2D（石头）直接用；
## 否则取它的 Visual 子节点（冰块是 StaticBody2D，贴图在 Visual 上）。
func _outline_sprite(target: Node) -> Sprite2D:
	if target is Sprite2D:
		return target
	return target.get_node_or_null("Visual") as Sprite2D


func _clear_highlight() -> void:
	if is_instance_valid(_highlight_outline):
		_highlight_outline.queue_free()
	_highlight_outline = null
	_highlighted = null


## 鼠标下、未结冰的水格（用于冻结预览）。只找水，不管是否带色/可赋予。
func _water_at_mouse() -> Node:
	var mp := get_global_mouse_position()
	if global_position.distance_to(mp) > interact_range:
		return null   # 工作圈之外：冻结预览同样无效
	var best: Node = null
	var best_z := -INF
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("is_frozen") or not obj.has_method("contains_point"):
			continue
		if bool(obj.call("is_frozen")):
			continue
		if not bool(obj.call("contains_point", mp)):
			continue
		var z := float(obj.get("z_index"))
		if z >= best_z:
			best_z = z
			best = obj
	return best


## 悬停水面反馈：手里是蓝时叠一个半透明冰块预览（提示「可结冰」）。
## 跟班跟随之后才有交互：未招募时不预览。
func _update_water_preview() -> void:
	if not _companion_recruited():
		if is_instance_valid(_freeze_preview_water) and _freeze_preview_water.has_method("set_freeze_preview"):
			_freeze_preview_water.set_freeze_preview(false)
		_freeze_preview_water = null
		_freeze_preview_on = false
		return
	var w := _water_at_mouse()
	var preview_on := w != null and _selected_element == "freeze"
	if w != _freeze_preview_water or preview_on != _freeze_preview_on:
		if is_instance_valid(_freeze_preview_water) and _freeze_preview_water.has_method("set_freeze_preview"):
			_freeze_preview_water.set_freeze_preview(false)
		_freeze_preview_water = w if preview_on else null
		_freeze_preview_on = preview_on
		if preview_on:
			w.set_freeze_preview(true)


func _build_sprite_frames() -> SpriteFrames:
	# 兜底：场景里已外挂 player_sprite_frames.tres，这里直接复用同一份资源。
	return preload("res://resources/player_sprite_frames.tres")


func _register_input_actions() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("run", [KEY_SHIFT])
	_add_action("jump", [KEY_SPACE])
	_add_action("rotate", [KEY_R])
	# 吸收/赋予改用鼠标：右键吸收、左键赋予。
	_add_mouse_action("absorb", MOUSE_BUTTON_RIGHT)
	_add_mouse_action("interact", MOUSE_BUTTON_LEFT)
	# 预留：以后有多种颜色时用滚轮切换选择。
	_add_mouse_action("cycle_color_up", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_action("cycle_color_down", MOUSE_BUTTON_WHEEL_DOWN)


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


## 给动作绑定一个鼠标按键（左键/右键/滚轮等）。pressed 必须显式置 true，
## 否则 is_action_just_pressed 会在「松开」时才触发。
func _add_mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	InputMap.action_add_event(action, ev)
