extends SceneTree
func _initialize():
	run.call_deferred()
func check(ok, message):
	if not ok:
		push_error(message)
		quit(1)
	return ok
func run():
	var gs=root.get_node("GameState")
	gs.reset()
	gs.companion_recruited=true
	gs.played_story["shrine"]=true
	var game=load("res://scenes/game.tscn").instantiate()
	game.show_main_menu=false
	game.start_room="res://scenes/level_4.tscn"
	root.add_child(game)
	current_scene=game
	gs.debug_save_disabled=true
	await create_timer(1.0).timeout
	var manager=root.get_node("SceneManager")
	var player=game.player
	for entrance in ["spawn","","missing_entrance"]:
		manager.change_room("res://scenes/level_4.tscn",entrance)
		await create_timer(0.8).timeout
		if not check(player.is_safe_respawn_position(player.global_position),"Unsafe entrance: "+entrance): return
		if not check(player.global_position.distance_to(Vector2(0,600))<2,"Must arrive at authored spawn"): return
		var before=player.global_position
		Input.action_press("move_right")
		await create_timer(0.2).timeout
		Input.action_release("move_right")
		if not check(player.global_position.x>before.x+80,"Player must be able to walk away"): return
		await create_timer(0.4).timeout
	gs.checkpoint_scene="res://scenes/level_4.tscn"
	gs.checkpoint_pos=Vector2.ZERO
	if not check(manager.resume_from_checkpoint(),"Must resume old checkpoint"):return
	await create_timer(0.8).timeout
	if not check(player.is_safe_respawn_position(player.global_position),"Old checkpoint inside altar must recover"):return
	if not check(player.global_position.distance_to(Vector2(0,600))<2,"Old checkpoint should recover at spawn"):return
	var altar=manager.current_room.get_node("BossAltar")
	gs.health_upgrades={"heart:a":1,"heart:b":1,"heart:c":1}
	altar.activated_dialogue=null
	altar.interact()
	altar.interact()
	if not check(altar.reward_claimed,"Altar reward must still work"):return
	print("LEVEL4_ARRIVAL_OK: spawn, empty/missing entrance, real movement, old overlapping checkpoint recovery, altar reward")
	quit()
