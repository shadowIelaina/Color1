extends Node
## 全局高度图（autoload）。按格子存每格的站立高度 z（像素）与可站立性 walkable。
## 数据来源：
##   静态地形 —— 来自 TileMapLayer 的 custom data「height」（int，单位像素），由
##             ground_height.gd 在场景加载时喂入；你在地图里画 tile 就是设高度。
##   动态地形 —— 水/冰由 WaterCell 在冻结/融化时用 set_cell 覆盖。
## 约定：z=0 岸/地面；正数=高台/台阶；负数=凹坑/水（不可站）。
## 格 = 256px（与地面 TileMap 的 tile_size 一致，一格 tile = 一格高度）。
## CELL 是全游戏「格大小」的单一来源：美术一格 256×256，TileSet 的 tile_size /
## 水深 / 玩家台阶都由此决定。改这里时，TileSet 的 tile_size 也要同步改成同一个数。

const CELL := 256.0

## Vector2i(grid) -> {"z": float, "walkable": bool}
var _cells := {}


func _grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / CELL), floor(world_pos.y / CELL))


## 设置单个 256px 格的高度。
func set_cell(world_pos: Vector2, z: float, walkable: bool) -> void:
	_cells[_grid(world_pos)] = {"z": z, "walkable": walkable}


## 采样某世界坐标的高度。未注册的格子默认地面（z=0，可站）。
func sample(world_pos: Vector2) -> Dictionary:
	return _cells.get(_grid(world_pos), {"z": 0.0, "walkable": true})


## 是否允许从高度 from_z 直接走到相邻格高度 to_z。
## 允许一格台阶（≤CELL），超过一格当作悬崖/墙挡住。
func can_step(from_z: float, to_z: float) -> bool:
	return absf(to_z - from_z) <= CELL


## 便捷：只取 z。
func sample_z(world_pos: Vector2) -> float:
	return float(sample(world_pos).get("z", 0.0))


func clear() -> void:
	_cells.clear()


## 从 TileMapLayer 读 custom data「height」构建静态高度。负高度 = 凹坑，不可站。
func load_from_tilemap(tilemap: TileMapLayer) -> void:
	for cell in tilemap.get_used_cells():
		var data := tilemap.get_cell_tile_data(cell)
		if data == null:
			continue
		var h := int(data.get_custom_data("height"))
		var wp := tilemap.to_global(tilemap.map_to_local(cell))
		set_cell(wp, float(h), h >= 0)
