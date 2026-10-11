extends Node2D
## 悬停描边：画在 CanvasLayer 里的矩形框，永远盖在主画布之上。
## 关键：本节点在**屏幕空间**（CanvasLayer transform 恒等）绘制，边框宽度是屏幕像素——
## 若用世界坐标，相机 zoom 0.25 会把 2px 边框缩成 0.5px 亚像素，在白底/黑草丛上根本看不见。
## cell_hover.gd 每帧把「世界中心/尺寸」换算成「屏幕中心/尺寸」后 call("set_box", ...)。


var _size := Vector2(64.0, 64.0)  # 屏幕像素尺寸
var _accent := Color(1.0, 0.82, 0.1, 1.0)
var _shown := false


func set_box(center: Vector2, size: Vector2, accent: Color, shown: bool) -> void:
	position = center
	_size = size
	_accent = accent
	_shown = shown
	queue_redraw()


func _draw() -> void:
	if not _shown:
		return
	var r := Rect2(-_size * 0.5, _size)
	draw_rect(r, Color(_accent.r, _accent.g, _accent.b, 0.18))        # 整块淡染
	draw_rect(r.grow(3.0), Color(0.03, 0.03, 0.05, 0.95), false, 3.0) # 深色外圈（屏幕 3px，保证对比）
	draw_rect(r, _accent, false, 2.0)                                 # 主色内圈（屏幕 2px）
