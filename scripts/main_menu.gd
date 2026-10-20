extends CanvasLayer
## 同一世界中的标题界面：房间准备后揭幕，镜头落稳后才开放玩法。

const DURATION := 1.35
const DROP_COUNT := 40
const DROP_LIFETIME := 4.2
const DROP_INTERVAL := 0.12
var _game: Node2D
var _root: Control
var _panel: VBoxContainer
var _shade: ColorRect
var _curtain: ColorRect
var _settings: VBoxContainer
var _start: Button
var _continue: Button
var _new_game_prompt: VBoxContainer
var _save_status: Label
var _settings_button: Button
var _quit_button: Button
var _ready_for_input := false
var _menu_camera: PhantomCamera2D
var _starting := false
var _title: Control
var _ink: ShaderMaterial
var _stains := PackedVector4Array()
var _spark: Control
var _elapsed := 0.0
var _brush_clock := 0.0
var _flight := 0.0
var _flight_origin := Vector2.ZERO
var _darkness: ShaderMaterial
var _light_radius := 0.0
var _release := 0.0
var _hint: Label
var _previous_mouse_mode: Input.MouseMode
var _drops := PackedVector4Array()
var _drop_clock := 0.0
var _last_drop := Vector2(-10000, -10000)
var _ink_tip := Vector2.ZERO


func prepare(game: Node2D) -> void:
	_game = game
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_build_ui()
	_game.get_node("HUD").hide()
	# 相机和声音继续运行，玩法与对话在揭幕前暂停。
	_game.get_node("Player/Camera").process_mode = Node.PROCESS_MODE_ALWAYS
	_game.get_node("MainPCam").process_mode = Node.PROCESS_MODE_ALWAYS
	get_node("/root/AudioManager").process_mode = Node.PROCESS_MODE_ALWAYS
	SceneManager.room_changed.connect(_on_room_ready, CONNECT_ONE_SHOT)


