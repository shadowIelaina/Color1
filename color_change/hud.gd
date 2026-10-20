extends CanvasLayer
## 顶部 HUD：显示玩家颜色库（持有的元素种子与数量）与当前选中。

const Rules := preload("res://scripts/element/element_rules.gd")
const HAND_FONT := preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")

## 胜利/击败文字。留空则保留场景里 WinLabel 的文本。
@export var win_text := ""
## 胜利文字字号。0 = 保留场景里的字号。
@export_range(0, 200, 1) var win_font_size := 0
## Boss 血条上显示的名字。
@export var boss_title := "失色之主"

## 右下角色轮方向盘：红/绿/蓝各一张独立成品图，选中哪个元素就显示哪张。
## 每张图都已画好「选中色高亮、其余两色压淡」，无需 shader 旋转 / 扇区遮罩。
const WHEEL_TEXTURES := {
	"burn": preload("res://art/ui/色轮/色轮_红.png"),     # 红
	"grow": preload("res://art/ui/色轮/色轮_绿.png"),     # 绿
	"freeze": preload("res://art/ui/色轮/色轮_蓝.png"),   # 蓝
}
## 新图为 2000×2000，色环外径约 600px（占图 60%）、内径约 131px；
## 按色环外径约 160px 反推显示尺寸，让新图与旧图视觉大小一致。
const WHEEL_SIZE := 256.0
const WHEEL_MARGIN := 20.0
const WHEEL_FADE := 0.22   # 切换颜色时淡入淡出各段时长（秒）
const BOSS_FONT := preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")
const BOSS_GOLD := Color(0.95, 0.78, 0.38, 1.0)
const BOSS_RED := Color(0.95, 0.28, 0.22, 1.0)
const BOSS_BLUE := Color(0.3, 0.55, 1.0, 1.0)
const BOSS_GREEN := Color(0.3, 0.9, 0.42, 1.0)
const BOSS_CYAN := Color(0.25, 0.9, 0.95, 1.0)

@onready var color_label: RichTextLabel = $ColorLabel
@onready var win_label: Label = $WinLabel

var wheel: TextureRect
var _wheel_tween: Tween
var _count_label: Label

var hint_label: Label
var status_label: Label
var notice_label: Label
var notice_panel: PanelContainer
var _notice_dot: Label
var _hint_tween: Tween
var _notice_tween: Tween

var alert_root: Control
var alert_panel: PanelContainer
var alert_icon: Label
var alert_title: Label
var alert_subtitle: Label
var alert_count: Label
var alert_bar: ProgressBar
var _alert_tween: Tween
var _alert_left := 0.0
var _alert_total := 1.0

var boss_root: Control
var boss_panel: PanelContainer
var boss_name_label: Label
var boss_tag: Label
var boss_phase_label: Label
var boss_status_label: Label
var boss_bar: ProgressBar
var boss_ghost_bar: ProgressBar
var boss_fill: StyleBoxFlat
var boss_pips: Array[Label] = []
var _boss: Node
var _boss_bar_tween: Tween
var _boss_ghost_tween: Tween
var _boss_fade_tween: Tween

var victory_root: Control
var victory_panel: PanelContainer
var victory_title: Label
var victory_subtitle: Label
var _victory_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	hint_label = _make_hint_label()
	status_label = _make_status_label()
	notice_label = _make_notice_label()
	var collection := Control.new()
	collection.set_script(preload("res://scripts/collection_ui.gd"))
	add_child(collection)
	_make_alert_banner()
	_make_hearts()
	_make_boss_hud()
	_make_victory_banner()
	_make_wheel()
	color_label.visible = false   # 调色盘改用右下角色轮，不再用左上角文字
	GameState.hint.connect(show_hint)
	GameState.notice.connect(show_notice)
	GameState.alert.connect(show_alert)
	GameState.alert_cancelled.connect(_on_alert_cancelled)
	GameState.key_added.connect(_refresh_status)
	GameState.key_used.connect(_refresh_status)
	GameState.prop_added.connect(_refresh_status)
	GameState.ability_added.connect(_refresh_status)
	_refresh_status()
	if win_label:
		win_label.add_theme_font_override("font", HAND_FONT)
		win_label.add_theme_color_override("font_color", Color("38352f"))
		win_label.add_theme_constant_override("outline_size", 5)
		win_label.add_theme_color_override("font_outline_color", Color("f4f0e5"))
		if win_text != "":
			win_label.text = win_text
		if win_font_size > 0:
			win_label.add_theme_font_size_override("font_size", win_font_size)
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


