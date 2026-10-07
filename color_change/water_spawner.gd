extends TileMapLayer
## 水层生成器：挂到 Water TileMapLayer。_ready 时把画好的每个水 tile 换成一个
## WaterCell 节点（复用冻结/冰/高度逻辑），然后清掉标记 tile。
## 这样你就能像画地面一样，在 Water 层上画任意形状的水。
##
## 水面外观在这里的 Inspector 编辑（water_color / water_texture / water_material /
## bank_color），会复制给本层每一个水格。

const WaterCellScript := preload("res://color_change/water_cell.gd")

## 纯色水面颜色（默认水蓝）。water_material / water_texture 为空时生效。
@export var water_color := Color(0.13, 0.48, 0.64)
## 可选：换美术贴图（PNG），设置后盖过 water_color。
@export var water_texture: Texture2D
## 可选：挂 shader（如 res://water/water_material.tres）得到动画水面，盖过颜色/贴图。
@export var water_material: Material
## 北侧岸壁颜色（水坑北面露出的土壁）。只有水坑北缘的水格才画。
@export var bank_color := Color(0.28, 0.26, 0.24)
## 南侧岸（近岸地面）贴图：默认用地面图集 grass.png（256px 格）。悬停时半透明露出水。
@export var shore_texture: Texture2D = preload("res://art/else/grass.png")
## 兜底：没有 shore_texture 时用的南侧岸纯色。
@export var shore_color := Color(0.35, 0.32, 0.27)
## 是否画冰块的影子（投在水面上的深色底图）。关掉可去掉结冰时底部那张深色贴图。
@export var ice_shadow_enabled := true
## 冰块顶面贴图（可选）：设置后顶面改用此贴图，否则用 ice_top_color 纯色。
@export var ice_top_texture: Texture2D
## 冰块侧面贴图（可选）：设置后侧面改用此贴图，否则用 ice_side_color 纯色。
@export var ice_side_texture: Texture2D
## 冰块顶面颜色（无 ice_top_texture 时生效）。
@export var ice_top_color := Color(0.88, 0.95, 1.0)
## 冰块侧面颜色（无 ice_side_texture 时生效）。
@export var ice_side_color := Color(0.45, 0.66, 0.88)
## 冻结预览（半透明冰块提示）透明度。悬停未结冰水格、手里是蓝时，叠一个半透明冰块预览。
@export_range(0.0, 1.0, 0.05) var freeze_preview_alpha := 0.4
## 冻结预览顶面贴图（可选）：想让预览（幽灵冰块）用独立美术时设置；为空则复用 ice_top_texture。
@export var freeze_preview_top_texture: Texture2D
## 冻结预览侧面贴图（可选）：为空则复用 ice_side_texture。
@export var freeze_preview_side_texture: Texture2D


func _ready() -> void:
	# 水格是运行时 add 的（顺序任意），必须让本层按南北 y 排序，否则水面/冰顶会被画错顺序——
	# 比如北面格子的水面下移 DROP_HEIGHT 后正好盖住南面格子的冰顶。
	y_sort_enabled = true
	var used: Dictionary = {}
	for cell in get_used_cells():
		used[cell] = true
	# 南侧岸要盖住水面，得知道南边有没有地面（岸）。取同级的 Ground 层。
	var ground: TileMapLayer = null
	var parent := get_parent()
	if parent != null:
		ground = parent.get_node_or_null("Ground") as TileMapLayer
	var tile_px := Vector2(ground.tile_set.tile_size) if ground != null else Vector2(256, 256)
	for cell in used:
		var wc := WaterCellScript.new()
		wc.name = "Water_%d_%d" % [cell.x, cell.y]
		wc.position = map_to_local(cell)
		wc.water_color = water_color
		wc.water_texture = water_texture
		wc.water_material = water_material
		wc.bank_color = bank_color
		wc.shore_texture = shore_texture
		wc.shore_color = shore_color
		wc.ice_shadow_enabled = ice_shadow_enabled
		wc.ice_top_texture = ice_top_texture
		wc.ice_side_texture = ice_side_texture
		wc.ice_top_color = ice_top_color
		wc.ice_side_color = ice_side_color
		wc.freeze_preview_alpha = freeze_preview_alpha
		wc.freeze_preview_top_texture = freeze_preview_top_texture
		wc.freeze_preview_side_texture = freeze_preview_side_texture
		# 北边（-y）没有水 = 本格是水坑北缘，画北侧岸壁补落差。
		wc.has_north_bank = not used.has(cell + Vector2i(0, -1))
		# 南侧岸（近岸地面）：本格南边（+y）没有水 = 水坑南缘。水面下移 DROP_HEIGHT
		# 后，最南一排水面正好落在南边那一格，被岸盖住；岸用南边地面的图集块当贴图，
		# 悬停时 set_reveal 让它半透明露出水。南边留了空行时，真正的岸在再南一格（+2）。
		var south: Vector2i = cell + Vector2i(0, 1)
		wc.has_south_bank = not used.has(south)
		wc.shore_region = Rect2(Vector2(2, 2) * tile_px, tile_px)  # 默认南岸块 (2,2)
		if wc.has_south_bank and ground != null:
			for d in [1, 2]:
				var atlas := ground.get_cell_atlas_coords(cell + Vector2i(0, d))
				if atlas != Vector2i(-1, -1):
					wc.shore_region = Rect2(Vector2(atlas) * tile_px, tile_px)
					break
		add_child(wc)
	# 清掉标记 tile，只留 WaterCell 子节点画真实水面。
	clear()
