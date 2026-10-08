class_name ElementBehavior
extends Node2D

## 元素行为组件：挂在可上色物体上，驱动「燃烧 / 冻结」的行为。
## 纯逻辑层——VFX 播放、状态、蔓延链式、烧尽碎裂、冻结交互。
## 视觉上色由父节点的 colorable_* 脚本负责，这里只做元素效果。

const Rules := preload("res://scripts/element/element_rules.gd")
const SHATTER := preload("res://effects/shatter/shatter.gd")

var _burning := false
var _frozen := false
var _element := ""

var _parent: Node2D
var _vfx: Node


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
	_schedule_spread("burn")
	_schedule_burnout()


func _apply_freeze() -> void:
	# 冻结正在燃烧的物体 = 熄灭火焰（交互：freeze × burn）。
	if _burning:
		_burning = false
		_element = ""
		_clear_vfx()

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
		var n := obj as Node2D
		if n == null or not is_instance_valid(n):
			continue
		if not n.has_method("apply_color"):
			continue  # 冰块等不可上色物体也在 colorable 组里，但没有 apply_color。
		if _parent.global_position.distance_to(n.global_position) <= radius:
			n.call("apply_color", cfg["color"], cfg["color_name"], _parent.global_position)


func _schedule_burnout() -> void:
	var cfg := Rules.config("burn")
	get_tree().create_timer(cfg["burn_duration"]).timeout.connect(_burn_out)


func _burn_out() -> void:
	if not _burning:
		return  # 已被冻结熄灭，不碎裂。
	_burning = false
	_element = ""
	_clear_vfx()
	_shatter()


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
	# 碎裂目标：优先取父节点本身的贴图；否则取它的 "visual" 子贴图（colorable_static 等）。
	var target: CanvasItem = null
	if _parent is Sprite2D:
		target = _parent
	else:
		var visual: CanvasItem = _parent.get("visual")
		if visual is Sprite2D:
			target = visual
	if target != null:
		var shatter := SHATTER.new()
		shatter.target = target
		shatter.loop = false
		_parent.add_child(shatter)
		shatter.shatter()
		get_tree().create_timer(shatter.duration + 0.2).timeout.connect(_parent.queue_free)
	else:
		# 非贴图物体（Polygon2D 等）：淡出后销毁。
		var t := create_tween()
		t.tween_property(_parent, "modulate:a", 0.0, 0.5)
		t.tween_callback(_parent.queue_free)
