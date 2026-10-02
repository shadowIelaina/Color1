class_name Player
extends CharacterBody2D

## 角色控制器：2D 场景下的 2.5D 俯视（3/4）角色。
## 白盒阶段只做移动、朝向和动画状态机，不包含碰撞玩法逻辑。

enum State {
	IDLE,
	WALK,
	RUN,
	JUMP,
	ROTATE,
}

const STATE_NAMES: Array[String] = ["idle", "walk", "run", "jump", "rotate"]

@export_group("Movement")
@export_range(0.0, 2000.0, 1.0) var walk_speed := 120.0
@export_range(0.0, 3000.0, 1.0) var run_speed := 220.0

@export_group("Jump")
@export_range(0.0, 200.0, 1.0) var jump_height := 12.0
@export_range(0.05, 2.0, 0.05) var jump_duration := 0.45

@export_group("Rotate")
@export_range(0.05, 2.0, 0.05) var rotate_duration := 0.5

@export_group("Visual")
@export_range(1.0, 8.0, 0.5) var pixel_scale := 4.0
@export var animation_frames: SpriteFrames

const FOOTPRINT_RADIUS := 4.0

## 8 方向（屏幕坐标，y 向下），顺时针：下、左下、左、左上、上、右上、右、右下。
const DIRS: Array[Vector2] = [
	Vector2(0, 1),
	Vector2(-0.7071068, 0.7071068),
	Vector2(-1, 0),
	Vector2(-0.7071068, -0.7071068),
	Vector2(0, -1),
	Vector2(0.7071068, -0.7071068),
	Vector2(1, 0),
	Vector2(0.7071068, 0.7071068),
]

## 素材里实际画出来的 5 个方向（从上到下 5 行）：
## 下、右下、右、右上、上。左侧方向通过 flip_h 镜像得到。
const DIR_NAMES: Array[String] = ["down", "down_right", "right", "up_right", "up"]

## 8 方向索引 -> 素材 5 行索引。
const DIR_DRAW: Array[int] = [0, 1, 2, 3, 4, 3, 2, 1]

## 8 方向索引 -> 是否需要水平镜像。
const DIR_FLIP: Array[bool] = [false, true, true, true, false, false, false, false]

var state: int = State.IDLE
var facing: int = 0

var _jump_t := 1.0
var _rotate_t := 0.0
var _base_sprite_offset := Vector2(0, -8)

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var collision: CollisionShape2D = $Collision


func _ready() -> void:
	_register_input_actions()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(pixel_scale, pixel_scale)
	var shape := collision.shape as CircleShape2D
	if shape:
		shape.radius = FOOTPRINT_RADIUS * pixel_scale
	sprite.sprite_frames = animation_frames if animation_frames != null else _build_sprite_frames()
	sprite.offset = _base_sprite_offset
	_apply_animation()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running := Input.is_action_pressed("run")

	if state == State.ROTATE:
		velocity = Vector2.ZERO
		_rotate_t += delta
		if _rotate_t >= rotate_duration:
			state = State.IDLE
			sprite.offset = _base_sprite_offset
			_apply_animation()
		move_and_slide()
		return

	if state == State.JUMP:
		_jump_t += delta / jump_duration
		velocity = input * (run_speed if running else walk_speed)
		if input != Vector2.ZERO:
			facing = _dir_from_input(input)
		if _jump_t >= 1.0:
			_jump_t = 1.0
			state = State.IDLE
		_update_hop_visual()
		_apply_animation()
		move_and_slide()
		return

	if Input.is_action_just_pressed("rotate"):
		_start_rotate()
		return

	if Input.is_action_just_pressed("jump"):
		_start_jump()
		return

	if input != Vector2.ZERO:
		var speed := run_speed if running else walk_speed
		velocity = input * speed
		facing = _dir_from_input(input)
		state = State.RUN if running else State.WALK
	else:
		velocity = Vector2.ZERO
		state = State.IDLE

	sprite.offset = _base_sprite_offset
	_apply_animation()
	move_and_slide()


func _start_jump() -> void:
	state = State.JUMP
	_jump_t = 0.0
	_apply_animation()


func _start_rotate() -> void:
	state = State.ROTATE
	_rotate_t = 0.0
	velocity = Vector2.ZERO
	_apply_animation()


func _update_hop_visual() -> void:
	var height := sin(_jump_t * PI) * jump_height
	sprite.offset = Vector2(_base_sprite_offset.x, _base_sprite_offset.y - height)


func _apply_animation() -> void:
	if state == State.ROTATE:
		sprite.play("rotate")
		sprite.flip_h = false
		return
	var drawn := DIR_DRAW[facing]
	var anim := "%s_%s" % [STATE_NAMES[state], DIR_NAMES[drawn]]
	sprite.play(anim)
	sprite.flip_h = DIR_FLIP[facing]


func _dir_from_input(v: Vector2) -> int:
	var n := v.normalized()
	var best := 0
	var best_dot := -2.0
	for i in range(DIRS.size()):
		var d := n.dot(DIRS[i])
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _build_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()

	_add_sheet(sf, "idle", preload("res://art/player/16x16/16x16 Idle-Sheet.png"), 4, 24, 6.0)
	_add_sheet(sf, "walk", preload("res://art/player/16x16/16x16 Walk-Sheet.png"), 4, 24, 8.0)
	_add_sheet(sf, "run", preload("res://art/player/16x16/16x16 Run-Sheet.png"), 6, 24, 12.0)
	_add_sheet(sf, "jump", preload("res://art/player/16x16/16x16 Jump-Sheet.png"), 5, 22, 12.0)

	sf.add_animation("rotate")
	sf.set_animation_speed("rotate", 16.0)
	sf.set_animation_loop("rotate", false)
	var rotate_tex: Texture2D = preload("res://art/player/16x16/16x16 Rotate-Sheet.png")
	for c in range(8):
		var at := AtlasTexture.new()
		at.atlas = rotate_tex
		at.region = Rect2(c * 24, 0, 24, 24)
		sf.add_frame("rotate", at)

	return sf


func _add_sheet(sf: SpriteFrames, state_name: String, tex: Texture2D, cols: int, frame_h: int, fps: float) -> void:
	for d in range(DIR_NAMES.size()):
		var anim := "%s_%s" % [state_name, DIR_NAMES[d]]
		sf.add_animation(anim)
		sf.set_animation_speed(anim, fps)
		sf.set_animation_loop(anim, true)
		for c in range(cols):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(c * 24, d * frame_h, 24, frame_h)
			sf.add_frame(anim, at)


func _register_input_actions() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("run", [KEY_SHIFT])
	_add_action("jump", [KEY_SPACE])
	_add_action("rotate", [KEY_E])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
