class_name ColorableStatic
extends ColorableBase
## 可上色静态体（带 "Visual" Sprite2D 贴图，如树/木条）：colorable_sprite 的「带碰撞」版本。
## 被赋予红则燃烧蔓延、烧尽后 Visual 碎裂并整体销毁（含碰撞）；赋予蓝则冻结。
## 上色/状态视觉反馈交给 ElementBehavior 的 VFX（火焰/冰霜）+ 烧尽碎裂，本脚本不接管贴图材质。
## 例外：勾选 burn_down 的物体（枯木等燃料），给红后由本脚本驱动 Visual 材质溶解烧毁。

@onready var visual: Sprite2D = $Visual

## 绿生长粒子（green_grow_tree.tscn）：被赋予绿时在视觉中心喷发一撮绿叶（藤桥同款·加大粒子量）。
const GrowFx := preload("res://shaders/green_grow_tree.tscn")

## 附魔着色器：给绿/红后在树体上叠一层，中心向外扩散一圈后常驻。
const GreenEnchant := preload("res://shaders/GreenInside.gdshader")
const RedEnchant := preload("res://shaders/Red_Inside.gdshader")
const BlueEnchant := preload("res://shaders/BlueInside.gdshader")
const CyanEnchant := preload("res://shaders/CyanInside.gdshader")
const YellowEnchant := preload("res://shaders/yellowinside.gdshader")

## 烧毁模式：给红后 Visual 溶解烧尽并整体销毁（枯木等燃料）。默认关，普通树/木条不受影响。
@export var burn_down := false
## 烧毁溶解时长（秒，默认 2）。
@export var burn_duration := 2.0

var _burn_tween: Tween
var _burning_away := false
var _enchant_overlay: Sprite2D
var _enchant_mat: ShaderMaterial
var _enchant_tween: Tween


func _ready() -> void:
	super._ready()
	if _behavior == null:
		return
	# 开局预置红色（initial_color_name = "红"）时同样烧毁。
	if burn_down and _behavior.current_element() == "burn":
		_start_burn_down()


## 注入视觉中心与碎裂目标：Visual 贴图中心在根原点上方（position 即偏移），碎裂就碎这张贴图。
func _configure_behavior(behavior: ElementBehavior) -> void:
	behavior.visual_center = visual.position
	behavior.shatter_target = visual
	# 溶解烧毁燃料用溶解 shader 表现燃烧，不叠加火焰粒子 VFX。
	behavior.play_burn_vfx = not burn_down


func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))


## 给绿（grow）时喷发一撮绿叶；给红（burn）时启动烧毁溶解；
## 变黄（红×绿）时取消烧毁，让燃料停在黄色态反射子弹。
func _apply_visual(_c: Color, _origin: Vector2) -> void:
	if _behavior == null:
		return
	var el := _behavior.current_element()
	if el == "grow":
		_play_grow_fx()
		_play_enchant(GreenEnchant)
	elif el == "burn" and not burn_down:
		_play_enchant(RedEnchant)
	elif el == "freeze":
		_play_enchant(BlueEnchant)
	elif el == "cyan":
		_play_enchant(CyanEnchant)
	elif el == "yellow":
		_play_enchant(YellowEnchant)
	else:
		_hide_enchant()
	if not burn_down:
		return
	if el == "burn":
		_start_burn_down()
	elif el == "yellow":
		_cancel_burn_down()


## 挂载绿生长粒子（green_grow.tscn）作一次性喷发：绿叶在视觉中心炸开，喷完自动销毁。
func _play_grow_fx() -> void:
	var fx := GrowFx.instantiate()
	fx.name = "GrowFx"
	add_child(fx)
	fx.position = visual.position
	var particles := fx.get_node_or_null("TipParticles") as CPUParticles2D
	if particles != null:
		particles.one_shot = true
		particles.emitting = true
	# 粒子寿命 0.5s，留足余量后销毁节点。
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(fx):
			fx.queue_free()
	)


