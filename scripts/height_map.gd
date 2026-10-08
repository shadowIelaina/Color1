extends Node
## 全局通行性地图（autoload）。按格子存每格是否可站。
## 数据来源：水/冰等动态地形由 WaterCell 在冻结/融化时用 set_walkable 覆盖；
## 未注册的格子默认可站（地面）。
## 格 = 256px（与地面 TileMap 的 tile_size 一致，一格 tile = 一格通行格）。
## CELL 是全游戏「格大小」的单一来源：美术一格 256×256，TileSet 的 tile_size、
## 水深、玩家足迹都由此决定。改这里时，TileSet 的 tile_size 也要同步改成同一个数。

const CELL := 256.0

## Vector2i(grid) -> bool（可站）
var _cells := {}


func _grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / CELL), floor(world_pos.y / CELL))


## 设置单个 256px 格的可站性。
func set_walkable(world_pos: Vector2, walkable: bool) -> void:
	_cells[_grid(world_pos)] = walkable


## 采样某世界坐标的可站性。未注册的格子默认可站（地面）。
func is_walkable(world_pos: Vector2) -> bool:
	return bool(_cells.get(_grid(world_pos), true))


func clear() -> void:
	_cells.clear()
