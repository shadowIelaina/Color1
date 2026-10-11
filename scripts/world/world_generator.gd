class_name WorldGenerator
## 纯函数世界生成：seed + 块坐标 → tile 数组 + 特征物散点。
## 两个噪声通道：海拔（水/岸/陆）+ 温度（生物群系：雪原/森林/沙漠）。
## 特征物用确定性每块哈希散点；纯函数无共享状态，Phase 4 已丢后台线程。

const CHUNK_SIZE := 16

enum Tile { WATER, SAND, SNOW, DESERT, FOREST }
enum Feature { NONE = -1, TREE, ROCK, GRASS, GRASS_BIG }

## 海拔阈值：低于 SEA_LEVEL 是水；SEA_LEVEL ~ SEA_LEVEL+SHORE_WIDTH 是沙滩。
const SEA_LEVEL := -0.12
const SHORE_WIDTH := 0.14
## 温度阈值：低于 COLD 雪原、高于 HOT 沙漠、中间森林。
const COLD := -0.25
const HOT := 0.25

## 每块特征散点尝试次数（越多越密）。草类要铺得密，需要比树/石头更高的尝试数。
const FEATURE_ATTEMPTS := 48

## 缓存同一 seed 的两个噪声通道（避免每块重复 new）。
static var _noise_cache: Dictionary = {}


static func _noises(seed_val: int) -> Array:
	if _noise_cache.has(seed_val):
		return _noise_cache[seed_val] as Array
	var arr: Array = [_new_elev(seed_val), _new_temp(seed_val)]
	_noise_cache[seed_val] = arr
	return arr


static func _new_elev(seed_val: int) -> FastNoiseLite:
	var elev := FastNoiseLite.new()
	elev.seed = seed_val
	elev.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elev.frequency = 0.02
	elev.fractal_type = FastNoiseLite.FRACTAL_FBM
	elev.fractal_octaves = 4
	return elev


static func _new_temp(seed_val: int) -> FastNoiseLite:
	var temp := FastNoiseLite.new()
	temp.seed = seed_val + 99991
	temp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	temp.frequency = 0.005   # 温度尺度更大 → 生物群系成片
	temp.fractal_type = FastNoiseLite.FRACTAL_FBM
	temp.fractal_octaves = 3
	return temp


static func generate(seed_val: int, cx: int, cy: int) -> PackedInt32Array:
	var noises := _noises(seed_val)
	var elev: FastNoiseLite = noises[0] as FastNoiseLite
	var temp: FastNoiseLite = noises[1] as FastNoiseLite
	var result := PackedInt32Array()
	result.resize(CHUNK_SIZE * CHUNK_SIZE)
	for ly in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var wx := cx * CHUNK_SIZE + lx
			var wy := cy * CHUNK_SIZE + ly
			var e := elev.get_noise_2d(wx, wy)
			var t := temp.get_noise_2d(wx, wy)
			result[ly * CHUNK_SIZE + lx] = _tile_at(e, t)
	return result


## 一次性生成一块的完整数据（tiles + atlas + features），每次新建噪声实例，
## 无共享可变状态 → 可安全丢进 WorkerThreadPool 后台线程。
## atlas[i] 是 5/6/9/10 之一（4×4 atlas 中间内部片的变体），群系之间靠噪声自然抖动过渡，不再用边缘暗边框片。
static func generate_chunk_data(seed_val: int, cx: int, cy: int) -> Dictionary:
	var elev := _new_elev(seed_val)
	var temp := _new_temp(seed_val)
	var base_x := cx * CHUNK_SIZE
	var base_y := cy * CHUNK_SIZE
	var tiles := PackedInt32Array()
	var atlas := PackedInt32Array()
	tiles.resize(CHUNK_SIZE * CHUNK_SIZE)
	atlas.resize(CHUNK_SIZE * CHUNK_SIZE)
	for ly in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var i := ly * CHUNK_SIZE + lx
			var wx := base_x + lx
			var wy := base_y + ly
			tiles[i] = _tile_at(elev.get_noise_2d(wx, wy), temp.get_noise_2d(wx, wy))
			atlas[i] = _ground_variant(seed_val, wx, wy)
	return {
		"tiles": tiles,
		"atlas": atlas,
		"features": generate_features(seed_val, cx, cy, tiles),
	}


