class_name RoomZone
extends Area2D
## 房间分区：玩家进入时把相机锁到本区域（用本节点的矩形碰撞盒做边界）。
## 用法：在每间房上盖一个 RoomZone，矩形 CollisionShape2D 框住整间房；
## 玩家一进入，相机就锁到这间房范围；走到下一间房时由下一间的 RoomZone 接管。
## 可选 room_name：进入时通过 HUD 顶部短暂提示房间名。
## 可选 dark：暗房——进入时把全局暗房遮罩压黑，靠燃烧/玩家微光照亮（塞尔达式）。
## 约定：本节点与碰撞盒不缩放、不旋转（轴对齐矩形）。

@export var room_name: String = ""
## 暗房：进入时把全局暗房遮罩压黑（darkness→1），只有光源（燃烧/玩家微光）能挖出可见区域。
@export var dark := false
@export var fade_time := 0.6

var _rect := Rect2()
var _overlay: DarknessOverlay
var _darkness_tween: Tween


func _ready() -> void:
	collision_layer = 0   # 本区域不被任何东西碰撞
	collision_mask = 1    # 只检测玩家（层 1）
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_rect = _compute_rect()


## 用本节点的矩形碰撞盒算相机边界（全局坐标）。
func _compute_rect() -> Rect2:
	for c in get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var col := c as CollisionShape2D
			var shape := col.shape as RectangleShape2D
			var center := to_global(col.position)
			return Rect2(center - shape.size * 0.5, shape.size)
	return Rect2()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_apply_camera(body)
	_apply_lighting()
	if room_name != "":
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_hint"):
			hud.show_hint(room_name)


## 把玩家身上的 Camera2D 边界锁到本房间矩形。
func _apply_camera(player: Node) -> void:
	var cam := player.get_node_or_null("Camera") as Camera2D
	if cam == null:
		return
	cam.limit_left = int(_rect.position.x)
	cam.limit_top = int(_rect.position.y)
	cam.limit_right = int(_rect.end.x)
	cam.limit_bottom = int(_rect.end.y)


## 离开暗房时把遮罩渐回亮，避免走到亮区仍一片黑。
func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if dark:
		_tween_darkness(0.0)


## 按本房明暗把全局暗房遮罩的 darkness 渐变（0 = 亮 / 1 = 全黑）。相机锁房间，全局遮罩只影响当前房。
func _apply_lighting() -> void:
	_tween_darkness(1.0 if dark else 0.0)


func _tween_darkness(target: float) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = get_tree().get_first_node_in_group("darkness") as DarknessOverlay
	if _overlay == null:
		return
	if _darkness_tween != null and _darkness_tween.is_valid():
		_darkness_tween.kill()
	_darkness_tween = create_tween()
	_darkness_tween.tween_property(_overlay, "darkness", target, fade_time)