func _on_room_ready(_room_id: String) -> void:
	get_tree().paused = true
	_menu_camera = PhantomCamera2D.new()
	_menu_camera.name = "MenuCamera"
	_menu_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_camera.follow_mode = PhantomCamera2D.FollowMode.NONE
	_menu_camera.zoom = Vector2(0.21, 0.21)
	_menu_camera.tween_on_load = false
	_menu_camera.priority = 30
	# 让角色位于右侧，为左侧标题留出空间；随窗口宽度调整构图。
	_menu_camera.position = _game.get_node("Player").global_position - Vector2(get_viewport().get_visible_rect().size.x * 0.19 / 0.21, 100)
	_game.add_child(_menu_camera)
	await get_tree().process_frame
	await get_tree().process_frame
	if _game.launch_action != "":
		_panel.hide()
		_curtain.hide()
		_play_transition()
		return
	var reveal := create_tween()
	reveal.tween_property(_curtain, "color:a", 0.0, 0.65)
	await reveal.finished
	_curtain.hide()
	_start.disabled = false
	_continue.disabled = not _game.menu_has_save
	_ready_for_input = true
	if _game.menu_has_save:
		_continue.grab_focus()
	else:
		_start.grab_focus()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var menu_theme := Theme.new()
	menu_theme.default_font = _game.menu_font
	menu_theme.default_font_size = 22
	_root.theme = menu_theme
	add_child(_root)
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color.WHITE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darkness = ShaderMaterial.new()
	_darkness.shader = preload("res://shaders/menu_darkness.gdshader")
	for i in DROP_COUNT:
		_drops.append(Vector4(0, 0, 0, 0))
	_shade.material = _darkness
	_root.add_child(_shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var center := HBoxContainer.new()
	margin.add_child(center)
	_panel = VBoxContainer.new()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size.x = 260
	_panel.add_theme_constant_override("separation", 14)
	center.add_child(_panel)
	_ink = ShaderMaterial.new()
	_ink.shader = preload("res://shaders/menu_ink.gdshader")
	_build_title()
	for i in 12:
		_stains.append(Vector4(-1000, -1000, 0, 0))
	_ink.set_shader_parameter("stains", _stains)
	var space := Control.new()
	space.custom_minimum_size.y = 22
	_panel.add_child(space)
	_continue = _button(_panel, "继续游戏    →", _continue_game)
	_continue.disabled = true
	_continue.tooltip_text = "回到最近的存档点" if _game.menu_has_save else "暂无可用存档"
	_start = _button(_panel, "开始游戏", _begin)
	_start.disabled = true
	var saved_level := GameState.checkpoint_scene.get_file().get_basename()
	var chapter_names := {"level_1": "第一关", "level_2": "第二关", "level_3": "第三关", "level_4": "第四关"}
	var save_text := "最近存档 · %s" % chapter_names[saved_level] if chapter_names.has(saved_level) else "最近的存档点"
	_save_status = _label(_panel, save_text if _game.menu_has_save else "尚无存档", 16, Color("646859"))
	_new_game_prompt = VBoxContainer.new()
	_new_game_prompt.add_theme_constant_override("separation", 8)
	_panel.add_child(_new_game_prompt)
	_label(_new_game_prompt, "重新开始将清除已有存档。", 16, Color("805c44"))
	_button(_new_game_prompt, "确认重新开始", func(): _request_session("new"))
	_button(_new_game_prompt, "返回", func(): _show_new_game_prompt(false))
	_new_game_prompt.hide()
	_settings_button = _button(_panel, "设置", _toggle_settings)
	_quit_button = _button(_panel, "退出游戏", func(): get_tree().quit())
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 10)
	_panel.add_child(_settings)
	_label(_settings, "总音量", 16, Color("646859"))
	var volume := HSlider.new()
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = AudioServer.get_bus_volume_linear(0)
	volume.value_changed.connect(func(value: float): AudioServer.set_bus_volume_linear(0, value))
	_settings.add_child(volume)
	var fullscreen := CheckButton.new()
	fullscreen.text = "全屏显示"
	fullscreen.add_theme_color_override("font_color", Color("41483c"))
	fullscreen.add_theme_color_override("font_hover_color", Color("263e30"))
	fullscreen.add_theme_color_override("font_pressed_color", Color("263e30"))
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(enabled: bool): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED))
	_settings.add_child(fullscreen)
	_settings.hide()
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color("777b6c"))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -300
	_hint.offset_top = -52
	_hint.offset_right = -32
	_hint.offset_bottom = -28
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)
	_spark = preload("res://scripts/menu_spark.gd").new()
	_spark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_spark)
	_spark.point = _root.get_local_mouse_position()
	_ink_tip = _spark.point
	_curtain = ColorRect.new()
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.color = Color("e6e0d1")
	_root.add_child(_curtain)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _build_title() -> void:
	if _game.menu_title_texture != null:
		var artwork := TextureRect.new()
		artwork.name = "TitleArtwork"
		artwork.texture = _game.menu_title_texture
		artwork.custom_minimum_size = _game.menu_title_size.max(Vector2(32, 32))
		artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(artwork)
		_title = artwork
	else:
		var placeholder := VBoxContainer.new()
		placeholder.name = "TitlePlaceholder"
		placeholder.add_theme_constant_override("separation", 4)
		_panel.add_child(placeholder)
		var subtitle := _label(placeholder, "失色", 70, Color.WHITE)
		var subtitle_font := FontVariation.new()
		subtitle_font.base_font = _game.menu_font
		subtitle_font.variation_embolden = 0.5
		subtitle.add_theme_font_override("font", subtitle_font)
		var subtitle_material := _ink.duplicate() as ShaderMaterial
		subtitle_material.set_shader_parameter("outline_width", 0.85)
		subtitle.material = subtitle_material
		var lettering := _label(placeholder, "招领处", 76, Color.WHITE)
		# 稍加厚原字笔画，再在着色器中挖空中心，保留手写字形的双轮廓。
		var title_font := FontVariation.new()
		title_font.base_font = _game.menu_font
		title_font.variation_embolden = 0.9
		lettering.add_theme_font_override("font", title_font)
		lettering.material = _ink
		_title = placeholder


