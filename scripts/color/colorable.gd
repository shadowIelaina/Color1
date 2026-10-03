class_name Colorable
extends Node2D
## 可上色实体基类。可以继承，也可以作为子节点组件使用。

signal color_applied(color: Color)

@export var supported_colors: Array[String] = ["red", "blue", "green", "black", "white"]

var current_color: Color = Color.WHITE


func apply_color(color: Color, color_name: String = "") -> bool:
	if color_name != "" and color_name not in supported_colors:
		return false
	current_color = color
	modulate = color
	_on_color_applied(color, color_name)
	color_applied.emit(color)
	EventBus.emit("color_applied", {"target": self, "color": color, "color_name": color_name})
	return true


func reset_color() -> void:
	current_color = Color.WHITE
	modulate = Color.WHITE
	_on_reset()


func _on_color_applied(_color: Color, _color_name: String = "") -> void:
	pass


func _on_reset() -> void:
	pass
