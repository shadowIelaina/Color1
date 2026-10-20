extends Node
## Boss 房的跟班提示调度：开场/战斗机制/胜利台词统一排队。
## 开场与胜利走对话框；战斗中的 7 条提示走跟班头顶纸片气泡。
## 新的小怪/绿怪提示会等跟班做完当前任务再显示，其余战斗提示立即显示。

const DEFAULT_DIALOGUE_UID := "uid://cs4tg8k8wjy13"

@export_group("对话")
@export var dialogue_resource: DialogueResource
@export var intro_cue := "hint_boss_intro"
@export var victory_cue := "hint_boss_victory"

@export_group("战斗气泡")
@export var ring_text := "小心红色弹幕！可以躲到石柱后面，或把场地里可上色的岩石染成黄色（红+绿），就能反弹！"
@export var ice_text := "Boss 的蓝色瞄准线锁定你了！快离开那条线！"
@export var heal_text := "Boss 要回血了！用蓝色点 Boss，引它撞墙！"
@export var charge_text := "Boss 冲过来了！快躲开，让它撞墙！"
@export var stun_text := "Boss 撞晕了！趁现在打它！"
@export var adds_text := "新的小怪出来了！蓝色小怪怕红，红色小怪怕蓝！"
@export var green_text := "绿色小怪会召唤藤蔓！用蓝色点它，能打断 Boss 回血！"
@export_range(0.5, 8.0, 0.1) var bubble_duration := 2.6

@export_group("节奏")
## 击杀后延迟多久播放胜利台词（让胜利横幅先出现）。
@export var victory_delay := 1.0

const INTRO_KEY := "hint_boss_intro"
const VICTORY_KEY := "hint_boss_victory"
const RING_KEY := "boss_hint_ring"
const ICE_KEY := "boss_hint_ice"
const HEAL_KEY := "boss_hint_heal"
const CHARGE_KEY := "boss_hint_charge"
const STUN_KEY := "boss_hint_stun"
const ADDS_KEY := "boss_hint_adds"
const GREEN_KEY := "boss_hint_green"

var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
var _boss: Node
var _companion: Node
var _victory_queued := false
var _intro_paused := false


func _ready() -> void:
	_ensure_dialogue()
	_setup.call_deferred()


func _setup() -> void:
	if not is_inside_tree() or GameState.is_switch_on("boss_defeated"):
		return
	_boss = get_tree().get_first_node_in_group("boss")
	if _boss == null:
		return
	_connect_boss()
	if _should_pause_for_intro():
		_set_boss_moving(false)
		_intro_paused = true
	_enqueue_dialogue(intro_cue, INTRO_KEY)
	_maybe_enqueue_phase_from_boss()


func _should_pause_for_intro() -> bool:
	if _boss == null or not is_instance_valid(_boss) or _boss.is_queued_for_deletion():
		return false
	if GameState.is_switch_on("boss_defeated") or GameState.hints.has(INTRO_KEY):
		return false
	_ensure_dialogue()
	return dialogue_resource != null and dialogue_resource.cues.has(intro_cue)


func _set_boss_moving(moving: bool) -> void:
	if is_instance_valid(_boss) and not _boss.is_queued_for_deletion():
		_boss.set_physics_process(moving)


func _on_intro_dialogue_done() -> void:
	_intro_paused = false
	_set_boss_moving(true)


func _resume_intro_boss() -> void:
	if _intro_paused:
		_on_intro_dialogue_done()


func _connect_boss() -> void:
	if _boss.has_signal("state_changed"):
		_boss.state_changed.connect(_on_state_changed)
	if _boss.has_signal("health_changed"):
		_boss.health_changed.connect(_on_health_changed)
	if _boss.has_signal("died"):
		_boss.died.connect(_on_boss_died)


func _process(_delta: float) -> void:
	_pump()


func _on_state_changed(state: int) -> void:
	match state:
		Boss.State.RING_CAST:
			_enqueue_bubble(ring_text, RING_KEY)
		Boss.State.ICE_CAST:
			_enqueue_bubble(ice_text, ICE_KEY)
		Boss.State.HEAL_WINDUP:
			_enqueue_bubble(heal_text, HEAL_KEY)
		Boss.State.CYAN_CHARGE:
			_enqueue_bubble(charge_text, CHARGE_KEY)
		Boss.State.STUNNED:
			_enqueue_bubble(stun_text, STUN_KEY)


func _on_health_changed(current: float, max_health: float) -> void:
	_maybe_enqueue_phase(current, max_health)


func _on_boss_died() -> void:
	if _victory_queued:
		return
	_victory_queued = true
	_queue.clear()
	_queued_keys.clear()
	await get_tree().create_timer(victory_delay).timeout
	if not is_inside_tree():
		return
	_enqueue_dialogue(victory_cue, VICTORY_KEY)


