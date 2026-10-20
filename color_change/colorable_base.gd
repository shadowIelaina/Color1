class_name ColorableBase
extends StaticBody2D
## colorable 契约基类：装配 ElementBehavior，并把「元素转发」这一块（apply_color 的元素派发、
## has_color / absorb_color 的状态读写）集中在这里。子类只需实现自己的视觉反馈钩子
## （_apply_visual / _reset_visual / _apply_seed_visual）和命中判定 contains_point。

const Rules := preload("res://scripts/element/element_rules.gd")
const Behavior := preload("res://scripts/element/element_behavior.gd")
const DepthSort := preload("res://scripts/depth_sort.gd")

## 燃烧光斑半径（世界像素，256px ≈ 1 格）。转发给 ElementBehavior，可在实例上调。
@export_range(16.0, 2048.0, 8.0) var light_radius := 352.0
## 燃烧光斑中心偏移（世界像素，相对视觉中心，Y 向下为正）。转发给 ElementBehavior。
@export var light_offset := Vector2.ZERO
## 青（蓝×绿混合）态：移动方向与距离。转发给 ElementBehavior，策划在此逐物体调节。
@export var cyan_move_dir := Vector2.RIGHT
@export_range(0.0, 4096.0, 8.0) var cyan_move_distance := 768.0
@export_range(0.05, 5.0, 0.05) var cyan_move_duration := 0.5
## 青色状态被玩家推动的速度（像素/秒）。
@export_range(0.0, 3000.0, 5.0) var cyan_push_speed := 600.0
## 黄（红×绿混合）态：是否开启子弹反射与反射参数。转发给 ElementBehavior。
@export var reflect_bullets := true
@export_range(8.0, 2048.0, 1.0) var reflect_radius := 176.0
@export var reflect_faction := "player"
## 初始颜色名：非空时开局直接以该颜色/元素起手（如 "red" = 预置燃烧）。
@export var initial_color_name := ""
## 是否参与上色/元素系统。false 时保留场景物体，但不加入 colorable 组、不创建行为组件。
@export var colorable := true

var _behavior: ElementBehavior


func _ready() -> void:
	# 深度排序：按脚底世界 Y 定 z_index，让玩家走到树/箱子后（北）侧时被它们挡住。
	z_index = DepthSort.z_for(global_position.y)
	if not colorable:
		return
	add_to_group("colorable")
	_setup_behavior()
	_seed_initial_color()


func _setup_behavior() -> void:
	_behavior = Behavior.new()
	_behavior.name = "ElementBehavior"
	_behavior.light_radius = light_radius
	_behavior.light_offset = light_offset
	_behavior.cyan_move_dir = cyan_move_dir
	_behavior.cyan_move_distance = cyan_move_distance
	_behavior.cyan_move_duration = cyan_move_duration
	_behavior.reflect_bullets = reflect_bullets
	_behavior.reflect_radius = reflect_radius
	_behavior.reflect_faction = reflect_faction
	_configure_behavior(_behavior)
	add_child(_behavior)


## 子类钩子：装配时注入行为组件所需的「视觉中心偏移 / 碎裂目标贴图」（默认空实现）。
func _configure_behavior(behavior: ElementBehavior) -> void:
	pass


## 上色入口：先派发元素给行为组件，状态真的变了才做视觉反馈（扩散）。
## 返回是否真的生效（同色重复给 = false），供玩家侧据此判断是否消耗种子。
func apply_color(c: Color, color_name: String = "", from_pos: Vector2 = Vector2.INF) -> bool:
	var element := Rules.element_for_color_name(color_name)
	if element == "":
		return false
	if not _behavior.apply(element, from_pos):
		return false
	var show := c
	var cur := _behavior.current_element()
	if cur == "cyan" or cur == "yellow":
		show = Rules.config(cur)["color"]
	var origin := global_position if from_pos == Vector2.INF else from_pos
	_apply_visual(show, origin)
	return true


func has_color() -> bool:
	return _behavior.has_element()


## 当前元素状态（非破坏性读取：burn / freeze / grow / ""）。供元素踏板等传感器查询。
func current_element() -> String:
	return _behavior.current_element() if _behavior != null else ""


## 青色状态可被玩家推动（推箱子式）；非青色返回不推。
func push(dir: Vector2, delta: float) -> void:
	if _behavior == null or _behavior.current_element() != "cyan":
		return
	if dir == Vector2.ZERO or delta <= 0.0:
		return
	move_and_collide(dir.normalized() * cyan_push_speed * delta)
	# 推动后按脚底世界 Y 重算深度排序，保证玩家在树北侧时被树遮挡、南侧时挡在树前。
	z_index = DepthSort.z_for(global_position.y)


## 命中判定：世界坐标点是否落在物体上。子类各自实现（多边形 / 贴图矩形）。
func contains_point(_world_pos: Vector2) -> bool:
	return false


## 抽走当前颜色/元素：返回颜色信息，并让子类把物体还原成初始色。
func absorb_color() -> Dictionary:
	var els: Array = _behavior.absorb()
	_reset_visual()
	if els.size() == 1 and els[0] != "":
		var el: String = els[0]
		var cfg := Rules.config(el)
		return {
			"element": el,
			"color": cfg.get("color", Color.WHITE),
			"color_name": cfg.get("color_name", ""),
		}
	# 多元素返还（青 → 蓝+绿）：直接退给玩家，跟班不再带回。
	_refund_elements(els)
	return {
		"element": "",
		"color": Color.WHITE,
		"color_name": "",
	}


## 把吸收得到的元素种子直接退还给玩家（青色返还蓝+绿时用）。
func _refund_elements(els: Array) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("refund_element"):
		return
	for el in els:
		if el != "":
			player.call("refund_element", el, 1)


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
