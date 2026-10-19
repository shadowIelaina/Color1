extends Control
## 手绘收集页：常驻小图、排队拾取纸签；不阻断场景鼠标输入。
const Paper := preload("res://scripts/paper_panel.gd")
const FontHand := preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")
const KeyArt := preload("res://art/picture_boluo/钥匙tm.png")
const HeartArt := preload("res://art/picture_boluo/生命值（红）tm.png")
var shelf: PanelContainer
var grid: GridContainer
var scroll: ScrollContainer
var card: PanelContainer
var pending: Array[Dictionary] = []
var presenting := false

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	shelf = PanelContainer.new()
	shelf.set_script(Paper)
	shelf.position = Vector2(18, 18)
	shelf.custom_minimum_size = Vector2(320, 0)
	add_child(shelf)
	var column := VBoxContainer.new()
	shelf.add_child(column)
	column.add_child(_label("随身拾记", 19))
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 132)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	GameState.key_added.connect(refresh)
	GameState.key_used.connect(refresh)
	GameState.prop_added.connect(refresh)
	GameState.pickup_presented.connect(_enqueue)
	refresh()
	# 纸页区域让鼠标穿透；滚动条与图标保留悬停说明。
	shelf.mouse_filter = MOUSE_FILTER_IGNORE
	column.mouse_filter = MOUSE_FILTER_IGNORE

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FontHand)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("38352f"))
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label

func _entry(kind: String, id: String) -> Dictionary:
	var fallback := GameState.key_display(id) if kind == "key" else str(GameState.health_upgrade_names.get(id, "未命名物品"))
	var entry = GameState.item_art.get(kind + ":" + id, {})
	return entry if entry is Dictionary and not entry.is_empty() else {"kind": kind, "id": id, "title": fallback, "texture": ""}

func _icon(entry: Dictionary, extent: float) -> Control:
	var path := str(entry.get("texture", ""))
	var texture: Texture2D
	if path.begins_with("res://") and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null and entry.get("kind") == "key": texture = KeyArt
	if texture == null and GameState.health_upgrades.has(str(entry.get("id", ""))): texture = HeartArt
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(extent, extent)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	if texture == null:
		var mark := _label("◇", int(extent * 0.6))
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_child(mark)
	return icon

func refresh(_id = null) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = []
	for id in GameState.held_key_ids(): entries.append(_entry("key", id))
	for id in GameState.props:
		if GameState.has_prop(id): entries.append(_entry("prop", str(id)))
	scroll.custom_minimum_size.y = 76.0 if entries.size() <= 5 else 158.0
	shelf.size = Vector2.ZERO
	for entry in entries:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = 54
		cell.tooltip_text = str(entry.title)
		cell.mouse_filter = MOUSE_FILTER_PASS
		cell.add_child(_icon(entry, 45))
		var caption := _label(str(entry.title), 13)
		caption.custom_minimum_size.x = 54
		caption.clip_text = true
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)
		grid.add_child(cell)
	shelf.visible = not entries.is_empty()

func _enqueue(entry: Dictionary) -> void:
	refresh()
	pending.append(entry.duplicate())
	if not presenting: _present_next()

func _present_next() -> void:
	if pending.is_empty():
		presenting = false
		return
	presenting = true
	var entry: Dictionary = pending.pop_front()
	card = PanelContainer.new()
	card.set_script(Paper)
	var resting_y := 160.0 if scroll.custom_minimum_size.y < 100.0 else 246.0
	card.position = Vector2(18, resting_y + 14.0)
	card.custom_minimum_size = Vector2(300, 112)
	card.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(card)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	row.add_child(_icon(entry, 76))
	var words := VBoxContainer.new()
	words.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(words)
	words.add_child(_label("拾得 · " + str(entry.get("title", "物品")), 23))
	words.add_child(_label(str(entry.get("detail", "已收好")), 17))
	card.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.25)
	tween.tween_property(card, "position:y", resting_y, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(2.0)
	tween.chain().tween_property(card, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(func():
		card.queue_free()
		_present_next()
	)
