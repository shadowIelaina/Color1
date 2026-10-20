extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _count(player: Node, element: String) -> int:
	return int(player.palette_snapshot().inventory.get(element, 0))


func _run() -> void:
	var gs := root.get_node("GameState")
	gs.reset()
	gs.companion_recruited = true
	gs.played_story["shrine"] = true
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_main_menu = false
	game.get_node("Player").set_script(load("res://tests/fixtures/paint_test_player.gd"))
	root.add_child(game)
	current_scene = game
	gs.debug_save_disabled = true
	await create_timer(1.0).timeout
	var player: Node = game.player
	var manager := root.get_node("SceneManager")
	var room: Node = manager.current_room
	var checkpoint: Node = room.get_node("Checkpoint_ItemRoute")
	if not _check(player.is_safe_respawn_position(checkpoint.global_position), "New route checkpoint must be on clear stable ground"): return
	# 从存档区侧面经过：记录身体实际经过点，而不是节点中心。
	player.global_position = checkpoint.global_position + Vector2(-80, 0)
	await physics_frame
	checkpoint._activate(player)
	var saved: Vector2 = gs.checkpoint_pos
	if not _check(saved == player.global_position and saved != checkpoint.global_position, "Checkpoint must record actual safe position"): return
	if "--capture-checkpoint" in OS.get_cmdline_user_args():
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/checkpoint-route-preview.png")
	var original_source: Node = room.get_node("IceBlock")
	var water: Node
	for obj in get_nodes_in_group("colorable"):
		if obj.get_script() != null and obj.get_script().resource_path.ends_with("water_cell.gd") and not obj.shallow:
			if water == null or obj.global_position.distance_to(saved) < water.global_position.distance_to(saved):
				water = obj
	if not _check(water != null, "First level must contain deep water"): return
	player.global_position = water.global_position + Vector2(-512, 0)
	player.receive_element("freeze", 3)
	player._select_element("freeze")
	player.test_target = water
	player._grant()
	await create_timer(1.0).timeout
	if not _check(water.is_frozen() and _count(player, "freeze") == 2, "Companion must place and register one blue seed"): return
	# 模拟在关键道具路线上被真实铁球撞死。
	player.global_position = room.get_node("Traps/Trap6").global_position
	player._invincible_until = 0
	room.get_node("Traps/Trap6")._on_body_entered(player)
	if not _check(player.global_position == saved, "Iron ball death must return to route checkpoint"): return
	if not _check(not water.is_frozen() and _count(player, "freeze") == 3, "Death must melt placed ice and refund exactly one seed"): return
	if not _check(original_source.has_color(), "Recovery must not collect untouched level source"): return
	player.reclaim_placed_colors()
	if not _check(_count(player, "freeze") == 3, "Repeated recovery must not duplicate seeds"): return
	# 水面旧位置不能阻止存档点强制回收；普通吸收仍保留踩冰保护。
	player.steal_element("freeze", 1)
	water.apply_color(Color.BLUE, "蓝")
	player.register_placed_color(water)
	player.global_position = water.global_position
	if not _check(player.return_to_checkpoint(), "Manual checkpoint return must be available"): return
	if not _check(player.global_position == saved and not water.is_frozen() and _count(player, "freeze") == 3, "Manual return must recover ice even when standing on it"): return
	# 冻结种子容器只收封层，绝不取走里面的原有蓝种子。
	var container: Node = load("res://scripts/seed_container.gd").new()
	container.freeze_seeds = 4
	container.position = saved + Vector2(500, 0)
	room.add_child(container)
	player.steal_element("freeze", 1)
	container.apply_color(Color.BLUE, "蓝")
	player.register_placed_color(container)
	player.reclaim_placed_colors()
	if not _check(container._store.freeze == 4 and not container._frozen and _count(player, "freeze") == 3, "Recovery must not drain source container"): return
	# 正常吸收已回来的蓝色不能再被记账；容器还有货也不能误收。
	player.steal_element("freeze", 1)
	container.apply_color(Color.BLUE, "蓝")
	player.register_placed_color(container)
	var info: Dictionary = container.absorb_color()
	player.settle_placed_absorption(container, info)
	player.receive_element(info.element, 1)
	player.reclaim_placed_colors()
	if not _check(container._store.freeze == 4 and _count(player, "freeze") == 3, "Normal absorption must settle recovery ledger"): return
	# 青色混合态一次吸收自行退还蓝绿，不能重复记账。
	var colored: Node = load("res://color_change/colorable_base.gd").new()
	colored.position = saved + Vector2(1000, 0)
	room.add_child(colored)
	player.receive_element("grow", 1)
	player.steal_element("freeze", 1)
	colored.apply_color(Color.BLUE, "蓝")
	player.register_placed_color(colored)
	player.steal_element("grow", 1)
	colored.apply_color(Color.GREEN, "绿")
	player.register_placed_color(colored)
	player.reclaim_placed_colors()
	if not _check(not colored.has_color() and _count(player, "freeze") == 3 and _count(player, "grow") == 1, "Mixed colors must refund once each"): return
	# 跟班飞行中尚未落地的预留颜色也必须退回。
	player.global_position = water.global_position + Vector2(-512, 0)
	player._select_element("freeze")
	player.test_target = water
	player._grant()
	var pause_menu: Node = get_first_node_in_group("pause_menu")
	pause_menu.open()
	if not _check(paused, "Pause menu must pause before return"): return
	if "--capture-checkpoint" in OS.get_cmdline_user_args():
		await create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/checkpoint-pause-preview.png")
	pause_menu._return_to_checkpoint()
	await create_timer(1.0).timeout
	if not _check(not paused and player.global_position == saved and not water.is_frozen() and _count(player, "freeze") == 3, "Pause return must cancel and refund pending paint"): return
	# 离开房间时回收，避免目标被卸载后失去颜色。
	player.steal_element("freeze", 1)
	water.apply_color(Color.BLUE, "蓝")
	player.register_placed_color(water)
	manager.change_room("res://scenes/level_4.tscn", "spawn")
	await create_timer(1.0).timeout
	if not _check(_count(player, "freeze") == 3 and player._placed_colors.is_empty(), "Room unload must recover colors before freeing targets"): return
	# 主动返回支持另一关的最近存档点。
	gs.checkpoint_scene = "res://scenes/level_1.tscn"
	gs.checkpoint_pos = saved
	if not _check(player.return_to_checkpoint(), "Cross-scene checkpoint return must start"): return
	await create_timer(1.0).timeout
	if not _check(manager.current_room_scene == gs.checkpoint_scene and player.global_position == saved, "Cross-scene return must use saved position"): return
	print("CHECKPOINT_RECOVERY_OK: stable route checkpoint, actual crossing position, real iron ball death, ice refund, manual return, untouched sources, normal absorption, mixed colors, pending orders, no duplication")
	quit()
