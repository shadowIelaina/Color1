class_name Player
extends CharacterBody2D

## 变色玩法：换色时发出，供 HUD 更新显示。
signal color_changed(new_color: Color, color_name: String)
## 颜色库/选中变化时发出，供 HUD 显示整套调色盘与当前选中。
signal inventory_changed(inventory: Dictionary, selected_element: String)
## 血量变化（current / max）。HUD 据此刷新红心。
signal health_changed(health: int, max_health: int)
## 血量归零死亡（重生由 Player 自行处理，这里只广播，供音效/演出等监听）。
signal died

## 角色控制器：2D 场景下的 2.5D 俯视（3/4）角色。
## 白盒阶段只做移动、朝向和动画状态机，不包含碰撞玩法逻辑。

enum State {
	IDLE,
	WALK,
	RUN,
	JUMP,
	ROTATE,
}

@export_group("Movement")
@export_range(0.0, 20000.0, 1.0) var walk_speed := 1920.0
@export_range(0.0, 30000.0, 1.0) var run_speed := 3520.0

@export_group("Jump")
@export_range(0.0, 200.0, 1.0) var jump_height := 12.0
@export_range(0.05, 2.0, 0.05) var jump_duration := 0.45

@export_group("Rotate")
@export_range(0.05, 2.0, 0.05) var rotate_duration := 0.5

@export_group("Visual")
@export_range(0.01, 32.0, 0.001) var pixel_scale := 0.28
@export var animation_frames: SpriteFrames

@export_group("Interact")
@export_range(8.0, 4096.0, 1.0) var interact_range := 768.0

@export_group("Light")
## 玩家自带微光半径（世界像素，256px ≈ 1 格）。暗房里照亮自身周围；相机 zoom 0.25，太小在屏幕上根本看不见。
@export_range(8.0, 4096.0, 8.0) var light_radius := 384.0

@export_group("Water Flow")
## 水流推力（像素/秒）。流向由脚下浅水格子的流向标记决定（见 flow_marker_spawner.gd）。
@export_range(0.0, 2000.0, 1.0) var flow_strength := 600.0

@export_group("Health")
## 最大血量（红心数）。初始 1 颗心；后续可加「心之容器」提高上限。
@export_range(1, 20, 1) var max_health := 1

const FOOTPRINT_RADIUS := 64.0
const OUTLINE_SHADER := preload("res://shaders/outline_colorful.gdshader")
const Rules := preload("res://scripts/element/element_rules.gd")
const DepthSort := preload("res://scripts/depth_sort.gd")
## 水格碰撞层（water_cell.gd 里 collision_layer=2）。站在水里时临时忽略这层，让玩家能在水里走动。
const WATER_COLLISION_LAYER := 2
## 高清图脚底距画布中心的帧像素（1294×1626 画布，脚底 bbox 底≈1518，中心 813 → 705）。
const FEET_FRAME_OFFSET := 705.0
## 影子压扁比例（y = x × 这个）。原像素图 shadow scale (16, 7.2) → 0.45。
const SHADOW_FLATTEN := 0.45
## 受击后无敌时长（毫秒），防止机关连发瞬间秒杀。
const INVINCIBLE_MS := 1000

## 4 方向（屏幕坐标，y 向下）：下、左、上、右。
const DIRS: Array[Vector2] = [
	Vector2(0, 1),
	Vector2(-1, 0),
	Vector2(0, -1),
	Vector2(1, 0),
]

## 素材里实际画的 4 个方向。左右各有独立素材，不再用 flip_h 镜像。
const DIR_NAMES: Array[String] = ["down", "left", "up", "right"]

var state: int = State.IDLE
var facing: int = 0
## 当前选中元素对应的颜色/名称（供 HUD 与描边显示）。
var selected_color := Color.WHITE
var selected_color_name := "无"
## 颜色库：玩家持有的元素种子（元素 id -> 数量）。种子守恒：只能从世界色源吸收获得。
var _inventory: Dictionary = {}
## 当前选中、用于「赋予」的元素 id；空 = 未持有任何元素。
var _selected_element := ""

