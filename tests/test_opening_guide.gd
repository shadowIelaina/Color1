extends SceneTree
## Run with --headless --path . --script tests/test_opening_guide.gd.

func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _close_dialogue() -> void:
	var found := false
	for i in 180:
		var balloon := get_first_node_in_group("dialogue_balloon")
		if balloon == null:
			if found:
				await create_timer(0.1).timeout
				return
		else:
			found = true
			if is_instance_valid(balloon.dialogue_line) and balloon.dialogue_label.dialogue_line != null and not balloon._closing:
				if balloon.dialogue_label.is_typing:
					balloon.dialogue_label.skip_typing()
				elif balloon.is_waiting_for_input:
					balloon.next(balloon.dialogue_line.next_id)
		await create_timer(0.1).timeout
	_check(false, "Expected dialogue to finish")


func _run() -> void:
	var state := root.get_node("GameState")
	state.reset()
	var compiled := DMCompiler.compile_string(FileAccess.get_file_as_string("res://dialogue/dia/prologue.dialogue"), "res://dialogue/dia/prologue.dialogue")
	if not _check(compiled.errors.is_empty(), "Opening dialogue must compile"): return
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	root.add_child(game)
	current_scene = game
	state.debug_save_disabled = true
	await create_timer(0.4).timeout
	var guide: Node = game.get_node("OpeningGuide")
	if not _check(guide.phase == guide.Phase.WAKING and game.player.opening_input_locked, "Wake must lock input"): return
	if not _check(not game.get_node("HUD").visible and not guide._companion.visible, "Wake must hide HUD and companion"): return
	await create_timer(2.5).timeout
	await _close_dialogue()
	if not _check(guide.phase == guide.Phase.MOVING and not game.player.opening_input_locked, "Finished wake must allow movement"): return
	if not _check(state.played_story.has("opening_woke"), "Wake completion must be remembered"): return
	guide._idle = 8.1
	await create_timer(0.05).timeout
	if not _check(guide._wisp.visible and not state.companion_recruited, "Idle hint must guide without auto recruiting"): return
	if "--capture-opening" in OS.get_cmdline_user_args():
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/opening-movement.png")
	Input.action_press("move_up")
	for i in 240:
		await physics_frame
		if guide.phase == guide.Phase.MEETING: break
	Input.action_release("move_up")
	if not _check(guide.phase == guide.Phase.MEETING, "Actual walking must trigger meeting"): return
	await _close_dialogue()
	if not _check(state.companion_recruited and guide.phase == guide.Phase.NORTH, "Meeting must recruit companion and point north"): return
	if not _check(not game.player.opening_input_locked and game.get_node("HUD").visible, "Meeting must restore input and HUD"): return
	if not _check(guide._guide_points.back() == game.get_node("RoomContainer/Level1/OpeningGuidePath/BeforeBlueIce").global_position, "Guide endpoint must be the authored blue ice passage"): return
	var before_flight: Vector2 = guide._companion.global_position
	if not _check(guide._companion.state == guide._companion.State.GUIDING, "Guide flight must own a dedicated companion state"): return
	if not _check(guide._companion.z_index > 4000 and guide._companion.z_index < 4096, "Flying spirit must remain above grass and below darkness"): return
	await create_timer(1.35).timeout
	if not _check(guide._companion.global_position.distance_to(before_flight) > 400.0, "North flight must visibly move companion"): return
	if not _check(guide._companion.global_position.distance_to(guide._north_goal) < 8.0, "Companion must actually fly to north goal"): return
	var waiting_position: Vector2 = guide._companion.global_position
	await create_timer(0.4).timeout
	if not _check(guide._companion.global_position.distance_to(waiting_position) < 8.0, "Companion must wait for player"): return
	if "--capture-opening" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/opening-north-wait.png")
	var player_start: Vector2 = game.player.global_position
	game.player.global_position = guide._north_goal + Vector2(1024, 0)
	await create_timer(0.1).timeout
	if not _check(guide.phase == guide.Phase.NORTH, "Matching north height far sideways must not finish guide"): return
	game.player.global_position = player_start
	for i in 1500:
		if guide.phase == guide.Phase.OFF: break
		var direction: Vector2 = guide._north_goal - game.player.global_position
		for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
		if direction.length() > 80.0:
			if absf(direction.x) > 60.0: Input.action_press("move_right" if direction.x > 0 else "move_left")
			if absf(direction.y) > 60.0: Input.action_press("move_down" if direction.y > 0 else "move_up")
		await physics_frame
	for action in ["move_left", "move_right", "move_up", "move_down"]: Input.action_release(action)
	await create_timer(0.1).timeout
	if not _check(guide.phase == guide.Phase.OFF and guide._companion.is_recruited(), "Reaching guide must restore following"): return
	if not _check(game.player.global_position.distance_to(guide._guide_points.back()) < 256.0, "Player must reach the actual blue ice passage"): return
	await create_timer(0.2).timeout
	if root.get_node("StoryDirector").is_busy(): await _close_dialogue()
	if "--capture-opening" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/opening-blue-passage.png")
	var followed_from: Vector2 = guide._companion.global_position
	Input.action_press("move_down")
	await create_timer(0.5).timeout
	Input.action_release("move_down")
	await create_timer(0.4).timeout
	if not _check(guide._companion.global_position.distance_to(followed_from) > 100.0, "After greeting, companion must actually follow walking player"): return
	guide._on_room_changed("level_1")
	if not _check(guide.phase == guide.Phase.OFF, "Completed opening must not replay"): return
	# 玩家提前跑到目标，也不能截断小白的出发动画。
	guide.phase = guide.Phase.MEETING
	guide._begin_north()
	game.player.global_position = guide._north_goal
	await create_timer(0.1).timeout
	if not _check(guide.phase == guide.Phase.NORTH and not guide._companion.is_waiting_for_guide(), "Early arrival must not cancel north flight"): return
	await create_timer(1.6).timeout
	if not _check(guide.phase == guide.Phase.NORTH and guide._guide_point_index == 1, "Early arrival must advance to next authored waypoint after flight"): return
	guide._finish()
	# 中途离开再回来：醒来对白不重复，移动教学仍可继续。
	state.companion_recruited = false
	state.played_story.erase("opening_complete")
	guide._on_room_changed("level_1")
	await create_timer(0.05).timeout
	if not _check(guide.phase == guide.Phase.MOVING, "Returning after wake must resume movement guide"): return
	guide._on_room_exited("level_1")
	if not _check(not game.player.opening_input_locked and not guide._white.visible and guide._companion.visible, "Leaving must clean up guide and locks"): return
	print("OPENING_GUIDE_OK: dialogue compile, white wake/input lock, movement, idle hint, meeting, visible north flight, waiting, proximity, actual following, no replay")
	quit()
