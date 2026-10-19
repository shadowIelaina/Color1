extends StaticBody2D
## 场景岩石：按脚底 Y 做深度排序；solid=false 时只做装饰、不挡路。

const DepthSort := preload("res://scripts/depth_sort.gd")

@export var solid := true
@export var z_offset := 0


func _ready() -> void:
	z_index = DepthSort.z_for(global_position.y) + z_offset
	if solid:
		return
	collision_layer = 0
	collision_mask = 0
	var col := get_node_or_null("Collision") as CollisionShape2D
	if col != null:
		col.disabled = true
