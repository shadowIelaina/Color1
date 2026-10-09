class_name ElementBehavior
extends Node2D

## 元素行为组件：挂在可上色物体上，驱动「燃烧 / 冻结」的行为。
## 纯逻辑层——VFX 播放、状态、蔓延链式、冻结摧毁、燃烧照明。
## 视觉上色由父节点的 colorable_* 脚本负责，这里只做元素效果。
## 视觉中心 / 碎裂目标由宿主装配时显式注入（visual_center / shatter_target），
## 组件不反向猜宿主结构（不再 get("visual")）。

const Rules := preload("res://scripts/element/element_rules.gd")
const SHATTER := preload("res://effects/shatter/shatter.gd")

## 燃烧光斑半径（世界像素，256px ≈ 1 格）。燃烧物在此挖出一片可见区域（塞尔达式遮罩挖洞），越小越聚焦。
@export_range(16.0, 2048.0, 8.0) var light_radius := 352.0
## 燃烧光斑中心偏移（世界像素，相对视觉中心 visual_center；Y 向下为正，往上移用负 Y）。
## 默认 ZERO；物体贴图视觉中心与根原点不一致时，在物品脚本的 Inspector 里微调此值。
@export var light_offset := Vector2.ZERO

var _burning := false
var _frozen := false
var _element := ""

var _parent: Node2D
## 由宿主装配时注入：视觉中心在父局部坐标里的偏移（燃烧光斑 / 碎裂定位用）。
var visual_center := Vector2.ZERO
## 由宿主装配时注入：碎裂时要碎裂的贴图节点；null = 非贴图物体，走淡出兜底。
var shatter_target: CanvasItem = null
var _vfx: Node
var _light: Node2D


func _ready() -> void:
	_parent = get_parent() as Node2D


## 入口：对父物体应用一个元素（由 colorable_* 的 apply_color 调用）。
func apply(element_id: String) -> void:
	if not Rules.has(element_id):
		return
	if element_id == "burn":
		_apply_burn()
	elif element_id == "freeze":
		_apply_freeze()


func has_element() -> bool:
	return _element != ""


func current_element() -> String:
	return _element


## 抽走元素：解除冻结 / 熄灭火焰，清除 VFX。由 colorable_* 的 absorb_color 调用。
func clear() -> void:
	_burning = false
	_frozen = false
	_element = ""
	_clear_vfx()
	_free_light()


func _apply_burn() -> void:
	if _burning:
		return
	# 点燃冻结中的物体 = 解冻后再燃烧。
	if _frozen:
		_frozen = false
		_clear_vfx()

	_burning = true
	_element = "burn"
	_spawn_vfx("burn")
	_spawn_light()
	_schedule_spread("burn")


func _apply_freeze() -> void:
	# 冻结正在燃烧的物体 = 熄灭并摧毁（交互：freeze × burn → 销毁）。
	if _burning:
		_burning = false
		_element = ""
		_clear_vfx()
		_free_light()
		_shatter()
		return

	if _frozen:
		return
	_frozen = true
	_element = "freeze"
	_spawn_vfx("freeze")
	_schedule_spread("freeze")


func _schedule_spread(element_id: String) -> void:
	var cfg := Rules.config(element_id)
	if not cfg.get("spreads", false):
		return
	get_tree().create_timer(cfg["spread_delay"]).timeout.connect(_do_spread.bind(element_id))


func _do_spread(element_id: String) -> void:
	if _element != element_id:
		return  # 状态已变（被熄灭/解冻），不再蔓延。
	if _parent == null or not is_instance_valid(_parent):
		return
	var cfg := Rules.config(element_id)
	var radius: float = cfg.get("spread_radius", 60.0)
	for obj in get_tree().get_nodes_in_group("colorable"):
		if obj == _parent:
			continue
		if not GameState.is_in_current_scene(obj):
			continue
		var n := obj as Node2D
		if n == null or not is_instance_valid(n):
			continue
		if not n.has_method("apply_color"):
			continue  # 冰块等不可上色物体也在 colorable 组里，但没有 apply_color。
		if _parent.global_position.distance_to(n.global_position) <= radius:
			n.call("apply_color", cfg["color"], cfg["color_name"], _parent.global_position)


## 点燃时在燃烧物视觉中心放一个光照标记，黑暗遮罩会在此挖出一片可见区域。
func _spawn_light() -> void:
	_free_light()
	if _parent == null or not is_instance_valid(_parent):
		return
	var l := LightSource.new()
	l.radius = light_radius
	l.position = visual_center + light_offset
	_parent.add_child(l)
	_light = l


func _free_light() -> void:
	if _light != null and is_instance_valid(_light):
		_light.queue_free()
	_light = null


func _spawn_vfx(element_id: String) -> void:
	_clear_vfx()
	var cfg := Rules.config(element_id)
	var scene: PackedScene = load(cfg.get("vfx", ""))
	if scene == null:
		return
	_vfx = scene.instantiate()
	_vfx.set("loop", false)  # 只播一次
	_parent.add_child(_vfx)


func _clear_vfx() -> void:
	if _vfx != null and is_instance_valid(_vfx):
		_vfx.queue_free()
	_vfx = null


func _shatter() -> void:
	if _parent == null or not is_instance_valid(_parent):
		return
	# 碎裂目标由宿主注入（shatter_target）；非贴图物体（Polygon2D 等）为 null，走淡出兜底。
	if shatter_target != null and is_instance_valid(shatter_target):
		var shatter := SHATTER.new()
		shatter.target = shatter_target
		shatter.loop = false
		_parent.add_child(shatter)
		shatter.shatter()
		get_tree().create_timer(shatter.duration + 0.2).timeout.connect(_parent.queue_free)
	else:
		# 非贴图物体（Polygon2D 等）：淡出后销毁。
		var t := create_tween()
		t.tween_property(_parent, "modulate:a", 0.0, 0.5)
		t.tween_callback(_parent.queue_free)
