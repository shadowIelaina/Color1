extends TileMapLayer
## 纯空气墙：把画好的格子转成不可见的 StaticBody2D 碰撞。
## 只阻挡玩家，不参与水、结冰、可上色，也不写 HeightMap。

const WORLD_LAYER := 2


func _ready() -> void:
	var size := Vector2(256, 256)
	if tile_set != null:
		size = Vector2(tile_set.tile_size)
	for cell in get_used_cells():
		var body := StaticBody2D.new()
		body.name = "AirWall_%d_%d" % [cell.x, cell.y]
		body.position = map_to_local(cell)
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		var col := CollisionShape2D.new()
		col.name = "Collision"
		var shape := RectangleShape2D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		add_child(body)
	# 运行时清掉可见 tile，只留下不可见碰撞。
	clear()
