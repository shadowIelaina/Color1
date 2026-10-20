extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var audio := root.get_node("AudioManager")
	var state := root.get_node("GameState")
	state.reset()
	await create_timer(0.8).timeout
	var source: AudioStream = audio._music_source
	audio._on_music_finished()
	assert(audio._music_source == source)
	assert(audio._music_player.stream.loop)
	var scene_manager := root.get_node("SceneManager")
	scene_manager.current_room_scene = "res://scenes/level_2.tscn"
	audio.play_room_music()
	await create_timer(1.2).timeout
	assert(audio._music_source.resource_path.ends_with("谜面.mp3"))
	var fade: Tween = audio._music_fade
	audio.play_room_music()
	assert(audio._music_fade == fade, "Same region must not restart music")
	var index: int = audio._se_next
	audio.play_ui_hover()
	assert(audio._se_next != index)
	index = audio._se_next
	audio.play_ui_hover()
	assert(audio._se_next == index, "Hover must not spam")
	audio.play_ui_select()
	var effect: AudioStreamPlayer = audio._se_pool[(audio._se_next - 1 + audio.SE_POOL_SIZE) % audio.SE_POOL_SIZE]
	assert(effect.stream == audio.UI_SELECT_STREAM and effect.pitch_scale >= 0.92)
	audio.play_ice_break()
	effect = audio._se_pool[(audio._se_next - 1 + audio.SE_POOL_SIZE) % audio.SE_POOL_SIZE]
	assert(effect.stream == audio.ICE_BREAK_STREAM and effect.pitch_scale == 1.0 and effect.volume_db == 0.0)
	for event in audio.EVENT_STREAMS:
		index = audio._se_next
		audio.play_event(event)
		assert(audio._se_next != index, "New audio event must play: " + event)
		effect = audio._se_pool[(audio._se_next - 1 + audio.SE_POOL_SIZE) % audio.SE_POOL_SIZE]
		assert(effect.stream == audio.EVENT_STREAMS[event])
		index = audio._se_next
		audio.play_event(event)
		assert(audio._se_next == index, "Repeated audio event must be limited")
	assert(audio._fire_player.stream.loop and audio._fire_player.bus == "BGS")
	var camera := Camera2D.new()
	camera.offset = Vector2(11, 7)
	camera.zoom = Vector2(0.25, 0.25)
	root.add_child(camera)
	camera.make_current()
	var player: Node = load("res://scenes/player.tscn").instantiate()
	player.max_health = 3
	root.add_child(player)
	player.set_physics_process(false)
	player.take_damage()
	assert(player.health == 2.0)
	await create_timer(0.04).timeout
	assert(camera.offset != Vector2(11, 7), "Damage must produce a small camera shake")
	player.take_damage()
	assert(player.health == 2.0, "Invulnerability must remain unchanged")
	await create_timer(0.3).timeout
	assert(camera.offset.is_equal_approx(Vector2(11, 7)))
	assert(player.sprite.self_modulate == Color.WHITE)
	audio._player = player
	var fire := Node2D.new()
	root.add_child(fire)
	fire.add_to_group("heat_source")
	fire.global_position = player.global_position
	audio._update_fire(1.0)
	assert(audio._fire_player.volume_db > -15.0, "Nearby fire must be audible")
	fire.queue_free()
	await process_frame
	audio._update_fire(2.0)
	assert(audio._fire_player.volume_db < -70.0, "Removed fire must fade out")

	print("AUDIO_FEEDBACK_OK: new event streams/debounce, fire proximity/fade, region loop, no restart, UI sounds/debounce, pooled audio reset, damage shake/reset/invulnerability")
	quit()
