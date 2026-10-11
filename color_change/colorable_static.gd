class_name ColorableStatic
extends ColorableBase
## 可上色静态体（带 "Visual" Sprite2D 贴图，如树/木条）：colorable_sprite 的「带碰撞」版本。
## 被赋予红则燃烧蔓延、烧尽后 Visual 碎裂并整体销毁（含碰撞）；赋予蓝则冻结。
## 上色反馈：ElementBehavior 的 VFX（火焰/冰霜）+ 本脚本用 visual.self_modulate 做持续着色（红=持续红、蓝=持续蓝）。

@onready var visual: Sprite2D = $Visual

## 初始 self_modulate（灰白）。用 self_modulate 而非 modulate，避免连累挂在 Visual 下的悬停描边。
var _initial_self_modulate := Color.WHITE
var _tween: Tween


## 注入视觉中心与碎裂目标：Visual 贴图中心在根原点上方（position 即偏移），碎裂就碎这张贴图。
func _configure_behavior(behavior: ElementBehavior) -> void:
	behavior.visual_center = visual.position
	behavior.shatter_target = visual
	# 记下初始 self_modulate（此刻在 _seed_initial_color 之前，还没被染色）。
	_initial_self_modulate = visual.self_modulate


func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))


## —— 视觉钩子：用 visual.self_modulate 做持续着色 ——

func _apply_visual(c: Color, _origin: Vector2) -> void:
	_tint(c)


func _reset_visual() -> void:
	_reset_tint()


func _apply_seed_visual(cfg: Dictionary) -> void:
	_tint(cfg["color"])


## 融化（自然解冻）时把颜色淡出回初始灰白（霜渐退）。
func fade_visual_out() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(visual, "self_modulate", _initial_self_modulate, 0.5)


func _tint(c: Color) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	visual.self_modulate = c


func _reset_tint() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	visual.self_modulate = _initial_self_modulate
