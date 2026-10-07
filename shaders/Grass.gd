extends Area2D

@export var bend_speed = 0.2
@export var recover_speed = 0.6
@export var max_angle = 0.35

var current_tween: Tween
var player_is_inside: bool = false

func _on_body_entered(body: Node2D) -> void:
	if player_is_inside or body.name != "Player":
		return
	player_is_inside = true
	print("✅ 进入，草弯曲")
	
	if current_tween:
		current_tween.kill()

	var dir = global_position.x - body.global_position.x
	var target_angle = sign(dir) * max_angle

	current_tween = create_tween()
	current_tween.set_ease(Tween.EASE_OUT)
	current_tween.set_trans(Tween.TRANS_SINE)
	current_tween.tween_property($Sprite2D, "rotation", target_angle, bend_speed)


func _on_body_exited(body: Node2D) -> void:
	if body.name != "Player":
		return
	player_is_inside = false
	print("✅ 离开，草回正")
	
	if current_tween:
		current_tween.kill()
	current_tween = create_tween()
	current_tween.set_ease(Tween.EASE_OUT)
	current_tween.set_trans(Tween.TRANS_ELASTIC)
	current_tween.tween_property($Sprite2D, "rotation", 0.0, recover_speed)
