extends TileMapLayer
## 流向标记层生成器：挂到一个专门画「流向箭头」的 TileMapLayer 上。
## _ready 时把画好的每个箭头 tile 读成流向，写进 HeightMap，供玩家脚下采样。
## 箭头 tile 的方向由 atlas 坐标决定（可配），默认一行四张：
##   (0,0)=→  (1,0)=↓  (2,0)=←  (3,0)=↑
## 美术只在这一层画箭头即可，水图（WaterShallow 层）完全不用动。
## 本层只作标记：读完后在运行时隐藏（箭头仅供编辑器里查看，不进游戏画面）。

## 各方向箭头在 TileSet atlas 里的坐标。
@export var atlas_right := Vector2i(0, 0)
@export var atlas_down := Vector2i(1, 0)
@export var atlas_left := Vector2i(2, 0)
@export var atlas_up := Vector2i(3, 0)


func _ready() -> void:
	for cell in get_used_cells():
		var atlas := get_cell_atlas_coords(cell)
		var dir := 0
		if atlas == atlas_right:
			dir = 1
		elif atlas == atlas_down:
			dir = 2
		elif atlas == atlas_left:
			dir = 3
		elif atlas == atlas_up:
			dir = 4
		if dir != 0:
			HeightMap.set_flow(to_global(map_to_local(cell)), dir)
	# 箭头只给美术在编辑器里看，游戏里不显示。
	visible = false
