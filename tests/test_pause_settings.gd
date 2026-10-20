extends SceneTree
var settings: Node

func _initialize() -> void:
	_run.call_deferred()

func _esc() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").contains(".godot/menu-save-test-user"))
	settings = root.get_node("UserSettings")
	var mode := str(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else "verify"
	if mode == "write":
		settings.set_volume(0.37)
		settings.set_fullscreen(true)
		settings.save_now()
		print("SETTINGS_WRITE_OK")
		quit()
		return
	if mode != "visual":
		assert(is_equal_approx(settings.volume, 0.37) and settings.fullscreen, "Fresh process must restore settings")
		assert(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.37))
	settings.set_fullscreen(false)
	var state := root.get_node("GameState")
	state.reset()
	assert(is_equal_approx(settings.volume, 0.37) or mode == "visual", "New game state must not reset settings")
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	root.add_child(game)
	current_scene = game
	await create_timer(1.0).timeout
	var menu: Node = get_first_node_in_group("pause_menu")
	assert(menu != null and not menu.overlay.visible)
	await _esc()
	assert(paused and menu.overlay.visible and menu._owns_pause)
	var position: Vector2 = game.player.global_position
	await create_timer(0.2).timeout
	assert(game.player.global_position == position)
	menu._show_settings()
	assert(menu.settings_page.visible)
	menu.volume_slider.value = 0.24
	await create_timer(0.3).timeout
	var config := ConfigFile.new()
	assert(config.load(settings.PATH) == OK)
	assert(is_equal_approx(float(config.get_value("audio", "volume")), 0.24))
	assert(config.get_value("display", "fullscreen") == false)
	await _esc()
	assert(paused and menu.main_page.visible and not menu.settings_page.visible)
	menu._ask_leave(true)
	assert(menu.confirm_page.visible)
	await _esc()
	assert(paused and menu.main_page.visible)
	await _esc()
	assert(not paused and not menu.overlay.visible)
	# A pause owned by another system (e.g. the title) must not be undone.
	paused = true
	await _esc()
	assert(paused and not menu._owns_pause)
	paused = false
	await _esc()
	if mode == "visual":
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/pause-preview.png")
	menu._ask_leave(false)
	menu._confirm_action.call()
	await create_timer(1.5).timeout
	assert(paused and get_first_node_in_group("pause_menu") != menu)
	var title: Node
	for child in current_scene.get_children():
		if child.get_script() == load("res://scripts/main_menu.gd"): title = child
	assert(title != null)
	title._toggle_settings()
	var found_volume := false
	for child in title._settings.get_children():
		if child is HSlider:
			found_volume = is_equal_approx(child.value, 0.24)
	assert(found_volume, "Title and pause settings must share the same values")
	settings.save_now()
	print("PAUSE_SETTINGS_OK: cross-process persistence, real Esc input, pause/resume, settings save while paused, cancel exit, title guard, return to title")
	quit()
