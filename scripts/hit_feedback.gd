extends Node
## 只影响视觉和手柄；不暂停时间、不修改角色位置或碰撞。
var _animation: Tween
var _camera: Camera2D
var _camera_origin := Vector2.ZERO
var _sprite: CanvasItem
var _sprite_origin := Color.WHITE

func play(visual: CanvasItem, pixels: float, vibrate: bool) -> void:
	_restore()
	_sprite = visual
	_sprite_origin = visual.self_modulate
	_camera = get_viewport().get_camera_2d()
	if _camera != null: _camera_origin = _camera.offset
	_animation = create_tween()
	_animation.tween_method(func(t: float):
		if is_instance_valid(_sprite):
			var flash := 0.65 * maxf(0.0, 1.0 - t * 3.0)
			_sprite.self_modulate = _sprite_origin.lerp(Color(1.8, 1.8, 1.8, _sprite_origin.a), flash)
		if is_instance_valid(_camera) and pixels > 0.0:
			var wobble := Vector2(sin(t * TAU * 3.0), sin(t * TAU * 4.0) * 0.55)
			_camera.offset = _camera_origin + wobble * pixels * (1.0 - t) / _camera.zoom
	, 0.0, 1.0, 0.22)
	_animation.tween_callback(_restore)
	if vibrate:
		for device in Input.get_connected_joypads():
			Input.start_joy_vibration(device, 0.15, 0.3, 0.14)

func _restore() -> void:
	if _animation != null and _animation.is_valid(): _animation.kill()
	if is_instance_valid(_camera): _camera.offset = _camera_origin
	if is_instance_valid(_sprite): _sprite.self_modulate = _sprite_origin

func _exit_tree() -> void:
	_restore()
