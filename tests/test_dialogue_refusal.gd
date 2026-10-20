extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state: Node = root.get_node("GameState")
	state.reset()
	# Load the same imported resource as the game, including its response tags.
	var resource = load("res://dialogue/dia/companion.dialogue")
	assert(resource != null)
	var player: Node = load("res://scenes/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var deaths := [0]
	player.died.connect(func(): deaths[0] += 1)
	var companion: Node = load("res://prefabs/creatures/companion.tscn").instantiate()
	companion.dialogue_resource = resource
	root.add_child(companion)
	companion._on_body_entered(player)
	await create_timer(0.1).timeout
	var balloon: Node = get_first_node_in_group("dialogue_balloon")
	assert(balloon != null)
	for step in 8:
		if balloon.dialogue_label.is_typing: balloon.dialogue_label.skip_typing()
		await process_frame
		if balloon.dialogue_line.responses.size() > 0: break
		balloon.next(balloon.dialogue_line.next_id)
		await process_frame
	assert(balloon.dialogue_line.responses.size() == 3)
	var refusal = balloon.dialogue_line.responses[2]
	assert(refusal.text == "不要" and refusal.has_tag("shake"))
	var item: Control
	for response_item in balloon.responses_menu.get_menu_items():
		if response_item.get_meta("response") == refusal: item = response_item
	assert(item != null)
	var original: Vector2 = item.position
	var line = balloon.dialogue_line
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	balloon.responses_menu._on_response_gui_input(click, item, refusal)
	balloon.responses_menu._on_response_gui_input(click, item, refusal)
	assert(balloon._response_shakes.size() == 1)
	await create_timer(0.05).timeout
	assert(absf(item.position.x - original.x) > 0.5, "Refusal must visibly move while shaking")
	await create_timer(0.3).timeout
	assert(item.position.is_equal_approx(original))
	assert(balloon.dialogue_line == line and balloon.responses_menu.visible)
	assert(deaths[0] == 0 and not companion.is_recruited() and not state.companion_recruited)
	# Another response still works after refusing; completion then recruits normally.
	balloon._on_responses_menu_response_selected(line.responses[0])
	await process_frame
	if balloon.dialogue_label.is_typing: balloon.dialogue_label.skip_typing()
	await process_frame
	balloon.next(balloon.dialogue_line.next_id)
	await create_timer(1.0).timeout
	assert(state.companion_recruited and companion.is_recruited())
	assert(deaths[0] == 0)
	print("REFUSAL_SHAKE_OK: mouse click, no death/no recruit, no advance, repeated click safety, exact position restore, acceptance recruits")
	quit()
