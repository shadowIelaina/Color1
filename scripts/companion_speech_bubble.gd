extends Control
## 跟班头顶纸片气泡：战斗中的短提示用这个，不占用对话系统、不挡输入。
## 由 HUD 创建，每帧跟随跟班屏幕位置。

const PaperPanel := preload("res://scripts/paper_panel.gd")
const HAND_FONT := preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")
const BUBBLE_WIDTH := 360.0
const TEXT_WIDTH := 326.0
const COMPANION_OFFSET := Vector2(0.0, -132.0)
const EDGE_MARGIN := 12.0

var _panel: PanelContainer
var _text: Label
var _fade: Tween
var _companion: Node2D


func _ready() -> void:
	name = "CompanionBubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	_build()
	visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "BubblePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_script(PaperPanel)
	_panel.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0.0)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)

	var name_label := Label.new()
	name_label.text = "小白"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", HAND_FONT)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color("5d7f8c"))
	box.add_child(name_label)

	_text = Label.new()
	_text.name = "Text"
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("font", HAND_FONT)
	_text.add_theme_font_size_override("font_size", 20)
	_text.add_theme_color_override("font_color", Color("38352f"))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(TEXT_WIDTH, 0.0)
	box.add_child(_text)


## 显示一段跟班提示；会替换当前气泡并重新计时。
func show_text(text: String, duration := 2.6) -> void:
	if text.strip_edges() == "":
		return
	_text.text = text
	_text.update_minimum_size()
	_panel.reset_size()
	visible = true
	modulate.a = 0.0
	_update_position()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.15)
	_fade.tween_interval(maxf(duration, 0.1))
	_fade.tween_property(self, "modulate:a", 0.0, 0.35)
	_fade.tween_callback(func(): visible = false)


func is_showing() -> bool:
	return visible and modulate.a > 0.01


func _process(_delta: float) -> void:
	if visible:
		_update_position()


func _update_position() -> void:
	var companion := _find_companion()
	if companion == null:
		visible = false
		return
	var screen := companion.get_global_transform_with_canvas().origin
	var bubble_size := _panel.size
	var viewport := get_viewport_rect().size
	var pos := screen + COMPANION_OFFSET + Vector2(-bubble_size.x * 0.5, -bubble_size.y)
	pos.x = clampf(pos.x, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport.x - bubble_size.x - EDGE_MARGIN))
	pos.y = clampf(pos.y, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport.y - bubble_size.y - EDGE_MARGIN))
	_panel.position = pos


func _find_companion() -> Node2D:
	if is_instance_valid(_companion) and not _companion.is_queued_for_deletion() and _companion.is_inside_tree():
		return _companion
	_companion = get_tree().get_first_node_in_group("companion") as Node2D
	return _companion