func _process(delta: float) -> void:
	if not is_instance_valid(_spark):
		return
	_elapsed += delta
	for i in _drops.size():
		_drops[i].z += delta
		if _drops[i].z >= DROP_LIFETIME:
			_drops[i].w = 0.0
	if _starting:
		# 每帧重新投影角色位置，镜头移动时光点仍准确落在角色身上。
		var player := _game.get_node("Player") as Node2D
		var target := player.get_global_transform_with_canvas() * Vector2(0, -100)
		var middle := (_flight_origin + target) * 0.5 + Vector2(0, -120)
		_spark.point = (1.0 - _flight) * (1.0 - _flight) * _flight_origin + 2.0 * (1.0 - _flight) * _flight * middle + _flight * _flight * target
		_update_darkness()
		return
	var local_mouse := _title.get_local_mouse_position()
	var hovering := Rect2(Vector2(-24, -24), _title.size + Vector2(48, 48)).has_point(local_mouse)
	var destination := _root.get_local_mouse_position()
	# 核心光点准确指向点击位置；拖尾提供柔和跟随感。
	_spark.point = destination
	_advance_ink(destination, delta)
	_update_darkness()
	_brush_clock += delta
	for i in _stains.size():
		_stains[i].z = maxf(0.0, _stains[i].z - delta * 0.22)
	if hovering and _brush_clock > 0.07:
		_brush_clock = 0.0
		_stains.remove_at(0)
		_stains.append(Vector4(local_mouse.x, local_mouse.y, 1.0, fmod(_elapsed * 0.08, 1.0)))
	_ink.set_shader_parameter("stains", _stains)


func _update_darkness() -> void:
	var viewport_size := _root.size
	_darkness.set_shader_parameter("viewport_size", viewport_size)
	_darkness.set_shader_parameter("light_position", _spark.point)
	_darkness.set_shader_parameter("light_radius", _light_radius * clampf(viewport_size.y / 648.0, 0.7, 2.0))
	_darkness.set_shader_parameter("release", _release)
	_darkness.set_shader_parameter("drops", _drops)


func _advance_ink(destination: Vector2, delta: float) -> void:
	var scale_factor := clampf(_root.size.y / 648.0, 0.7, 2.0)
	# 笔尖指示准确，起稿区域平滑追随；快速移动也不截断已有笔触。
	var movement := (destination - _ink_tip) * (1.0 - exp(-delta * 12.0))
	_ink_tip += movement.limit_length(700.0 * scale_factor * delta)
	_drop_clock += delta
	if not _curtain.visible and ((_drop_clock >= DROP_INTERVAL and _ink_tip.distance_to(_last_drop) >= 28.0 * scale_factor) or _drop_clock >= 0.7):
		_deposit_ink(_ink_tip)


func _deposit_ink(point: Vector2) -> void:
	var viewport_size := _root.size.max(Vector2.ONE)
	# 固定槽位：只使用空闲或完全淡出的槽位，绝不截断可见墨迹。
	for i in _drops.size():
		if _drops[i].w == 0.0 or _drops[i].z >= DROP_LIFETIME:
			_drops[i] = Vector4(point.x / viewport_size.x, point.y / viewport_size.y, 0.0, 1.0)
			_last_drop = point
			_drop_clock = 0.0
			return