## 附魔覆盖层：给绿/红时叠一层对应着色器，中心向外扫一圈后常驻。
func _play_enchant(shader: Shader) -> void:
	_ensure_enchant_overlay()
	_enchant_overlay.visible = true
	if _enchant_tween and _enchant_tween.is_valid():
		_enchant_tween.kill()
	_enchant_mat = ShaderMaterial.new()
	_enchant_mat.shader = shader
	_enchant_mat.set_shader_parameter("enchant_progress", 0.0)
	_enchant_mat.set_shader_parameter("enchant_speed", 0.8)
	_enchant_overlay.material = _enchant_mat
	var duration := 1.0 / float(_enchant_mat.get_shader_parameter("enchant_speed"))
	_enchant_tween = create_tween()
	_enchant_tween.tween_method(_set_enchant_progress, 0.0, 1.0, duration)


func _set_enchant_progress(v: float) -> void:
	if _enchant_mat != null:
		_enchant_mat.set_shader_parameter("enchant_progress", v)


## 懒建覆盖层：复制 Visual（贴图/缩放/偏移完全对齐），插到 Visual 之后（粒子仍画在其上）。
func _ensure_enchant_overlay() -> void:
	if _enchant_overlay != null and is_instance_valid(_enchant_overlay):
		return
	if visual == null:
		return
	_enchant_overlay = visual.duplicate() as Sprite2D
	_enchant_overlay.name = "EnchantOverlay"
	visual.add_sibling(_enchant_overlay)


## 抽走颜色 / 进入混合态时收起附魔（树体还原）。
func _hide_enchant() -> void:
	if _enchant_tween and _enchant_tween.is_valid():
		_enchant_tween.kill()
		_enchant_tween = null
	if _enchant_overlay != null and is_instance_valid(_enchant_overlay):
		_enchant_overlay.visible = false


## 开局预置颜色时直接以终态常驻（不重播扩散动画）。
func _apply_seed_visual(cfg: Dictionary) -> void:
	var color_name: String = cfg.get("color_name", "")
	var shader: Shader = null
	if color_name == "绿":
		shader = GreenEnchant
	elif color_name == "红" and not burn_down:
		shader = RedEnchant
	elif color_name == "蓝":
		shader = BlueEnchant
	elif color_name == "青":
		shader = CyanEnchant
	elif color_name == "黄":
		shader = YellowEnchant
	if shader == null:
		return
	_ensure_enchant_overlay()
	_enchant_overlay.visible = true
	_enchant_mat = ShaderMaterial.new()
	_enchant_mat.shader = shader
	_enchant_mat.set_shader_parameter("enchant_progress", 1.0)
	_enchant_overlay.material = _enchant_mat


## 吸收颜色（熄灭）时打断烧毁，恢复完整树体。
func _reset_visual() -> void:
	_cancel_burn_down()
	_hide_enchant()


func _start_burn_down() -> void:
	if _burning_away or not (visual.material is ShaderMaterial):
		return
	_burning_away = true
	# 树正在烧没，先移除碰撞，让玩家可通行。
	if has_node("CollisionShape2D"):
		($CollisionShape2D as CollisionShape2D).set_deferred("disabled", true)
	# 复制材质，避免共享 ShaderMaterial 互相影响。
	visual.material = (visual.material as ShaderMaterial).duplicate() as ShaderMaterial
	# 溶解 0 → 1，烧尽后整体销毁（含行为组件/光/火）。
	_burn_tween = create_tween()
	_burn_tween.tween_property(visual.material, "shader_parameter/dissolve", 1.0, burn_duration)
	_burn_tween.tween_callback(queue_free)


func _cancel_burn_down() -> void:
	if not _burning_away:
		return
	_burning_away = false
	if _burn_tween and _burn_tween.is_valid():
		_burn_tween.kill()
	_burn_tween = null
	if visual.material is ShaderMaterial:
		(visual.material as ShaderMaterial).set_shader_parameter("dissolve", 0.0)
	if has_node("CollisionShape2D"):
		($CollisionShape2D as CollisionShape2D).set_deferred("disabled", false)