var _jump_t := 1.0
var _rotate_t := 0.0
## 贴图基准偏移（帧像素，会被 sprite.scale 一起缩放）。高清图本身已居中，置 0 即可。
var _base_sprite_offset := Vector2.ZERO
var _outline_material: ShaderMaterial
var _highlighted: Node = null
var _highlight_outline: Sprite2D = null
var _freeze_preview_water: Node = null   # 当前显示冻结预览的水格
var _freeze_preview_on := false          # 预览当前是否开启（含「手里是蓝」这一条件）
var _base_collision_mask := 0    # 场景里配好的碰撞掩码（含水层）
var _in_water := false           # 是否正站在水里（不可站水格）→ 临时忽略水层碰撞以便踩水
var _knockback_vel := Vector2.ZERO   # 被飞行物命中时的击退速度（逐帧衰减）
var health := 1
var _invincible_until := 0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var collision: CollisionShape2D = $Collision
@onready var shadow: CharacterShadow = $Shadow


func _ready() -> void:
	add_to_group("player")
	health = max_health
	_base_collision_mask = collision_mask
	_register_input_actions()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(pixel_scale, pixel_scale)
	# 脚底对齐玩家原点：画布居中，脚底在中心下方 FEET_FRAME_OFFSET 帧像素。
	sprite.position.y = -FEET_FRAME_OFFSET * pixel_scale
	# 影子跟随玩家尺寸（宽同玩家、高按比例压扁），只改 pixel_scale 就整体联动。
	shadow.set_rest_scale(Vector2(pixel_scale, pixel_scale * SHADOW_FLATTEN))
	var shape := collision.shape as CircleShape2D
	if shape:
		shape.radius = FOOTPRINT_RADIUS * pixel_scale
	sprite.sprite_frames = animation_frames if animation_frames != null else _build_sprite_frames()
	sprite.offset = _base_sprite_offset
	_apply_animation()
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_select_element("")  # 初始化 HUD + 描边 + 首次信号
	_setup_light()


## 玩家自带微光：黑暗房间里照亮自身周围（遮罩挖洞；亮房里遮罩全透明，无影响）。
func _setup_light() -> void:
	var l := LightSource.new()
	l.radius = light_radius
	add_child(l)


func _physics_process(delta: float) -> void:
	_handle_color_input()
	_update_highlight()
	_update_water_preview()
	_update_water_wade()
	_knockback_vel = _knockback_vel.move_toward(Vector2.ZERO, 2500.0 * delta)
	# 水流推力：脚下浅水格的流向标记（HeightMap）非 0 时被冲走；结冰那格不推。
	var flow_vel := Vector2.ZERO
	var flow_dir := HeightMap.flow_at(global_position)
	if flow_dir != 0 and not _on_frozen_ice():
		flow_vel = _flow_vector(flow_dir) * flow_strength
	# 深度排序：按脚底世界 Y 更新 z_index，让玩家被南侧的树/岩石正确遮挡。
	z_index = DepthSort.z_for(global_position.y)

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
		velocity += _knockback_vel
		velocity += flow_vel
		move_and_slide()
		_push_boxes(input, delta)
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
	velocity += _knockback_vel
	velocity += flow_vel
	move_and_slide()
	_push_boxes(input, delta)


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


## 被飞行物命中：沿 dir 方向给一个短促击退（velocity 逐帧衰减，见 _physics_process 顶部）。
func knockback(dir: Vector2, strength := 700.0) -> void:
	_knockback_vel = dir.normalized() * strength


## 流向编号 → 方向向量（屏幕坐标）。1=右 2=下 3=左 4=上，其它=无。
func _flow_vector(dir: int) -> Vector2:
	match dir:
		1:
			return Vector2.RIGHT
		2:
			return Vector2.DOWN
		3:
			return Vector2.LEFT
		4:
			return Vector2.UP
		_:
			return Vector2.ZERO