func _exit_tree() -> void:
	Input.mouse_mode = _previous_mouse_mode


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("41483c"))
	button.add_theme_color_override("font_hover_color", Color("263e30"))
	button.add_theme_color_override("font_pressed_color", Color("263e30"))
	button.add_theme_color_override("font_focus_color", Color("263e30"))
	button.add_theme_color_override("font_disabled_color", Color("909184"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.35, 0.43, 0.31, 0.10 if state != "normal" else 0.015)
		style.content_margin_left = 16
		style.border_width_bottom = 1
		style.border_color = Color(0.30, 0.38, 0.26, 0.55 if state != "normal" else 0.16)
		button.add_theme_stylebox_override(state, style)
	button.mouse_entered.connect(func():
		if not button.disabled: AudioManager.play_ui_hover()
	)
	button.focus_entered.connect(func():
		if not button.disabled: AudioManager.play_ui_hover()
	)
	button.pressed.connect(AudioManager.play_ui_select)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _toggle_settings() -> void:
	if _starting:
		return
	_settings.visible = not _settings.visible
	# 设置与主操作共用区域，新增继续按钮后，小窗口也不会被挤出屏幕。
	for control in [_continue, _start, _save_status, _quit_button]:
		control.visible = not _settings.visible
	_settings_button.text = "返回主菜单" if _settings.visible else "设置"


func _begin() -> void:
	if _starting or not _ready_for_input:
		return
	if _game.menu_has_save:
		_settings.hide()
		_show_new_game_prompt(true)
		return
	_request_session("new")


func _show_new_game_prompt(show_prompt: bool) -> void:
	_new_game_prompt.visible = show_prompt
	for control in [_continue, _start, _save_status, _settings_button, _quit_button]:
		control.visible = not show_prompt
	if show_prompt:
		var back := _new_game_prompt.get_child(_new_game_prompt.get_child_count() - 1) as Button
		back.grab_focus()
	else:
		_start.grab_focus()


func _continue_game() -> void:
	if _starting or not _ready_for_input:
		return
	if not GameState.has_valid_save():
		_continue.disabled = true
		_game.menu_has_save = false
		_save_status.text = "存档不可用，请开始新游戏"
		return
	_request_session("continue")


func _request_session(action: String) -> void:
	if _starting:
		return
	_starting = true
	_ready_for_input = false
	for button in _panel.find_children("*", "Button", true, false):
		button.disabled = true
	# 先用纸面遮住重建过程，再按选项重新读取或清空进度。
	_curtain.show()
	_curtain.color.a = 0.0
	var cover := create_tween()
	cover.tween_property(_curtain, "color:a", 1.0, 0.2)
	await cover.finished
	GameState.menu_launch_action = action
	get_tree().paused = false
	var error := get_tree().reload_current_scene()
	if error != OK:
		GameState.menu_launch_action = ""
		get_tree().paused = true
		_starting = false
		_ready_for_input = true
		_start.disabled = false
		_continue.disabled = not _game.menu_has_save
		_curtain.hide()
		_save_status.text = "场景加载失败，请重试"


func _play_transition() -> void:
	if _starting:
		return
	_starting = true
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for button in _panel.find_children("*", "Button", true, false):
		button.disabled = true
	_settings.hide()
	_flight_origin = _spark.point
	_deposit_ink(_flight_origin)
	var awaken := create_tween()
	awaken.tween_method(func(value: float): _ink.set_shader_parameter("awaken", value), 0.0, 1.0, 0.2)
	await awaken.finished
	var camera := _game.get_node("MainPCam") as PhantomCamera2D
	camera.tween_resource = camera.tween_resource.duplicate()
	camera.tween_resource.duration = DURATION
	camera.tween_resource.transition = PhantomCameraTween.TransitionType.CUBIC
	camera.tween_resource.ease = PhantomCameraTween.EaseType.EASE_IN_OUT
	_menu_camera.priority = 0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.3)
	tween.tween_property(_panel, "position:y", _panel.position.y - 18, 0.35)
	tween.tween_property(_hint, "modulate:a", 0.0, 0.25)
	# 起稿从局部铺到整页，最后还原场景原本的纸面与色彩。
	var reveal_radius := _root.size.length() * 1.8
	tween.tween_property(self, "_light_radius", reveal_radius, 0.95).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "_release", 1.0, 0.25).set_delay(1.15)
	tween.tween_property(self, "_flight", 1.0, DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_spark, "strength", 0.0, 0.25).set_delay(DURATION - 0.1)
	await tween.finished
	_game.get_node("HUD").show()
	get_tree().paused = false
	_menu_camera.queue_free()
	queue_free()
