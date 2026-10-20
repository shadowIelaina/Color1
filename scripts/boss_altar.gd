class_name BossAltar
extends Node2D
## Boss 圣坛：集齐三颗心后，玩家点击交互点亮圣坛并开启 Boss 传送门。
## 交互走跟班链路（与宝箱一致）：Player 左键 -> Companion.interact(self) -> interact()。

signal activated

@export var required_hearts := 3
@export var unlock_switch := "boss_altar"
@export var dormant_color := Color(0.5, 0.5, 0.56, 1.0)
@export var active_color := Color(1.0, 0.96, 0.82, 1.0)
@export var interact_radius := 480.0

@export_group("剧情")
## 点亮圣坛后播放的跟班对话资源（留空 = 不播）。
@export var activated_dialogue: DialogueResource
## 点亮圣坛后播放的段落名。
@export var activated_cue := "hint_boss_portal"

@onready var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
@onready var heart_slots: Node2D = get_node_or_null("HeartSlots") as Node2D

var is_open := false
var _pulse: Tween


func _ready() -> void:
	add_to_group("altar")
	is_open = GameState.is_switch_on(unlock_switch)
	_refresh_visual()
	GameState.switch_changed.connect(_on_switch_changed)


func _on_switch_changed(switch_id: String, value: bool) -> void:
	if switch_id != unlock_switch or not value or is_open:
		return
	is_open = true
	_refresh_visual()
	_start_pulse()


## 被跟班调用：检查心数 -> 点亮圣坛 -> 写入全局开关（供 Boss 门解锁）。
func interact() -> void:
	if is_open:
		return
	var missing := required_hearts - heart_count()
	if missing > 0:
		GameState.hint.emit("圣坛沉睡着，还需要 %d 颗心" % missing)
		return
	_activate()


func _activate() -> void:
	is_open = true
	GameState.set_switch(unlock_switch, true)
	GameState.notice.emit("圣坛被点亮了，南侧的 Boss 传送门已开启")
	_refresh_visual()
	_start_pulse()
	activated.emit()
	_play_activated_dialogue()


func _play_activated_dialogue() -> void:
	if activated_dialogue == null or activated_cue == "":
		return
	if not activated_dialogue.cues.has(activated_cue):
		return
	StoryDirector.request(self, activated_dialogue, activated_cue)


## 鼠标命中检测（Player._interact 通过 contains_point 选中）。
func contains_point(point: Vector2) -> bool:
	return global_position.distance_to(point) <= interact_radius


## 已收集的心之容器数量（心拾取统一落在 GameState.health_upgrades 里）。
func heart_count() -> int:
	var count := 0
	for id in GameState.health_upgrades.keys():
		if str(id).begins_with("heart:"):
			count += 1
	return count


func _refresh_visual() -> void:
	if visual != null:
		visual.modulate = active_color if is_open else dormant_color
	if heart_slots != null:
		var count := heart_count()
		var slots := heart_slots.get_children()
		for i in slots.size():
			var slot := slots[i] as CanvasItem
			if slot != null:
				slot.modulate = Color(1, 1, 1, 1) if i < count else Color(0.28, 0.28, 0.32, 1)


func _start_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	if visual == null:
		return
	var base := visual.scale
	_pulse = create_tween().set_loops()
	_pulse.tween_property(visual, "scale", base * 1.03, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(visual, "scale", base, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