## 脚下那格是不是已结冰的浅水（WaterCell.is_frozen()）。结冰后水流不推人。
func _on_frozen_ice() -> bool:
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("is_frozen") or not obj.has_method("contains_point"):
			continue
		if not bool(obj.call("is_frozen")):
			continue
		if bool(obj.call("contains_point", global_position)):
			return true
	return false


## 受伤：扣血并广播 health_changed。受击后有短暂无敌，防止机关连发瞬间秒杀。
func take_damage(amount := 1) -> void:
	if amount <= 0:
		return
	if Time.get_ticks_msec() < _invincible_until:
		return
	_invincible_until = Time.get_ticks_msec() + INVINCIBLE_MS
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()


## 死亡：广播 died，然后回出生点重生（满血 + 短暂无敌）。
func _die() -> void:
	died.emit()
	_respawn()


## 重生：回到当前房间出生点，恢复满血并给略长一点的无敌时间。
func _respawn() -> void:
	health = max_health
	velocity = Vector2.ZERO
	_knockback_vel = Vector2.ZERO
	global_position = _spawn_position()
	_invincible_until = Time.get_ticks_msec() + INVINCIBLE_MS * 2
	health_changed.emit(health, max_health)


## 出生点：当前房间的 "spawn" 入口位置（约定每个房间都有 entrance_id=spawn）。
func _spawn_position() -> Vector2:
	var room := GameState.current_room as Room
	if room == null:
		return global_position  # 兜底：不知道出生点就原地满血复活
	return room.get_entrance_position("spawn")


## 供 HUD 在连接信号前读取当前血量快照。
func health_snapshot() -> Dictionary:
	return {"health": health, "max_health": max_health}


## 站在水里（不可站水格）时，临时忽略水层碰撞，让玩家能在水里走动（踩水）；
## 爬回岸/冰（可站）后恢复碰撞。这样「掉进水里」后能挪动，而不是被困在一格里。
func _update_water_wade() -> void:
	# 用碰撞盒中心采样，而不是玩家节点原点。玩家碰撞盒相对原点有偏移，
	# 否则从不同方向进入水格时，进水/出水判定会不一致，导致卡死。
	var sample_pos := global_position + collision.position
	var in_water := not HeightMap.is_walkable(sample_pos)
	if in_water == _in_water:
		return
	_in_water = in_water
	collision_mask = (_base_collision_mask & ~WATER_COLLISION_LAYER) if in_water else _base_collision_mask


