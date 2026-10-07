class_name WaterCell
extends StaticBody2D
## 单个水格：初始为水（凹坑里的水面，阻挡玩家）。被赋予「蓝」(freeze) 后结冰——
## 冰块填满坑、顶面与岸齐平（可通行）；吸收蓝色则冰融回水、重新挡路。
## 属于 "colorable" group，实现 contains_point / apply_color 契约，供玩家鼠标赋予。
##
## 高程约定（伪 2.5D 正交投影）：岸/玩家 z=0，水面 z=-drop_height（凹下去）。
## 所以水面整体下移 drop_height，冰块顶面固定在 0（与岸齐平），侧面朝下伸到水面。

const Rules := preload("res://scripts/element/element_rules.gd")

## 格子边长（世界单位）。一格水 = 一格 tile（= HeightMap.CELL，256px）。
var cell_size := Vector2(HeightMap.CELL, HeightMap.CELL)

## 岸与水的落差（像素）：水面凹下去的高度 = 冰块厚度（= 一格高 HeightMap.CELL）。
var drop_height := HeightMap.CELL
const GROW_TIME := 0.25

## —— 水面外观（在 Water 层节点的 Inspector 编辑，spawner 会复制给每个水格）——
## 纯色水面颜色（默认水蓝）。water_material / water_texture 都为空时生效。
@export var water_color := Color(0.13, 0.48, 0.64)
## 可选：换美术贴图（PNG），设置后盖过 water_color，一格贴一张、缩放到一格大小无缝平铺。
@export var water_texture: Texture2D
## 可选：挂 shader（如 res://water/water_material.tres）得到动画水面，设置后盖过颜色/贴图。
@export var water_material: Material
## 北侧岸壁颜色（水坑北面露出的土壁，默认暗土色）。只有水坑北缘的水格才画。
@export var bank_color := Color(0.28, 0.26, 0.24)
## 南侧岸（近岸地面）贴图：盖住最南一排水面的「岸」。默认用地面图集（spawner 传入 ground.png）。
## 鼠标悬停时半透明露出水。只有水坑南缘（南边没有水）的水格才画。
@export var shore_texture: Texture2D
## 南侧岸贴图在图集里的区域（region）。由 spawner 按南边地面的 atlas 坐标算出；默认南岸块 (2,2)。
var shore_region := Rect2(2 * HeightMap.CELL, 2 * HeightMap.CELL, HeightMap.CELL, HeightMap.CELL)
## 兜底：没有 shore_texture 时用的南侧岸纯色。
@export var shore_color := Color(0.35, 0.32, 0.27)
## 是否画冰块的影子（投在水面上的深色底图）。关掉可去掉结冰时底部那张深色贴图。
@export var ice_shadow_enabled := true
## 冰块顶面贴图（可选）：设置后顶面改用此贴图（缩放到一格），否则用 ice_top_color 纯色。
@export var ice_top_texture: Texture2D
## 冰块侧面贴图（可选）：设置后侧面改用此贴图（纵向拉伸），否则用 ice_side_color 纯色。
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

var _frozen := false
## 是否画北侧岸壁（本格北边没有水 = 水坑北缘）。由 spawner 按邻居判定后设置。
var has_north_bank := false
var _col: CollisionShape2D
var _visual: Node2D      # 水面（Polygon2D 纯色/shader，或 Sprite2D 贴图），整体下移 drop_height
var _ice: Node2D         # 冰块容器（影子 → 侧面 → 顶面）
var _ice_side: Node2D      # 侧面：Sprite2D 贴图 / Polygon2D 纯色
var _ice_top: Node2D       # 顶面：Sprite2D 贴图 / Polygon2D 纯色
var _tween: Tween
## 是否画南侧岸（本格南边没有水 = 水坑南缘）。由 spawner 按邻居判定后设置。
var has_south_bank := false
var _south_bank: Node2D      # 近岸地面（Sprite2D 贴图 / Polygon2D 纯色），盖在最南一排水面上；悬停时半透明露出水
var _revealed := false
var _player_revealed := false   # 玩家在水里、站在本格（被南岸挡住）时：岸画到最前 + 半透明露出玩家
var _reveal_tween: Tween
var _preview: Node2D           # 冻结预览容器（半透明冰块，悬停提示）
var _player_standing := false   # 玩家正站在这块冰上（掉进水里后）：碰撞保持关闭，等玩家离开本格再恢复


