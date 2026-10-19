@tool
class_name StoryTrigger
extends Node2D
## 通用剧情触发点：auto_start 时场景加载后立即播放；否则玩家走进 radius 内触发一次。
## 对话统一走 StoryDirector 排队，结束后可顺手招募小跟班（recruit_companion）。

@export var dialogue_resource: DialogueResource
@export var cue: String = ""
## true = 进入场景后立即播放（出生点开场用）；false = 玩家走进 radius 才触发。
@export var auto_start: bool = false
@export_range(1.0, 4096.0, 1.0, "or_greater") var radius: float = 96.0
## 对话结束后把场景里的 Companion 切到跟随状态（首触开场用）。
@export var recruit_companion: bool = false
## 整局唯一标识（对应 GameState.played_story）；填了则整局只播一次，重进场景/读档不再复播。
@export var story_id: String = ""

var _triggered := false
var _player: Node2D


func _ready() -> void:
	add_to_group("story_trigger")
	_player = get_tree().get_first_node_in_group("player") as Node2D
	if Engine.is_editor_hint():
		return
	if auto_start:
		# 等房间加载、玩家定位完成后再播。
		call_deferred("_fire")
	else:
		set_process(true)


func _process(_delta: float) -> void:
	if _triggered or _player == null or not is_instance_valid(_player):
		return
	if _player.global_position.distance_to(global_position) <= radius:
		_fire()


func _fire() -> void:
	if _triggered:
		return
	# 开场招募型触发：小跟班已招募说明开场已播过，重进本关不再复播。
	if recruit_companion and GameState.companion_recruited:
		_triggered = true
		set_process(false)
		return
	# 整局一次：story_id 已播过则不再复播（出生点开场等）。
	if story_id != "" and GameState.played_story.has(story_id):
		_triggered = true
		set_process(false)
		return
	if dialogue_resource == null or (cue != "" and not dialogue_resource.cues.has(cue)):
		return
	_triggered = true
	set_process(false)
	var started := Callable()
	if story_id != "":
		var sid := story_id
		started = func() -> void: GameState.played_story[sid] = true
	var finished := Callable()
	if recruit_companion:
		finished = _recruit_companion
	if not StoryDirector.request(self, dialogue_resource, cue, started, finished):
		_triggered = false
		set_process(not auto_start)


func _recruit_companion() -> void:
	GameState.companion_recruited = true
	var companion: Node = get_tree().get_first_node_in_group("companion")
	if companion != null and companion.has_method("restore_following"):
		companion.restore_following(false)
