class_name SeedContainer
extends StaticBody2D
## 种子容器：世界里的元素种子储藏点（固定数量，关卡设计给定，非背包道具）。
##
##   取种（右击）  → 抽走一颗种子入背包（absorb_color 返回一颗，跟班带回收库）。
##   红(burn)     → 烧掉全部内容物：store 清空，种子销毁、不返还（「红清空」）。
##   蓝(freeze)   → 冻结锁定：不能取种、不能烧；吸收蓝解冻（与元素阀同款「吸收蓝解锁」）。
##   绿(增殖)      → 搁置（「存取+利息」的银行复合机制，暂不做）。
##
## 取种/解冻都走右击的 absorb_color：优先解冻（若冻结），否则取一颗种子，最后空。
## 需要子节点：Visual（贴图 CanvasItem）、Collision（CollisionShape2D，容器做成实心障碍）。
## ⚠️ 不要定义 is_frozen()（player._water_at_mouse 会误判成水格崩溃）。

const Rules := preload("res://scripts/element/element_rules.gd")

@export_group("内容物（初始种子）")
@export var burn_seeds: int = 0     # 红种子数量
@export var freeze_seeds: int = 0   # 蓝种子数量
@export var grow_seeds: int = 0     # 绿种子数量

@export_group("视觉")
@export var full_color := Color(0.75, 0.55, 0.28)   # 有货
@export var empty_color := Color(0.35, 0.35, 0.35)  # 空了（或烧掉）
@export var frozen_color := Color(0.4, 0.65, 1.0)   # 冻结锁定
@export var hit_radius: float = 56.0

@export_group("状态")
@export var state_id: String = ""

@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem
@onready var collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D

var _store: Dictionary = {}   # element_id -> count
var _frozen := false


func _ready() -> void:
	add_to_group("colorable")
	add_to_group("stateful")
	if state_id == "":
		state_id = name
	collision_layer = 2   # 实心障碍，挡玩家（玩家 collision_mask 含层 2）
	collision_mask = 0
	_store = {}
	if burn_seeds > 0:
		_store["burn"] = burn_seeds
	if freeze_seeds > 0:
		_store["freeze"] = freeze_seeds
	if grow_seeds > 0:
		_store["grow"] = grow_seeds
	_update_visual()


## 取种顺序固定：先红后蓝后绿（确定性，便于关卡设计）。
func _withdraw_order() -> Array:
	return ["burn", "freeze", "grow"]


func _total_seeds() -> int:
	var n := 0
	for el in _store:
		n += int(_store[el])
	return n


func _update_visual() -> void:
	if visual == null:
		return
	var c: Color = frozen_color if _frozen else (full_color if _total_seeds() > 0 else empty_color)
	var t := create_tween()
	t.tween_property(visual, "modulate", c, 0.2)


# —— colorable 契约 ——
func apply_color(_c: Color, color_name: String = "", _from_pos: Vector2 = Vector2.INF) -> bool:
	var element := Rules.element_for_color_name(color_name)
	if element == "freeze":
		if _frozen:
			return false   # 已冻结，重复给不耗种子
		_frozen = true
		_update_visual()
		return true
	if element == "burn":
		if _frozen:
			return false   # 冻结锁住内容，烧不掉
		if _store.is_empty():
			return false   # 空的，没东西可烧，不耗种子
		_store.clear()
		_update_visual()
		return true
	return false   # 绿/其它：搁置


func absorb_color() -> Dictionary:
	# 优先解冻：吸收蓝 = 解锁（与元素阀一致）。
	if _frozen:
		_frozen = false
		_update_visual()
		return {
			"element": "freeze",
			"color": Rules.config("freeze")["color"],
			"color_name": Rules.config("freeze")["color_name"],
			"amount": 1,
		}
	# 否则取一颗种子。
	for el in _withdraw_order():
		if int(_store.get(el, 0)) > 0:
			_store[el] = int(_store[el]) - 1
			if int(_store[el]) <= 0:
				_store.erase(el)
			var cfg := Rules.config(el)
			_update_visual()
			return {
				"element": el,
				"color": cfg.get("color", Color.WHITE),
				"color_name": cfg.get("color_name", ""),
				"amount": 1,
			}
	return {"element": "", "color": Color.WHITE, "color_name": ""}


func has_color() -> bool:
	return _frozen or (not _store.is_empty())


## 回收玩家的冻结封层，绝不继续提取容器内原有种子。
func reclaim_placed_color() -> Dictionary:
	if not _frozen: return {"element": ""}
	return absorb_color()


func contains_point(world_pos: Vector2) -> bool:
	if visual is Polygon2D:
		var poly := (visual as Polygon2D).polygon
		if not poly.is_empty():
			var mn := poly[0]
			var mx := poly[0]
			for p in poly:
				mn = mn.min(p)
				mx = mx.max(p)
			return Rect2(mn, mx - mn).has_point(to_local(world_pos))
	return global_position.distance_to(world_pos) <= hit_radius


# —— 状态持久化 ——
func save_state() -> Dictionary:
	return {"store": _store.duplicate(), "frozen": _frozen}


func restore_state(data: Dictionary) -> void:
	# 只有存在存档数据时才覆盖 store。第一次进房 room.restore_state 传的是空 {}，
	# 若不加判断会把 _ready 里刚按 grow_seeds/burn_seeds/freeze_seeds 初始化的种子清空。
	if data.has("store"):
		_store = {}
		for el in data["store"]:
			_store[el] = int(data["store"][el])
	_frozen = data.get("frozen", false)
	_update_visual()
