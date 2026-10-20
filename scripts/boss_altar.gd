class_name BossAltar
extends Node2D
## Boss 圣坛：集齐三颗心后，玩家点击交互点亮圣坛并开启 Boss 传送门；
## 点亮后再让跟班飞来一次，领取一次三色赐福。
## 交互走跟班链路（与宝箱一致）：Player 左键 -> Companion.interact(self) -> interact()。

signal activated

const Rules := preload("res://scripts/element/element_rules.gd")

@export var required_hearts := 3
@export var unlock_switch := "boss_altar"
@export var dormant_color := Color(0.5, 0.5, 0.56, 1.0)
@export var active_color := Color(1.0, 0.96, 0.82, 1.0)
@export var interact_radius := 480.0

@export_group("奖励")
## 领取记录开关（写入 GameState，保证赐福只能领一次）。
@export var reward_switch := "boss_altar_reward"
## 第二次交互领取的元素（红/蓝/绿）。
@export var reward_elements: Array[String] = ["burn", "freeze", "grow"]
## 每个元素发放的数量（叠加到玩家当前库存上）。
@export_range(0, 99, 1) var reward_amount := 5

@export_group("剧情")
## 点亮圣坛后播放的跟班对话资源（留空 = 不播）。
@export var activated_dialogue: DialogueResource
## 点亮圣坛后播放的段落名。
@export var activated_cue := "hint_boss_portal"

@onready var visual: Sprite2D = get_node_or_null("Visual") as Sprite2D
@onready var heart_slots: Node2D = get_node_or_null("HeartSlots") as Node2D

var is_open := false
var reward_claimed := false
var _pulse: Tween


func _ready() -> void:
	add_to_group("altar")
	is_open = GameState.is_switch_on(unlock_switch)
	reward_claimed = GameState.is_switch_on(reward_switch)
	_refresh_visual()
	GameState.switch_changed.connect(_on_switch_changed)


func _on_switch_changed(switch_id: String, value: bool) -> void:
	if switch_id == reward_switch:
		if value:
			reward_claimed = true
		return
	if switch_id != unlock_switch or not value or is_open:
		return
	is_open = true
	_refresh_visual()
	_start_pulse()


## 被跟班调用：未点亮时检查心数并点亮；已点亮时领取一次赐福。
func interact() -> void:
	if is_open:
		_claim_reward()
		return
	var missing := required_hearts - heart_count()
	if missing > 0:
		GameState.hint.emit("圣坛沉睡着，还需要 %d 颗心" % missing)
		return
	_activate()


## 跟班是否可以接取祭坛交互：未点亮时可点亮，点亮后还可领取一次赐福。
func can_interact() -> bool:
	if not is_open:
		return true
	return not reward_claimed


func _activate() -> void:
	if is_open:
		return
	is_open = true
	GameState.set_switch(unlock_switch, true)
	GameState.notice.emit("圣坛被点亮了，南侧的 Boss 传送门已开启；再让跟班来领取赐福")
	_refresh_visual()
	_start_pulse()
	activated.emit()
	_play_activated_dialogue()


## 第二次交互：发放一次赐福并写入领取记录，之后祭坛不再可交互。
func _claim_reward() -> void:
	if reward_claimed:
		GameState.hint.emit("圣坛的赐福已经领取过了")
		return
	var reward_text := _grant_reward()
	if reward_text == "":
		return
	reward_claimed = true
	GameState.set_switch(reward_switch, true)
	GameState.notice.emit("圣坛赐福：" + reward_text)


## 把奖励元素按数量叠加给玩家，返回用于提示的文案（无玩家时返回空）。
func _grant_reward() -> String:
	if reward_amount <= 0:
		return ""
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("receive_element"):
		return ""
	var names: Array[String] = []
	for element in reward_elements:
		if element == "":
			continue
		player.call("receive_element", element, reward_amount)
		var color_name := str(Rules.config(element).get("color_name", element))
		if color_name != "":
			names.append(color_name)
	if names.is_empty():
		return ""
	return "获得%s能力各 %d 个" % ["、".join(names), reward_amount]


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
