class_name Companion
extends Node2D
## 小跟班：首触对话结束后开始跟随玩家，并成为「上色/吸收」的执行者。
## 玩家鼠标指示→到场上色/吸收→直接去下一目标；无指令时稍候再返回。
## 用 tween 做呼吸挤压、待机浮动、飞行弧线 + squash&stretch 落地弹跳，生动可爱。
## 结构：Node2D（本脚本）+ InteractArea（首触检测）+ Visual（占位色块，可换 Sprite2D）。

enum State { IDLE, FOLLOWING, TASK }

@export_group("Dialogue")
@export var dialogue_resource: DialogueResource
## 首触对话的起始 cue（留空 = 文件开头）。
@export var start_cue: String = ""
## 卡住超时提醒用的 cue 标题（~ hint_idle）。
@export var idle_reminder_cue: String = "hint_idle"

@export_group("Follow")
## 相对玩家的固定偏移（屏幕坐标，y 向下）。右下后方的跟班位置。
@export var follow_offset: Vector2 = Vector2(-96, 64)
## 指数平滑系数，越大贴得越紧。
@export var follow_speed: float = 8.0
## 小于此距离视为已到位。
@export var stop_distance: float = 8.0

@export_group("Cute")
## 移动时小跳的高度（像素）。
@export var hop_height: float = 12.0
## 移动时小跳的频率。
@export var hop_frequency: float = 7.0
## 待机上下浮动幅度。
@export var bob_amplitude: float = 4.0
## 待机浮动速度。
@export var bob_speed: float = 3.0
## 呼吸挤压幅度（scale.y 在 1±breathe_amount 间循环）。
@export var breathe_amount: float = 0.06

@export_group("Flight")
## 飞行弧线的抬升高度（像素）。
@export var flight_arc: float = 96.0
## 单程飞行时长（秒）。
@export var flight_duration: float = 0.5
## 完成动作后在目标旁等待下一条指令的时间。
@export_range(0.1, 1.5, 0.05) var return_delay := 0.6

@export_group("Reminders")
## 暂时关闭卡住超时提醒；区域标记提示不受影响。
@export var idle_reminders_enabled := false
## 玩家卡住多久后提醒（秒）。
@export var idle_reminder_delay: float = 12.0
## 这个时间窗口内净位移小于此值就算「卡住」。0 = 动一点点都算没卡住。
@export var idle_move_threshold: float = 0.0
## 两次提醒之间的最小间隔（秒）。
@export var idle_reminder_cooldown: float = 30.0

var state: int = State.IDLE
var player: Node2D

var _talking := false
var _visual: Node2D
var _area: Area2D
var _hop_phase := 0.0
var _idle_t := 0.0
var _idle_accum := 0.0
var _idle_ref_pos := Vector2.ZERO
var _last_reminder_ms := 0
var _facing := 1.0
var _breath_tween: Tween
var _fly_tween: Tween
var _task: Dictionary = {}    # 当前任务：{type, target, color, color_name, element}
var _pending: Dictionary = {}
var _phase := ""
var _visual_base_scale := Vector2.ONE


func _ready() -> void:
	# 切关后小跟班已常驻；旧关重新实例化时会出现第二个，这里让后加载的自毁，避免重复。
	for c in get_tree().get_nodes_in_group("companion"):
		if is_instance_valid(c) and c != self:
			queue_free()
			return
	add_to_group("companion")
	player = get_tree().get_first_node_in_group("player") as Node2D
	_area = $InteractArea as Area2D
	_visual = $Visual as Node2D
	# 旧跟随动画以 x=1 为基准；保留这个实际游玩尺寸及贴图纵横比例。
	_visual_base_scale = _visual.scale / maxf(absf(_visual.scale.x), 0.001)
	_visual.scale = _visual_base_scale
	_area.body_entered.connect(_on_body_entered)
	SceneManager.room_exited.connect(_on_room_exited)
	if player != null:
		player.died.connect(cancel_orders)
	if player != null:
		_idle_ref_pos = player.global_position
	_start_breathing()
	if GameState.companion_recruited:
		restore_following(false)


