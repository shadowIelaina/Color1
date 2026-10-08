class_name Goal
extends Area2D
## 目标：玩家踏入即过关。放在需要靠颜色解谜才能到达的位置。
## 过关后广播 reached，并让 HUD 显示「过关！」。

signal reached

@onready var visual: Node2D = $Visual

var _reached := false
var _pulse := 0.0


func _ready() -> void:
	add_to_group("goal")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_pulse += delta
	var s := 1.0 + 0.08 * sin(_pulse * 3.0)
	visual.scale = Vector2(s, s)


func _on_body_entered(body: Node) -> void:
	if _reached:
		return
	if not body.is_in_group("player"):
		return
	_reached = true
	reached.emit()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_win"):
		hud.show_win()
