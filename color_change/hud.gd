extends CanvasLayer
## 顶部 HUD：显示玩家颜色库（持有的元素种子与数量）与当前选中。

const Rules := preload("res://scripts/element/element_rules.gd")

@onready var color_label: RichTextLabel = $ColorLabel
@onready var win_label: Label = $WinLabel

var hint_label: Label
var _hint_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	hint_label = _make_hint_label()
	_make_hearts()
	GameState.hint.connect(show_hint)
	if win_label:
		win_label.visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.inventory_changed.connect(_on_inventory_changed)
		var snap: Dictionary = player.palette_snapshot()
		_on_inventory_changed(snap["inventory"], snap["selected"])
		player.health_changed.connect(_on_health_changed)
		var hsnap: Dictionary = player.health_snapshot()
		_rebuild_hearts(hsnap["health"], hsnap["max_health"])


func show_win() -> void:
	if win_label:
		win_label.visible = true


## 顶部短暂提示（如「门已解锁」）：显示 1.5 秒后淡出。
func show_hint(text: String) -> void:
	if hint_label == null:
		return
	hint_label.text = text
	hint_label.modulate.a = 1.0
	hint_label.visible = true
	if _hint_tween and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(1.5)
	_hint_tween.tween_property(hint_label, "modulate:a", 0.0, 0.4)
	_hint_tween.tween_callback(func():
		hint_label.visible = false
		hint_label.modulate.a = 1.0
	)


## 代码里创建提示 Label（全屏居中），免去改 .tscn。
func _make_hint_label() -> Label:
	var l := Label.new()
	l.name = "HintLabel"
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	l.visible = false
	add_child(l)
	return l


func _on_inventory_changed(inventory: Dictionary, selected_element: String) -> void:
	color_label.text = _palette_text(inventory, selected_element)


## 用 bbcode 渲染颜色库：每个持有中的元素用自身颜色显示，选中的加 ▸。
func _palette_text(inventory: Dictionary, selected: String) -> String:
	var order := ["burn", "freeze", "grow"]
	var parts: Array[String] = []
	for el in order:
		var count := int(inventory.get(el, 0))
		if count <= 0:
			continue
		var cfg := Rules.config(el)
		var cname := str(cfg.get("color_name", el))
		var col: Color = cfg.get("color", Color.WHITE)
		var mark := "▸ " if el == selected else ""
		parts.append("%s[color=#%s]%s×%d[/color]" % [mark, _hex(col), cname, count])
	if parts.is_empty():
		return "持有：无"
	return "持有：%s　（滚轮=切换）" % "  ".join(parts)


func _hex(c: Color) -> String:
	return "%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]


# —— 红心血量显示 ——
## 当前用文字 ♥/♡ 占位；后续换美术贴图时，把 _make_heart 改成返回 TextureRect 并设贴图即可。
const HEART_FILLED := "♥"
const HEART_EMPTY := "♡"

var hearts: HBoxContainer


func _make_hearts() -> void:
	hearts = HBoxContainer.new()
	hearts.name = "Hearts"
	hearts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hearts.offset_left = -120.0
	hearts.offset_top = 12.0
	hearts.offset_right = -12.0
	hearts.offset_bottom = 44.0
	hearts.alignment = BoxContainer.ALIGNMENT_END
	hearts.add_theme_constant_override("separation", 2)
	add_child(hearts)


func _on_health_changed(health: int, max_health: int) -> void:
	_rebuild_hearts(health, max_health)


func _rebuild_hearts(health: int, max_health: int) -> void:
	for c in hearts.get_children():
		c.queue_free()
	for i in max_health:
		hearts.add_child(_make_heart(i < health))


func _make_heart(filled: bool) -> Control:
	var h := Label.new()
	h.text = HEART_FILLED if filled else HEART_EMPTY
	h.add_theme_font_size_override("font_size", 28)
	h.add_theme_color_override("font_color", Color(0.95, 0.22, 0.22) if filled else Color(1, 1, 1, 0.35))
	return h
