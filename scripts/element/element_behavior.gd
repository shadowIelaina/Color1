class_name ElementBehavior
extends Node2D

## 元素行为组件：挂在可上色物体上，驱动「燃烧 / 冻结」的行为。
## 纯逻辑层——VFX 播放、状态、蔓延链式、冻结摧毁、燃烧照明。
## 视觉上色由父节点的 colorable_* 脚本负责，这里只做元素效果。
## 视觉中心 / 碎裂目标由宿主装配时显式注入（visual_center / shatter_target），
## 组件不反向猜宿主结构（不再 get("visual")）。

const Rules := preload("res://scripts/element/element_rules.gd")
const SHATTER := preload("res://effects/shatter/shatter.gd")
const Reflector := preload("res://scripts/mechanics/bullet_reflector.gd")

## 燃烧光斑半径（世界像素，256px ≈ 1 格）。燃烧物在此挖出一片可见区域（塞尔达式遮罩挖洞），越小越聚焦。
@export_range(16.0, 2048.0, 8.0) var light_radius := 352.0
## 燃烧光斑中心偏移（世界像素，相对视觉中心 visual_center；Y 向下为正，往上移用负 Y）。
## 默认 ZERO；物体贴图视觉中心与根原点不一致时，在物品脚本的 Inspector 里微调此值。
@export var light_offset := Vector2.ZERO
## 燃烧时是否播放火焰 VFX（fire.tscn）。溶解烧毁类燃料（枯木等）用溶解 shader 取代火焰，宿主装配时关掉。
@export var play_burn_vfx := true
## 青（蓝×绿混合）态：物体朝哪个方向移动（单位向量；拿不到赋予来源时用此兜底方向）。
@export var cyan_move_dir := Vector2.RIGHT
## 青态移动距离（世界像素，256 = 一格）。
@export var cyan_move_distance := 768.0
## 青态移动时长（秒）。
@export var cyan_move_duration := 0.5
## 黄（红×绿混合）态：是否自动开启子弹反射（变黄后把范围内的可弹反子弹弹回去）。
@export var reflect_bullets := true
## 黄色反射范围（世界像素）。
@export_range(8.0, 2048.0, 1.0) var reflect_radius := 176.0
## 反射后子弹归属阵营。
@export var reflect_faction := "player"

var _burning := false
var _frozen := false
var _grown := false
var _cyan := false
var _yellow := false
var _element := ""

var _parent: Node2D
## 由宿主装配时注入：视觉中心在父局部坐标里的偏移（燃烧光斑 / 碎裂定位用）。
var visual_center := Vector2.ZERO
## 由宿主装配时注入：碎裂时要碎裂的贴图节点；null = 非贴图物体，走淡出兜底。
var shatter_target: CanvasItem = null
var _vfx: Node
var _light: Node2D
var _reflector: Node2D
## 变黄前父物体的碰撞层（变黄时临时切到 layer 3 让子弹穿过，吸收/破坏时还原）。
var _original_collision_layer := -1


func _ready() -> void:
	_parent = get_parent() as Node2D


## 入口：对父物体应用一个元素（由 colorable_* 的 apply_color 调用）。
## from_pos = 赋予来源位置（跟班落点），用于决定青态的移动方向（物体被推向远离来源的一侧）。
## 返回是否真的改变了状态（false = 与当前元素相同，调用方据此避免消耗种子）。
func apply(element_id: String, from_pos: Vector2 = Vector2.INF) -> bool:
	if not Rules.has(element_id):
		return false
	if element_id == "burn":
		return _apply_burn()
	elif element_id == "freeze":
		return _apply_freeze(from_pos)
	elif element_id == "grow":
		return _apply_grow(from_pos)
	return false


func has_element() -> bool:
	return _element != ""


func current_element() -> String:
	return _element


## 吸收：清空状态并返回应返还给玩家的元素 id 列表。
## 单元素返回 [el]；青返回 ["freeze", "grow"]，黄返回 ["burn", "grow"]。
func absorb() -> Array:
	var result: Array = []
	if _cyan:
		result = ["freeze", "grow"]
	elif _yellow:
		result = ["burn", "grow"]
	elif _element != "":
		result = [_element]
	clear()
	return result


## 抽走元素：解除冻结 / 熄灭火焰，清除 VFX。由 colorable_* 的 absorb_color 调用。
func clear() -> void:
	_burning = false
	_frozen = false
	_grown = false
	_cyan = false
	_yellow = false
	_element = ""
	_clear_vfx()
	_free_light()
	_free_reflector()
	_restore_collision_layer()
	_set_heat(false)
	_set_growth(false)


func _apply_burn() -> bool:
	if _burning:
		return false
	# 青/黄都已是混合态，红不再叠加（可后续定义「红破坏黄」等交互）。
	if _cyan or _yellow:
		return false
	# 点燃冻结中的物体 = 解冻后再燃烧。
	if _frozen:
		_frozen = false
		_clear_vfx()
	# 红 × 绿 = 黄：给缠藤物上红 → 混合成黄并开启反射。
	if _grown:
		_grown = false
		_enter_yellow()
		return true

	_burning = true
	_element = "burn"
	if play_burn_vfx:
		_spawn_vfx("burn")
	_spawn_light()
	_set_heat(true)
	_schedule_spread("burn")
	return true


