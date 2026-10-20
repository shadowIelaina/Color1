extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state := root.get_node("GameState")
	state.reset()
	state.hints["tutorial_color_quantity"] = true
	state.debug_save_disabled = true
	var notices: Array[String] = []
	state.notice.connect(func(message: String): notices.append(message))
	var player: Node = load("res://scenes/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.receive_element("freeze", 1)
	player.receive_element("freeze", 2)
	await create_timer(0.7).timeout
	assert(notices.is_empty(), "More of the same color must not trigger tutorial")
	player.steal_element("freeze", 3)
	player.opening_input_locked = true
	player.receive_element("burn", 1)
	await create_timer(0.7).timeout
	assert(notices.is_empty(), "Tutorial must wait until input is available")
	player.opening_input_locked = false
	await create_timer(0.7).timeout
	assert(notices.size() == 1 and notices[0].contains("鼠标滚轮"), "First second distinct color must teach wheel even if the first was spent")
	player.receive_element("grow", 1)
	player.refund_element("freeze", 1)
	await create_timer(0.7).timeout
	assert(notices.size() == 1, "Third color and returned seeds must not repeat tutorial")
	player.queue_free()
	await process_frame
	player = load("res://scenes/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.receive_element("burn", 1)
	await create_timer(0.7).timeout
	assert(notices.size() == 1, "Recreating player must preserve tutorial completion")
	print("COLOR_WHEEL_HINT_OK: distinct acquisition, spent first color, delayed until playable, no repeats after third color/refund/player recreation")
	quit()
