extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").contains(".godot/menu-save-test-user"))
	var state: Node = root.get_node("GameState")
	state.new_game()
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.debug_boss_test = false
	game.show_main_menu = false
	game.start_room = "res://scenes/level_4.tscn"
	root.add_child(game)
	current_scene = game
	await create_timer(0.8).timeout
	assert(state.checkpoint_scene == "res://scenes/level_4.tscn")
	assert(state.checkpoint_pos == Vector2(0, 600) and state.has_valid_save())
	var hints: Array[String] = []
	state.hint.connect(func(message: String): hints.append(message))
	var door: Node2D = load("res://prefabs/rooms/room_door.tscn").instantiate()
	door.required_key_id = "checkpoint_test_key"
	door.position = Vector2(10000, 10000)
	root.add_child(door)
	door._on_body_entered(game.player)
	assert(not door.is_open and hints.is_empty())
	state.add_key("checkpoint_test_key")
	door._on_body_entered(game.player)
	assert(door.is_open and not state.has_key("checkpoint_test_key"))
	assert(hints.is_empty())
	state.new_game()
	print("LEVEL4_CHECKPOINT_OK: spawn auto-save and valid resume data; RoomDoor missing-key hint suppressed, key lock still works")
	quit()
