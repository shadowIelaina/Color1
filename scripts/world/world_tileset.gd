class_name WorldTileset
## 运行时构建世界 TileSet（256px/格，直接加载现有美术贴图）。
## source id == WorldGenerator.Tile 枚举值：0 水 / 1 沙滩 / 2 雪(冰) / 3 沙漠 / 4 森林。
## 现有素材：湖水.png(水) 土墙过渡(沙/岸) 地块1tm.png(雪/灰白) grass.png(森林)；沙漠无素材 → 纯色占位。
## 每格按位置哈希从 4×4 atlas 选片：群系内部取中间 4 片，群系边缘取四周片（自动过渡，见 world_generator 的 _atlas_index）。


const TILE_PX := 256

const TEX_WATER := "res://art/picture_boluo/湖水.png"
const TEX_SAND := "res://art/picture_boluo/土墙块（湖水过渡）1.png"
const TEX_SNOW := "res://art/picture_boluo/地块1tm.png"
const TEX_FOREST := "res://art/else/grass.png"
const TEX_DESERT := ""   # 缺沙漠素材 → 占位纯色

static var _cache: TileSet = null
static var _base_cache: TileSet = null
static var _paint_cache: TileSet = null
static var _paint_sources := {"burn": 0, "freeze": 1}


static func get_tileset() -> TileSet:
	if _cache != null:
		return _cache
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	_add_source(ts, 0, TEX_WATER, Color.TRANSPARENT)
	_add_source(ts, 1, TEX_SAND, Color.TRANSPARENT)
	_add_source(ts, 2, TEX_SNOW, Color.TRANSPARENT)
	_add_source(ts, 3, TEX_DESERT, Color(0.90, 0.72, 0.38))
	_add_source(ts, 4, TEX_FOREST, Color.TRANSPARENT)
	# 水的碰撞改由 chunk.gd 里逐格 WaterCell 承担（可冻结成冰、吸蓝融回水）。
	# TileSet 层不再给水加物理，否则冻成冰后物理仍挡路，走不过去。
	_cache = ts
	return ts


## 纯白底图 TileSet（单片 256×256 白），垫在世界 tile 下面遮住贴图透明角落的空隙。
static func get_base_tileset() -> TileSet:
	if _base_cache != null:
		return _base_cache
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	var img := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	src.texture = ImageTexture.create_from_image(img)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, 0)
	_base_cache = ts
	return ts


## 加一个 atlas source（id == tile 类型）。有素材加载贴图，无素材用纯色占位。
## 所有 source 统一铺成 4×4 atlas（16 片），让 _atlas_index 的选片对所有群系都有效。
static func _add_source(ts: TileSet, id: int, tex_path: String, fallback: Color) -> void:
	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	if tex_path == "":
		var img := Image.create(TILE_PX * 4, TILE_PX * 4, false, Image.FORMAT_RGBA8)
		img.fill(fallback)
		src.texture = ImageTexture.create_from_image(img)
	else:
		src.texture = _load_atlas(tex_path)
	for ay in 4:
		for ax in 4:
			src.create_tile(Vector2i(ax, ay))
	ts.add_source(src, id)


## 加载贴图为 atlas：1024×1024 直接用；单格（256×256）铺成 4×4 让 16 片都有效。
static func _load_atlas(tex_path: String) -> Texture2D:
	var tex := load(tex_path) as Texture2D
	if tex.get_width() > TILE_PX:
		return tex
	var img := tex.get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var big := Image.create(TILE_PX * 4, TILE_PX * 4, false, Image.FORMAT_RGBA8)
	for ay in 4:
		for ax in 4:
			big.blit_rect(img, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i(ax * TILE_PX, ay * TILE_PX))
	return ImageTexture.create_from_image(big)


## 地面颜料 TileSet：source id 0=红(burn)、1=蓝(freeze)，半透明纯色单格。
## 半透明（α≈0.55）盖在被泼的陆地格上，透出底下灰度地形纹理、同时看出颜色。
static func get_paint_tileset() -> TileSet:
	if _paint_cache != null:
		return _paint_cache
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_PX, TILE_PX)
	_add_paint_source(ts, 0, Color(1.0, 0.3, 0.3))    # 红 burn
	_add_paint_source(ts, 1, Color(0.3, 0.55, 1.0))   # 蓝 freeze
	_paint_cache = ts
	return ts


## 元素 id → 颜料 source id（未知元素 → -1）。
static func paint_source_id(element: String) -> int:
	return int(_paint_sources.get(element, -1))


## 颜料 source id → 元素 id（未知 → 空串）。
static func paint_element(source_id: int) -> String:
	for el in _paint_sources:
		if int(_paint_sources[el]) == source_id:
			return el
	return ""


static func _add_paint_source(ts: TileSet, id: int, color: Color) -> void:
	var src := TileSetAtlasSource.new()
	src.texture_region_size = Vector2i(TILE_PX, TILE_PX)
	var img := Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, 0.55))
	src.texture = ImageTexture.create_from_image(img)
	src.create_tile(Vector2i(0, 0))
	ts.add_source(src, id)


