extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var state := root.get_node("GameState")
	state.reset()
	state.companion_recruited = true
	state.played_story["shrine"] = true
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	root.add_child(game)
	current_scene = game
	state.debug_save_disabled = true
	await create_timer(1.0).timeout
	game.player.receive_element("freeze", 1)
	game.player.receive_element("burn", 1)
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	var path := "res://output/color-wheel-hint-preview.png"
	var result := root.get_texture().get_image().save_png(path)
	print("COLOR_WHEEL_SCREENSHOT: ", result)
	quit(result)
