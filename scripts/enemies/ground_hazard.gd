class_name GroundHazard
extends Area2D
## 地面危险物：由小怪/子弹弹道留下的地面残留。
##
## kind：
##   BURN        燃烧痕迹——玩家碰到掉血；入组 "burn_trail"（小火怪/绿怪互作用它点燃）。
##   ICE_CRYSTAL 冰晶——玩家经过减速；入组 "ice_crystal"（红能力可烧掉、红怪碰到会熄灭）。
##
## 自带 lifetime 计时自毁；接触效果按 contact_cooldown 节流（站着不动也会周期性触发）。
## 玩家侧接口：take_damage(amount) / slow(factor, duration)，二者都已存在。

const DepthSort := preload("res://scripts/depth_sort.gd")

enum Kind { BURN, ICE_CRYSTAL }

@export var kind: Kind = Kind.BURN
## 存活时长（秒），到点自毁。
@export_range(0.2, 60.0, 0.1) var lifetime := 6.0
## 燃烧痕迹每次接触造成的伤害。
@export_range(0.0, 5.0, 0.05) var burn_damage := 0.2
## 冰晶减速系数（1 = 不减速，越小越慢）。
@export_range(0.05, 1.0, 0.05) var slow_factor := 0.5
## 冰晶减速持续时长（秒），每次接触刷新。
@export_range(0.1, 5.0, 0.1) var slow_duration := 1.0
## 连续接触的触发间隔（秒），避免每帧刷伤害/刷新减速。
@export_range(0.05, 3.0, 0.05) var contact_cooldown := 0.4
## 小怪接触到该残留的熄灭判定半径（世界像素）。
@export_range(30.0, 400.0, 5.0) var minion_extinguish_radius := 130.0

var _age := 0.0
var _contact_cd := 0.0

@onready var visual: CanvasItem = get_node_or_null("Visual")


func _ready() -> void:
	z_index = DepthSort.z_for(global_position.y)
	collision_layer = 0
	collision_mask = 1   # 只感应玩家层（玩家在层 1）
	monitoring = true
	_apply_kind()


func _physics_process(delta: float) -> void:
	_age += delta
	_contact_cd = maxf(0.0, _contact_cd - delta)
	if _age >= lifetime:
		queue_free()
		return
	_affect_minions()
	if _contact_cd > 0.0:
		return
	for body in get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			_affect_player(body)
			break


## 扫描附近小怪：红怪碰冰晶、蓝/绿怪碰火焰痕迹时进入熄灭状态。
func _affect_minions() -> void:
	var element_id := "burn" if kind == Kind.BURN else "freeze"
	for m in get_tree().get_nodes_in_group("minion"):
		if not GameState.is_in_current_scene(m):
			continue
		var n := m as Node2D
		if n == null or n.is_queued_for_deletion():
			continue
		if not m.has_method("extinguish_from_hazard"):
			continue
		if n.global_position.distance_to(global_position) <= minion_extinguish_radius:
			m.call("extinguish_from_hazard", element_id)


func _apply_kind() -> void:
	if kind == Kind.BURN:
		add_to_group("burn_trail")
		remove_from_group("ice_crystal")
		if visual is Polygon2D:
			(visual as Polygon2D).color = Color(1.0, 0.5, 0.15, 0.75)
	else:
		add_to_group("ice_crystal")
		remove_from_group("burn_trail")
		if visual is Polygon2D:
			(visual as Polygon2D).color = Color(0.55, 0.8, 1.0, 0.85)


func _affect_player(player: Node) -> void:
	_contact_cd = contact_cooldown
	if kind == Kind.BURN:
		if player.has_method("take_damage"):
			player.call("take_damage", burn_damage)
	else:
		if player.has_method("slow"):
			player.call("slow", slow_factor, slow_duration)


## 元素交互入口：红烧冰晶 / 蓝灭火痕 → 直接消失。供后续小怪系统调用。
func extinguish() -> void:
	queue_free()


func is_damaging() -> bool:
	return kind == Kind.BURN


# —— 纯逻辑查询（供单测 / 外部按 kind 取组）——

static func group_for_kind(k: int) -> String:
	return "burn_trail" if k == Kind.BURN else "ice_crystal"


static func is_damaging_kind(k: int) -> bool:
	return k == Kind.BURN
