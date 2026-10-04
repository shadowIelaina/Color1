class_name ColorableObject
extends Colorable
## 立体可上色物体（前/顶面）：继承 Colorable，覆写前后面颜色表现。

@onready var front: Polygon2D = $Front
@onready var top_face: Polygon2D = $Top


func _on_color_applied(color: Color, _color_name: String = "") -> void:
	front.color = color
	top_face.color = color.lightened(0.18)


func _on_reset() -> void:
	front.color = Color(0.95, 0.95, 0.95, 1)
	top_face.color = Color(0.78, 0.78, 0.8, 1)