func _apply_freeze(from_pos: Vector2) -> bool:
	# 冻结正在燃烧的物体 = 熄灭并摧毁（交互：freeze × burn → 销毁）。
	if _burning:
		_burning = false
		_element = ""
		_clear_vfx()
		_free_light()
		_set_heat(false)
		_refund_destroyed_elements()
		_shatter()
		return true

	# 蓝 × 绿 = 青：冻结缠藤物 → 混合成青并移动。
	if _grown:
		_grown = false
		_enter_cyan(from_pos)
		return true
	if _cyan:
		return false
	if _yellow:
		return false
	if _frozen:
		return false
	_frozen = true
	_element = "freeze"
	_spawn_vfx("freeze")
	_schedule_spread("freeze")
	return true


## 生长（绿）：让有机物体「发芽缠藤」，登记为生长源。
## 绿 × 蓝 = 青：已冻结物体被赋予绿 → 混合成青并移动。
## 其余情况：已有任何元素（燃烧/已生长/已混合）都长不出来（返回 false 不耗种子）。
func _apply_grow(from_pos: Vector2) -> bool:
	if _cyan or _yellow:
		return false
	if _frozen:
		_frozen = false
		_enter_cyan(from_pos)
		return true
	# 绿 × 红 = 黄：给燃烧中的物体上绿 → 混合成黄并开启反射。
	if _burning:
		_burning = false
		_clear_vfx()
		_free_light()
		_set_heat(false)
		_enter_yellow()
		return true
	if _element != "":
		return false
	_grown = true
	_element = "grow"
	_spawn_vfx("grow")
	_schedule_spread("grow")
	_set_growth(true)
	return true


## 进入青色混合态：蓝 × 绿 = 青。清除旧的蓝/绿视觉状态，登记为混合态。
## 不再自动移动：青色物体改为可被玩家推动（推动逻辑见 colorable 的 push）。
func _enter_cyan(_from_pos: Vector2) -> void:
	_clear_vfx()
	_set_growth(false)
	_cyan = true
	_element = "cyan"


## 进入黄色混合态：红 × 绿 = 黄。清除旧的燃烧/生长状态，登记为混合态，
## 并按配置挂一个子弹反射组件（黄被破坏/吸收时关闭）。
func _enter_yellow() -> void:
	_clear_vfx()
	_free_light()
	_set_heat(false)
	_set_growth(false)
	_yellow = true
	_element = "yellow"
	if _parent == null or not is_instance_valid(_parent):
		return
	_switch_to_yellow_layer()
	if reflect_bullets:
		_setup_reflector()


## 变黄时把父物体切到 layer 3：玩家（mask 6 含 3）仍被挡，子弹（mask 7 不含 3）能穿过，
## 让子弹能进入反射器范围而不是撞在物体碰撞上被销毁。
func _switch_to_yellow_layer() -> void:
	if not (_parent is CollisionObject2D):
		return
	var body := _parent as CollisionObject2D
	if _original_collision_layer == -1:
		_original_collision_layer = body.collision_layer
	body.collision_layer = 3


## 黄被吸收/破坏后还原父物体原来的碰撞层。
func _restore_collision_layer() -> void:
	if _original_collision_layer == -1:
		return
	if _parent != null and is_instance_valid(_parent) and (_parent is CollisionObject2D):
		(_parent as CollisionObject2D).collision_layer = _original_collision_layer
	_original_collision_layer = -1


## 挂一个 BulletReflector 到父物体并开启（变黄后反射子弹）。
func _setup_reflector() -> void:
	_free_reflector()
	var r := Reflector.new()
	r.name = "BulletReflector"
	r.radius = reflect_radius
	r.faction = reflect_faction
	_parent.add_child(r)
	r.set_enabled(true)
	_reflector = r


## 移除并关闭反射组件（黄被吸收/破坏时）。
func _free_reflector() -> void:
	if _reflector != null and is_instance_valid(_reflector):
		_reflector.queue_free()
	_reflector = null


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


## 燃烧物登记为「热源」：元素阀/火机关靠扫描 heat_source 组判断附近有没有火。
## 与 light_source（发光，供暗房挖洞/焰虱追光）区分——热源是「能开火驱动机关」的火。
func _set_heat(on: bool) -> void:
	if _parent == null or not is_instance_valid(_parent):
		return
	if on:
		_parent.add_to_group("heat_source")
	else:
		_parent.remove_from_group("heat_source")


## 缠藤物登记为「生长源」：未来「扫描生长源」的机关据此判断附近有没有藤蔓。
## 与 heat_source（开火机关）/ light_source（暗房挖洞、焰虱追光）同款组原语。
func _set_growth(on: bool) -> void:
	if _parent == null or not is_instance_valid(_parent):
		return
	if on:
		_parent.add_to_group("growth_source")
	else:
		_parent.remove_from_group("growth_source")


func _spawn_vfx(element_id: String) -> void:
	_clear_vfx()
	var cfg := Rules.config(element_id)
	var scene: PackedScene = load(cfg.get("vfx", ""))
	if scene == null:
		return
	_vfx = scene.instantiate()
	_vfx.set("loop", false)  # 只播一次
	_parent.add_child(_vfx)


## 红+蓝销毁：把烧掉的红与扑灭用的蓝各返还一颗给玩家（种子守恒回流）。
func _refund_destroyed_elements() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("refund_element"):
		return
	player.call("refund_element", "burn", 1)
	player.call("refund_element", "freeze", 1)


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
