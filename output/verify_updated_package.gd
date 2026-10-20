extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node("GameState")
	gs.reset()
	gs.companion_recruited = true
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	root.add_child(game)
	current_scene = game
	gs.debug_save_disabled = true
	await create_timer(1.0).timeout
	assert(not FileAccess.file_exists("res://tests/test_opening_guide.gd"), "Tests must stay outside distribution")
	assert(not FileAccess.file_exists("res://output/color-quantity-hint-preview.png"), "Preview assets must stay outside distribution")
	assert(not root.has_node("_mcp_game_helper"), "Editor runtime helper must be excluded")
	var manager := root.get_node("SceneManager")
	var room: Node = manager.current_room
	var player: Node = game.player
	assert(room.get_node("OpeningGuidePath/BeforeBlueIce").global_position == Vector2(4864, -2560))
	var cp: Node = room.get_node("Checkpoint2")
	# 关卡存档区可以跨越岸边，按玩家实际经过的稳定地面记录。
	var collision: Node = cp.get_node("Collision")
	var checkpoint_pos := Vector2.INF
	for x in range(-7, 8):
		for y in range(-3, 4):
			var candidate: Vector2 = collision.to_global(Vector2(x * 16.0, y * 32.0))
			if player.is_safe_respawn_position(candidate):
				checkpoint_pos = candidate
				break
		if checkpoint_pos != Vector2.INF: break
	if checkpoint_pos == Vector2.INF:
		push_error("Current item-route checkpoint has no safe ground in trigger area")
		quit(1)
		return
	player.global_position = checkpoint_pos
	cp._activate(player)
	assert(gs.checkpoint_pos == checkpoint_pos)
	player.receive_element("freeze", 3)
	await create_timer(0.8).timeout
	assert(gs.hints.get("tutorial_color_quantity", false), "First color quantity tutorial must be packaged")
	player._color_tutorial_wait = 0.0
	player.receive_element("burn", 1)
	await create_timer(0.8).timeout
	assert(gs.hints.get("tutorial_color_wheel", false), "Second color wheel tutorial must be packaged")
	var water: Node
	for node in get_nodes_in_group("colorable"):
		if node.get_script() != null and node.get_script().resource_path.ends_with("water_cell.gd"):
			water = node
			break
	assert(water != null)
	player.steal_element("freeze", 1)
	assert(water.apply_color(Color.BLUE, "蓝"))
	player.register_placed_color(water)
	var trap: Node = room.get_node("Traps/Trap6")
	player.global_position = trap.global_position
	player._invincible_until = 0
	trap._on_body_entered(player)
	assert(player.global_position == gs.checkpoint_pos and not water.is_frozen())
	assert(player.palette_snapshot().inventory.freeze == 3)
	assert(root.get_node("AudioManager").EVENT_STREAMS.size() == 7)
	print("UPDATED_PACKAGE_OK: packed resources, excluded tests/previews/editor helper, authored blue ice route, route checkpoint, first/second color tutorials, iron ball death and exact ice refund, new audio")
	quit()
