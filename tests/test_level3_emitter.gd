extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _run() -> void:
	var state := root.get_node("GameState")
	state.reset()
	state.companion_recruited = true
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	game.start_room = "res://scenes/level_3.tscn"
	root.add_child(game)
	current_scene = game
	state.debug_save_disabled = true
	await create_timer(0.8).timeout
	game.player.set_physics_process(false)
	game.player._invincible_until = Time.get_ticks_msec() + 60000
	var emitters := get_nodes_in_group("parry_emitter")
	if not _check(emitters.size() == 6, "Level 3 must test all six real emitters"): return
	for emitter in emitters: emitter.set_physics_process(false)
	for emitter in emitters:
		var shots: Array[Node] = []
		emitter.projectile_fired.connect(func(projectile: Node): shots.append(projectile))
		emitter._t = emitter.fire_interval
		emitter._windup = 0.0
		game.player.global_position = emitter.global_position + Vector2(0, emitter.activate_radius + 1024)
		emitter.set_physics_process(true)
		await create_timer(0.3).timeout
		if not _check(shots.is_empty(), "Emitter must stay idle outside activation radius"): return
		game.player.global_position = emitter.global_position + Vector2(0, 900)
		await create_timer(0.45).timeout
		if not _check(shots.size() == 1 and is_instance_valid(shots[0]), "Automatic shot must survive its own muzzle: " + str(emitter.name)): return
		var bullet: Node = shots[0]
		if not _check(bullet.global_position.y > emitter.global_position.y + emitter.muzzle_offset + 30, "Bullet must actually advance toward player"): return
		if not _check(bullet.z_index > 4000 and bullet.get_collision_exceptions().has(emitter), "Bullet must be visible and ignore its source before reflection"): return
		if emitter == emitters[0]:
			await create_timer(emitter.fire_interval + emitter.windup_time + 0.2).timeout
			if not _check(shots.size() >= 2, "Emitter must continue firing periodically"): return
		emitter.set_physics_process(false)
		for projectile in shots:
			if is_instance_valid(projectile): projectile.queue_free()
		await physics_frame
	# 反弹回原发射器，验证出膛豁免不会变成永久无敌。
	var source: Node = emitters[0]
	game.player.global_position = source.global_position + Vector2(0, 900)
	var before: int = source.health
	var reflected: Node = source.fire()
	await create_timer(0.3).timeout
	if not _check(is_instance_valid(reflected), "Bullet must survive until reflection"): return
	if not _check(reflected.parry(Vector2.UP, game.player), "Bullet must remain parryable"): return
	if not _check(not reflected.get_collision_exceptions().has(source), "Reflection must remove source collision exception"): return
	await create_timer(0.6).timeout
	if not _check(source.health == before - 1, "Reflected bullet must damage original emitter"): return
	print("LEVEL3_EMITTER_OK: six emitters, activation range, real automatic shots, projectile travel, periodic fire, visibility, self-collision prevention, reflected hit on original source")
	quit()
