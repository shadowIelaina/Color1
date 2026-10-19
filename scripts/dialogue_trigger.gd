@tool
class_name DialogueTrigger
extends CompanionHint
## 拖入关卡配置剧情，不依赖跟班。范围与编辑器预览使用世界像素。

@export_group("剧情触发")
@export_enum("进入区域", "按键交互") var trigger_mode: int = 0
@export_enum("整局一次", "每次进入关卡一次", "每次进入区域") var repeat_mode: int = 0:
	set(value):
		repeat_mode = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
## 整局一次的唯一标识；同一剧情可在多个位置共用标识。
@export var story_id: String = "":
	set(value):
		story_id = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
@export_enum("圆形", "矩形") var area_shape: int = 0:
	set(value):
		area_shape = value
		queue_redraw()
		if Engine.is_editor_hint():
			update_configuration_warnings()
@export var area_size := Vector2(512, 256):
	set(value):
		area_size = value
		queue_redraw()
		if Engine.is_editor_hint():
			update_configuration_warnings()
@export var interaction_text := "按 E 交谈"
## 运行游戏时也显示范围，方便验证；正式游玩保持关闭。
@export var show_range_in_game := false:
	set(value):
		show_range_in_game = value
		queue_redraw()

var _inside := false
var _pending := false
var _played := false
var _prompt: Label
var _director: Node


func _ready() -> void:
	_ensure_dialogue_resource()
	set_process(Engine.is_editor_hint())
	set_physics_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint():
		# 关卡的 TileMap/Y 排序可能盖住辅助范围，编辑器中放到最前。
		z_index = 4095
		z_as_relative = false
		queue_redraw()
		return
	_director = get_node("/root/StoryDirector")
	add_to_group("dialogue_trigger")
	if not InputMap.has_action("story_interact"):
		InputMap.add_action("story_interact")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event("story_interact", key)
	_prompt = Label.new()
	_prompt.text = interaction_text
	_prompt.add_theme_font_override("font", preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf"))
	_prompt.add_theme_color_override("font_color", Color("38352f"))
	_prompt.add_theme_color_override("font_outline_color", Color("f4f0e5"))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_font_size_override("font_size", 48)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.hide()
	add_child(_prompt)
	queue_redraw()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	super._process(delta)
	# 脚本热更新不会再次调用已有实例的 _ready，逐帧补齐预览层级和变换。
	z_index = 4095
	z_as_relative = false
	queue_redraw()


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var inside := player != null and GameState.is_in_current_scene(self) and _contains(player.global_position)
	if inside and not _inside and trigger_mode == 0:
		request_dialogue()
	_inside = inside
	_prompt.visible = inside and trigger_mode == 1 and can_trigger() and not _director.is_busy()
	var extent := radius if area_shape == 0 else area_size.y * 0.5
	_prompt.global_position = global_position + Vector2(-_prompt.size.x * 0.5, -extent - 64.0)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or trigger_mode != 1 or not _inside or _director.is_busy():
		return
	if event.is_action_pressed("story_interact") and not event.is_echo() and request_dialogue():
		get_viewport().set_input_as_handled()


func _contains(point: Vector2) -> bool:
	var offset := point - global_position
	if area_shape == 0:
		return offset.length() <= radius
	return absf(offset.x) <= area_size.x * 0.5 and absf(offset.y) <= area_size.y * 0.5


func can_trigger() -> bool:
	if _pending or dialogue_resource == null or not dialogue_resource.cues.has(cue):
		return false
	if repeat_mode == 0:
		return story_id.strip_edges() != "" and not GameState.played_story.has(story_id)
	return repeat_mode == 2 or not _played


func request_dialogue() -> bool:
	if not can_trigger():
		return false
	_pending = _director.request(self, dialogue_resource, cue, _on_started, _on_finished, _on_cancelled, _can_start_queued)
	return _pending


func _can_start_queued() -> bool:
	# 相同标识的多个触发点同时入队，也只播放一次。
	return repeat_mode != 0 or not GameState.played_story.has(story_id)


func _on_started() -> void:
	_played = true
	if repeat_mode == 0:
		GameState.played_story[story_id] = true


func _on_finished() -> void:
	_pending = false


func _on_cancelled() -> void:
	_pending = false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super._get_configuration_warnings()
	if repeat_mode == 0 and story_id.strip_edges() == "":
		warnings.append("整局一次需要填写唯一的 Story Id，例如 level1_first_meeting。")
	if area_shape == 1 and (area_size.x <= 0 or area_size.y <= 0):
		warnings.append("矩形范围的 Area Size 必须大于零。")
	return warnings


func _draw() -> void:
	if (not Engine.is_editor_hint() and not show_range_in_game) or absf(global_transform.determinant()) < 0.00001:
		return
	draw_set_transform_matrix(global_transform.affine_inverse() * Transform2D(0.0, global_position))
	var fill := Color(0.3, 0.85, 1.0, 0.15)
	var outline := Color(0.3, 0.85, 1.0, 1.0)
	if area_shape == 0:
		draw_circle(Vector2.ZERO, radius, fill)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, outline, 4.0, true)
	else:
		var rect := Rect2(-area_size * 0.5, area_size)
		draw_rect(rect, fill)
		draw_rect(rect, outline, false, 4.0)
	draw_line(Vector2(-16, 0), Vector2(16, 0), outline, 3.0)
	draw_line(Vector2(0, -16), Vector2(0, 16), outline, 3.0)
