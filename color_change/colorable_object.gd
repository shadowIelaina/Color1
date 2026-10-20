extends ColorableBase
## 可上色物体（反射箱 ReflectBox）：初始为岩石原色，被赋予颜色后从中心向外扫一圈
## 附魔着色（Inside 系列 shader）并常驻发光。红×绿=黄开启子弹反射、蓝×绿=青可被推动，
## 这些混合/反射行为由 ElementBehavior 统一驱动，本脚本只接管贴图着色。

## 附魔着色器：给红/绿/蓝/青/黄后给岩石贴图换一层对应 Inside shader（中心扩散 + 轮廓辉光）。
const RedEnchant := preload("res://shaders/Red_Inside.gdshader")
const GreenEnchant := preload("res://shaders/GreenInside.gdshader")
const BlueEnchant := preload("res://shaders/BlueInside.gdshader")
const CyanEnchant := preload("res://shaders/CyanInside.gdshader")
const YellowEnchant := preload("res://shaders/yellowinside.gdshader")

## 附魔扩散扫过一遍的速度（shader 内 enchant_speed，越大扫得越快）。
@export var enchant_speed := 0.8

@onready var visual: Sprite2D = $Sprite2D

var _enchant_mat: ShaderMaterial
var _enchant_tween: Tween


func _ready() -> void:
	super._ready()


## 注入视觉中心与碎裂目标：岩石贴图中心在根原点上方，燃烧光斑 / 碎裂都以它为准。
func _configure_behavior(behavior: ElementBehavior) -> void:
	behavior.visual_center = visual.position
	behavior.shatter_target = visual


## 点击命中：世界坐标点是否落在岩石贴图矩形内。
func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))


## 上色视觉：按当前元素选对应 Inside shader，中心向外扫一圈后常驻；无元素则还原。
func _apply_visual(_c: Color, _origin: Vector2) -> void:
	var el := _behavior.current_element() if _behavior != null else ""
	var shader := _shader_for_element(el)
	if shader == null:
		_hide_enchant()
	else:
		_play_enchant(shader)


## 抽走颜色 / 进入空态时还原成岩石原色。
func _reset_visual() -> void:
	_hide_enchant()


## 开局预置颜色时直接以终态常驻（不重播扩散动画）。
func _apply_seed_visual(cfg: Dictionary) -> void:
	var el := Rules.element_for_color_name(cfg.get("color_name", ""))
	var shader := _shader_for_element(el)
	if shader == null:
		return
	_enchant_mat = ShaderMaterial.new()
	_enchant_mat.shader = shader
	_enchant_mat.set_shader_parameter("enchant_progress", 1.0)
	visual.material = _enchant_mat


func _shader_for_element(el: String) -> Shader:
	match el:
		"burn":
			return RedEnchant
		"freeze":
			return BlueEnchant
		"grow":
			return GreenEnchant
		"cyan":
			return CyanEnchant
		"yellow":
			return YellowEnchant
	return null


## 附魔：给岩石贴图换一层对应 Inside shader，中心向外扫一圈后常驻。
func _play_enchant(shader: Shader) -> void:
	if _enchant_tween and _enchant_tween.is_valid():
		_enchant_tween.kill()
	_enchant_mat = ShaderMaterial.new()
	_enchant_mat.shader = shader
	_enchant_mat.set_shader_parameter("enchant_progress", 0.0)
	_enchant_mat.set_shader_parameter("enchant_speed", enchant_speed)
	visual.material = _enchant_mat
	var duration := 1.0 / float(enchant_speed)
	_enchant_tween = create_tween()
	_enchant_tween.tween_method(_set_enchant_progress, 0.0, 1.0, duration)


func _set_enchant_progress(v: float) -> void:
	if _enchant_mat != null:
		_enchant_mat.set_shader_parameter("enchant_progress", v)


## 还原：打断扩散并清掉贴图 shader，岩石回到原色。
func _hide_enchant() -> void:
	if _enchant_tween and _enchant_tween.is_valid():
		_enchant_tween.kill()
		_enchant_tween = null
	if visual != null and is_instance_valid(visual):
		visual.material = null
