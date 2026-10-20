class_name BossFreezeOrb
extends ParryProjectile
## Boss 冰冻弹：复用 ParryProjectile 的飞行 / 弹反 / 阵营契约，命中时改为「冻结玩家」而非扣血。
## 命中目标若实现 freeze(duration) 则冻结，否则退化为普通伤害。

@export var freeze_duration := 3.0


func _resolve_hit(collider: Node) -> void:
	if collider == null:
		return
	if collider.is_in_group(source_group):
		return   # 同阵营：不生效
	if _parried and collider.has_method("take_reflected_damage"):
		collider.call("take_reflected_damage")
		hit.emit(collider)
	elif collider.has_method("freeze"):
		collider.call("freeze", freeze_duration)
		hit.emit(collider)
	elif collider.has_method("take_damage"):
		collider.call("take_damage", damage)
		hit.emit(collider)
	if collider.has_method("knockback"):
		collider.call("knockback", direction, knockback_strength)


## 被弹反后除了本体变金，拖尾也一起变金，避免蓝金混色。
func _on_parried_visual() -> void:
	super()
	if visual == null:
		return
	var gold := Color(1.0, 0.9, 0.35, 1.0)
	for child in visual.get_children():
		if child is Line2D:
			(child as Line2D).self_modulate = gold
