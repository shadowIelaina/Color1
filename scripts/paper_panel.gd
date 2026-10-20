extends PanelContainer
## 双重略错位的铅笔边线，保持静止，不做随机闪动。
func _ready() -> void:
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f4f0e5")
	paper.shadow_color = Color(0.12, 0.10, 0.08, 0.12)
	paper.shadow_size = 3
	paper.shadow_offset = Vector2(2, 3)
	paper.content_margin_left = 14
	paper.content_margin_right = 14
	paper.content_margin_top = 12
	paper.content_margin_bottom = 12
	add_theme_stylebox_override("panel", paper)
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_polyline(PackedVector2Array([Vector2(2, 4), Vector2(w * 0.49, 2), Vector2(w - 3, 4), Vector2(w - 2, h - 4), Vector2(w * 0.48, h - 2), Vector2(3, h - 3), Vector2(2, 4)]), Color(0.19, 0.18, 0.16, 0.8), 1.2, true)
	draw_line(Vector2(6, h - 6), Vector2(w - 7, h - 5), Color(0.25, 0.23, 0.20, 0.23), 1.0, true)
