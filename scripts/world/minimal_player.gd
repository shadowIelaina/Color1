extends CharacterBody2D
## 实验用最小玩家：WASD/方向键移动，自带方块视觉、碰撞和跟随相机。
## 相机 zoom 0.25 与主游戏一致；按脚底 Y 做深度排序，跟树正确互相遮挡。
## 注意：procedural_test.tscn 实际用的是主游戏玩家（scenes/player.tscn），此文件未接入。

const DepthSort := preload("res://scripts/depth_sort.gd")

@export var speed := 1200.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2   # 撞障碍物（树在 layer 2）
	# 视觉：一个亮色方块
	var half := 48.0
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	visual.color = Color(1.0, 0.88, 0.3)
	add_child(visual)
	# 碰撞
	var shape := RectangleShape2D.new()
	shape.size = Vector2(half * 2.0, half * 2.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	# 跟随相机（zoom 与主游戏一致）
	var cam := Camera2D.new()
	cam.zoom = Vector2(0.25, 0.25)
	cam.enabled = true
	add_child(cam)


func _physics_process(_delta: float) -> void:
	velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed
	move_and_slide()
	z_index = DepthSort.z_for(global_position.y)
