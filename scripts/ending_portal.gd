extends "res://scripts/door.gd"
## Boss 胜利传送门：沿用解锁条件，进入后播放本章结局。

var _ending_started := false

func _teleport() -> void:
	if _ending_started or not GameState.is_switch_on("boss_defeated"): return
	_ending_started = true
	_using = true
	_start_ending.call_deferred()


func _start_ending() -> void:
	# 等胜利对白完整退场，避免旁白和跟班对白同时出现。
	while StoryDirector.is_busy():
		await get_tree().process_frame
		if not is_inside_tree(): return
	if not get_tree().get_nodes_in_group("ending").is_empty(): return
	var ending := preload("res://scripts/ending_sequence.gd").new()
	get_tree().current_scene.add_child(ending)
	ending.start(global_position)
