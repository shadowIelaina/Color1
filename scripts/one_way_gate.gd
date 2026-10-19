class_name OneWayGate
extends StaticBody2D
## 单侧可开启的捷径门：玩家从 pass_dir 的入口侧碰门后，门消失并永久放行。
## - 阻挡碰撞取自 Collision（矩形）；block_scale 非零时按 Visual 宽高放大（同 RoomDoor 的「点小、区域大」）。
## - 另一侧碰门保持阻挡；开启后两边均可通行，并随现有存档点保存。
##
## 需要子节点：Visual（门贴图 CanvasItem）、Collision（矩形 CollisionShape2D）。

## 允许穿过的方向（单位向量；通常为 ±X 或 ±Y）。
@export var pass_dir: Vector2 = Vector2.RIGHT
## 同 RoomDoor：阻挡区 = Visual 宽高 × block_scale。Vector2.ZERO = 用场景里手动配的 Collision。
@export var block_scale: Vector2 = Vector2.ZERO

@export_group("剧情")
## 开门时播放的主线剧情段落（prologue.dialogue 的 cue）；空 = 不播。
@export var story_cue: String = ""
## 整局唯一标识，防止重复播放；空 = 每次开门都播。
@export var story_id: String = ""

@onready var collision: CollisionShape2D = get_node_or_null("Collision")
@onready var visual: CanvasItem = get_node_or_null("Visual") as CanvasItem

var _open := false
var _dir := Vector2.RIGHT
var _progress_key := ""


func _ready() -> void:
	add_to_group("one_way_gate")
	if visual == null:
		visual = get_node_or_null("Sprite2D") as CanvasItem
	collision_layer = 2   # 挡玩家（玩家 collision_mask 含层 2）
	collision_mask = 0
	_dir = pass_dir.normalized()
	if _dir == Vector2.ZERO:
		_dir = Vector2.RIGHT
	_apply_region()
	var room := get_parent()
	while room != null and not room is Room:
		room = room.get_parent()
	var scene_path := room.scene_file_path if room != null else scene_file_path
	var local_path := str(room.get_path_to(self)) if room != null else str(name)
	_progress_key = "one_way_gate:%s:%s" % [scene_path, local_path]
	if GameState.is_gate_opened(_progress_key):
		open()


func _physics_process(_delta: float) -> void:
	if _open:
		return
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null or collision == null:
		return
	if (player.global_position - collision.global_position).dot(_dir) >= 0.0:
		return
	# 读取真实的滑动碰撞，必须碰到入口面；路过附近或擦到侧边不会开门。
	for i in player.get_slide_collision_count():
		var hit := player.get_slide_collision(i)
		if hit.get_collider() == self and hit.get_normal().dot(-_dir) > 0.7:
			open()
			return


func open() -> void:
	if _open:
		return
	_open = true
	GameState.mark_gate_opened(_progress_key)
	if collision != null:
		collision.set_deferred("disabled", true)
	if visual != null:
		visual.hide()
	StoryPort.play(self, story_cue, story_id)


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
