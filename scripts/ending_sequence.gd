extends CanvasLayer
## 黑白世界的负片结局。暂停世界，演出和结尾按钮保持运行。

signal stage_changed(stage: String)
const FONT := preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")
const INVERSION := preload("res://shaders/ending_inversion.gdshader")
var stage := "idle"
var _root: Control
var _image: ColorRect
var _material: ShaderMaterial
var _flash: ColorRect
var _dark: ColorRect
var _narration: Label
var _title: Label
var _subtitle: Label
var _buttons: HBoxContainer
var _tween: Tween
var _bus_volumes: Dictionary = {}
var _previous_mouse: Input.MouseMode
var _previous_pause := false
var _started := false


func _ready() -> void:
	name = "EndingSequence"
	layer = 300
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ending")
	_build_ui()


func _rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


func _text(text: String, size: int, top: float, bottom: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("eeece7"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.anchor_top = top
	label.anchor_bottom = bottom
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	_root.add_child(label)
	return label


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_image = _rect(Color.WHITE)
	_material = ShaderMaterial.new()
	_material.shader = INVERSION
	_material.set_shader_parameter("inversion", 0.0)
	_material.set_shader_parameter("shock", 0.0)
	_image.material = _material
	_dark = _rect(Color(0, 0, 0, 0))
	_flash = _rect(Color(1, 1, 1, 0))
	_narration = _text("应该结束了吧", 34, 0.38, 0.62)
	_narration.visible_ratio = 0.0
	_title = _text("未完待续", 64, 0.32, 0.57)
	_subtitle = _text("T O  B E  C O N T I N U E D", 16, 0.57, 0.65)
	_buttons = HBoxContainer.new()
	_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_buttons.offset_left = -200
	_buttons.offset_right = 200
	_buttons.offset_top = -100
	_buttons.offset_bottom = -52
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 32)
	_root.add_child(_buttons)
	for title in ["返回标题", "退出游戏"]:
		var button := Button.new()
		button.text = title
		button.custom_minimum_size = Vector2(160, 44)
		button.add_theme_font_override("font", FONT)
		button.add_theme_font_size_override("font_size", 20)
		button.flat = true
		button.add_theme_color_override("font_color", Color("a9a69e"))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.pressed.connect(_return_to_title if title == "返回标题" else _quit_game)
		_buttons.add_child(button)
	_buttons.hide()
	_root.hide()


func _set_stage(value: String) -> void:
	stage = value
	stage_changed.emit(value)


func start(portal_position: Vector2) -> void:
	if _started: return
	_started = true
	_previous_pause = get_tree().paused
	_previous_mouse = Input.mouse_mode
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.reclaim_placed_colors()
		player.velocity = Vector2.ZERO
		var screen_position: Vector2 = player.get_canvas_transform() * portal_position
		_material.set_shader_parameter("center", screen_position / get_viewport().get_visible_rect().size)
	for hud in get_tree().get_nodes_in_group("hud"): hud.hide()
	GameState.set_switch("ending_seen", true)
	GameState.save_game()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_root.show()
	_fade_audio()
	_set_stage("stillness")
	_tween = create_tween()
	_tween.tween_interval(0.7)
	_tween.tween_callback(_start_inversion)
	_tween.tween_method(func(value: float): _material.set_shader_parameter("inversion", value), 0.0, 1.0, 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(2.0)
	_tween.tween_callback(func(): _set_stage("narration"))
	_tween.tween_property(_dark, "color:a", 0.72, 1.0)
	_tween.tween_property(_narration, "modulate:a", 1.0, 0.6)
	_tween.tween_property(_narration, "visible_ratio", 1.0, 1.2)
	_tween.tween_interval(2.0)
	_tween.tween_property(_narration, "modulate:a", 0.0, 0.8)
	_tween.tween_property(_dark, "color:a", 1.0, 0.8)
	_tween.tween_interval(0.6)
	_tween.tween_callback(func(): _set_stage("to_be_continued"))
	_tween.tween_property(_title, "modulate:a", 1.0, 1.4)
	_tween.tween_property(_subtitle, "modulate:a", 0.6, 0.7)
	_tween.tween_interval(1.0)
	_tween.tween_callback(_show_end_screen)


func _start_inversion() -> void:
	_set_stage("inversion")
	_play_impact()
	var shock := create_tween().set_parallel(true)
	shock.tween_method(func(value: float): _material.set_shader_parameter("shock", value), 0.0, 1.0, 1.3)
	_flash.color.a = 0.72
	shock.tween_property(_flash, "color:a", 0.0, 0.22)


func _fade_audio() -> void:
	for bus in ["Music", "BGS", "SE"]:
		var index := AudioServer.get_bus_index(bus)
		if index < 0: continue
		_bus_volumes[bus] = AudioServer.get_bus_volume_db(index)
		create_tween().tween_method(func(db: float): AudioServer.set_bus_volume_db(index, db), float(_bus_volumes[bus]), -60.0, 1.2)


func _play_impact() -> void:
	# 短促低频坠落声，不依赖新增的外部音频文件。
	const RATE := 22050
	var bytes := PackedByteArray()
	bytes.resize(RATE * 3)
	var phase := 0.0
	for i in RATE * 3 / 2:
		var t := float(i) / RATE
		phase += TAU * lerpf(68.0, 28.0, minf(t, 1.0)) / RATE
		var envelope := minf(t / 0.02, 1.0) * exp(-3.8 * t)
		bytes.encode_s16(i * 2, int(sin(phase) * envelope * 18000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = -10.0
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()


func _show_end_screen() -> void:
	_set_stage("finished")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_buttons.show()
	_buttons.get_child(0).grab_focus()


func _return_to_title() -> void:
	GameState.menu_launch_action = ""
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit_game() -> void:
	get_tree().quit()


func _unhandled_input(_event: InputEvent) -> void:
	if _started: get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if not _started: return
	for bus in _bus_volumes:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0: AudioServer.set_bus_volume_db(index, _bus_volumes[bus])
	Input.mouse_mode = _previous_mouse
	get_tree().paused = _previous_pause