## 读档只恢复可跟随状态，不重复首遇对话或恢复半途飞行任务。
func restore_following(snap_to_player := true) -> void:
	state = State.FOLLOWING
	_talking = false
	_area.set_deferred("monitoring", false)
	_idle_accum = 0.0
	if is_instance_valid(player):
		_idle_ref_pos = player.global_position
		if snap_to_player:
			global_position = player.global_position + follow_offset
			var trail := get_node_or_null("Line2D") as Line2D
			if trail != null:
				trail.clear_points()
				trail.set("points_array", PackedVector2Array())
				trail.set("last_target_pos", global_position)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _visual == null or not is_instance_valid(_visual):
		return
	if state == State.TASK:
		return   # 飞行/执行动画由 tween 控制
	if state == State.FOLLOWING and not _talking:
		_follow(delta)
		_check_reminders(delta)
	else:
		_idle_bob(delta)


## —— 跟随 / 待机动效 ——

func _follow(delta: float) -> void:
	var target := player.global_position + follow_offset
	var to := target - global_position
	if to.length() <= stop_distance:
		_idle_bob(delta)
		return
	var speed := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(target, speed)
	if absf(to.x) > 1.0:
		_facing = 1.0 if to.x > 0.0 else -1.0
	_visual.scale.x = _facing * _visual_base_scale.x
	_hop_phase += delta * hop_frequency
	_visual.position.y = -absf(sin(_hop_phase)) * hop_height


func _idle_bob(delta: float) -> void:
	_visual.scale.x = _facing * _visual_base_scale.x
	_idle_t += delta
	_visual.position.y = sin(_idle_t * bob_speed) * bob_amplitude


