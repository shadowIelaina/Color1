extends Node2D
## 悬停格高亮 + 提示框：显示鼠标下那格 tile 的物质、物品与状态（程序化世界专用 POC）。
## 高亮 = 世界空间里给「鼠标下那块占地（footprint）」画边框；提示框 = CanvasLayer 里的 Label 跟随鼠标。
## 不另造网格系统——格子就是现成的 256px tile（WorldTileset.TILE_PX）。
## 多格物品（建筑/大树）：物品声明 footprint（占地格数），高亮与提示按 footprint 展开。
##
## 描边画在独立 CanvasLayer（永远盖在主画布之上）：草的 MeshInstance2D 在主画布里 z 排序不可靠，
## 会盖住普通 _draw 出来的边框，放进 CanvasLayer 后绕开该问题。

const TILE := 256.0
const MATERIAL_NAMES := {0: "水", 1: "沙", 2: "雪", 3: "沙漠", 4: "森林"}
const Rules := preload("res://scripts/element/element_rules.gd")
const OutlineScript := preload("res://scripts/world/hover_outline.gd")

# 高亮描边颜色：默认亮金（未上色/可互动）。悬停到已上色物品时改成它的元素色（红=烧/蓝=冻）。
const ACCENT := Color(1.0, 0.82, 0.1, 1.0)

var _tooltip: Label
var _hover_cell := Vector2i(-1000000, -1000000)
var _hover_size := Vector2(TILE, TILE)  # 高亮框世界尺寸（= footprint 格数 × TILE）
var _visible := false
var _accent := ACCENT  # 当前高亮主色（描边节点据此派生外圈/填充色）
# 描边画在 CanvasLayer 里（永远盖在主画布之上）。
var _outline_layer: CanvasLayer
var _outline: Node2D


func _ready() -> void:
	_build_outline()
	_build_tooltip()


func _process(_delta: float) -> void:
	var mp := get_global_mouse_position()
	var cell := Vector2i(floori(mp.x / TILE), floori(mp.y / TILE))
	var material := _material_at(mp)
	_visible = material != -1
	if not _visible:
		_tooltip.visible = false
		_outline.call("set_box", Vector2.ZERO, _hover_size, _accent, false)
		return
	if cell != _hover_cell:
		_hover_cell = cell
		_apply_footprint(cell)
	_update_accent(cell, material)
	_update_outline()
	_update_tooltip(mp, cell, material)


## 把当前高亮框同步到 CanvasLayer 里的描边节点。
## 描边节点在屏幕空间绘制（边框是屏幕像素），所以这里把世界中心/尺寸换算成屏幕中心/尺寸。
func _update_outline() -> void:
	var ct := get_viewport().get_canvas_transform()
	var screen_center := ct * position
	var screen_size := _hover_size * ct.get_scale()
	_outline.call("set_box", screen_center, screen_size, _accent, true)


## 鼠标下的格上若有物品，高亮/提示按物品 footprint 展开；否则只亮这一格。
func _apply_footprint(cell: Vector2i) -> void:
	var obj := _object_at(cell)
	var fp := Rect2i(cell, Vector2i(1, 1))
	if obj != null:
		var size: Vector2i = obj.get_meta("footprint", Vector2i(1, 1))
		var anchor := _object_anchor(obj)
		var origin := Vector2i(floori(anchor.x / TILE), floori(anchor.y / TILE))
		fp = Rect2i(origin, size)
	var world_origin := Vector2(fp.position) * TILE
	_hover_size = Vector2(fp.size) * TILE
	position = world_origin + _hover_size * 0.5


## 高亮主色随悬停对象/地面状态变：对象元素色 > 地面颜料色 > 默认金。
func _update_accent(cell: Vector2i, material: int) -> void:
	var col := ACCENT
	var obj := _object_at(cell)
	if obj != null and obj.has_method("get_element_color"):
		var c := obj.call("get_element_color") as Color
		if c.a > 0.0:
			col = c
	if col == ACCENT:
		var painted := _painted_at(cell) if material != WorldGenerator.Tile.WATER else -1
		if painted == 0:
			col = _element_color("burn")
		elif painted == 1:
			col = _element_color("freeze")
	_accent = col


