class_name ColorableBase
extends StaticBody2D
## colorable 契约基类：装配 ElementBehavior，并把「元素转发」这一块（apply_color 的元素派发、
## has_color / absorb_color 的状态读写）集中在这里。子类只需实现自己的视觉反馈钩子
## （_apply_visual / _reset_visual / _apply_seed_visual）和命中判定 contains_point。

const Rules := preload("res://scripts/element/element_rules.gd")
const Behavior := preload("res://scripts/element/element_behavior.gd")

## 燃烧光斑半径（世界像素，256px ≈ 1 格）。转发给 ElementBehavior，可在实例上调。
@export_range(16.0, 2048.0, 8.0) var light_radius := 352.0
## 燃烧光斑中心偏移（世界像素，相对视觉中心，Y 向下为正）。转发给 ElementBehavior。
@export var light_offset := Vector2.ZERO
## 初始颜色名：非空时开局直接以该颜色/元素起手（如 "red" = 预置燃烧）。
@export var initial_color_name := ""

var _behavior: ElementBehavior


func _ready() -> void:
	add_to_group("colorable")
	_setup_behavior()
	_seed_initial_color()


func _setup_behavior() -> void:
	_behavior = Behavior.new()
	_behavior.name = "ElementBehavior"
	_behavior.light_radius = light_radius
	_behavior.light_offset = light_offset
	_configure_behavior(_behavior)
	add_child(_behavior)


## 子类钩子：装配时注入行为组件所需的「视觉中心偏移 / 碎裂目标贴图」（默认空实现）。
func _configure_behavior(behavior: ElementBehavior) -> void:
	pass


## 上色入口：先让子类做视觉反馈（扩散），再把元素派发给行为组件。
func apply_color(c: Color, color_name: String = "", from_pos: Vector2 = Vector2.INF) -> bool:
	var origin := global_position if from_pos == Vector2.INF else from_pos
	_apply_visual(c, origin)
	var element := Rules.element_for_color_name(color_name)
	if element != "":
		_behavior.apply(element)
	return true


func has_color() -> bool:
	return _behavior.has_element()


## 命中判定：世界坐标点是否落在物体上。子类各自实现（多边形 / 贴图矩形）。
func contains_point(_world_pos: Vector2) -> bool:
	return false


## 抽走当前颜色/元素：返回颜色信息，并让子类把物体还原成初始色。
func absorb_color() -> Dictionary:
	var el := _behavior.current_element()
	_behavior.clear()
	_reset_visual()
	var cfg := Rules.config(el)
	return {
		"element": el,
		"color": cfg.get("color", Color.WHITE),
		"color_name": cfg.get("color_name", ""),
	}


## 开局种子：若在编辑器中设了 initial_color_name，则物体直接以该颜色/元素起手。
func _seed_initial_color() -> void:
	var el := Rules.element_for_color_name(initial_color_name)
	if el == "":
		return
	var cfg := Rules.config(el)
	_apply_seed_visual(cfg)
	_behavior.apply(el)


## —— 子类视觉钩子（默认空实现）——

## 上色时的视觉反馈（如颜色扩散动画）。默认无视觉，直接由 VFX 表现。
func _apply_visual(_c: Color, _origin: Vector2) -> void:
	pass


## 抽走颜色后把视觉还原成初始态。
func _reset_visual() -> void:
	pass


## 开局种子色应用到视觉（默认无视觉）。
func _apply_seed_visual(_cfg: Dictionary) -> void:
	pass
