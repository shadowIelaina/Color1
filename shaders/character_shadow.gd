class_name CharacterShadow
extends Sprite2D

## 角色投影阴影：一个放在角色脚底、跟随动画帧的剪影节点。
## 挂到任意角色身上，指向它的 AnimatedSprite2D，就能自动镜像当前动画帧并投影到地面。
## 用法：
##   1. 在角色下新建 Sprite2D，命名为 Shadow，放在主 Sprite 之前（先画，压在下层）。
##   2. 挂本脚本，把 source_path 指向主 AnimatedSprite2D（留空则自动找同级第一个）。
##   3. 用节点自身的 position / scale / skew / rotation 摆出「压扁倾斜」的地面投影。

const SHADER := preload("res://shaders/character_shadow.gdshader")

## 提供动画帧的主角色精灵。留空则自动找同级第一个 AnimatedSprite2D。
@export var source_path: NodePath

@export_group("Shadow")
## 阴影颜色（黑色半透明）。
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.45)
## 软边模糊半径（帧像素）。0 = 硬边剪影。
@export_range(0.0, 8.0, 0.25) var softness := 1.0
## 跳起时阴影收缩幅度（每「帧像素」腾空高度）。0 = 不收缩。
## 注意：_update_lift 里 lift 取自 _source.offset.y 的差值，是帧像素（jump_height=12），
## 不会被 sprite.scale(=pixel_scale) 放大，所以这里保持帧像素单位，别跟着 16→256 迁移 ×/÷。
@export_range(0.0, 0.1, 0.001) var jump_scale_falloff := 0.03
## 跳起时阴影变淡幅度（每「帧像素」腾空高度）。0 = 不变淡。
@export_range(0.0, 0.1, 0.001) var jump_alpha_falloff := 0.02

var _source: AnimatedSprite2D
var _mat: ShaderMaterial
var _rest_scale := Vector2.ONE
var _ground_offset_y := -INF


func _ready() -> void:
	_source = _resolve_source()
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rest_scale = scale

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("shadow_color", shadow_color)
	_mat.set_shader_parameter("softness", softness)
	material = _mat


func _process(_delta: float) -> void:
	if _source == null:
		return
	var frames := _source.sprite_frames
	var anim := _source.animation
	if frames == null or anim == &"" or not frames.has_animation(anim):
		return

	var frame: int = _source.frame
	var tex: Texture2D = frames.get_frame_texture(anim, frame)
	texture = tex
	flip_h = _source.flip_h
	flip_v = _source.flip_v

	_update_region(tex)
	_update_lift()


func _resolve_source() -> AnimatedSprite2D:
	if not source_path.is_empty():
		var n := get_node_or_null(source_path)
		if n is AnimatedSprite2D:
			return n
	for sibling in get_parent().get_children():
		if sibling is AnimatedSprite2D and sibling != self:
			return sibling
	return null


## 把当前帧在图集里的区域写进 shader，保证软边采样不越界串到相邻帧。
func _update_region(tex: Texture2D) -> void:
	if tex is AtlasTexture and (tex as AtlasTexture).atlas != null:
		var at := tex as AtlasTexture
		var atlas_size := Vector2(at.atlas.get_size())
		if atlas_size.x > 0.0 and atlas_size.y > 0.0:
			_mat.set_shader_parameter("region_min", at.region.position / atlas_size)
			_mat.set_shader_parameter("region_size", at.region.size / atlas_size)
			return
	_mat.set_shader_parameter("region_min", Vector2.ZERO)
	_mat.set_shader_parameter("region_size", Vector2.ONE)


## 跳起时（源精灵 offset 上移）让阴影收缩、变淡，模拟离地。
func _update_lift() -> void:
	_ground_offset_y = maxf(_ground_offset_y, _source.offset.y)
	var lift := clampf(_ground_offset_y - _source.offset.y, 0.0, 999.0)
	if lift <= 0.0:
		scale = _rest_scale
		_mat.set_shader_parameter("shadow_color", shadow_color)
		return
	var s := 1.0 / (1.0 + lift * jump_scale_falloff)
	scale = _rest_scale * s
	var a := clampf(shadow_color.a * (1.0 - lift * jump_alpha_falloff), 0.0, 1.0)
	_mat.set_shader_parameter("shadow_color", Color(shadow_color.r, shadow_color.g, shadow_color.b, a))