## 推动接触到的可推箱（PushableBody）。
## 仅当玩家朝箱子方向推（被箱子挡住）时，才沿玩家前进方向推动箱子；
## 只是贴着箱子滑过去（速度与表面平行）不会推动它。
func _push_boxes(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		return
	dir = dir.normalized()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body is CharacterBody2D and body.has_method("push"):
			var into := -col.get_normal()   # 指向箱子内部（被挡住的推入方向）
			if dir.dot(into) > 0.3:
				body.push(dir, delta)


func _apply_animation() -> void:
	sprite.flip_h = false  # 左右各有独立素材，不再镜像
	# 目前只有 4 方向的 walk 与朝下的 idle 动画；run/jump/rotate 暂复用，后续补。
	if state == State.IDLE or state == State.ROTATE:
		sprite.play("idle_down")
	else:
		sprite.play("walk_%s" % DIR_NAMES[facing])


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


func _handle_color_input() -> void:
	if Input.is_action_just_pressed("absorb"):
		_absorb()
	if Input.is_action_just_pressed("interact"):
		_grant()
	if Input.is_action_just_pressed("cycle_color_up"):
		_cycle_selection(1)
	if Input.is_action_just_pressed("cycle_color_down"):
		_cycle_selection(-1)


## 当前选中元素的颜色（未选中时为白）。
func _color_of(element_id: String) -> Color:
	return Rules.config(element_id).get("color", Color.WHITE)


## 当前选中元素的颜色名（未选中时为「无」）。
func _color_name_of(element_id: String) -> String:
	return str(Rules.config(element_id).get("color_name", ""))


## 更新选中元素：同步描边颜色 + 发射 UI 信号。
func _select_element(element_id: String) -> void:
	_selected_element = element_id
	selected_color = _color_of(element_id)
	selected_color_name = _color_name_of(element_id) if element_id != "" else "无"
	# 描边改用彩虹 shader，颜色不再随选中元素变化，无需设置 outline_color。
	color_changed.emit(selected_color, selected_color_name)
	inventory_changed.emit(_inventory, _selected_element)
	GameState.set_elements(_inventory.duplicate())


## 仅数量变化（选中不变）时刷新 UI。
func _notify_inventory() -> void:
	inventory_changed.emit(_inventory, _selected_element)
	GameState.set_elements(_inventory.duplicate())


## 供 HUD 在连接前读取颜色库快照。
func palette_snapshot() -> Dictionary:
	return {"inventory": _inventory.duplicate(), "selected": _selected_element}


## 颜色库里按固定顺序（burn→freeze→grow）列出持有中的元素，用于滚轮循环。
func _held_elements() -> Array:
	var order := ["burn", "freeze", "grow"]
	var out: Array = []
	for el in order:
		if int(_inventory.get(el, 0)) > 0:
			out.append(el)
	for el in _inventory:
		if int(_inventory[el]) > 0 and not out.has(el):
			out.append(el)
	return out


## 滚轮在颜色库中循环切换选中元素。dir = +1 下一个 / -1 上一个。
func _cycle_selection(dir: int) -> void:
	var held := _held_elements()
	if held.is_empty():
		return
	var idx := held.find(_selected_element)
	if idx == -1:
		idx = 0
	else:
		idx = posmod(idx + dir, held.size())
	_select_element(held[idx])


## 吸收：从鼠标指向的带色物体抽走元素，存入颜色库（种子守恒）。
func _absorb() -> void:
	var target := _colored_at_mouse()
	if target == null:
		return
	var info: Dictionary = target.call("absorb_color")
	var el := str(info.get("element", ""))
	if el == "":
		return
	var amt := int(info.get("amount", 1))
	_inventory[el] = int(_inventory.get(el, 0)) + amt
	_select_element(el)  # 吸收后自动选中新拿到的颜色


## 赋予：把当前选中的元素种到鼠标指向的可上色物体，消耗一颗种子（种子守恒）。
func _grant() -> void:
	if _selected_element == "":
		return
	var target := _grantable_at_mouse()
	if target == null:
		return
	var cfg := Rules.config(_selected_element)
	# 只在目标真的吃下这个颜色时才扣种子（水只吃蓝、已结冰不再吃，避免白扣）。
	var applied: bool = bool(target.call("apply_color", cfg.get("color", Color.WHITE), cfg.get("color_name", ""), global_position))
	if not applied:
		return
	_inventory[_selected_element] = int(_inventory[_selected_element]) - 1
	if int(_inventory[_selected_element]) <= 0:
		_inventory.erase(_selected_element)
		var rest := _held_elements()
		_select_element(rest[0] if not rest.is_empty() else "")
	else:
		_notify_inventory()


## 鼠标当前指向、且在 "colorable" group 里的物体（重叠时取 z_index 最高/最上层）。
func _colorable_at_mouse() -> Node:
	var mp := get_global_mouse_position()
	var best: Node = null
	var best_z := -INF
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("contains_point"):
			continue
		if not bool(obj.call("contains_point", mp)):
			continue
		var z := float(obj.get("z_index"))
		if z >= best_z:
			best_z = z
			best = obj
	return best


## 鼠标下、且当前带颜色（可被吸收）的物体。
func _colored_at_mouse() -> Node:
	var t := _colorable_at_mouse()
	if t != null and t.has_method("absorb_color") and t.has_method("has_color") and bool(t.call("has_color")):
		return t
	return null


## 鼠标下、且能上色（可被赋予）的物体。
func _grantable_at_mouse() -> Node:
	var t := _colorable_at_mouse()
	if t != null and t.has_method("apply_color"):
		return t
	return null


## 给鼠标指向的可交互物体加描边提示，目标变化时自动切换。
## 优先级：带色（可吸收/溶解）> 可赋予（可上色）。这样手里攥着颜色时，
## 鼠标下的冰/带色物仍提示「可吸收」，而不是误导成「可赋予」。
func _update_highlight() -> void:
	var target := _colored_at_mouse()
	if target == null and _selected_element != "":
		target = _grantable_at_mouse()
	if target == _highlighted:
		return
	_clear_highlight()
	if target != null:
		_highlighted = target
		_add_outline(target)


func _add_outline(target: Node) -> void:
	var sprite := _outline_sprite(target)
	if sprite == null:
		return
	_highlight_outline = Sprite2D.new()
	_highlight_outline.texture = sprite.texture
	_highlight_outline.centered = sprite.centered
	_highlight_outline.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_highlight_outline.material = _outline_material
	sprite.add_child(_highlight_outline)


## 取画描边要挂的 Sprite2D：目标本身是 Sprite2D（石头）直接用；
## 否则取它的 Visual 子节点（冰块是 StaticBody2D，贴图在 Visual 上）。
func _outline_sprite(target: Node) -> Sprite2D:
	if target is Sprite2D:
		return target
	return target.get_node_or_null("Visual") as Sprite2D


func _clear_highlight() -> void:
	if is_instance_valid(_highlight_outline):
		_highlight_outline.queue_free()
	_highlight_outline = null
	_highlighted = null


## 鼠标下、未结冰的水格（用于冻结预览）。只找水，不管是否带色/可赋予。
func _water_at_mouse() -> Node:
	var mp := get_global_mouse_position()
	var best: Node = null
	var best_z := -INF
	for obj in get_tree().get_nodes_in_group("colorable"):
		if not GameState.is_in_current_scene(obj):
			continue
		if not obj.has_method("is_frozen") or not obj.has_method("contains_point"):
			continue
		if bool(obj.call("is_frozen")):
			continue
		if not bool(obj.call("contains_point", mp)):
			continue
		var z := float(obj.get("z_index"))
		if z >= best_z:
			best_z = z
			best = obj
	return best


## 悬停水面反馈：手里是蓝时叠一个半透明冰块预览（提示「可结冰」）。
func _update_water_preview() -> void:
	var w := _water_at_mouse()
	var preview_on := w != null and _selected_element == "freeze"
	if w != _freeze_preview_water or preview_on != _freeze_preview_on:
		if is_instance_valid(_freeze_preview_water) and _freeze_preview_water.has_method("set_freeze_preview"):
			_freeze_preview_water.set_freeze_preview(false)
		_freeze_preview_water = w if preview_on else null
		_freeze_preview_on = preview_on
		if preview_on:
			w.set_freeze_preview(true)


func _build_sprite_frames() -> SpriteFrames:
	# 兜底：场景里已外挂 player_sprite_frames.tres，这里直接复用同一份资源。
	return preload("res://resources/player_sprite_frames.tres")


func _register_input_actions() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("run", [KEY_SHIFT])
	_add_action("jump", [KEY_SPACE])
	_add_action("rotate", [KEY_R])
	# 吸收/赋予改用鼠标：右键吸收、左键赋予。
	_add_mouse_action("absorb", MOUSE_BUTTON_RIGHT)
	_add_mouse_action("interact", MOUSE_BUTTON_LEFT)
	# 预留：以后有多种颜色时用滚轮切换选择。
	_add_mouse_action("cycle_color_up", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_action("cycle_color_down", MOUSE_BUTTON_WHEEL_DOWN)


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


## 给动作绑定一个鼠标按键（左键/右键/滚轮等）。pressed 必须显式置 true，
## 否则 is_action_just_pressed 会在「松开」时才触发。
func _add_mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	InputMap.action_add_event(action, ev)