## 交互与通关消息也走同一张纸签，不在画面中央叠加裸文字。
func show_hint(text: String) -> void:
	show_notice(text)


## 代码里创建提示 Label（全屏居中），免去改 .tscn。
func _make_hint_label() -> Label:
	var l := Label.new()
	l.name = "HintLabel"
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0))
	l.visible = false
	add_child(l)
	return l


## 道具 / 能力持有行（左上角，颜色库下方），由 GameState 信号驱动刷新。
func _make_status_label() -> Label:
	var l := Label.new()
	l.name = "StatusLabel"
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	l.offset_left = 12.0
	l.offset_top = 64.0
	l.offset_right = 720.0
	l.offset_bottom = 96.0
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_font_override("font", HAND_FONT)
	l.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0))
	l.visible = false
	add_child(l)
	return l


func _refresh_status(_a = null, _b = null) -> void:
	if status_label == null:
		return
	var abilities := _true_keys(GameState.abilities)
	# 钥匙与道具交给贴图收集页，能力仍保留简短文字说明。
	status_label.text = "能力：%s" % ", ".join(abilities) if not abilities.is_empty() else ""
	status_label.offset_top = 350.0
	status_label.offset_bottom = 380.0
	status_label.visible = not abilities.is_empty()


## 取字典里值为 true 的键（背包用 id -> true 存法），排序后返回。
static func _true_keys(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in d:
		if d[k] == true:
			out.append(str(k))
	out.sort()
	return out


## 底部纸签短提示，与手绘收集页使用相同的纸张、铅笔边线。
func _make_notice_label() -> Label:
	notice_panel = PanelContainer.new()
	notice_panel.name = "NoticePanel"
	notice_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice_panel.offset_left = -160.0
	notice_panel.offset_top = -94.0
	notice_panel.offset_right = 160.0
	notice_panel.offset_bottom = -42.0
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel.set_script(preload("res://scripts/paper_panel.gd"))
	notice_panel.visible = false
	add_child(notice_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	notice_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_notice_dot = Label.new()
	_notice_dot.text = "—"
	_notice_dot.add_theme_font_size_override("font_size", 16)
	_notice_dot.add_theme_color_override("font_color", Color("686154"))
	_notice_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_notice_dot)

	var l := Label.new()
	l.name = "NoticeLabel"
	l.add_theme_font_override("font", preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf"))
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color("38352f"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return l


func show_notice(text: String) -> void:
	if notice_label == null or notice_panel == null:
		return
	notice_label.text = text
	notice_label.update_minimum_size()
	var text_size := notice_label.get_minimum_size()
	var width := clampf(text_size.x + 92.0, 180.0, 760.0)
	notice_panel.offset_left = -width * 0.5
	notice_panel.offset_right = width * 0.5
	notice_panel.offset_bottom = notice_panel.offset_top + maxf(text_size.y + 24.0, 44.0)
	notice_panel.modulate.a = 1.0
	notice_panel.visible = true
	if _notice_tween and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_property(notice_panel, "modulate:a", 1.0, 0.18).from(0.0)
	_notice_tween.tween_interval(2.0)
	_notice_tween.tween_property(notice_panel, "modulate:a", 0.0, 0.5)
	_notice_tween.tween_callback(func():
		notice_panel.visible = false
		notice_panel.modulate.a = 1.0
	)


## 屏幕上方居中的 Boss 警告横幅（标题 + 副标题 + 倒计时进度条）。
func _make_alert_banner() -> void:
	alert_root = Control.new()
	alert_root.name = "BossAlert"
	alert_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	alert_root.offset_left = -220.0
	alert_root.offset_right = 220.0
	alert_root.offset_top = 132.0
	alert_root.offset_bottom = 258.0
	alert_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_root.pivot_offset = Vector2(220.0, 63.0)
	alert_root.visible = false
	add_child(alert_root)

	alert_panel = PanelContainer.new()
	alert_panel.set_script(preload("res://scripts/paper_panel.gd"))
	alert_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_root.add_child(alert_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	alert_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	box.add_child(top)

	alert_icon = Label.new()
	alert_icon.text = "!"
	alert_icon.custom_minimum_size = Vector2(26, 0)
	alert_icon.add_theme_font_size_override("font_size", 32)
	alert_icon.add_theme_color_override("font_color", Color(0.6, 1.0, 0.65))
	alert_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(alert_icon)

	alert_title = Label.new()
	alert_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alert_title.add_theme_font_size_override("font_size", 28)
	alert_title.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75))
	alert_title.add_theme_constant_override("outline_size", 5)
	alert_title.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
	alert_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(alert_title)

	alert_count = Label.new()
	alert_count.add_theme_font_size_override("font_size", 22)
	alert_count.add_theme_color_override("font_color", Color(0.85, 1.0, 0.9))
	alert_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(alert_count)

	alert_subtitle = Label.new()
	alert_subtitle.add_theme_font_size_override("font_size", 17)
	alert_subtitle.add_theme_color_override("font_color", Color(0.86, 0.9, 0.96))
	alert_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(alert_subtitle)
	for label in [alert_icon, alert_title, alert_count, alert_subtitle]:
		label.add_theme_font_override("font", HAND_FONT)
		label.add_theme_color_override("font_color", Color("38352f"))
		label.add_theme_constant_override("outline_size", 0)
	alert_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	alert_bar = ProgressBar.new()
	alert_bar.custom_minimum_size = Vector2(0, 6)
	alert_bar.show_percentage = false
	alert_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(alert_bar)


func show_alert(title: String, subtitle: String, color: Color, duration: float) -> void:
	if alert_root == null:
		return
	_alert_total = maxf(duration, 0.1)
	_alert_left = _alert_total
	alert_title.text = title
	alert_subtitle.text = subtitle
	# 纸上使用较深的彩铅色，避免亮色文字在纸白底上难以辨认。
	var pencil := color.darkened(0.55)
	alert_icon.add_theme_color_override("font_color", pencil)
	alert_title.add_theme_color_override("font_color", pencil)
	alert_count.add_theme_color_override("font_color", Color("38352f"))

	var fill := StyleBoxFlat.new()
	fill.bg_color = pencil
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.18, 0.15, 0.12)
	bg.set_corner_radius_all(3)
	alert_bar.add_theme_stylebox_override("fill", fill)
	alert_bar.add_theme_stylebox_override("background", bg)
	alert_bar.max_value = _alert_total
	alert_bar.value = _alert_left
	alert_count.text = "%ds" % int(ceil(_alert_left))

	alert_root.visible = true
	alert_root.modulate.a = 1.0
	alert_root.scale = Vector2(0.94, 0.94)
	if _alert_tween and _alert_tween.is_valid():
		_alert_tween.kill()
	_alert_tween = create_tween()
	_alert_tween.tween_property(alert_root, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_alert() -> void:
	_alert_left = 0.0
	if alert_root != null:
		alert_root.visible = false
		alert_root.modulate.a = 1.0


func _on_alert_cancelled() -> void:
	hide_alert()


func _tick_alert(delta: float) -> void:
	if _alert_left <= 0.0 or alert_root == null:
		return
	_alert_left = maxf(_alert_left - delta, 0.0)
	alert_bar.value = _alert_left
	alert_count.text = "%ds" % int(ceil(_alert_left))
	if _alert_left <= 0.0:
		hide_alert()
	elif _alert_left < 0.3:
		alert_root.modulate.a = _alert_left / 0.3


func _on_inventory_changed(inventory: Dictionary, selected_element: String) -> void:
	_update_wheel(selected_element, int(inventory.get(selected_element, 0)))


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


# —— 右下角色轮方向盘 ——
## 代码里创建色轮 TextureRect（右下角）：贴图在 _update_wheel 里按选中元素切换。
func _make_wheel() -> void:
	wheel = TextureRect.new()
	wheel.name = "ColorWheel"
	wheel.custom_minimum_size = Vector2.ONE * WHEEL_SIZE
	wheel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wheel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.anchor_left = 1.0
	wheel.anchor_top = 1.0
	wheel.anchor_right = 1.0
	wheel.anchor_bottom = 1.0
	wheel.offset_left = -(WHEEL_SIZE + WHEEL_MARGIN)
	wheel.offset_top = -(WHEEL_SIZE + WHEEL_MARGIN)
	wheel.offset_right = -WHEEL_MARGIN
	wheel.offset_bottom = -WHEEL_MARGIN
	wheel.visible = false
	_count_label = _make_wheel_count_label()
	wheel.add_child(_count_label)
	add_child(wheel)


## 色轮中心的数量角标：白字加描边，盖在轮心透明轮毂上。
func _make_wheel_count_label() -> Label:
	var l := Label.new()
	l.name = "WheelCount"
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 根据当前选中元素切换显示对应色轮图，并在轮心显示持有数量。
## 选中元素用完时保留选中色，数量角标显示 0，而非把色轮整个藏掉。
func _update_wheel(selected_element: String, count: int) -> void:
	if wheel == null:
		return
	if selected_element == "" or not WHEEL_TEXTURES.has(selected_element):
		wheel.visible = false
		return
	wheel.visible = true
	_count_label.text = str(count)
	_switch_wheel_texture(WHEEL_TEXTURES[selected_element])


## 交叉淡入换图：先把旧图淡出，换上新图再淡入。
## 只动 self_modulate，不影响作为子节点的中心数量角标。
func _switch_wheel_texture(tex: Texture2D) -> void:
	if wheel.texture == tex:
		return
	if _wheel_tween and _wheel_tween.is_valid():
		_wheel_tween.kill()
	wheel.self_modulate.a = 1.0
	_wheel_tween = create_tween()
	_wheel_tween.tween_property(wheel, "self_modulate:a", 0.0, WHEEL_FADE).set_trans(Tween.TRANS_CUBIC)
	_wheel_tween.tween_callback(func():
		wheel.texture = tex
	)
	_wheel_tween.tween_property(wheel, "self_modulate:a", 1.0, WHEEL_FADE).set_trans(Tween.TRANS_CUBIC)


# —— 黑白贴图血量显示 ——
const HEART_TEXTURE := preload("res://art/things/生命值(黑)tm.png")
const HEART_ICON_SIZE := 56.0

var hearts: GridContainer
var _last_health := -1.0
var _heart_tweens: Dictionary = {}


func _make_hearts() -> void:
	hearts = GridContainer.new()
	hearts.columns = 10
	hearts.name = "Hearts"
	hearts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hearts.offset_left = -368.0
	hearts.offset_top = 12.0
	hearts.offset_right = -12.0
	hearts.offset_bottom = 84.0
	hearts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hearts.add_theme_constant_override("h_separation", 4)
	hearts.add_theme_constant_override("v_separation", 4)
	add_child(hearts)


func _on_health_changed(health: float, max_health: int) -> void:
	_rebuild_hearts(health, max_health)


func _rebuild_hearts(health: float, max_health: int) -> void:
	hearts.columns = mini(10, maxi(1, max_health))
	hearts.offset_left = -12.0 - (float(hearts.columns) * (HEART_ICON_SIZE + 4.0) - 4.0)
	var previous_count := hearts.get_child_count()
	while hearts.get_child_count() > max_health:
		var last := hearts.get_child(hearts.get_child_count() - 1)
		if _heart_tweens.has(last):
			_heart_tweens[last].kill()
			_heart_tweens.erase(last)
		hearts.remove_child(last)
		last.queue_free()
	for i in range(previous_count, max_health):
		var icon := _make_heart(true)
		hearts.add_child(icon)
		if _last_health >= 0.0:
			icon.scale = Vector2(0.2, 0.2)
			icon.modulate.a = 0.0
			var pop := create_tween().set_parallel(true)
			pop.tween_property(icon, "scale", Vector2.ONE, 0.45).set_delay(0.08 * (i - previous_count)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pop.tween_property(icon, "modulate:a", 1.0, 0.25)
			_heart_tweens[icon] = pop
	# 少量伤害也显示亮度差异，避免 0.2 点伤害完全没有血量反馈。
	for i in max_health:
		var icon := hearts.get_child(i) as TextureRect
		var fill := clampf(health - float(i), 0.0, 1.0)
		icon.self_modulate.a = 0.22 + fill * 0.78
		if _last_health >= 0.0 and health < _last_health and float(i) < _last_health and float(i + 1) > health:
			if _heart_tweens.has(icon):
				_heart_tweens[icon].kill()
			var hit := create_tween()
			_heart_tweens[icon] = hit
			hit.tween_property(icon, "scale", Vector2(1.2, 0.85), 0.08)
			hit.tween_property(icon, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_last_health = health


func _make_heart(filled: bool) -> Control:
	var h := TextureRect.new()
	h.texture = HEART_TEXTURE
	h.custom_minimum_size = Vector2.ONE * HEART_ICON_SIZE
	h.pivot_offset = Vector2.ONE * HEART_ICON_SIZE * 0.5
	h.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.self_modulate.a = 1.0 if filled else 0.22
	return h


# —— Boss 血条（顶部居中，绑定 "boss" 组里的 Boss）——

# —— Boss HUD ——

func _make_boss_hud() -> void:
	boss_root = Control.new()
	boss_root.name = "BossHUD"
	boss_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_root.offset_left = -410.0
	boss_root.offset_right = 410.0
	boss_root.offset_top = 14.0
	boss_root.offset_bottom = 124.0
	boss_root.pivot_offset = Vector2(410.0, 55.0)
	boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.visible = false
	add_child(boss_root)

	boss_panel = PanelContainer.new()
	boss_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_panel.add_theme_stylebox_override("panel", _boss_panel_style())
	boss_root.add_child(boss_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)

	boss_name_label = Label.new()
	boss_name_label.text = boss_title
	boss_name_label.add_theme_font_override("font", BOSS_FONT)
	boss_name_label.add_theme_font_size_override("font_size", 30)
	boss_name_label.add_theme_color_override("font_color", BOSS_GOLD)
	boss_name_label.add_theme_constant_override("outline_size", 4)
	boss_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	top.add_child(boss_name_label)

	boss_tag = Label.new()
	boss_tag.text = "BOSS"
	boss_tag.add_theme_font_override("font", BOSS_FONT)
	boss_tag.add_theme_font_size_override("font_size", 14)
	boss_tag.add_theme_color_override("font_color", Color(0.72, 0.55, 0.28, 1.0))
	boss_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(boss_tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pips)
	boss_pips.clear()
	for c in [BOSS_RED, BOSS_BLUE, BOSS_GREEN]:
		var pip := Label.new()
		pip.text = "◆"
		pip.add_theme_font_override("font", BOSS_FONT)
		pip.add_theme_font_size_override("font_size", 16)
		pip.add_theme_color_override("font_color", c)
		pip.modulate.a = 0.22
		pips.add_child(pip)
		boss_pips.append(pip)

	boss_phase_label = Label.new()
	boss_phase_label.text = "红相"
	boss_phase_label.add_theme_font_override("font", BOSS_FONT)
	boss_phase_label.add_theme_font_size_override("font_size", 16)
	boss_phase_label.add_theme_color_override("font_color", BOSS_RED)
	boss_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(boss_phase_label)

	var bar_holder := Control.new()
	bar_holder.custom_minimum_size = Vector2(0, 20)
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar_holder)

	boss_ghost_bar = ProgressBar.new()
	boss_ghost_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_ghost_bar.min_value = 0.0
	boss_ghost_bar.max_value = 100.0
	boss_ghost_bar.value = 100.0
	boss_ghost_bar.show_percentage = false
	boss_ghost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_ghost_bar.add_theme_stylebox_override("background", _boss_bar_bg())
	boss_ghost_bar.add_theme_stylebox_override("fill", _boss_bar_fill(Color(1.0, 0.82, 0.55, 0.45)))
	bar_holder.add_child(boss_ghost_bar)

	boss_bar = ProgressBar.new()
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_bar.min_value = 0.0
	boss_bar.max_value = 100.0
	boss_bar.value = 100.0
	boss_bar.show_percentage = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_fill = _boss_bar_fill(BOSS_RED)
	var clear_bg := StyleBoxFlat.new()
	clear_bg.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	boss_bar.add_theme_stylebox_override("background", clear_bg)
	boss_bar.add_theme_stylebox_override("fill", boss_fill)
	bar_holder.add_child(boss_bar)

	for ratio in [0.34, 0.66]:
		var marker := ColorRect.new()
		marker.color = Color(0.95, 0.82, 0.5, 0.55)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.anchor_left = ratio
		marker.anchor_right = ratio
		marker.anchor_top = 0.0
		marker.anchor_bottom = 1.0
		marker.offset_left = -1.0
		marker.offset_right = 1.0
		bar_holder.add_child(marker)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bottom)

	var status_tag := Label.new()
	status_tag.text = "状态"
	status_tag.add_theme_font_override("font", BOSS_FONT)
	status_tag.add_theme_font_size_override("font_size", 14)
	status_tag.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45, 1.0))
	bottom.add_child(status_tag)

	boss_status_label = Label.new()
	boss_status_label.text = "追击"
	boss_status_label.add_theme_font_override("font", BOSS_FONT)
	boss_status_label.add_theme_font_size_override("font_size", 17)
	boss_status_label.add_theme_color_override("font_color", BOSS_GOLD)
	bottom.add_child(boss_status_label)

	var hint := Label.new()
	hint.text = "蓝可打断回复 · 红+绿变黄反射"
	hint.add_theme_font_override("font", BOSS_FONT)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66, 1.0))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(hint)


