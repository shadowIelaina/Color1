extends SceneTree
## Run only with APPDATA inside .godot/menu-save-test-user.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").contains(".godot/menu-save-test-user"))
	var state := root.get_node("GameState")
	var manager := root.get_node("SceneManager")
	state.reset()
	state.companion_recruited = true
	state.health_upgrades = {"heart:release_red": 1, "heart:release_blue": 1}
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	game.start_room = "res://scenes/level_4.tscn"
	root.add_child(game)
	current_scene = game
	await create_timer(1.5).timeout
	var altar: Node = get_first_node_in_group("altar")
	assert(altar != null)
	altar.interact()
	assert(not state.is_switch_on("boss_altar"), "Two hearts must not unlock the boss")
	state.health_upgrades["heart:release_green"] = 1
	altar.interact()
	assert(state.is_switch_on("boss_altar"))
	var portal: Node = manager.current_room.get_node("BossPortal")
	await physics_frame
	assert(portal.monitoring and portal.get_node("Visual").visible)
	portal._on_body_entered(game.player)
	await create_timer(1.5).timeout
	assert(manager.current_room_scene == "res://scenes/boss_room.tscn")
	assert(get_nodes_in_group("companion").size() == 1)
	var boss: Node = manager.current_room.get_node("BossEncounter/Boss")
	assert(boss != null)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = game.player.get_node("Collision").shape
	query.transform = game.player.get_node("Collision").global_transform
	query.collision_mask = 2
	query.exclude = [game.player.get_rid()]
	var overlaps: Array = game.player.get_world_2d().direct_space_state.intersect_shape(query)
	assert(overlaps.is_empty(), "Boss entrance must not overlap walls")
	game.player._die()
	assert(game.player.global_position == manager.current_room.get_entrance_position("spawn"))
	game.player._invincible_until = Time.get_ticks_msec() + 60000
	boss.take_damage(100000.0)
	await create_timer(1.0).timeout
	assert(state.is_switch_on("boss_defeated"))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.SAVE_PATH))
	assert(saved.switches.get("boss_defeated", false), "Victory must be saved before returning to a checkpoint")
	var back: Node = manager.current_room.get_node("ReturnPortal")
	assert(back.monitoring and back.get_node("Visual").visible)
	back._on_body_entered(game.player)
	await create_timer(1.5).timeout
	assert(manager.current_room_scene == "res://scenes/level_4.tscn")
	print("BOSS_RETURN_CHECK actual=", game.player.global_position, " entrance=", manager.current_room.get_entrance_position("boss_return"))
	assert(game.player.global_position == manager.current_room.get_entrance_position("boss_return"))
	assert(get_nodes_in_group("companion").size() == 1)
	state.save_game()
	assert(state.load_game() and state.is_switch_on("boss_defeated"))
	manager.change_room("res://scenes/boss_room.tscn", "spawn")
	await create_timer(1.5).timeout
	assert(manager.current_room.get_node_or_null("BossEncounter/Boss") == null)
	assert(manager.current_room.get_node("ReturnPortal").monitoring)
	print("RELEASE_FLOW_OK: altar requirements, real portal, boss spawn/death/victory/return, save and reentry")
	quit()
