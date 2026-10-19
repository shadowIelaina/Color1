extends Node
## AudioManager（Autoload）：全局音效/环境音。只做音频，不改玩法与场景。
##
## 脚步声：按脚下地表类型 + 累计移动距离触发。
##   水 walkinWater 每 3 格一次；草 walkongrass、泥地 walkondirt 每 2 格一次。
##   同类多音效轮换（交叉）播放，避免连续两声相同。
## WaterFlow：离最近未结冰水面 ≤ 7 格时淡入，否则淡出。
## IceBreak：冰块破碎时由 ice_block.gd 调用 play_ice_break()。
##
## 地表判定「以地图上实际贴的 png 为准」：
##   水/冰 → colorable 组里的 WaterCell（is_frozen + contains_point）。
##   草/泥地 → 采样脚下地面 tile 的贴图文件名（草/grass → 草；地块/土墙 → 泥地）。

const CELL := 256.0  # 一格像素（与 HeightMap.CELL 一致）

## 脚步间隔（单位：格）。水 3 格、草 2 格、泥地 2 格。
const STEP_INTERVAL_TILES := {"water": 3, "grass": 2, "ground": 2}
## 水面环境音触发距离（单位：格）。
const WATERFLOW_RANGE_TILES := 5
## 水流声交叉淡入时长（秒）：MP3 循环点有编码静音间隙，用双播放器交叉淡入抹平。
const WATERFLOW_CROSSFADE := 0.8

## 每类脚步的可选音效（轮换播放）。
const STEP_STREAMS := {
	"water": [
		preload("res://audio/SE/WalkInWater1.mp3"),
		preload("res://audio/SE/WalkInWater2.mp3"),
	],
	"grass": [
		preload("res://audio/SE/WalkOnGrass1.mp3"),
		preload("res://audio/SE/WalkOnGrass2.mp3"),
		preload("res://audio/SE/WalkOnGrass3.mp3"),
	],
	"ground": [
		preload("res://audio/SE/WalkOnDirt1.mp3"),
		preload("res://audio/SE/WalkOnDirt2.mp3"),
		preload("res://audio/SE/WalkOnDirt3.mp3"),
	],
}
const ICE_BREAK_STREAM := preload("res://audio/SE/IceBreak.mp3")
const WATERFLOW_STREAM := preload("res://audio/BGS/WaterFlow.mp3")

## 普通背景音乐（audio/music/ 下除 trial! 外），轮流循环播放。
const MUSIC_STREAMS := [
	preload("res://audio/music/拿铁.mp3"),
	preload("res://audio/music/谜面.mp3"),
	preload("res://audio/music/雪云.mp3"),
]
## 最终 boss 战音乐，暂未启用。
const BOSS_MUSIC_STREAM := preload("res://audio/music/trial!.mp3")
const MUSIC_VOLUME_DB := -10.0

## 草 / 泥地贴图文件名关键词（小写）。
const GRASS_KEYWORDS := ["草", "grass"]
const GROUND_KEYWORDS := ["地块", "土墙", "ground", "dirt", "泥"]
## 水面贴图文件名关键词（小写）：深水/浅水/背景水层的贴图都含「湖/水」。
const WATER_KEYWORDS := ["湖", "水", "water"]
## 含这些词的地面贴图（如「土墙块（湖水过渡）」）不算水面。
const WATER_EXCLUDE := ["过渡", "土墙", "地块", "rock", "草"]

## SE 播放器池大小（轮换播放，允许脚步轻微重叠）。
const SE_POOL_SIZE := 6

var _wf_a: AudioStreamPlayer
var _wf_b: AudioStreamPlayer
var _se_pool: Array[AudioStreamPlayer] = []
var _se_next := 0
var _waterflow_volume := 0.0
var _wf_cur := 0       # 当前主水流播放器：0=a，1=b
var _wf_xfade := 0.0   # 交叉淡入进度 0~1（0=全用 cur，1=全用 next）
var _music_player: AudioStreamPlayer
var _music_idx := 0

var _player: Node2D = null
var _last_pos := Vector2.ZERO
var _step_accum := 0.0
var _surface := ""
var _step_idx := {}           # surface -> 下一个要播的变体下标
var _ground_layers: Array[TileMapLayer] = []
var _water_layers: Array[TileMapLayer] = []


func _ready() -> void:
	_ensure_bus("BGS")
	_ensure_bus("SE")
	_ensure_bus("Music")
	_setup_music()

	var wf := WATERFLOW_STREAM
	if wf is AudioStreamMP3:
		# 音频够长才用双播放器交叉淡入无缝循环；太短则退回单播放器循环（有间隙但至少有声）。
		(wf as AudioStreamMP3).loop = WATERFLOW_STREAM.get_length() <= WATERFLOW_CROSSFADE * 2.0
	_wf_a = _make_wf_player()
	_wf_b = _make_wf_player()
	add_child(_wf_a)
	add_child(_wf_b)
	_wf_a.play()

	for i in SE_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SE"
		add_child(p)
		_se_pool.append(p)

	SceneManager.room_changed.connect(_on_room_changed)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
		_last_pos = _player.global_position
		_step_accum = 0.0
		_surface = ""
	_update_footsteps()
	_update_waterflow(delta)


