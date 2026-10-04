class_name ColorableObject
extends Colorable
## 立体可上色物体（箱子/石块）：实现颜色特性。
## 红=强度、蓝=稳定、绿=复制、白=重置（红箱子则破碎）。

@onready var front: Polygon2D = $Front
@onready var top_face: Polygon2D = $Top


func _on_color_applied(color: Color, color_name: String = "", direction: Vector2 = Vector2.ZERO) -> void:
	match color_name:
		"green":
			record_trait(color_name)
			_paint(color)
			if previous_color_name != "green":
				duplicate_in_direction(direction)
		"white":
			if previous_color_name == "red":
				shatter()
			else:
				record_trait(color_name)
				_on_reset()
		_:
			record_trait(color_name)
			_paint(color)


func _on_reset() -> void:
	front.color = Color(0.95, 0.95, 0.95, 1)
	top_face.color = Color(0.78, 0.78, 0.8, 1)


func _paint(color: Color) -> void:
	front.color = color
	top_face.color = color.lightened(0.18)