func _ready() -> void:
	add_to_group("colorable")
	collision_layer = 2   # 阻挡玩家（玩家 mask 6 = 层 2+3）
	collision_mask = 0
	_build_collision()
	_build_north_bank()
	_build_visual()
	# Ice 要在 BankSouth 之前构建：南岸（近岸地面）是最上层，冻结时盖住冰的侧面（前立面），
	# 这样结冰不会把岸边遮住。
	_build_ice()
	_build_preview()
	_build_south_bank()
	_ice.visible = false
	_set_grow(0.0)
	_register_height(-drop_height, false)   # 水：凹坑，不可站


## 点击命中：世界坐标点是否落在本格「可见范围」内。
## 水（未结冰）可见的是下移 drop_height 的水面；冰（结冰）可见的是整个坑（顶面+侧面）。
## 命中区域按状态切换，跟玩家眼睛看到的位置一致：点蓝色水面命中水，点冰块命中冰。
func contains_point(world_pos: Vector2) -> bool:
	var local := to_local(world_pos)
	var h := cell_size.x * 0.5
	if _frozen:
		# 冰：整个坑，从岸高（本格）到水面（下移 drop_height）。
		return Rect2(Vector2(-h, -h), Vector2(cell_size.x, cell_size.y + drop_height)).has_point(local)
	# 水：水面（下移 drop_height 后的位置）。
	return Rect2(Vector2(-h, -h + drop_height), cell_size).has_point(local)


## 被赋予颜色：目前只有「蓝」会让水结冰，其它颜色暂不处理。
## 返回是否真的生效（已结冰或非蓝都不生效），供玩家侧判断是否该消耗种子。
func apply_color(_c: Color, color_name: String = "", _from_pos: Vector2 = Vector2.INF) -> bool:
	if _frozen:
		return false
	if color_name == "蓝":
		_freeze()
		return true
	return false


## 是否已结冰。
func is_frozen() -> bool:
	return _frozen


## 是否当前带色：结冰 = 带蓝（可被吸收）。
func has_color() -> bool:
	return _frozen


## 吸收蓝色：冰融回水（重新挡路），玩家获得蓝。
func absorb_color() -> Dictionary:
	if not _frozen:
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	_frozen = false
	# 玩家正站在这块冰上时先别恢复碰撞：否则碰撞会把玩家顶到岸边/地面上。
	# 改为让玩家「掉进水里」（HeightMap 变 -16，脚下滑落），等玩家离开本格再恢复碰撞。
	if _player_on_cell(get_tree().get_first_node_in_group("player")):
		_player_standing = true
	else:
		_col.set_deferred("disabled", false)  # 恢复碰撞 → 重新挡路
	_tween_grow(drop_height, 0.0, _on_melt_done)
	_register_height(-drop_height, false)  # 冰融回水：凹坑，不可站
	return {
		"element": "freeze",
		"color": Rules.config("freeze")["color"],
		"color_name": Rules.config("freeze")["color_name"],
	}


## 结冰：取消碰撞（可通行），冰块从坑里「长满」到岸高。
func _freeze() -> void:
	_frozen = true
	_col.set_deferred("disabled", true)
	_visual.visible = false
	_ice.visible = true
	_tween_grow(0.0, drop_height)
	_register_height(0.0, true)   # 冰：与岸齐平，可站


## 冰块厚度补间：顶面固定在岸高，侧面从 0 向下长到 drop_height（伸到水面）。
func _tween_grow(from_v: float, to_v: float, done: Callable = Callable()) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_grow, from_v, to_v, GROW_TIME)
	if done.is_valid():
		_tween.tween_callback(done)


