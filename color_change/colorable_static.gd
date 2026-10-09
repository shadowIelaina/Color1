class_name ColorableStatic
extends ColorableBase
## 可上色静态体（带 "Visual" Sprite2D 贴图，如树/木条）：colorable_sprite 的「带碰撞」版本。
## 被赋予红则燃烧蔓延、烧尽后 Visual 碎裂并整体销毁（含碰撞）；赋予蓝则冻结。
## 上色/状态视觉反馈交给 ElementBehavior 的 VFX（火焰/冰霜）+ 烧尽碎裂，本脚本不接管贴图材质。

@onready var visual: Sprite2D = $Visual


## 注入视觉中心与碎裂目标：Visual 贴图中心在根原点上方（position 即偏移），碎裂就碎这张贴图。
func _configure_behavior(behavior: ElementBehavior) -> void:
	behavior.visual_center = visual.position
	behavior.shatter_target = visual


func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))
