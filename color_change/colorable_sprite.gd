class_name ColorableSprite
extends Sprite2D
## 可上色物体（Sprite 版）：初始保持原色，被上色后颜色从靠近玩家的一侧扩散直到填满整个贴图。

const FILL_SHADER := preload("res://shaders/color_fill_texture.gdshader")
const Rules := preload("res://scripts/element/element_rules.gd")
const Behavior := preload("res://scripts/element/element_behavior.gd")

@export var fill_duration := 0.5
@export var fill_softness := 14.0
@export var initial_color_name := ""

var _mat: ShaderMaterial
var _tween: Tween
var _current_color: Color
var _initial_color: Color
var _behavior: Node2D


func _ready() -> void:
	_current_color = modulate
	_initial_color = modulate
	_mat = ShaderMaterial.new()
	_mat.shader = FILL_SHADER
	_mat.set_shader_parameter("base_color", _current_color)
	_mat.set_shader_parameter("fill_color", _current_color)
	_mat.set_shader_parameter("fill_origin", Vector2.ZERO)
	_mat.set_shader_parameter("fill_front", -1.0)
	_mat.set_shader_parameter("fill_softness", fill_softness)
	material = _mat
	# 颜色统一交给 shader 处理，避免 modulate 双重叠加。
	modulate = Color.WHITE
	_behavior = Behavior.new()
	_behavior.name = "ElementBehavior"
	add_child(_behavior)
	_seed_initial_color()


func apply_color(c: Color, color_name: String = "", from_pos: Vector2 = Vector2.INF) -> void:
	var origin := global_position if from_pos == Vector2.INF else from_pos
	_start_fill(c, origin)
	var element := Rules.element_for_color_name(color_name)
	if element != "":
		_behavior.call("apply", element)


func has_color() -> bool:
	return bool(_behavior.call("has_element"))


## 点击命中：世界坐标点是否落在贴图矩形内（get_rect + to_local 自动处理缩放/偏移）。
func contains_point(world_pos: Vector2) -> bool:
	return get_rect().has_point(to_local(world_pos))


## 抽走当前颜色/元素：返回颜色信息，并把物体还原成初始色。
func absorb_color() -> Dictionary:
	var el := str(_behavior.call("current_element"))
	_behavior.call("clear")
	_reset_visual()
	var cfg := Rules.config(el)
	return {
		"element": el,
		"color": cfg.get("color", Color.WHITE),
		"color_name": cfg.get("color_name", ""),
	}


func _reset_visual() -> void:
	_current_color = _initial_color
	_mat.set_shader_parameter("base_color", _initial_color)
	_mat.set_shader_parameter("fill_color", _initial_color)
	_mat.set_shader_parameter("fill_front", -1.0)


## 开局种子：若在编辑器中设了 initial_color_name，则物体直接以该颜色/元素起手。
func _seed_initial_color() -> void:
	var el := Rules.element_for_color_name(initial_color_name)
	if el == "":
		return
	var cfg := Rules.config(el)
	_current_color = cfg["color"]
	_mat.set_shader_parameter("base_color", cfg["color"])
	_mat.set_shader_parameter("fill_color", cfg["color"])
	_behavior.call("apply", el)


func _start_fill(c: Color, origin: Vector2) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var near_far := _compute_near_far(origin)

	_mat.set_shader_parameter("base_color", _current_color)
	_mat.set_shader_parameter("fill_color", c)
	_mat.set_shader_parameter("fill_origin", origin)

	var start := near_far.x - fill_softness
	var end := near_far.y + fill_softness
	_tween = create_tween()
	_tween.tween_method(_set_fill_front, start, end, fill_duration)
	_tween.tween_callback(_finish_fill.bind(c))


func _set_fill_front(v: float) -> void:
	_mat.set_shader_parameter("fill_front", v)


func _finish_fill(c: Color) -> void:
	_current_color = c
	_mat.set_shader_parameter("base_color", c)


func _compute_near_far(origin: Vector2) -> Vector2:
	var tex_size := Vector2.ZERO
	if texture != null:
		tex_size = texture.get_size()
	# 贴图在局部坐标中的包围矩形（含 centered / offset）。
	var rect_pos := offset - (tex_size * 0.5 if centered else Vector2.ZERO)
	var corners: Array[Vector2] = [
		rect_pos,
		rect_pos + Vector2(tex_size.x, 0.0),
		rect_pos + tex_size,
		rect_pos + Vector2(0.0, tex_size.y),
	]
	var near := INF
	var far := -INF
	for p in corners:
		var d := origin.distance_to(to_global(p))
		near = min(near, d)
		far = max(far, d)
	return Vector2(near, far)
