extends CanvasLayer
## 首关开场：等待主菜单退场，再依次睁眼、移动、相遇、向北探索。

enum Phase { OFF, WAITING, WAKING, MOVING, MEETING, NORTH }
const FONT := preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")
const WAKE_ID := "opening_woke"
const DONE_ID := "opening_complete"
var phase := Phase.OFF
var _player: Node2D
var _companion: Node2D
var _hud: CanvasLayer
var _white: ColorRect
var _card: PanelContainer
var _title: Label
var _detail: Label
var _wisp: Label
var _advance: Label
var _origin := Vector2.ZERO
var _last_position := Vector2.ZERO
var _distance := 0.0
var _idle := 0.0
var _north_goal := Vector2.ZERO
var _north_player_reached := false
var _north_wait := 0.0
var _guide_points: Array[Vector2] = []
var _guide_point_index := 0
var _animation: Tween


func _ready() -> void:
	name = "OpeningGuide"
	layer = 40
	_player = get_parent().get_node("Player")
	_hud = get_parent().get_node("HUD")
	_build_ui()
	SceneManager.room_changed.connect(_on_room_changed)
	SceneManager.room_exited.connect(_on_room_exited)


func _build_ui() -> void:
	_white = ColorRect.new()
	_white.color = Color("f5f3ed")
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_white)
	_white.hide()
	_card = PanelContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_card.offset_left = -240
	_card.offset_right = 240
	_card.offset_top = -126
	_card.offset_bottom = -42
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.97, 0.96, 0.93, 0.94)
	paper.set_corner_radius_all(14)
	paper.content_margin_left = 24
	paper.content_margin_right = 24
	paper.content_margin_top = 12
	paper.content_margin_bottom = 12
	_card.add_theme_stylebox_override("panel", paper)
	add_child(_card)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(lines)
	for i in 2:
		var label := Label.new()
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", 22 if i == 0 else 16)
		label.add_theme_color_override("font_color", Color("514d47") if i == 0 else Color("817b70"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(label)
		if i == 0: _title = label
		else: _detail = label
	_card.hide()
	_wisp = Label.new()
	_wisp.text = "✧"
	_wisp.add_theme_font_override("font", FONT)
	_wisp.add_theme_font_size_override("font_size", 42)
	_wisp.add_theme_color_override("font_color", Color("d2bd8d"))
	_wisp.add_theme_constant_override("outline_size", 8)
	_wisp.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.5))
	_wisp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wisp)
	_wisp.hide()
	var dialogue_hint := CanvasLayer.new()
	dialogue_hint.layer = 110
	add_child(dialogue_hint)
	_advance = Label.new()
	_advance.text = "点击 · 展开 / 继续对白"
	_advance.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_advance.offset_left = -290
	_advance.offset_right = -24
	_advance.offset_top = 24
	_advance.offset_bottom = 54
	_advance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_advance.add_theme_font_override("font", FONT)
	_advance.add_theme_font_size_override("font_size", 16)
	_advance.add_theme_color_override("font_color", Color("625d54"))
	_advance.add_theme_constant_override("outline_size", 4)
	_advance.add_theme_color_override("font_outline_color", Color("f5f3ed"))
	_advance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_hint.add_child(_advance)
	_advance.hide()


func _on_room_changed(_room_id: String) -> void:
	if SceneManager.current_room_scene != "res://scenes/level_1.tscn": return
	if GameState.companion_recruited or GameState.played_story.has(DONE_ID): return
	_companion = get_tree().get_first_node_in_group("companion") as Node2D
	if not is_instance_valid(_companion): return
	_companion.hide()
	_companion.get_node("InteractArea").set_deferred("monitoring", false)
	_origin = _player.global_position
	_last_position = _origin
	_distance = 0.0
	_idle = 0.0
	phase = Phase.WAITING