## 更新冰块厚度：侧面墙从岸高（y=h）向下长到水面（y=h+d）。
## 贴图模式用 Sprite2D 纵向缩放（顶边固定在水面高度 h）；纯色模式改 Polygon2D。
func _set_grow(d: float) -> void:
	var h := cell_size.x * 0.5
	if _ice_side is Polygon2D:
		(_ice_side as Polygon2D).polygon = PackedVector2Array([
			Vector2(-h, h),
			Vector2(h, h),
			Vector2(h, h + d),
			Vector2(-h, h + d),
		])
	elif _ice_side is Sprite2D:
		var side := _ice_side as Sprite2D
		var ts := side.texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			side.scale = Vector2(cell_size.x / ts.x, d / ts.y)
		# 顶边固定在水面高度 h，向下长 d。
		side.position = Vector2(0, h + d * 0.5)


func _on_melt_done() -> void:
	_visual.visible = true
	_ice.visible = false


## 把本格高度写入全局高度图：水 = -drop_height（凹，不可站），冰 = 0（与岸齐平，可站）。
## 一格水 = 一格 256px 高度格，直接 set_cell。
func _register_height(z: float, walkable: bool) -> void:
	HeightMap.set_cell(global_position, z, walkable)


## 玩家是否正站在本格（脚底在本格 16×16 范围内）。用于「吸收脚下的冰 → 掉进水里」：
## 站高只移动贴图、不移动身体，所以玩家身体始终在本格自然范围内，用紧贴的一格矩形判断即可。
func _player_on_cell(player: Node) -> bool:
	if player == null or not (player is Node2D):
		return false
	var local := to_local((player as Node2D).global_position)
	var h := cell_size.x * 0.5
	return Rect2(Vector2(-h, -h), cell_size).has_point(local)


## 玩家是否「被本格南岸挡住」：在水里（不可站）且脚底站在本格范围内。
## 满足时岸要盖住玩家（画到最前），同时半透明让玩家能透出来。
func _player_behind_bank(player: Node) -> bool:
	if not has_south_bank:
		return false
	if not (player is Node2D):
		return false
	if bool(HeightMap.sample((player as Node2D).global_position).get("walkable", true)):
		return false
	return _player_on_cell(player)


## 每帧两件事：
## 1) 掉进水里后，等玩家离开本格再恢复碰撞（重新挡路）。
## 2) 玩家在水里、站在本格（被南岸挡住）时，把南岸画到最前盖住玩家，并半透明露出被挡的玩家。
func _physics_process(_delta: float) -> void:
	if not has_south_bank and not _player_standing:
		return
	var player := get_tree().get_first_node_in_group("player")
	if _player_standing:
		if player == null or not _player_on_cell(player):
			_player_standing = false
			_col.set_deferred("disabled", false)
	var behind := player != null and _player_behind_bank(player)
	if behind != _player_revealed:
		_player_revealed = behind
		_refresh_bank()


func _build_collision() -> void:
	var shape := RectangleShape2D.new()
	shape.size = cell_size
	_col = CollisionShape2D.new()
	_col.name = "Collision"
	_col.shape = shape
	add_child(_col)


## 北侧岸壁：水坑北缘露出的立墙（岸高 → 水面的 drop_height 落差）。
## 只有 has_north_bank 的水格才画，填掉水面下移后北边露出的空隙。
func _build_north_bank() -> void:
	if not has_north_bank:
		return
	var h := cell_size.y * 0.5
	var ext := 0.5  # 相邻格轻微重叠，消除接缝
	var bank := Polygon2D.new()
	bank.name = "BankNorth"
	bank.color = bank_color
	bank.polygon = PackedVector2Array([
		Vector2(-h - ext, -h),
		Vector2(h + ext, -h),
		Vector2(h + ext, -h + drop_height),
		Vector2(-h - ext, -h + drop_height),
	])
	add_child(bank)