func _boss_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.035, 0.06, 0.92)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(BOSS_GOLD.r, BOSS_GOLD.g, BOSS_GOLD.b, 0.85)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	return sb


func _boss_bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.02, 0.03, 0.9)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(BOSS_GOLD.r, BOSS_GOLD.g, BOSS_GOLD.b, 0.45)
	sb.set_corner_radius_all(6)
	return sb


func _boss_bar_fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(5)
	return sb


# —— 胜利横幅 ——

func _make_victory_banner() -> void:
	victory_root = Control.new()
	victory_root.name = "BossVictory"
	victory_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	victory_root.offset_left = -360.0
	victory_root.offset_right = 360.0
	victory_root.offset_top = -88.0
	victory_root.offset_bottom = 88.0
	victory_root.pivot_offset = Vector2(360.0, 88.0)
	victory_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_root.visible = false
	add_child(victory_root)

	victory_panel = PanelContainer.new()
	victory_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_panel.add_theme_stylebox_override("panel", _victory_style())
	victory_root.add_child(victory_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var ornament := HBoxContainer.new()
	ornament.alignment = BoxContainer.ALIGNMENT_CENTER
	ornament.add_theme_constant_override("separation", 12)
	box.add_child(ornament)
	var line_l := ColorRect.new()
	line_l.color = Color(BOSS_GOLD.r, BOSS_GOLD.g, BOSS_GOLD.b, 0.65)
	line_l.custom_minimum_size = Vector2(100, 2)
	ornament.add_child(line_l)
	var diamond := Label.new()
	diamond.text = "◆"
	diamond.add_theme_font_override("font", BOSS_FONT)
	diamond.add_theme_font_size_override("font_size", 18)
	diamond.add_theme_color_override("font_color", BOSS_GOLD)
	ornament.add_child(diamond)
	var line_r := ColorRect.new()
	line_r.color = Color(BOSS_GOLD.r, BOSS_GOLD.g, BOSS_GOLD.b, 0.65)
	line_r.custom_minimum_size = Vector2(100, 2)
	ornament.add_child(line_r)

	victory_title = Label.new()
	victory_title.text = "BOSS 已击败"
	victory_title.add_theme_font_override("font", BOSS_FONT)
	victory_title.add_theme_font_size_override("font_size", 46)
	victory_title.add_theme_color_override("font_color", BOSS_GOLD)
	victory_title.add_theme_constant_override("outline_size", 5)
	victory_title.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.95))
	victory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(victory_title)

	victory_subtitle = Label.new()
	victory_subtitle.text = "归途传送门已开启"
	victory_subtitle.add_theme_font_override("font", BOSS_FONT)
	victory_subtitle.add_theme_font_size_override("font_size", 20)
	victory_subtitle.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82, 1.0))
	victory_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(victory_subtitle)