## 由海拔 + 温度决定一格 tile。沙漠更干（整体海平面更低 → 水更少）。
static func _tile_at(e: float, t: float) -> int:
	var sea := SEA_LEVEL - 0.12 if t > HOT else SEA_LEVEL
	if e < sea:
		return Tile.WATER
	if e < sea + SHORE_WIDTH:
		return Tile.SAND
	if t < COLD:
		return Tile.SNOW
	if t > HOT:
		return Tile.DESERT
	return Tile.FOREST


## 单个世界坐标的 tile 类型（确定性、无状态）。用于出生点校正等单点查询。
static func tile_at(seed_val: int, wx: int, wy: int) -> int:
	var elev := _new_elev(seed_val)
	var temp := _new_temp(seed_val)
	return _tile_at(elev.get_noise_2d(wx, wy), temp.get_noise_2d(wx, wy))


## 从 (wx, wy) 螺旋向外找最近的陆地（非水）格，返回该格 tile 坐标。
## 保证玩家不会出生在水里被水碰撞卡死。极端全水时退回原点。
static func find_land(seed_val: int, wx: int, wy: int, max_radius: int = 32) -> Vector2i:
	if tile_at(seed_val, wx, wy) != Tile.WATER:
		return Vector2i(wx, wy)
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dy)) != r:
					continue
				var tx := wx + dx
				var ty := wy + dy
				if tile_at(seed_val, tx, ty) != Tile.WATER:
					return Vector2i(tx, ty)
	return Vector2i(wx, wy)


## 确定性整数混合：把 (seed, cx, cy) 混成一个稳定种子。
## 不用 Godot 内置 hash()（跨版本不稳定），自写简单混合。
static func _chunk_seed(seed_val: int, cx: int, cy: int) -> int:
	return _tile_hash(seed_val, cx, cy)


## 每格确定性哈希（跨版本稳定），用于在等价图集片里挑变化。
static func _tile_hash(seed_val: int, x: int, y: int) -> int:
	return (seed_val ^ (x * 0x9E3779B1) ^ (y * 0x85EBCA77)) & 0x7FFFFFFF


## 无缝地面：只从 4×4 atlas 的中间 4 片内部格（5/6/9/10）按位置哈希挑变体，
## 不用外圈带暗边框的边缘片 —— 群系之间靠噪声自然抖动过渡，而非硬边（饥荒式）。
static func _ground_variant(seed_val: int, wx: int, wy: int) -> int:
	match _tile_hash(seed_val, wx, wy) & 3:
		0: return 5
		1: return 6
		2: return 9
		_: return 10


## 一块的特征物：[{type, x, y, size}]；x/y 是本地格坐标（格中心 ±0.25 抖动），size 是缩放。
static func generate_features(seed_val: int, cx: int, cy: int, tiles: PackedInt32Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(seed_val, cx, cy)
	var features: Array = []
	for _i in FEATURE_ATTEMPTS:
		var tx := rng.randi_range(0, CHUNK_SIZE - 1)
		var ty := rng.randi_range(0, CHUNK_SIZE - 1)
		var feat := _roll_feature(tiles[ty * CHUNK_SIZE + tx], rng)
		if feat != Feature.NONE:
			features.append({
				"type": feat,
				"x": float(tx) + 0.5 + rng.randf_range(-0.25, 0.25),
				"y": float(ty) + 0.5 + rng.randf_range(-0.25, 0.25),
				"size": rng.randf_range(0.8, 1.3),
			})
	return features


## 每种群系能散出哪些物件（饥荒式加权表）。
## FOREST：草最密 + 大草丛 + 稀疏的树；雪原/沙漠：石头；沙滩/水：无。
static func _roll_feature(t: int, rng: RandomNumberGenerator) -> int:
	match t:
		Tile.FOREST:
			var r := rng.randf()
			if r < 0.52:
				return Feature.GRASS
			if r < 0.64:
				return Feature.GRASS_BIG
			if r < 0.72:
				return Feature.TREE
			return Feature.NONE
		Tile.SNOW, Tile.DESERT:
			return Feature.ROCK if rng.randf() < 0.45 else Feature.NONE
		_:
			return Feature.NONE
