extends Area2D

@export var bend_speed = 0.1
@export var recover_speed = 0.3
@export var max_bend = 0.3

var current_tween: Tween
var player_is_inside: bool = false
var mat: ShaderMaterial

func _ready():
	mat = $MeshInstance2D.material.duplicate()
	$MeshInstance2D.material = mat
	
	mat.set_shader_parameter("bend_amount", 0.0)

func _on_body_entered(body: Node2D) -> void:
	if player_is_inside or body.name != "Player":
		return
	player_is_inside = true
	
	if current_tween:
		current_tween.kill()

	var dir = global_position.x - body.global_position.x
	var target_bend = sign(dir) * max_bend

	current_tween = create_tween()
	current_tween.set_ease(Tween.EASE_OUT)
	current_tween.set_trans(Tween.TRANS_SINE)
	current_tween.tween_property(mat, "shader_parameter/bend_amount", target_bend, bend_speed)


func _on_body_exited(body: Node2D) -> void:
	if body.name != "Player":
		return
	player_is_inside = false
	
	if current_tween:
		current_tween.kill()
	current_tween = create_tween()
	current_tween.set_ease(Tween.EASE_OUT)
	current_tween.set_trans(Tween.TRANS_ELASTIC)
	current_tween.tween_property(mat, "shader_parameter/bend_amount", 0.0, recover_speed)
