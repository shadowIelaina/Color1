class_name Interactable
extends Node2D
## 通用可互动世界物品（无碰撞）：把任意视觉（Sprite2D "Visual" 或一个 prefab 实例）包起来，
## 获得 colorable 契约（泼色/吸收/命中）+ ElementBehavior（按物质分表反应）+ 网格占地。
## 与 ColorableStatic（带碰撞的树/木）并列；草/石头/未来新物品用它，天生可互动。
## 命中判定用 footprint 占地矩形（不依赖贴图形状），悬停描边/提示也按 footprint 展开。

const Rules := preload("res://scripts/element/element_rules.gd")
const Behavior := preload("res://scripts/element/element_behavior.gd")
const DepthSort := preload("res://scripts/depth_sort.gd")

const TILE := 256.0

@export var material_id := "stone"          # 物质 id（对应 ElementRules.MATERIALS）
@export var grid_label := ""                 # 悬停提示里显示的名字
@export var footprint := Vector2i(1, 1)      # 占地格数（建筑/大树写 w,h）
@export var visual_offset := Vector2.ZERO    # 视觉贴图相对节点原点的偏移（草/树贴图不在原点，命中/高亮应对准视觉）
@export_range(16.0, 2048.0, 8.0) var light_radius := 352.0
@export var initial_color_name := ""

var _behavior: ElementBehavior
## 实际要染色的视觉节点：草=MeshInstance2D（贴图在网格上）、石头=Visual Sprite2D。
var _visual_canvas: CanvasItem = null
var _initial_self_modulate := Color.WHITE
var _tween: Tween


func _ready() -> void:
	z_index = DepthSort.z_for(global_position.y)
	add_to_group("colorable")
	add_to_group("grid_object")
	set_meta("grid_label", grid_label)
	set_meta("footprint", footprint)
	set_meta("visual_offset", visual_offset)
	_setup_behavior()
	_ensure_visual_proxy()
	_setup_visual_canvas()
	if initial_color_name != "":
		var el := Rules.element_for_color_name(initial_color_name)
		if el != "":
			_behavior.apply(el)
			_tint(Rules.config(el).get("color", Color.WHITE))


func _setup_behavior() -> void:
	_behavior = Behavior.new()
	_behavior.name = "ElementBehavior"
	_behavior.material_id = material_id
	_behavior.light_radius = light_radius
	# 视觉中心/碎裂目标：有 "Visual" 贴图（石头）则注入；纯 prefab（草，无贴图）走淡出兜底。
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual != null:
		_behavior.visual_center = visual.position
		_behavior.shatter_target = visual
	add_child(_behavior)


## 草这类视觉是 MeshInstance2D（贴图在网格上、没有 "Visual" Sprite2D），而玩家的彩色描边
## （player.gd _outline_sprite）只认 Sprite2D，所以草一直没描边。这里补一个隐藏的 "Visual"
## Sprite2D 代理：贴图/位置/旋转/缩放与网格完全一致，只用来给描边当锚点，自己不显示。
func _ensure_visual_proxy() -> void:
	if get_node_or_null("Visual") != null:
		return
	var mesh := find_child("MeshInstance2D", true, false) as MeshInstance2D
	if mesh == null:
		return
	var tex := mesh.texture
	if tex == null:
		return
	var proxy := Sprite2D.new()
	proxy.name = "Visual"
	proxy.texture = tex
	proxy.centered = true
	proxy.position = mesh.position
	proxy.rotation = mesh.rotation
	# 网格把贴图铺在 1×1 四边形上再乘 scale；Sprite2D 按贴图像素尺寸渲染，故要除以像素尺寸换算。
	proxy.scale = mesh.scale / tex.get_size()
	# QuadMesh 在 MeshInstance2D 里会把贴图竖向翻转（UV 的 V 轴与 Sprite2D 相反），
	# 直接抄 rotation 会让描边上下颠倒。补一个 flip_v 抵消，方向才能和网格一致。
	proxy.flip_v = true
	proxy.self_modulate = Color(1.0, 1.0, 1.0, 0.0)  # 隐藏自身，只当描边锚点
	add_child(proxy)


## 找到要染色的视觉节点：草=MeshInstance2D（贴图在网格上）、石头=Visual Sprite2D。
## 染色用 self_modulate（不向下传播），避免连累挂在 "Visual" 下的悬停描边一起被染。
func _setup_visual_canvas() -> void:
	var mesh := find_child("MeshInstance2D", true, false) as MeshInstance2D
	if mesh != null:
		_visual_canvas = mesh
	else:
		_visual_canvas = get_node_or_null("Visual") as Sprite2D
	if _visual_canvas != null:
		_initial_self_modulate = _visual_canvas.self_modulate


## 命中：占地矩形（footprint 格数 × 256px，以节点原点为中心）。世界坐标点是否落在里面。
func contains_point(world_pos: Vector2) -> bool:
	var size := Vector2(footprint) * TILE
	return Rect2(global_position + visual_offset - size * 0.5, size).has_point(world_pos)


func apply_color(c: Color, color_name: String = "", _from_pos: Vector2 = Vector2.INF) -> bool:
	var el := Rules.element_for_color_name(color_name)
	if el == "":
		return false
	_behavior.apply(el)
	_tint(c)
	return true


func has_color() -> bool:
	return _behavior.has_element()


## 当前元素颜色（透明 = 未上色），供悬停描边取色。
func get_element_color() -> Color:
	var el := _behavior.current_element()
	if el == "":
		return Color.TRANSPARENT
	return Rules.config(el).get("color", Color.WHITE)


func absorb_color() -> Dictionary:
	var el := _behavior.current_element()
	_behavior.clear()
	_reset_tint()
	var cfg := Rules.config(el)
	return {
		"element": el,
		"color": cfg.get("color", Color.WHITE),
		"color_name": cfg.get("color_name", ""),
	}


## 染色：把视觉节点的 self_modulate 直接设为元素色（红=燃烧持续红、蓝=冻结持续蓝）。
func _tint(c: Color) -> void:
	if _visual_canvas == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_visual_canvas.self_modulate = c


func _reset_tint() -> void:
	if _visual_canvas == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_visual_canvas.self_modulate = _initial_self_modulate


## 融化（自然解冻）时把颜色淡出回初始灰白（霜渐退）。
func fade_visual_out() -> void:
	if _visual_canvas == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_visual_canvas, "self_modulate", _initial_self_modulate, 0.5)
