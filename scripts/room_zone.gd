@tool
class_name RoomZone
extends Area2D
## 房间分区：玩家进入时把相机锁到本区域（用本节点的矩形碰撞盒做边界）。
## 用法：在每间房上盖一个 RoomZone，矩形 CollisionShape2D 框住整间房；
## 玩家一进入，相机就锁到这间房范围；走到下一间房时由下一间的 RoomZone 接管。
## 可选 room_name：进入时通过 HUD 顶部短暂提示房间名。
## 可选 dark：暗房——进入时把全局暗房遮罩压黑，靠燃烧/玩家微光照亮（塞尔达式）。
## 约定：本节点与碰撞盒不缩放、不旋转（轴对齐矩形）。

@export var room_name: String = ""
## 留空沿用关卡配乐；填写后，本区域固定循环此曲。
@export var background_music: AudioStream
## 暗房：进入时把全局暗房遮罩压黑（darkness→1），只有光源（燃烧/玩家微光）能挖出可见区域。
@export var dark := false
@export var fade_time := 0.6
## 房间矩形大小（编辑器里可直接改，会同步到 Collision 碰撞盒；也可拖 Collision 手柄）。
@export var size := Vector2(2560, 1280):
	set(value):
		size = value
		_sync_collision()
		if Engine.is_editor_hint():
			queue_redraw()

var _rect := Rect2()
var _overlay: DarknessOverlay
var _darkness_tween: Tween


func _ready() -> void:
	if Engine.is_editor_hint():
		_pull_size_from_collision()
		return
	collision_layer = 0   # 本区域不被任何东西碰撞
	collision_mask = 1    # 只检测玩家（层 1）
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_rect = _compute_rect()


## 本房间分区的世界矩形（供相机边界 / 运行时导航烘焙使用）。
func get_rect() -> Rect2:
	if _rect.size == Vector2.ZERO:
		_rect = _compute_rect()
	return _rect


## 用本节点的矩形碰撞盒算相机边界（全局坐标）。
func _compute_rect() -> Rect2:
	for c in get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var col := c as CollisionShape2D
			var shape := col.shape as RectangleShape2D
			var center := to_global(col.position)
			return Rect2(center - shape.size * 0.5, shape.size)
	return Rect2()


## 把 size 字段写到 Collision 的矩形碰撞盒（编辑器里 Inspector 改 size 时触发）。
func _sync_collision() -> void:
	for c in get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var shape := (c as CollisionShape2D).shape as RectangleShape2D
			if shape.size != size:
				shape.size = size
			return


## 编辑器里用现有碰撞盒反向初始化 size 显示值（避免覆盖手搓房间，如 level_1 的 DarkRoom）。
func _pull_size_from_collision() -> void:
	for c in get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var shape := (c as CollisionShape2D).shape as RectangleShape2D
			if shape.size != size:
				size = shape.size
			return


## 编辑器里画房间范围边框，选中 RoomZone 就能看清边界（运行时不画）。
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	for c in get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var col := c as CollisionShape2D
			var shape := col.shape as RectangleShape2D
			draw_rect(Rect2(col.position - shape.size * 0.5, shape.size), Color(0.35, 0.75, 1.0, 0.7), false, 3.0)
			return


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_apply_lighting()
	if background_music != null: AudioManager.play_music(background_music)
	else: AudioManager.play_room_music()


## 把相机边界锁到本房间矩形（优先 PhantomCamera2D，回退玩家身上的 Camera2D）。
func _apply_camera(_player: Node) -> void:
	CameraLimits.apply(
		int(_rect.position.x),
		int(_rect.position.y),
		int(_rect.end.x),
		int(_rect.end.y)
	)


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