func _build_visual() -> void:
	if water_texture != null:
		# 贴图模式：Sprite2D，缩放到一格大小无缝平铺。
		var s := Sprite2D.new()
		s.name = "Visual"
		s.centered = true
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.texture = water_texture
		var ts := water_texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			s.scale = cell_size / ts
		s.position.y = drop_height
		_visual = s
	else:
		# 纯色 / shader 模式：Polygon2D，相邻格轻微重叠消除接缝。
		var p := Polygon2D.new()
		p.name = "Visual"
		var ext := cell_size * 0.5 + Vector2(0.5, 0.5)
		p.polygon = PackedVector2Array([
			Vector2(-ext.x, -ext.y),
			Vector2(ext.x, -ext.y),
			Vector2(ext.x, ext.y),
			Vector2(-ext.x, ext.y),
		])
		if water_material != null:
			p.material = water_material
		else:
			p.color = water_color
		# 水面整体下移 drop_height，让水比岸低（凹坑）。
		p.position.y = drop_height
		_visual = p
	add_child(_visual)


## 南侧岸：近岸地面，盖在最南一排水面（下移 drop_height 后的位置）上，正确遮挡水底。
## 只有 has_south_bank（水坑南缘）的水格才画；add 在 _visual 之后，保证画在水面之上。
## 鼠标悬停时 set_reveal(true) 让它半透明，露出被挡的水面。
func _build_south_bank() -> void:
	if not has_south_bank:
		return
	if shore_texture != null:
		# 贴图模式：取地面图集里南边地面那一块，1:1 平铺（region 已按 16px 格算好）。
		var s := Sprite2D.new()
		s.name = "BankSouth"
		s.centered = true
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.texture = shore_texture
		s.region_enabled = true
		s.region_rect = shore_region
		s.position = Vector2(0, drop_height)
		# 水面 Polygon2D 每边有 0.5px 重叠（17x17）消除水格接缝；岸条也放大到 17x17，
		# 否则蓝色水面会从岸条四周多出的 0.5px 露出来（细蓝边）。
		s.scale = (cell_size + Vector2.ONE) / cell_size
		_south_bank = s
	else:
		# 兜底：没有贴图时用纯色，相邻格轻微重叠消除接缝。
		var ext := cell_size * 0.5 + Vector2(0.5, 0.5)
		var p := Polygon2D.new()
		p.name = "BankSouth"
		p.color = shore_color
		p.polygon = PackedVector2Array([
			Vector2(-ext.x, -ext.y),
			Vector2(ext.x, -ext.y),
			Vector2(ext.x, ext.y),
			Vector2(-ext.x, ext.y),
		])
		p.position = Vector2(0, drop_height)
		_south_bank = p
	add_child(_south_bank)


## 悬停提示：鼠标在本格水面/岸上时，把南侧岸变半透明，露出被挡的水面，让玩家看清能点哪里。
func set_reveal(value: bool) -> void:
	if _revealed == value:
		return
	_revealed = value
	_refresh_bank()


## 统一刷新南岸的「遮挡层级 + 透明度」：
##  - 玩家被岸挡住（_player_revealed）时，岸画到最前（z_index 2，盖住 z=0 的玩家），
##    否则回到 0（仍在水层 z=-1 之下，正常让玩家盖住岸）。
##  - 鼠标悬停或玩家被挡住时，岸变半透明（0.35），否则恢复不透明。
func _refresh_bank() -> void:
	if _south_bank == null:
		return
	_south_bank.z_index = 2 if _player_revealed else 0
	var target := 0.35 if (_revealed or _player_revealed) else 1.0
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(_south_bank, "modulate:a", target, 0.15)