## —— 脚步声 ——

func _update_footsteps() -> void:
	var pos := _player.global_position
	var moved := pos.distance_to(_last_pos)
	_last_pos = pos
	if moved > CELL * 2.0:
		# 瞬移（切房/重生）：重置累计，不发声。
		_step_accum = 0.0
		return
	var surf := surface_at(pos)
	if surf != _surface:
		_surface = surf
		_step_accum = 0.0
	if moved <= 0.0:
		return
	_step_accum += moved
	var tiles := int(STEP_INTERVAL_TILES.get(surf, 0))
	if tiles <= 0:
		# 冰面等未定义地表：不出脚步。
		_step_accum = 0.0
		return
	if _step_accum >= tiles * CELL:
		_step_accum = fmod(_step_accum, tiles * CELL)
		_play_step(surf)


func _play_step(surf: String) -> void:
	var streams: Array = STEP_STREAMS.get(surf, [])
	if streams.is_empty():
		return
	var idx := int(_step_idx.get(surf, 0))
	_step_idx[surf] = (idx + 1) % streams.size()
	_play_sfx(streams[idx])


## —— 背景音乐（BGM）——

func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = MUSIC_VOLUME_DB
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	_play_music_track(0)


func _play_music_track(idx: int) -> void:
	if MUSIC_STREAMS.is_empty():
		return
	_music_idx = idx % MUSIC_STREAMS.size()
	_music_player.stream = MUSIC_STREAMS[_music_idx]
	_music_player.play()


func _on_music_finished() -> void:
	_play_music_track(_music_idx + 1)


## —— 环境音 ——

func _update_waterflow(delta: float) -> void:
	var target := 1.0 if _nearest_water_distance(_player.global_position) <= WATERFLOW_RANGE_TILES * CELL else 0.0
	_waterflow_volume = lerpf(_waterflow_volume, target, 1.0 - exp(-3.0 * delta))
	_update_waterflow_crossfade(delta)
	var cur := _wf_a if _wf_cur == 0 else _wf_b
	var next := _wf_b if _wf_cur == 0 else _wf_a
	cur.volume_db = linear_to_db(maxf(_waterflow_volume * (1.0 - _wf_xfade), 0.0001))
	next.volume_db = linear_to_db(maxf(_waterflow_volume * _wf_xfade, 0.0001))


## 双播放器交叉淡入无缝循环：主播放器快播完时提前启动另一个，循环点的 MP3 静音被盖掉。
func _update_waterflow_crossfade(delta: float) -> void:
	var length := WATERFLOW_STREAM.get_length()
	if length <= WATERFLOW_CROSSFADE * 2.0:
		return   # 音频太短，交叉淡入没意义（也不会有明显循环间隙）
	var cur := _wf_a if _wf_cur == 0 else _wf_b
	var next := _wf_b if _wf_cur == 0 else _wf_a
	if not next.playing and (not cur.playing or cur.get_playback_position() >= length - WATERFLOW_CROSSFADE):
		next.play()
	if next.playing:
		_wf_xfade = minf(_wf_xfade + delta / WATERFLOW_CROSSFADE, 1.0)
		if _wf_xfade >= 1.0:
			cur.stop()
			_wf_cur = 1 - _wf_cur
			_wf_xfade = 0.0


func _make_wf_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "BGS"
	p.stream = WATERFLOW_STREAM
	p.volume_db = -80.0
	return p


## 最近未结冰水面距离：深水/浅水走 colorable 组的 WaterCell（冻结的冰不算「流水」），
## 背景水等纯视觉水面走水面层 tile 补距离。
func _nearest_water_distance(pos: Vector2) -> float:
	var best := INF
	var frozen: Array[Vector2] = []
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("is_frozen"):
			continue
		if not obj is Node2D:
			continue
		var opos := (obj as Node2D).global_position
		if bool(obj.call("is_frozen")):
			frozen.append(opos)
			continue
		best = minf(best, pos.distance_to(opos))
	# 纯视觉水面层（背景水）：逐格补距离；跳过已结冰的格（tile 还在但已不是流水）。
	for layer in _water_layers:
		if not is_instance_valid(layer):
			continue
		for cell in layer.get_used_cells():
			var wpos := layer.to_global(layer.map_to_local(cell))
			if _near_any(wpos, frozen, CELL * 0.5):
				continue
			best = minf(best, pos.distance_to(wpos))
	return best


