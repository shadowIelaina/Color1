extends TileMapLayer
## 水层生成器：挂到 Water TileMapLayer。_ready 时把画好的每个水 tile 换成一个
## WaterCell 节点（复用冻结/冰/通行性逻辑），然后清掉标记 tile。
## 这样你就能像画地面一样，在 Water 层上画任意形状的水。
## 水面/冰外观在这里的 Inspector 编辑，会复制给本层每一个水格。

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


func _ready() -> void:
	for cell in get_used_cells():
		var wc := WaterCellScript.new()
		wc.name = "Water_%d_%d" % [cell.x, cell.y]
		wc.position = map_to_local(cell)
		wc.water_texture = water_texture
		wc.water_color = water_color
		wc.ice_texture = ice_texture
		wc.ice_color = ice_color
		wc.freeze_preview_alpha = freeze_preview_alpha
		add_child(wc)
	# 清掉标记 tile，只留 WaterCell 子节点画真实水面。
	clear()
