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
## 冻结持续时长（秒）：到点自然融化回无色。≤0 = 永不自然融化。
@export var melt_time := 8.0
## 靠近燃烧物此半径内（世界像素），融化速度 ×6（快速化）。
@export var melt_heat_radius := 512.0

var _burning := false
var _frozen := false
var _element := ""
var _melt_left := 0.0   # 剩余冻结时间（秒）；<0 = 永不自然融化；=0 = 未在倒计时

var _parent: Node2D
## 物质 id（由宿主注入，对应 ElementRules.MATERIALS）：决定蔓延/光斑/交叉反应等专属行为。
var material_id := ""
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


## 当前是否处于冻结状态（供蔓延判断「挡火」等用）。
## 这是 ElementBehavior 节点上的方法（本身不在 colorable 组），与水格 WaterCell.is_frozen() 不冲突。
func is_frozen() -> bool:
	return _frozen


## 当前是否处于燃烧状态（供「冰靠近火加速融化」判断）。
func is_burning() -> bool:
	return _burning


## 抽走元素：解除冻结 / 熄灭火焰，清除 VFX。由 colorable_* 的 absorb_color 调用。
func clear() -> void:
	_burning = false
	_frozen = false
	_element = ""
	_melt_left = 0.0
	_clear_vfx()
	_free_light()


func _apply_burn() -> void:
	if _burning:
		return
	# 火烧到冻结物 = 先融化（解冻、清霜 VFX）再燃烧。火↔冰双向：红胜于冻。
	if _frozen:
		_frozen = false
		_clear_vfx()
		_melt_left = 0.0

	_burning = true
	_element = "burn"
	_spawn_vfx("burn")
	_spawn_light()
	_schedule_spread("burn")


func _apply_freeze() -> void:
	if _frozen:
		return
	# 浇蓝到燃烧物 = 灭火保留：熄火、撤光斑，转成冻结（fire × freeze 不再销毁物体，改为「火被冰压下去」）。
	if _burning:
		_burning = false
		_free_light()
	_frozen = true
	_element = "freeze"
	_spawn_vfx("freeze")  # 内部先 _clear_vfx 清掉火 VFX，再上霜
	_schedule_spread("freeze")
	# 启动自然融化倒计时：按物质分表取时长（石头存冷最久、草最易化），缺省回 @export 默认。
	var dur := float(Rules.material_config(material_id).get("melt_time", melt_time))
	_melt_left = dur if dur > 0.0 else -1.0


func _process(delta: float) -> void:
	if not _frozen or _melt_left < 0.0:
		return
	# 靠近火源 → 6 倍速融化；否则正常倒计时。
	_melt_left -= delta * (6.0 if _near_fire() else 1.0)
	if _melt_left <= 0.0:
		_melt()


## 自然融化：解冻、清霜 VFX、滴水、回无色（霜渐退交给宿主）。
func _melt() -> void:
	_frozen = false
	_element = ""
	_melt_left = 0.0
	_clear_vfx()
	_spawn_melt_vfx()
	# 霜渐退：让宿主把颜色淡出回初始色（有该钩子才调；草/树无持久色则跳过）。
	if _parent != null and is_instance_valid(_parent) and _parent.has_method("fade_visual_out"):
		_parent.call("fade_visual_out")


func _spawn_melt_vfx() -> void:
	if _parent == null or not is_instance_valid(_parent):
		return
	var scene: PackedScene = load(Rules.config("freeze").get("melt_vfx", ""))
	if scene == null:
		return
	var drip := scene.instantiate()
	_parent.add_child(drip)


## 周围是否有燃烧中的物体（用于「冰靠近火加速融化」）。
func _near_fire() -> bool:
	if _parent == null or not is_instance_valid(_parent):
		return false
	for obj in get_tree().get_nodes_in_group("colorable"):
		if obj == _parent:
			continue
		if not GameState.is_in_current_scene(obj):
			continue
		var n := obj as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var beh := n.get_node_or_null("ElementBehavior") as ElementBehavior
		if beh == null or not beh.is_burning():
			continue
		if _parent.global_position.distance_to(n.global_position) <= melt_heat_radius:
			return true
	return false


func _schedule_spread(element_id: String) -> void:
	var cfg := Rules.config(element_id)
	var spreads: bool = cfg.get("spreads", false)
	if element_id == "burn":
		# 按物质分表：木头/草会蔓延，石头不蔓延。
		spreads = bool(Rules.material_config(material_id).get("burn_spreads", spreads))
	if not spreads:
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
		if not n.is_in_group("grid_object"):
			continue  # 只向真实物体（树/石头/草）蔓延，不泼到地面颜料层/水格。
		# 冻结的物体 = 防火隔离带：火不蔓延过去。用 ElementBehavior.is_frozen()（不动宿主公共方法，避免与水格 is_frozen 冲突）。
		var tbeh := n.get_node_or_null("ElementBehavior") as ElementBehavior
		if tbeh != null and tbeh.is_frozen():
			continue
		if _parent.global_position.distance_to(n.global_position) <= radius:
			n.call("apply_color", cfg["color"], cfg["color_name"], _parent.global_position)


## 点燃时在燃烧物视觉中心放一个光照标记，黑暗遮罩会在此挖出一片可见区域。
func _spawn_light() -> void:
	_free_light()
	if _parent == null or not is_instance_valid(_parent):
		return
	var l := LightSource.new()
	var r := light_radius
	if _element == "burn":
		r = float(Rules.material_config(material_id).get("burn_light", light_radius))
	l.radius = r
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


## 红+蓝 交叉反应：按物质分表决定碎裂销毁(木头)还是烧毁/枯萎淡出(石头/草)。
func _destroy() -> void:
	if Rules.cross_reaction(material_id) == "fade":
		_fade_out()
	else:
		_shatter()


## 淡出销毁（石头开裂 / 草枯萎 / 无贴图物体兜底）。
func _fade_out() -> void:
	if _parent == null or not is_instance_valid(_parent):
		return
	var t := create_tween()
	t.tween_property(_parent, "modulate:a", 0.0, 0.5)
	t.tween_callback(_parent.queue_free)
