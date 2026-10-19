extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state := root.get_node("GameState")
	state.reset()
	var hud: Node = load("res://prefabs/ui/hud.tscn").instantiate()
	root.add_child(hud)
	var player := Node2D.new()
	player.add_to_group("player")
	root.add_child(player)
	var key: Node = load("res://prefabs/items/interaction/key.tscn").instantiate()
	key.key_id = "collection_test_key"
	key.key_name = "庭院钥匙"
	root.add_child(key)
	key._on_body_entered(player)
	await process_frame
	var collection: Control
	for node in hud.get_children():
		if node.get_script() == load("res://scripts/collection_ui.gd"): collection = node
	assert(collection != null and collection.grid.get_child_count() == 1)
	assert(collection.presenting and collection.card.visible)
	assert(not hud.status_label.visible)
	assert(state.item_art["key:collection_test_key"].texture.ends_with("钥匙tm.png"))
	state.set_checkpoint("res://scenes/level_1.tscn", Vector2.ZERO)
	assert(state.load_game())
	assert(state.item_art["key:collection_test_key"].title == "庭院钥匙")
	assert(state.consume_key("collection_test_key"))
	assert(collection.grid.get_child_count() == 0 and not collection.shelf.visible)
	var prop: Node = load("res://prefabs/items/interaction/item_pickup.tscn").instantiate()
	prop.prop_id = "test_prop"
	prop.item_name = "手绘信物"
	prop.inventory_icon = load("res://art/picture_boluo/钥匙tm.png")
	root.add_child(prop)
	prop._on_body_entered(player)
	assert(state.has_prop("test_prop") and collection.grid.get_child_count() == 1)
	assert(collection.pending.size() == 1)
	var heart: Node = load("res://prefabs/items/interaction/red_heart.tscn").instantiate()
	heart.prop_id = "test_heart"
	root.add_child(heart)
	assert(state.item_art["prop:test_heart"].title == heart.display_name)
	assert(state.item_art["prop:test_heart"].texture != "")
	# Rebuild a preview with several collected items, using existing art.
	for i in 3:
		var id := "preview_%d" % i
		state.register_key(id, ["庭院钥匙", "钟楼钥匙", "旧钥匙"][i])
		state.add_key(id)
	hud.show_notice("门锁打开了")
	hud.show_hint("已记录存档点")
	assert(hud.notice_label.text == "已记录存档点" and not hud.hint_label.visible)
	hud.show_alert("青色冲锋！", "躲开冲锋路线，引它撞墙", Color.CYAN, 2.0)
	assert(hud.alert_root.visible and hud.alert_bar.max_value == 2.0)
	await create_timer(0.6).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/collection-preview.png")
	print("COLLECTION_UI_OK: real key pickup, card, texture, save/load, key consumption")
	quit()