func _start_breathing() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	_stop_breathing()
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_property(_visual, "scale:y", _visual_base_scale.y * (1.0 + breathe_amount), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(_visual, "scale:y", _visual_base_scale.y * (1.0 - breathe_amount), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_breathing() -> void:
	if _breath_tween and _breath_tween.is_valid():
		_breath_tween.kill()


## —— 任务入口（玩家调用）——

## 是否已招募（首触对话结束、开始跟随之后）。
func is_recruited() -> bool:
	return state != State.IDLE


## 跟班当前是否空闲、能接任务（已招募 + 不在任务中 + 不在对话）。
func is_available() -> bool:
	return state == State.FOLLOWING and not _talking


## 上色种子由 Player 预留；接受后在到场时消耗，取消/失败则退款。
func paint(target: Node, color: Color, color_name: String, element: String) -> bool:
	return _submit({"type": "paint", "color": color, "color_name": color_name, "element": element}, target)


func absorb(target: Node) -> bool:
	return _submit({"type": "absorb"}, target)


func interact(target: Node) -> bool:
	return _submit({"type": "interact"}, target)


func _submit(job: Dictionary, target: Node) -> bool:
	if not is_recruited() or _talking or StoryDirector.is_busy() or not _valid_target(target, str(job.type)):
		return false
	# 重复点击同一指令不叠加扣种；仅允许一个可替换的下一步。
	for existing in [_task, _pending]:
		if not existing.is_empty() and existing.type == job.type and existing.target.get_ref() == target and existing.get("element", "") == job.get("element", ""):
			return false
	job.target = weakref(target)
	job.settled = false
	if job.type == "paint" and target.has_method("lock_for_paint"):
		target.call("lock_for_paint", str(job.get("color_name", "")), float(flight_duration) + 1.0)
	var marker := preload("res://scripts/companion_order_marker.gd").new()
	marker.target = job.target
	marker.tint = job.get("color", Color("687b8c"))
	job.marker = marker
	add_child(marker)
	if state == State.FOLLOWING or _phase in ["linger", "return"]:
		_kill_fly()
		_start_job(job)
	else:
		_cancel_job(_pending)
		_pending = job
		marker.queued = true
	return true


func _valid_target(target: Node, kind: String) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(target) or not target is Node2D or not target.is_inside_tree() or target.is_queued_for_deletion():
		return false
	if player.global_position.distance_to(target.global_position) > float(player.get("interact_range")):
		return false
	# 不允许离开旧关卡后继续对旧物体操作。
	if is_instance_valid(GameState.current_room) and not GameState.is_in_current_scene(target):
		return false
	match kind:
		"paint": return target.has_method("apply_color") or target.has_method("apply_boss_color")
		"absorb": return target.has_method("absorb_color") and (not target.has_method("has_color") or target.has_color())
		"interact": return target.has_method("interact") and not bool(target.get("is_open"))
	return false


func _start_job(job: Dictionary) -> void:
	_task = job
	state = State.TASK
	_phase = "fly"
	_stop_breathing()
	var target: Node = job.target.get_ref()
	if not _valid_target(target, str(job.type)) or not is_instance_valid(_visual):
		_cancel_job(_task)
		_task = {}
		_after_job()
		return
	if is_instance_valid(job.marker):
		job.marker.queued = false
	_visual.position = Vector2.ZERO
	_task.from_pos = global_position
	_fly_to(target.global_position, _arrive)


func _fly_to(end: Vector2, on_arrive: Callable) -> void:
	_kill_fly()
	var start := global_position
	_facing = 1.0 if end.x >= start.x else -1.0
	_visual.scale = _visual_base_scale * Vector2(_facing, 1)
	var mid := (start + end) * 0.5 - Vector2(0, minf(flight_arc, start.distance_to(end) * 0.2))
	var duration := clampf(start.distance_to(end) / 2200.0, 0.3, 0.6)
	if _phase == "return":
		duration = flight_duration
	var animation := create_tween()
	animation.tween_method(_set_arc_pos.bind(start, mid, end), 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	animation.tween_callback(on_arrive)
	_fly_tween = animation


func _set_arc_pos(t: float, start: Vector2, mid: Vector2, end: Vector2) -> void:
	# 移动目标的落点持续跟随，避免对着它之前的位置做动作。
	if _phase == "fly" and not _task.is_empty():
		var target: Node = _task.target.get_ref()
		if is_instance_valid(target):
			end = target.global_position
	elif _phase == "return" and is_instance_valid(player):
		end = player.global_position + follow_offset
	global_position = start.lerp(mid, t).lerp(mid.lerp(end, t), t)


func _arrive() -> void:
	_phase = "work"
	var target: Node = _task.target.get_ref()
	if not _valid_target(target, str(_task.type)):
		_cancel_job(_task)
		_task = {}
		_after_job()
		return
	global_position = target.global_position
	var animation := create_tween()
	# 上色轻触，吸收稍作收拢；不再每次做大幅压扁与弹跳。
	var duration := 0.22 if _task.type == "absorb" else 0.16
	animation.tween_property(_visual, "scale", _visual_base_scale * Vector2(_facing * 1.1, 0.86), duration * 0.4).set_trans(Tween.TRANS_SINE)
	animation.tween_property(_visual, "scale", _visual_base_scale * Vector2(_facing, 1), duration * 0.6).set_trans(Tween.TRANS_SINE)
	animation.tween_callback(_execute_task)
	_fly_tween = animation


func _execute_task() -> void:
	var target: Node = _task.target.get_ref()
	if _talking or StoryDirector.is_busy() or not _valid_target(target, str(_task.type)):
		_cancel_job(_task)
	else:
		# 标记结算后再调用目标：回调可能消耗/销毁物体或触发其他信号。
		_task.settled = true
		match str(_task.type):
			"paint":
				var applied := false
				if target.has_method("apply_boss_color"):
					applied = bool(target.call("apply_boss_color", _task.color, _task.color_name, _task.from_pos))
				elif target.has_method("apply_color"):
					applied = bool(target.call("apply_color", _task.color, _task.color_name, _task.from_pos))
				if not applied:
					_task.settled = false
					_cancel_job(_task)
				else:
					if target.has_method("release_paint_lock"):
						target.call("release_paint_lock")
					if is_instance_valid(player) and player.has_method("purge_element_hazards"):
						player.call("purge_element_hazards", str(_task.element), global_position)
			"absorb":
				var info: Dictionary = target.absorb_color()
				var element := str(info.get("element", ""))
				if element != "":
					player.receive_element(element, int(info.get("amount", 1)))
			"interact": target.interact()
	_clear_marker(_task)
	_task = {}
	_after_job()


func _after_job() -> void:
	if not _pending.is_empty():
		var next := _pending
		_pending = {}
		_start_job(next)
		return
	_phase = "linger"
	var animation := create_tween()
	animation.tween_interval(return_delay)
	animation.tween_callback(_fly_back)
	_fly_tween = animation


func _fly_back() -> void:
	if not is_instance_valid(player):
		_finish_task()
		return
	_phase = "return"
	_fly_to(player.global_position + follow_offset, _finish_task)


func _finish_task() -> void:
	_phase = ""
	_task = {}
	state = State.FOLLOWING
	if is_instance_valid(player):
		_idle_ref_pos = player.global_position
	_start_breathing()


func _clear_marker(job: Dictionary) -> void:
	if is_instance_valid(job.get("marker")):
		job.marker.queue_free()


func _cancel_job(job: Dictionary) -> void:
	if job.is_empty():
		return
	if job.type == "paint":
		var target: Node = job.target.get_ref()
		if is_instance_valid(target) and target.has_method("release_paint_lock"):
			target.call("release_paint_lock")
		if not job.settled and is_instance_valid(player):
			job.settled = true
			player.refund_element(str(job.element), 1)
	_clear_marker(job)


func reserved_elements() -> Dictionary:
	var result := {}
	for job in [_task, _pending]:
		if not job.is_empty() and job.type == "paint" and not job.settled:
			result[job.element] = int(result.get(job.element, 0)) + 1
	return result


func cancel_orders() -> void:
	_kill_fly()
	_cancel_job(_task)
	_cancel_job(_pending)
	_task = {}
	_pending = {}
	_phase = ""
	if state != State.IDLE:
		state = State.FOLLOWING
	if is_instance_valid(_visual):
		_visual.scale = _visual_base_scale * Vector2(_facing, 1)
	_start_breathing()


func _on_room_exited(_room_id: String) -> void:
	cancel_orders()


func _exit_tree() -> void:
	_kill_fly()
	_cancel_job(_task)
	_cancel_job(_pending)


func _kill_fly() -> void:
	if _fly_tween and _fly_tween.is_valid():
		_fly_tween.kill()



## —— 对话触发 / 提醒 ——

func _on_body_entered(body: Node) -> void:
	if state != State.IDLE or _talking:
		return
	if not body.is_in_group("player"):
		return
	if dialogue_resource == null:
		push_warning("Companion '%s' 未配置 dialogue_resource" % name)
		return
	_area.set_deferred("monitoring", false)   # 首触后关掉触碰检测，之后改跟随
	_play_dialogue(start_cue)


func _play_dialogue(cue: String, resource: DialogueResource = null) -> void:
	var source := resource if resource != null else dialogue_resource
	if source == null:
		return
	_talking = true
	if not StoryDirector.request(self, source, cue, Callable(), _on_own_dialogue_finished, _on_own_dialogue_cancelled):
		_talking = false


func _on_own_dialogue_finished() -> void:
	if not _talking:
		return
	_talking = false
	if state == State.IDLE:
		GameState.companion_recruited = true
		state = State.FOLLOWING
		if player != null:
			_idle_ref_pos = player.global_position


func _on_own_dialogue_cancelled() -> void:
	_talking = false


func _check_reminders(delta: float) -> void:
	if StoryDirector.is_busy():
		return
	# 1. 位置标记提醒
	for hint in get_tree().get_nodes_in_group("companion_hint"):
		if not GameState.is_in_current_scene(hint):
			continue
		var h: CompanionHint = hint as CompanionHint
		if h == null or not h.can_trigger():
			continue
		if player.global_position.distance_to(h.global_position) <= h.radius:
			_play_dialogue(h.trigger(), h.dialogue_resource)
			return

	# 2. 卡住超时提醒
	if not idle_reminders_enabled:
		_idle_accum = 0.0
		_idle_ref_pos = player.global_position
		return
	_idle_accum += delta
	if _idle_accum < idle_reminder_delay:
		return
	if player.global_position.distance_to(_idle_ref_pos) > idle_move_threshold:
		# 没卡住，只是走到别处了：重开窗口
		_idle_accum = 0.0
		_idle_ref_pos = player.global_position
		return
	var now := Time.get_ticks_msec()
	if now - _last_reminder_ms >= int(idle_reminder_cooldown * 1000.0):
		_last_reminder_ms = now
		_play_dialogue(idle_reminder_cue)
	_idle_accum = 0.0
	_idle_ref_pos = player.global_position