## 重进房间时按当前血量补排小怪提示，避免错过阶段。
func _maybe_enqueue_phase_from_boss() -> void:
	if _boss == null or not _boss.has_method("health_snapshot"):
		return
	var snap: Dictionary = _boss.health_snapshot()
	_maybe_enqueue_phase(float(snap.get("health", 0.0)), float(snap.get("max_health", 0.0)))


func _maybe_enqueue_phase(current: float, max_health: float) -> void:
	if max_health <= 0.0:
		return
	var ratio := current / max_health
	if ratio <= 0.5:
		_enqueue_bubble(adds_text, ADDS_KEY, true)
	if ratio <= 0.3:
		_enqueue_bubble(green_text, GREEN_KEY, true)


func _enqueue_dialogue(cue: String, key: String) -> void:
	if cue == "" or key == "":
		return
	if GameState.hints.has(key) or _queued_keys.has(key):
		return
	_ensure_dialogue()
	if dialogue_resource == null or not dialogue_resource.cues.has(cue):
		push_warning("BossHintDirector: 对话段落不存在：%s" % cue)
		return
	_queued_keys[key] = true
	_queue.append({"kind": "dialogue", "cue": cue, "key": key})


func _enqueue_bubble(text: String, key: String, wait_companion := false) -> void:
	if text.strip_edges() == "" or key == "":
		return
	if GameState.hints.has(key) or _queued_keys.has(key):
		return
	_queued_keys[key] = true
	_queue.append({"kind": "bubble", "text": text, "key": key, "wait_companion": wait_companion})


## 每帧尝试处理队首提示。
func _pump() -> void:
	if _queue.is_empty() or not is_inside_tree():
		return
	if StoryDirector.is_busy():
		return
	var entry: Dictionary = _queue[0]
	var kind := str(entry.get("kind", "bubble"))
	if kind == "dialogue":
		_pump_dialogue(entry)
	else:
		_pump_bubble(entry)


func _pump_dialogue(entry: Dictionary) -> void:
	var hud := _find_hud()
	if hud != null and hud.has_method("is_companion_hint_showing") and bool(hud.call("is_companion_hint_showing")):
		return
	var companion := _find_companion()
	if companion == null or not bool(companion.call("is_available")):
		return
	var key := str(entry.get("key", ""))
	var is_intro := key == INTRO_KEY
	var cue := str(entry.get("cue", ""))
	if dialogue_resource == null or not dialogue_resource.cues.has(cue):
		_pop_entry(entry)
		if is_intro:
			_resume_intro_boss()
		return
	if is_intro:
		var ok := bool(companion.call(
			"say",
			cue,
			dialogue_resource,
			Callable(),
			_on_intro_dialogue_done,
			_on_intro_dialogue_done
		))
		if not ok:
			return
	else:
		if not bool(companion.call("say", cue, dialogue_resource)):
			return
	_mark_played(entry)


func _pump_bubble(entry: Dictionary) -> void:
	var hud := _find_hud()
	if hud == null or not hud.has_method("show_companion_hint"):
		GameState.hint.emit("小白：" + str(entry.get("text", "")))
		_mark_played(entry)
		return
	if bool(hud.call("is_companion_hint_showing")):
		return
	if bool(entry.get("wait_companion", false)):
		var companion := _find_companion()
		if companion == null or not bool(companion.call("is_available")):
			return
	var text := str(entry.get("text", ""))
	if text.strip_edges() == "":
		_pop_entry(entry)
		return
	if not bool(hud.call("show_companion_hint", text, bubble_duration)):
		return
	_mark_played(entry)


func _mark_played(entry: Dictionary) -> void:
	var key := str(entry.get("key", ""))
	if key != "":
		GameState.hints[key] = true
	_pop_entry(entry)


func _pop_entry(entry: Dictionary) -> void:
	var key := str(entry.get("key", ""))
	if key != "":
		_queued_keys.erase(key)
	if not _queue.is_empty() and _queue[0] == entry:
		_queue.pop_front()
	else:
		_queue.erase(entry)


func _find_companion() -> Node:
	if is_instance_valid(_companion) and not _companion.is_queued_for_deletion() and _companion.is_inside_tree():
		return _companion
	_companion = get_tree().get_first_node_in_group("companion")
	return _companion


func _find_hud() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		var hud := scene.get_node_or_null("HUD")
		if hud != null:
			return hud
	return get_tree().get_first_node_in_group("hud")


func _ensure_dialogue() -> void:
	if dialogue_resource != null:
		return
	if ResourceLoader.exists(DEFAULT_DIALOGUE_UID):
		dialogue_resource = load(DEFAULT_DIALOGUE_UID) as DialogueResource