func _victory_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.05, 0.94)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(BOSS_GOLD.r, BOSS_GOLD.g, BOSS_GOLD.b, 0.9)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	return sb


func show_boss_victory(title: String, subtitle: String = "归途传送门已开启", duration: float = 3.0) -> void:
	if victory_root == null:
		return
	victory_title.text = title
	victory_subtitle.text = subtitle
	victory_root.visible = true
	victory_root.modulate.a = 0.0
	victory_root.scale = Vector2(0.94, 0.94)
	if _victory_tween != null and _victory_tween.is_valid():
		_victory_tween.kill()
	_victory_tween = create_tween()
	_victory_tween.tween_property(victory_root, "modulate:a", 1.0, 0.25)
	_victory_tween.parallel().tween_property(victory_root, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_victory_tween.tween_interval(maxf(duration, 0.1))
	_victory_tween.tween_property(victory_root, "modulate:a", 0.0, 0.4)
	_victory_tween.tween_callback(func(): victory_root.visible = false)


func hide_boss_victory() -> void:
	if _victory_tween != null and _victory_tween.is_valid():
		_victory_tween.kill()
	if victory_root != null:
		victory_root.visible = false
		victory_root.modulate.a = 1.0
		victory_root.scale = Vector2.ONE

# Boss HUD / victory banner end.


## 每帧尝试绑定场景中的 Boss（房间异步加载 / Boss 死亡重生后自动重连）。
func _process(delta: float) -> void:
	_tick_alert(delta)
	if _boss != null and is_instance_valid(_boss) and not _boss.is_queued_for_deletion():
		return
	_boss = null
	var found := get_tree().get_first_node_in_group("boss")
	if found == null:
		_set_boss_hud_visible(false)
		return
	_boss = found
	if _boss.has_signal("health_changed"):
		_boss.health_changed.connect(_on_boss_health_changed)
	if _boss.has_signal("state_changed"):
		_boss.state_changed.connect(_on_boss_state_changed)
	if _boss.has_signal("died"):
		_boss.died.connect(_on_boss_died)
	var snap: Dictionary = _boss.health_snapshot()
	var current := float(snap["health"])
	var max_health := float(snap["max_health"])
	boss_bar.max_value = max_health
	boss_ghost_bar.max_value = max_health
	boss_bar.value = current
	boss_ghost_bar.value = current
	_on_boss_health_changed(current, max_health)
	_on_boss_state_changed(Boss.State.CHASE)
	_set_boss_hud_visible(true)


func _on_boss_health_changed(current: float, max_health: float) -> void:
	if boss_bar == null or boss_ghost_bar == null:
		return
	boss_bar.max_value = maxf(max_health, 1.0)
	boss_ghost_bar.max_value = maxf(max_health, 1.0)
	if _boss_bar_tween != null and _boss_bar_tween.is_valid():
		_boss_bar_tween.kill()
	_boss_bar_tween = create_tween()
	_boss_bar_tween.tween_property(boss_bar, "value", current, 0.12)
	if _boss_ghost_tween != null and _boss_ghost_tween.is_valid():
		_boss_ghost_tween.kill()
	_boss_ghost_tween = create_tween()
	_boss_ghost_tween.tween_interval(0.2)
	_boss_ghost_tween.tween_property(boss_ghost_bar, "value", current, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_update_boss_phase(current, max_health)


func _update_boss_phase(current: float, max_health: float) -> void:
	if boss_phase_label == null:
		return
	var ratio := current / maxf(max_health, 1.0)
	var idx := 0
	if ratio <= 0.66:
		idx = 1
	if ratio <= 0.34:
		idx = 2
	var colors := [BOSS_RED, BOSS_BLUE, BOSS_GREEN]
	var names := ["红相", "蓝相", "绿相"]
	for i in boss_pips.size():
		boss_pips[i].modulate.a = 1.0 if i == idx else 0.22
	boss_phase_label.text = names[idx]
	boss_phase_label.add_theme_color_override("font_color", colors[idx])
	if boss_fill != null:
		boss_fill.bg_color = colors[idx]


func _on_boss_state_changed(state: int) -> void:
	if boss_status_label == null:
		return
	var text := "追击"
	var color := BOSS_GOLD
	match state:
		Boss.State.RING_CAST:
			text = "红环蓄力"
			color = BOSS_RED
		Boss.State.ICE_CAST:
			text = "冰弹锁定"
			color = BOSS_BLUE
		Boss.State.HEAL_WINDUP:
			text = "回复蓄力"
			color = BOSS_GREEN
		Boss.State.HEAL:
			text = "回复中"
			color = BOSS_GREEN
		Boss.State.CYAN_CHARGE:
			text = "青色冲锋"
			color = BOSS_CYAN
		Boss.State.STUNNED:
			text = "眩晕"
			color = BOSS_GOLD
		Boss.State.DEAD:
			text = "已击败"
			color = BOSS_GOLD
	boss_status_label.text = text
	boss_status_label.add_theme_color_override("font_color", color)


func _on_boss_died() -> void:
	_set_boss_hud_visible(false)


func _set_boss_hud_visible(visible: bool) -> void:
	if boss_root == null:
		return
	if _boss_fade_tween != null and _boss_fade_tween.is_valid():
		_boss_fade_tween.kill()
	if visible:
		if boss_root.visible and boss_root.modulate.a > 0.99:
			return
		boss_root.visible = true
		boss_root.modulate.a = 0.0
		boss_root.scale = Vector2(0.97, 0.97)
		_boss_fade_tween = create_tween()
		_boss_fade_tween.set_parallel(true)
		_boss_fade_tween.tween_property(boss_root, "modulate:a", 1.0, 0.25)
		_boss_fade_tween.tween_property(boss_root, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		if not boss_root.visible:
			return
		_boss_fade_tween = create_tween()
		_boss_fade_tween.tween_property(boss_root, "modulate:a", 0.0, 0.25)
		_boss_fade_tween.tween_callback(func(): boss_root.visible = false)
