extends CanvasLayer
## 常驻暂停层：Esc 优先截获，暂停对话和玩法；关闭后恢复原鼠标与焦点。
const HAND_FONT := preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")
var overlay: Control
var main_page: VBoxContainer
var settings_page: VBoxContainer
var confirm_page: VBoxContainer
var volume_slider: HSlider
var fullscreen_button: CheckButton
var _confirmation: Label
var _confirm_action: Callable
var _resume_button: Button
var _settings_button: Button
var _mouse_before: Input.MouseMode
var _focus_before: WeakRef
var _owns_pause := false
var _leaving := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	name = "PauseMenu"
	add_to_group("pause_menu")
	_build()
	overlay.hide()

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo(): return
	if _leaving: return
	if _owns_pause:
		if settings_page.visible or confirm_page.visible: _show_main()
		else: resume()
	elif not get_tree().paused and not SceneManager.is_busy():
		open()
	else:
		return # 标题揭幕/其他系统暂停时不抢占暂停权。
	get_viewport().set_input_as_handled()

func open() -> void:
	if _owns_pause or get_tree().paused: return
	_owns_pause = true
	_mouse_before = Input.mouse_mode
	var focused := get_viewport().gui_get_focus_owner()
	_focus_before = weakref(focused) if focused != null else null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	overlay.show()
	_show_main()

func resume() -> void:
	if not _owns_pause: return
	overlay.hide()
	var player := get_parent().get_node_or_null("Player")
	if player != null and player.has_method("suppress_action_input"): player.suppress_action_input()
	get_tree().paused = false
	_owns_pause = false
	Input.mouse_mode = _mouse_before
	if _focus_before != null:
		var previous: Control = _focus_before.get_ref()
		if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()

func _build() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	theme.default_font = HAND_FONT
	theme.default_font_size = 22
	overlay.theme = theme
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.13, 0.12, 0.10, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var paper := PanelContainer.new()
	paper.set_script(preload("res://scripts/paper_panel.gd"))
	paper.custom_minimum_size = Vector2(420, 0)
	center.add_child(paper)
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 14)
	paper.add_child(pages)
	main_page = _page(pages, "歇一会儿")
	_resume_button = _button(main_page, "继续游戏", resume)
	_button(main_page, "返回存档点 · 收回放置的颜色", _return_to_checkpoint)
	_settings_button = _button(main_page, "设置", _show_settings)
	_button(main_page, "返回主菜单", func(): _ask_leave(false))
	_button(main_page, "退出游戏", func(): _ask_leave(true))
	var hint := _label("Esc 返回游戏", 16)
	main_page.add_child(hint)
	settings_page = _page(pages, "设置")
	settings_page.add_child(_label("总音量", 20))
	volume_slider = HSlider.new()
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.custom_minimum_size.y = 32
	volume_slider.value_changed.connect(UserSettings.set_volume)
	settings_page.add_child(volume_slider)
	fullscreen_button = CheckButton.new()
	fullscreen_button.text = "全屏显示"
	fullscreen_button.add_theme_color_override("font_color", Color("38352f"))
	fullscreen_button.toggled.connect(UserSettings.set_fullscreen)
	settings_page.add_child(fullscreen_button)
	_button(settings_page, "返回", _show_main)
	confirm_page = _page(pages, "离开之前")
	_confirmation = _label("", 19)
	_confirmation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirmation.custom_minimum_size.x = 360
	confirm_page.add_child(_confirmation)
	_button(confirm_page, "确定离开", func():
		if _confirm_action.is_valid(): _confirm_action.call()
	)
	_button(confirm_page, "留下继续", _show_main)

func _page(parent: Node, title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	parent.add_child(page)
	page.add_child(_label(title, 30))
	return page

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("38352f"))
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_color_override("font_color", Color("38352f"))
	button.add_theme_color_override("font_hover_color", Color("263e30"))
	button.add_theme_color_override("font_pressed_color", Color("263e30"))
	button.add_theme_color_override("font_focus_color", Color("263e30"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.35, 0.25, 0.10 if state != "normal" else 0.0)
		style.border_width_bottom = 1
		style.border_color = Color(0.25, 0.25, 0.20, 0.25)
		button.add_theme_stylebox_override(state, style)
	button.mouse_entered.connect(AudioManager.play_ui_hover)
	button.pressed.connect(AudioManager.play_ui_select)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _show_main() -> void:
	main_page.show()
	settings_page.hide()
	confirm_page.hide()
	_confirm_action = Callable()
	_resume_button.grab_focus()

func _show_settings() -> void:
	main_page.hide()
	confirm_page.hide()
	settings_page.show()
	volume_slider.set_value_no_signal(UserSettings.volume)
	fullscreen_button.set_pressed_no_signal(UserSettings.fullscreen)
	volume_slider.grab_focus()


func _return_to_checkpoint() -> void:
	var player := get_parent().get_node_or_null("Player")
	resume()
	if player != null:
		# 等暂停退出后的物理帧再查询安全位置、移动角色。
		_return_after_pause.call_deferred(player)


func _return_after_pause(player: Node) -> void:
	await get_tree().physics_frame
	if is_instance_valid(player) and not player.return_to_checkpoint():
		GameState.notice.emit("请先完成当前对话或开场引导")

func _ask_leave(quit_game: bool) -> void:
	main_page.hide()
	settings_page.hide()
	confirm_page.show()
	_confirmation.text = "将从最近的存档点继续，尚未保存的进度不会保留。" if GameState.has_valid_save() else "目前尚无存档，离开后需要重新开始。"
	_confirm_action = _quit if quit_game else _return_to_title
	# 默认聚焦取消，避免连续确认误退出。
	(confirm_page.get_child(confirm_page.get_child_count() - 1) as Button).grab_focus()

func _return_to_title() -> void:
	UserSettings.save_now()
	_leaving = true
	GameState.menu_launch_action = ""
	resume()
	var error := get_tree().reload_current_scene()
	if error != OK:
		_leaving = false
		open()
		GameState.notice.emit("返回菜单失败，请重试")

func _quit() -> void:
	UserSettings.save_now()
	get_tree().quit()

func _exit_tree() -> void:
	if _owns_pause and is_inside_tree(): resume()