func _element_color(element_id: String) -> Color:
	return Rules.config(element_id).get("color", ACCENT) as Color


## 鼠标世界坐标 → 那格 tile 的物质（source id == Tile 枚举值）。无 chunk 覆盖返回 -1。
func _material_at(world_pos: Vector2) -> int:
	for chunk in get_tree().get_nodes_in_group("colorable"):
		if not (chunk is TileMapLayer) or not chunk.has_method("absorb_color"):
			continue
		var layer := chunk as TileMapLayer
		var src := layer.get_cell_source_id(layer.local_to_map(layer.to_local(world_pos)))
		if src != -1:
			return src
	return -1


## 格 (x,y) 上覆盖的网格物品（footprint 含该格的第一个），没有返回 null。
func _object_at(cell: Vector2i) -> Node2D:
	for node in get_tree().get_nodes_in_group("grid_object"):
		if not (node is Node2D):
			continue
		var obj := node as Node2D
		var size: Vector2i = obj.get_meta("footprint", Vector2i(1, 1))
		var anchor := _object_anchor(obj)
		var origin := Vector2i(floori(anchor.x / TILE), floori(anchor.y / TILE))
		if Rect2i(origin, size).has_point(cell):
			return obj
	return null


## 对象视觉中心的世界坐标：草/树等贴图从节点原点向上偏移，命中与高亮应对准视觉而非原点。
## Interactable 写 meta "visual_offset"；带 "Visual" 子贴图（树/石头）直接取它的全局位置。
func _object_anchor(obj: Node2D) -> Vector2:
	if obj.has_meta("visual_offset"):
		return obj.global_position + (obj.get_meta("visual_offset") as Vector2)
	var visual := obj.get_node_or_null("Visual") as Node2D
	if visual != null:
		return visual.global_position
	return obj.global_position


func _update_tooltip(mp: Vector2, cell: Vector2i, material: int) -> void:
	var painted := -1
	var frozen := false
	if material == WorldGenerator.Tile.WATER:
		frozen = _water_frozen_at(mp)
	else:
		painted = _painted_at(cell)
	var obj := _object_at(cell)
	var obj_label := ""
	if obj != null:
		obj_label = str(obj.get_meta("grid_label", ""))
	_tooltip.text = _make_text(material, frozen, painted, obj_label)
	_tooltip.visible = true
	_tooltip.position = get_viewport().get_mouse_position() + Vector2(18, 18)


func _make_text(material: int, frozen: bool, painted: int, obj_label: String = "") -> String:
	var mat_name: String = MATERIAL_NAMES.get(material, "?")
	var state := ""
	if material == WorldGenerator.Tile.WATER:
		state = " · 已结冰" if frozen else " · 挡路（蓝→结冰）"
	elif painted == 0:
		state = " · 已泼红"
	elif painted == 1:
		state = " · 已泼蓝"
	var obj_part := (" · " + obj_label) if obj_label != "" else ""
	return mat_name + obj_part + state


func _painted_at(cell: Vector2i) -> int:
	var paint := get_tree().get_first_node_in_group("ground_paint")
	if paint == null:
		return -1
	return paint.get_cell_source_id(cell)


func _water_frozen_at(world_pos: Vector2) -> bool:
	for obj in get_tree().get_nodes_in_group("colorable"):
		if obj.has_method("is_frozen") and obj.has_method("contains_point"):
			if bool(obj.call("contains_point", world_pos)) and bool(obj.call("is_frozen")):
				return true
	return false


func _build_outline() -> void:
	_outline_layer = CanvasLayer.new()
	_outline_layer.name = "OutlineLayer"
	_outline_layer.layer = 9  # 低于提示框(10)，但仍盖在主画布之上
	add_child(_outline_layer)
	_outline = OutlineScript.new() as Node2D
	_outline.name = "Outline"
	_outline_layer.add_child(_outline)


func _build_tooltip() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HoverUI"
	layer.layer = 10
	add_child(layer)
	_tooltip = Label.new()
	_tooltip.name = "CellTooltip"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	sb.border_color = ACCENT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	_tooltip.add_theme_stylebox_override("normal", sb)
	_tooltip.add_theme_color_override("font_color", Color(1, 1, 1))
	_tooltip.visible = false
	layer.add_child(_tooltip)
