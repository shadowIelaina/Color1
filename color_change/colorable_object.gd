extends ColorableBase
## 可上色物体（箱子）：初始为白色，被赋予颜色后，颜色从赋予源一侧扩散直到填满整个物体。
## 视觉：Front/Top 两个 Polygon2D 各挂一个 fill shader，做「从一侧扩散填满」的动画。

const FILL_SHADER := preload("res://shaders/color_fill.gdshader")

@export var fill_duration := 0.5
@export var fill_softness := 224.0

@onready var front: Polygon2D = $Front
@onready var top_face: Polygon2D = $Top

var _front_mat: ShaderMaterial
var _top_mat: ShaderMaterial
var _tween: Tween
var _front_current: Color
var _top_current: Color
var _front_initial: Color
var _top_initial: Color


func _ready() -> void:
	_front_current = front.color
	_top_current = top_face.color
	_front_initial = front.color
	_top_initial = top_face.color
	_front_mat = _make_material(_front_current)
	_top_mat = _make_material(_top_current)
	front.material = _front_mat
	top_face.material = _top_mat
	super._ready()


func _make_material(base: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FILL_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("fill_color", base)
	m.set_shader_parameter("fill_origin", Vector2.ZERO)
	m.set_shader_parameter("fill_front", -1.0)
	m.set_shader_parameter("fill_softness", fill_softness)
	return m


## 点击命中：世界坐标点是否落在 Front 或 Top 多边形内。
func contains_point(world_pos: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(front.to_local(world_pos), front.polygon):
		return true
	return Geometry2D.is_point_in_polygon(top_face.to_local(world_pos), top_face.polygon)


func _apply_visual(c: Color, origin: Vector2) -> void:
	_start_fill(c, origin)


func _reset_visual() -> void:
	_front_current = _front_initial
	_top_current = _top_initial
	_front_mat.set_shader_parameter("base_color", _front_initial)
	_front_mat.set_shader_parameter("fill_color", _front_initial)
	_top_mat.set_shader_parameter("base_color", _top_initial)
	_top_mat.set_shader_parameter("fill_color", _top_initial)
	_front_mat.set_shader_parameter("fill_front", -1.0)
	_top_mat.set_shader_parameter("fill_front", -1.0)


func _apply_seed_visual(cfg: Dictionary) -> void:
	_front_current = cfg["color"]
	_top_current = cfg["color"].lightened(0.18)
	_front_mat.set_shader_parameter("base_color", _front_current)
	_front_mat.set_shader_parameter("fill_color", _front_current)
	_top_mat.set_shader_parameter("base_color", _top_current)
	_top_mat.set_shader_parameter("fill_color", _top_current)


func _start_fill(c: Color, origin: Vector2) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var top_target := c.lightened(0.18)
	var near_far := _compute_near_far(origin)

	_front_mat.set_shader_parameter("base_color", _front_current)
	_front_mat.set_shader_parameter("fill_color", c)
	_top_mat.set_shader_parameter("base_color", _top_current)
	_top_mat.set_shader_parameter("fill_color", top_target)
	_front_mat.set_shader_parameter("fill_origin", origin)
	_top_mat.set_shader_parameter("fill_origin", origin)

	# 从最近边缘（近侧已 0）扩散到最远边缘（远侧已满）。
	var start := near_far.x - fill_softness
	var end := near_far.y + fill_softness
	_tween = create_tween()
	_tween.tween_method(_set_fill_front, start, end, fill_duration)
	_tween.tween_callback(_finish_fill.bind(c, top_target))


func _set_fill_front(v: float) -> void:
	_front_mat.set_shader_parameter("fill_front", v)
	_top_mat.set_shader_parameter("fill_front", v)


func _finish_fill(c: Color, top_target: Color) -> void:
	_front_current = c
	_top_current = top_target
	_front_mat.set_shader_parameter("base_color", c)
	_top_mat.set_shader_parameter("base_color", top_target)


func _compute_near_far(origin: Vector2) -> Vector2:
	var near := INF
	var far := -INF
	for poly in [front, top_face]:
		for v in poly.polygon:
			var d := origin.distance_to(poly.to_global(v))
			near = min(near, d)
			far = max(far, d)
	return Vector2(near, far)
