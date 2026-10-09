extends TileMapLayer
## 水层生成器：挂到 Water TileMapLayer。_ready 时把画好的每个水 tile 换成一个
## WaterCell 节点（复用冻结/冰/通行性逻辑），然后清掉标记 tile。
## 这样你就能像画地面一样，在 Water 层上画任意形状的水。
## 水面/冰外观在这里的 Inspector 编辑，会复制给本层每一个水格。
## 深/浅水各用一层 TileMapLayer：深水层 shallow=false（挡路），浅水层 shallow=true（可走），
## 两层用不同的 water_texture/ice_texture 区分外观。

const WaterCellScript := preload("res://color_change/water_cell.gd")

## 水面贴图（可选），为空时用纯色 water_color。
@export var water_texture: Texture2D
## 水面颜色（无贴图时）。
@export var water_color := Color(0.13, 0.48, 0.64)
## 冰块贴图（可选），为空时用纯色 ice_color。
@export var ice_texture: Texture2D
## 冰块颜色（无贴图时）。
@export var ice_color := Color(0.88, 0.95, 1.0)
## 冻结预览（半透明冰块提示）透明度。
@export_range(0.0, 1.0, 0.05) var freeze_preview_alpha := 0.4
## 本层是浅水（true，可行走）还是深水（false，挡路）。深/浅水各用一层 TileMapLayer 画。
@export var shallow := false
## 基础水面是否直接使用本 TileMapLayer 的 tile 贴图。
## true：保留你画的 tile，WaterCell 只负责碰撞/结冰/预览，不再画基础水。
## false：沿用旧逻辑，清掉 tile，由 WaterCell 用 water_texture / water_color 画水。
@export var render_water_from_tilemap := true
## 是否生成逐格 WaterCell。
## true：水格会拥有碰撞、结冰、可上色等玩法逻辑（水很多时开销较大）。
## false：本层变成纯视觉水面，只显示 tilemap 贴图，不生成 WaterCell（性能最好）。
@export var spawn_cells := true


func _ready() -> void:
	if not spawn_cells:
		return
	for cell in get_used_cells():
		var wc := WaterCellScript.new()
		wc.name = "Water_%d_%d" % [cell.x, cell.y]
		wc.position = map_to_local(cell)
		wc.water_texture = water_texture
		wc.water_color = water_color
		wc.ice_texture = ice_texture
		wc.ice_color = ice_color
		wc.freeze_preview_alpha = freeze_preview_alpha
		wc.shallow = shallow
		wc.draw_water = not render_water_from_tilemap
		add_child(wc)
	# 用 tilemap 显示水面时保留 tile；否则清掉 tile，交给 WaterCell 画水。
	if not render_water_from_tilemap:
		clear()
