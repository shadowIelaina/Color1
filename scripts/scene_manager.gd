extends Node
## SceneManager（Autoload 单例）：负责房间切换。
## GameContainer 启动时调用 setup() 注入玩家与房间容器。
## change_room()：卸载旧房 -> 加载新房 -> 定位玩家到目标入口。

signal room_changed(room_id: String)
signal room_entered(room_id: String)
signal room_exited(room_id: String)

const SWITCH_COOLDOWN := 0.4  # 切房冷却，防重复触发
const SAFE_POS := Vector2(1e7, 1e7)  # 切房瞬间玩家的临时安全位，避免与新房拾取区重叠误触发

var player: Node2D = null
var room_container: Node = null
var current_room: Node = null

var _switching := false
var _cooldown := 0.0


func setup(p_player: Node2D, p_room_container: Node) -> void:
	player = p_player
	room_container = p_room_container


func is_busy() -> bool:
	return _switching


func _process(delta: float) -> void:
	if _switching:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_switching = false


## 核心：切换到目标场景，并把玩家定位到目标入口。
## 场景增删（add_child/queue_free）不能在物理回调（如门 Area2D 的 body_entered）里同步执行，
## 否则会触发 "Can't change this state while flushing queries"。这里同步只置切换守卫，实际切房
## 用 call_deferred 放到帧末执行。
func change_room(target_scene: String, target_entrance: String) -> void:
	if _switching:
		return
	if player == null or room_container == null:
		push_warning("SceneManager 未初始化，请先调用 setup()")
		return
	_switching = true
	_cooldown = SWITCH_COOLDOWN
	_do_change_room.call_deferred(target_scene, target_entrance)


func _do_change_room(target_scene: String, target_entrance: String) -> void:
	# 1. 退出并卸载旧房
	if current_room != null and is_instance_valid(current_room):
		room_exited.emit(current_room.get("room_id"))
		if current_room.has_method("exit"):
			current_room.exit()
		current_room.queue_free()
		current_room = null
		GameState.current_room = null
		GameState.current_room_id = ""
		HeightMap.clear()

	# 2. 加载新房
	var packed: PackedScene = load(target_scene)
	if packed == null:
		push_error("无法加载房间场景：%s" % target_scene)
		return
	var new_room: Node = packed.instantiate()
	# 先把玩家挪到远处安全位：新房 Area2D 入树时若与玩家旧位置重叠，会在下一物理帧
	# 误触发拾取/开门。add_child 前移开，稍后（第 4 步）再定位到入口。
	player.global_position = SAFE_POS
	room_container.add_child(new_room)
	current_room = new_room

	# 3. 进入新房（标记访问、恢复状态、相机边界）
	if new_room.has_method("enter"):
		new_room.enter()

	# 4. 定位玩家到目标入口
	var pos := Vector2.ZERO
	if new_room.has_method("get_entrance_position"):
		pos = new_room.get_entrance_position(target_entrance)
	player.global_position = pos
	if player is CharacterBody2D:
		player.velocity = Vector2.ZERO

	room_entered.emit(new_room.get("room_id"))
	room_changed.emit(new_room.get("room_id"))