## 立体冰块：影子（投在水面，可关）→ 侧面墙（前立面，朝下伸到水面）→ 顶面（与岸齐平）。
## 侧面/顶面有贴图时用 Sprite2D（美术贴图），否则用 Polygon2D 纯色。
func _build_ice() -> void:
	var h := cell_size.x * 0.5
	_ice = Node2D.new()
	_ice.name = "Ice"
	add_child(_ice)

	if ice_shadow_enabled:
		var shadow := Polygon2D.new()
		shadow.name = "Shadow"
		shadow.color = Color(0.02, 0.12, 0.22, 0.35)
		var s := 3.0
		shadow.polygon = PackedVector2Array([
			Vector2(-h - s, -h - s), Vector2(h + s, -h - s),
			Vector2(h + s, h + s), Vector2(-h - s, h + s),
		])
		# 影子投在凹下去的水面上（下移 drop_height），再朝右下偏一点模拟光照。
		shadow.position = Vector2(3, drop_height + 4)
		_ice.add_child(shadow)

	if ice_side_texture != null:
		var side := Sprite2D.new()
		side.name = "Side"
		side.centered = true
		side.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		side.texture = ice_side_texture
		_ice_side = side
	else:
		var side := Polygon2D.new()
		side.name = "Side"
		side.color = ice_side_color   # 侧面（背光的冰蓝）
		_ice_side = side
	_ice.add_child(_ice_side)

	if ice_top_texture != null:
		var top := Sprite2D.new()
		top.name = "Top"
		top.centered = true
		top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		top.texture = ice_top_texture
		var ts := ice_top_texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			top.scale = cell_size / ts   # 缩放到一格大小
		_ice_top = top
	else:
		var top := Polygon2D.new()
		top.name = "Top"
		top.color = ice_top_color   # 顶面（亮冰白，与岸齐平）
		top.polygon = PackedVector2Array([
			Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h),
		])
		_ice_top = top
	_ice.add_child(_ice_top)


## 冻结预览：半透明冰块（顶面 + 前立面），悬停未结冰水格时提示「点这里会结冰」。
## 贴图优先用 freeze_preview_top/side_texture（预览专属美术），为空则复用 ice_top/ice_side
## 的贴图，再退纯色；整体再降透明度。
func _build_preview() -> void:
	var h := cell_size.x * 0.5
	_preview = Node2D.new()
	_preview.name = "FreezePreview"
	_preview.modulate = Color(1, 1, 1, freeze_preview_alpha)
	_preview.visible = false

	# 前立面（侧墙）：南缘（近岸）水格的冰侧面会被南岸盖住，预览里不画它，
	# 否则半透明的冰侧面会透过半透明的岸边露出来、像是把岸遮住了。
	if not has_south_bank:
		# 侧面：优先用预览专属贴图，否则复用冰的侧面贴图，再退纯色。
		var side_tex := freeze_preview_side_texture if freeze_preview_side_texture != null else ice_side_texture
		if side_tex != null:
			var side := Sprite2D.new()
			side.name = "Side"
			side.centered = true
			side.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			side.texture = side_tex
			side.position = Vector2(0, h + drop_height * 0.5)
			var ts := side_tex.get_size()
			if ts.x > 0.0 and ts.y > 0.0:
				side.scale = Vector2(cell_size.x / ts.x, drop_height / ts.y)
			_preview.add_child(side)
		else:
			var side := Polygon2D.new()
			side.name = "Side"
			side.color = ice_side_color
			side.polygon = PackedVector2Array([
				Vector2(-h, h), Vector2(h, h), Vector2(h, h + drop_height), Vector2(-h, h + drop_height),
			])
			_preview.add_child(side)

	# 顶面：优先用预览专属贴图，否则复用冰的顶面贴图，再退纯色。
	var top_tex := freeze_preview_top_texture if freeze_preview_top_texture != null else ice_top_texture
	if top_tex != null:
		var top := Sprite2D.new()
		top.name = "Top"
		top.centered = true
		top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		top.texture = top_tex
		var ts := top_tex.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			top.scale = cell_size / ts
		_preview.add_child(top)
	else:
		var top := Polygon2D.new()
		top.name = "Top"
		top.color = ice_top_color
		top.polygon = PackedVector2Array([
			Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h),
		])
		_preview.add_child(top)

	add_child(_preview)


## 显示/隐藏冻结预览（半透明冰块）。
func set_freeze_preview(value: bool) -> void:
	if _preview != null:
		_preview.visible = value