## —— 音效（冰块破碎等） ——

func play_ice_break() -> void:
	_play_sfx(ICE_BREAK_STREAM)


func _play_sfx(stream: AudioStream) -> void:
	if stream == null or _se_pool.is_empty():
		return
	var p := _se_pool[_se_next]
	_se_next = (_se_next + 1) % _se_pool.size()
	p.stream = stream
	p.play()


## —— 地表判定 ——

## 采样某世界坐标的地表类型：water / ice / grass / ground。
func surface_at(pos: Vector2) -> String:
	# 1. 水/冰：colorable 组里的 WaterCell。
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("is_frozen") or not obj.has_method("contains_point"):
			continue
		if not bool(obj.call("contains_point", pos)):
			continue
		return "ice" if bool(obj.call("is_frozen")) else "water"
	# 2. 草/泥地：脚下地面 tile 的贴图文件名。多层重叠时取 z_index 最高（最上层）的那格。
	var best_z := -INF
	var best_surf := ""
	for layer in _ground_layers:
		if not is_instance_valid(layer):
			continue
		var cell := layer.local_to_map(layer.to_local(pos))
		var src_id := layer.get_cell_source_id(cell)
		if src_id == -1:
			continue
		var src := layer.tile_set.get_source(src_id)
		var atlas := src as TileSetAtlasSource
		if atlas != null and atlas.texture != null:
			var fname := atlas.texture.resource_path.get_file().to_lower()
			var surf := "grass" if _matches_any(fname, GRASS_KEYWORDS) else "ground"
			if layer.z_index >= best_z:
				best_z = layer.z_index
				best_surf = surf
	return best_surf if best_surf != "" else "ground"


## —— 地面层收集 ——

func _on_room_changed(_room_id: String) -> void:
	# 立即清空旧层引用：切关后旧场景的 TileMapLayer 已释放，rescan 延迟执行前不能留着 freed 引用。
	_ground_layers.clear()
	_water_layers.clear()
	_rescan_layers.call_deferred()
	_step_accum = 0.0
	_surface = ""


func _rescan_layers() -> void:
	_ground_layers.clear()
	_water_layers.clear()
	_collect_layers(get_tree().root)


func _collect_layers(node: Node) -> void:
	if node is TileMapLayer and GameState.is_in_current_scene(node):
		if _layer_is_ground(node):
			_ground_layers.append(node)
		elif _layer_is_water(node):
			_water_layers.append(node)
	for child in node.get_children():
		_collect_layers(child)


## 该 TileMapLayer 是否属于「地面」层（tileset 里有草/泥地贴图）。
## 水层、流向箭头层、空气墙层会被自然排除（它们的贴图不匹配草/泥地关键词）。
func _layer_is_ground(layer: TileMapLayer) -> bool:
	var ts := layer.tile_set
	if ts == null:
		return false
	for i in ts.get_source_count():
		var atlas := ts.get_source(i) as TileSetAtlasSource
		if atlas != null and atlas.texture != null:
			var fname := atlas.texture.resource_path.get_file().to_lower()
			if _matches_any(fname, GRASS_KEYWORDS) or _matches_any(fname, GROUND_KEYWORDS):
				return true
	return false


## 该 TileMapLayer 是否属于「水面」层（tileset 里有湖水贴图，且运行时仍有水面 tile）。
## 深水/浅水/背景水层都用湖水贴图；「土墙块（湖水过渡）」等地面贴图被 WATER_EXCLUDE 排除；
## 空气墙等标记层复用了湖水贴图但运行时已 clear（get_used_cells 空），也一并排除。
func _layer_is_water(layer: TileMapLayer) -> bool:
	if layer.get_used_cells().is_empty():
		return false
	var ts := layer.tile_set
	if ts == null:
		return false
	for i in ts.get_source_count():
		var atlas := ts.get_source(i) as TileSetAtlasSource
		if atlas != null and atlas.texture != null:
			var fname := atlas.texture.resource_path.get_file().to_lower()
			if _matches_water(fname):
				return true
	return false


func _matches_any(text: String, keywords: Array) -> bool:
	for k in keywords:
		if k in text:
			return true
	return false


## 水面贴图判定：含「湖/水」等关键词，且不含地面过渡词。
func _matches_water(text: String) -> bool:
	if not _matches_any(text, WATER_KEYWORDS):
		return false
	return not _matches_any(text, WATER_EXCLUDE)


## p 是否靠近 points 中任一点（距离 < radius）。
func _near_any(p: Vector2, points: Array[Vector2], radius: float) -> bool:
	var r2 := radius * radius
	for q in points:
		if p.distance_squared_to(q) < r2:
			return true
	return false


## —— 工具 ——

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, bus_name)
