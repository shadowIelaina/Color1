class_name HeartPickup
extends ItemPickup
## 宝箱心之容器：拾取后增加最大生命，彩色贴图仅用于世界中的道具。

@export var display_name := "红心"
@export_range(1, 10, 1) var health_bonus := 1
var _collecting := false
var _float: Tween
var _rays_tween: Tween


func _ready() -> void:
	add_to_group("heart_pickup")
	# 直接摆在关卡里也使用位置路径区分，避免多个同名道具互相覆盖。
	if prop_id == "":
		prop_id = "heart:%s" % get_path()
	super._ready()
	preload("res://scripts/pickup_presentation.gd").register_item("prop", prop_id, display_name, _visual, inventory_icon)
	_pickup_area.set_deferred("monitoring", false)
	var rays := get_node_or_null("Visual/Rays") as Control
	if rays != null:
		rays.scale = Vector2(0.6, 0.6)
		_rays_tween = create_tween()
		_rays_tween.tween_property(rays, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_settle()


func _settle() -> void:
	await get_tree().create_timer(0.45).timeout
	if GameState.has_prop(prop_id):
		return
	_pickup_area.monitoring = true
	_float = create_tween().set_loops()
	_float.tween_property(_visual, "position:y", -14.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_float.tween_property(_visual, "position:y", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_body_entered(body: Node) -> void:
	if _collecting or not body is Player or GameState.has_prop(prop_id):
		return
	GameState.health_upgrade_names[prop_id] = display_name
	if not body.acquire_heart_container(prop_id, health_bonus):
		return
	_collecting = true
	_pickup_area.set_deferred("monitoring", false)
	if _float != null:
		_float.kill()
	preload("res://scripts/pickup_presentation.gd").announce("prop", prop_id, item_description if item_description != "" else "最大生命 +%d" % health_bonus)
	var start := _visual.global_position
	var original_scale := _visual.scale
	var tween := create_tween()
	tween.tween_property(_visual, "scale", original_scale * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(t: float):
		if is_instance_valid(body):
			_visual.global_position = start.lerp(body.global_position + Vector2(0, -80), t) + Vector2(0, -sin(t * PI) * 90)
	, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_visual, "scale", original_scale * 0.15, 0.45)
	tween.parallel().tween_property(_visual, "modulate:a", 0.0, 0.18).set_delay(0.27)
	tween.tween_callback(hide)