func _process(delta: float) -> void:
	_advance.visible = phase in [Phase.WAKING, Phase.MEETING] and not _white.visible and StoryDirector.is_busy()
	_wisp.visible = (phase == Phase.MOVING and _idle >= 8.0 or phase == Phase.NORTH) and not StoryDirector.is_busy()
	if _wisp.visible:
		var target := _north_goal if phase == Phase.NORTH else _player.global_position + Vector2(0, -256)
		_wisp.position = _player.get_canvas_transform() * target - Vector2(16, 40)
		_wisp.modulate.a = 0.65 + sin(Time.get_ticks_msec() * 0.003) * 0.3
	match phase:
		Phase.WAITING:
			# 主菜单的镜头飞行动画结束且游戏恢复后才揭幕。
			if get_tree().paused: return
			_start_waking()
		Phase.WAKING, Phase.MEETING:
			_hud.hide()
		Phase.MOVING:
			if StoryDirector.is_busy():
				_card.hide()
				_last_position = _player.global_position
				return
			_card.show()
			var moved := _player.global_position.distance_to(_last_position)
			_last_position = _player.global_position
			# 仅计主动行走，排除传送与水流推动。
			if Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO and moved < 512.0:
				_distance += moved
			_idle += delta
			if _idle >= 8.0:
				_detail.text = "WASD / 方向键 · 向前走走，看看附近"
			if _distance >= 256.0: _meet_spirit()
		Phase.NORTH:
			if _companion.state != _companion.State.GUIDING:
				# 死亡/存档点返回会取消引路；此时恢复普通跟随，不留悬空引导。
				_finish()
				return
			_card.visible = not StoryDirector.is_busy()
			# 先记住玩家是否真的走近目标，不能只凭纵坐标提前结束飞行。
			if _player.global_position.distance_to(_north_goal) <= 192.0:
				_north_player_reached = true
			if _companion.is_waiting_for_guide():
				_north_wait += delta
			if _north_player_reached and _north_wait >= 0.4 and not StoryDirector.is_busy():
				_guide_point_index += 1
				if _guide_point_index < _guide_points.size():
					_fly_to_guide_point()
				else:
					_finish()


func _start_waking() -> void:
	phase = Phase.WAKING
	_player.opening_input_locked = true
	_hud.hide()
	if GameState.played_story.has(WAKE_ID):
		_begin_movement()
		return
	_white.color.a = 1.0
	_white.show()
	_animation = create_tween()
	_animation.tween_interval(0.4)
	_animation.tween_property(_white, "color:a", 0.0, 2.0).set_trans(Tween.TRANS_SINE)
	_animation.tween_callback(func():
		_white.hide()
		if not StoryPort.play(self, "spawn", "", _on_woke): _begin_movement()
	)


func _on_woke() -> void:
	GameState.played_story[WAKE_ID] = true
	_begin_movement()


func _begin_movement() -> void:
	phase = Phase.MOVING
	_player.opening_input_locked = false
	_player.suppress_action_input()
	_last_position = _player.global_position
	_show_hint("试着走动", "WASD / 方向键 · 移动")


func _meet_spirit() -> void:
	phase = Phase.MEETING
	_card.hide()
	_player.opening_input_locked = true
	_companion.global_position = _player.global_position + Vector2(160, -180)
	_companion.show()
	if not StoryPort.play(self, "spirit_meet", "", _begin_north): _begin_north()


func _begin_north() -> void:
	GameState.companion_recruited = true
	GameState.played_story[DONE_ID] = true
	_player.opening_input_locked = false
	_player.suppress_action_input()
	_hud.show()
	phase = Phase.NORTH
	_guide_points.clear()
	var path := SceneManager.current_room.get_node_or_null("OpeningGuidePath")
	if path != null:
		for marker in path.get_children():
			if marker is Marker2D: _guide_points.append(marker.global_position)
	if _guide_points.is_empty():
		_finish()
		return
	_guide_point_index = 0
	_fly_to_guide_point()


func _fly_to_guide_point() -> void:
	_north_goal = _guide_points[_guide_point_index]
	_north_player_reached = false
	_north_wait = 0.0
	# 沿关卡标记逐段带路，最终停在北侧蓝色冰块前的通道。
	_companion.guide_to(_north_goal)
	_show_hint("跟上小白，前往北边的通道", "WASD / 方向键 · 靠近小白后继续前进")


func _show_hint(title: String, detail: String) -> void:
	_title.text = title
	_detail.text = detail
	_card.modulate.a = 0.0
	_card.show()
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.35)


func _finish() -> void:
	if is_instance_valid(_animation): _animation.kill()
	if is_instance_valid(_companion):
		_companion.show()
		if GameState.companion_recruited: _companion.restore_following(false)
	_player.opening_input_locked = false
	_hud.show()
	_white.hide()
	_card.hide()
	_wisp.hide()
	_advance.hide()
	phase = Phase.OFF


func _on_room_exited(_room_id: String) -> void:
	if phase != Phase.OFF: _finish()


func _exit_tree() -> void:
	if is_instance_valid(_player): _player.opening_input_locked = false
