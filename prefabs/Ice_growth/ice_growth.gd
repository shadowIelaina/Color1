extends Node2D

@export var grow_duration : float = 3.0
@export var grow_dir : Vector2 = Vector2.RIGHT
@export var auto_start : bool = true
@export var glow_fade_time : float = 0.3   # 新增：边缘光淡出时长

@onready var _visual: Sprite2D = $Sprite2D
@onready var _particles: GPUParticles2D = $GPUParticles2D

var _progress : float = 0.0
var _growing  : bool  = false
var _size     : Vector2
var _center   : Vector2
var _glow_tween : Tween

func _ready() -> void:
	var mat := _visual.material as ShaderMaterial
	if mat == null:
		push_error("Sprite2D 的 Material 必须是 ShaderMaterial，并加载 grow.gdshader")
		return
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("grow_dir", grow_dir)
	mat.set_shader_parameter("glow_strength", 1.0)

	if _visual.texture == null:
		push_error("Sprite2D 没有设置 Texture")
		return
	_size   = _visual.texture.get_size() * _visual.scale
	_center = Vector2.ZERO

	_particles.local_coords = false
	_particles.emitting = false

	_setup_particles()

	if auto_start:
		start()

func _setup_particles() -> void:
	var pm := _particles.process_material as ParticleProcessMaterial
	if pm == null:
		push_error("GPUParticles2D 的 Process Material 必须是 ParticleProcessMaterial")
		return

	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX

	var perp := Vector2(-grow_dir.y, grow_dir.x)

	var edge_len: float
	if absf(grow_dir.x) > 0.5:
		edge_len = _size.y
	else:
		edge_len = _size.x

	pm.emission_box_extents = Vector3(
		absf(perp.x) * edge_len * 0.5,
		absf(perp.y) * edge_len * 0.5,
		0.0
	)

	pm.direction = Vector3(perp.x, perp.y, 0)

func start() -> void:
	_progress = 0.0
	_growing  = true

	# 让 grow_dir 在本次生长生效：shader 与粒子发射都按最新方向重配。
	# （外部在 start() 前改了 grow_dir 也能生效，例如水格每次结冰随机一个方向。）
	var mat := _visual.material as ShaderMaterial
	mat.set_shader_parameter("grow_dir", grow_dir)
	mat.set_shader_parameter("glow_strength", 1.0)
	_setup_particles()
	_particles.emitting = true

	# 如果之前的淡出还没跑完，先杀掉，并把强度拉回 1
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()

func _process(delta: float) -> void:
	if not _growing:
		return

	_progress = minf(_progress + delta / grow_duration, 1.0)
	(_visual.material as ShaderMaterial).set_shader_parameter("progress", _progress)

	_move_emitter_to_edge()

	if _progress >= 1.0:
		_growing = false
		_particles.emitting = false
		_fade_out_glow()

# 新增：把边缘光平滑淡出
func _fade_out_glow() -> void:
	var mat := _visual.material as ShaderMaterial
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_method(
		func(v: float): mat.set_shader_parameter("glow_strength", v),
		1.0, 0.0, glow_fade_time
	)

func _move_emitter_to_edge() -> void:
	var half := _size * 0.5
	var local_edge := _center

	if grow_dir == Vector2.RIGHT:
		local_edge.x = _center.x - half.x + _size.x * _progress
	elif grow_dir == Vector2.LEFT:
		local_edge.x = _center.x + half.x - _size.x * _progress
	elif grow_dir == Vector2.DOWN:
		local_edge.y = _center.y - half.y + _size.y * _progress
	else:
		local_edge.y = _center.y + half.y - _size.y * _progress

	_particles.global_position = _visual.global_transform * local_edge
