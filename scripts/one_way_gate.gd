class_name OneWayGate
extends StaticBody2D
## 真正单向的通道闸：玩家只能沿 pass_dir 方向穿过一次，反向永久挡住。
## - 阻挡碰撞取自 Collision（矩形）；block_scale 非零时按 Visual 宽高放大（同 RoomDoor 的「点小、区域大」）。
## - 玩家在入口侧、对齐门洞并靠近时自动放行；完全穿到出口侧后自动重新封堵。
## - 从出口侧靠近不会开门 → 反向永远走不过去。
## - 不持久化：每次进入大场景都从「封堵」开始。
##
## 需要子节点：Visual（门贴图 CanvasItem）、Collision（矩形 CollisionShape2D）。

## 允许穿过的方向（单位向量；通常为 ±X 或 ±Y）。
@export var pass_dir: Vector2 = Vector2.RIGHT
## 同 RoomDoor：阻挡区 = Visual 宽高 × block_scale。Vector2.ZERO = 用场景里手动配的 Collision。
@export var block_scale: Vector2 = Vector2.ZERO
## 入口侧「靠近即开」的探测距离（世界像素，从阻挡带边缘算起）。须大于玩家碰撞盒半宽。
@export var open_reach: float = 128.0
## 玩家沿 pass_dir 完全离开阻挡带多少像素后重新封堵。须大于玩家碰撞盒半宽。
@export var close_clearance: float = 96.0
## 判定玩家在门洞横向范围内的额外容差（像素）。
@export var mouth_margin: float = 64.0

@onready var collision: CollisionShape2D = get_node_or_null("Collision")
@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

var _open := false
var _dir := Vector2.RIGHT
var _half_along := 0.0   # 阻挡矩形沿 pass_dir 的半长
var _half_perp := 0.0    # 阻挡矩形垂直 pass_dir 的半长


func _ready() -> void:
	add_to_group("one_way_gate")
	collision_layer = 2   # 挡玩家（玩家 collision_mask 含层 2）
	collision_mask = 0
	_dir = pass_dir.normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	_apply_region()


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var rel := player.global_position - global_position
	var along := rel.dot(_dir)
	var perp := absf(rel.dot(_dir.orthogonal()))

	# 不在门洞横向范围 → 保持封堵。
	if perp > _half_perp + mouth_margin:
		_set_open(false)
		return

	if along <= -(_half_along + open_reach):
		# 入口侧但离得远 → 保持封堵。
		_set_open(false)
	elif along <= 0.0:
		# 入口侧靠近 → 放行，玩家可推门穿过。
		_set_open(true)
	elif along > _half_along + close_clearance:
		# 已完全穿到出口侧 → 重新封堵，反向再也进不来。
		_set_open(false)
	# 其余：出口侧但仍在阻挡带内 → 保持当前状态（刚穿过则继续放行，否则维持封堵）。


func _set_open(value: bool) -> void:
	if _open == value:
		return
	_open = value
	if collision != null:
		collision.set_deferred("disabled", value)
	if visual != null:
		var t := create_tween()
		t.tween_property(visual, "modulate:a", 0.25 if value else 1.0, 0.15)


## 计算阻挡尺寸与半长：优先 block_scale（按 Visual 放大），否则取 Collision 现有矩形。
func _apply_region() -> void:
	var block := Vector2.ZERO
	if block_scale != Vector2.ZERO:
		var dot_size := _visual_size()
		if dot_size != Vector2.ZERO:
			block = dot_size * block_scale
	if block == Vector2.ZERO and collision != null and collision.shape is RectangleShape2D:
		block = (collision.shape as RectangleShape2D).size
	if block == Vector2.ZERO:
		return
	if block_scale != Vector2.ZERO and collision != null:
		# 新建 RectangleShape2D 再赋值（不原地改共享的 shape）。
		var rect := RectangleShape2D.new()
		rect.size = block
		collision.shape = rect
		collision.position = Vector2.ZERO
	# 矩形轴对齐：沿 pass_dir 的投影半长为各轴分量与其尺寸之积。
	_half_along = (absf(_dir.x) * block.x + absf(_dir.y) * block.y) * 0.5
	_half_perp = (absf(_dir.x) * block.y + absf(_dir.y) * block.x) * 0.5


func _visual_size() -> Vector2:
	if visual == null:
		return Vector2.ZERO
	if visual is Polygon2D:
		var poly := (visual as Polygon2D).polygon
		if poly.is_empty():
			return Vector2.ZERO
		var mn := poly[0]
		var mx := poly[0]
		for p in poly:
			mn = mn.min(p)
			mx = mx.max(p)
		return (mx - mn) * (visual as Polygon2D).scale
	if visual is Sprite2D:
		var spr := visual as Sprite2D
		if spr.texture != null:
			return spr.texture.get_size() * spr.scale
	return Vector2.ZERO
