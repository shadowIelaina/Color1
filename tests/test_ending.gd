extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").contains(".godot/menu-save-test-user"))
	var state := root.get_node("GameState")
	state.reset()
	state.companion_recruited = true
	state.switches["boss_defeated"] = true
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	game.start_room = "res://scenes/boss_room.tscn"
	root.add_child(game)
	current_scene = game
	state.debug_save_disabled = true
	await create_timer(1.2).timeout
	var manager := root.get_node("SceneManager")
	state.checkpoint_scene = "res://scenes/boss_room.tscn"
	state.checkpoint_pos = manager.current_room.get_entrance_position("spawn")
	state.debug_save_disabled = false
	var portal: Node = manager.current_room.get_node("ReturnPortal")
	assert(portal.get_script().resource_path.ends_with("ending_portal.gd"))
	state.switches["boss_defeated"] = false
	portal._teleport()
	assert(get_first_node_in_group("ending") == null, "Ending must remain locked before boss victory")
	state.switches["boss_defeated"] = true
	var music_bus := AudioServer.get_bus_index("Music")
	var music_db := AudioServer.get_bus_volume_db(music_bus)
	game.player.global_position = portal.global_position
	portal._on_body_entered(game.player)
	for i in 180:
		if get_first_node_in_group("ending") != null: break
		await process_frame
	var ending: Node = get_first_node_in_group("ending")
	assert(ending != null and paused and state.is_switch_on("ending_seen"))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.SAVE_PATH))
	assert(saved.switches.ending_seen and saved.switches.boss_defeated)
	assert(manager.current_room_scene == "res://scenes/boss_room.tscn", "Portal must trigger ending instead of returning to level 4")
	portal._teleport()
	await process_frame
	assert(get_nodes_in_group("ending").size() == 1, "Portal must not duplicate ending")
	var recorded: Array[String] = []
	ending.stage_changed.connect(func(stage: String): recorded.append(stage))
	await create_timer(2.2).timeout
	assert(ending._material.get_shader_parameter("inversion") == 1.0)
	if "--capture-ending" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/ending-inversion.png")
	await create_timer(4.9).timeout
	assert(ending._narration.visible_ratio == 1.0)
	assert(ending._narration.text == "应该结束了吧")
	if "--capture-ending" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/ending-narration.png")
	for i in 140:
		if ending.stage == "finished": break
		await create_timer(0.1).timeout
	assert(ending.stage == "finished" and ending._buttons.visible)
	assert(recorded == ["inversion", "narration", "to_be_continued", "finished"])
	assert(paused and ending._title.text == "未完待续")
	if "--capture-ending" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/ending-final.png")
	ending.queue_free()
	await process_frame
	assert(not paused and is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_db))
	# 实际执行结尾的返回标题按钮，确认不会把主菜单卡在旧结局里。
	ending = load("res://scripts/ending_sequence.gd").new()
	game.add_child(ending)
	ending.start(portal.global_position)
	ending._return_to_title()
	await create_timer(1.5).timeout
	assert(current_scene != game and get_first_node_in_group("ending") == null)
	assert(paused and state.is_switch_on("ending_seen"))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_db))
	print("ENDING_OK: victory gate, single trigger, completion saved, inversion, narration, to be continued, buttons, audio/pause cleanup, actual return to title")
	quit()
