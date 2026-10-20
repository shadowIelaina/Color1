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
## 当前房间的场景路径（res://...，供存档点记录所在场景）。
var current_room_scene: String = ""

var _switching := false
var _cooldown := 0.0
## 切房时是否定位到存档点坐标（而不是入口）。由 resume_from_checkpoint 置位，切完即清。
var _resume_at_checkpoint := false


func setup(p_player: Node2D, p_room_container: Node) -> void:
	# 主菜单重开整个游戏根节点后，单例不能保留已释放的房间引用和切房守卫。
	if not is_instance_valid(current_room):
		current_room = null
		current_room_scene = ""
		_switching = false
		_resume_at_checkpoint = false
	player = p_player
	room_container = p_room_container


func is_busy() -> bool:
	return _switching


## 继续游戏：切到存档点所在场景，并把玩家定位到存档点坐标。
func resume_from_checkpoint() -> bool:
	if _switching or not GameState.has_checkpoint() or not ResourceLoader.exists(GameState.checkpoint_scene, "PackedScene"):
		return false
	_resume_at_checkpoint = true
	change_room(GameState.checkpoint_scene, "spawn")
	return true


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
		# 房间卸载后临时冰面/颜色会消失，先收回玩家放置的种子。
		if is_instance_valid(player) and player.has_method("reclaim_placed_colors"):
			player.reclaim_placed_colors()
		room_exited.emit(current_room.get("room_id"))
		if current_room.has_method("exit"):
			current_room.exit()
		# 小跟班要跨关跟随：在卸载旧房前，把属于旧房的 companion 移到常驻容器，避免一起被 free。
		var companions: Array = []
		for c in get_tree().get_nodes_in_group("companion"):
			if current_room.is_ancestor_of(c):
				companions.append(c)
		for c in companions:
			if is_instance_valid(c) and c.get_parent() != room_container:
				c.reparent(room_container, true)
		current_room.queue_free()
		current_room = null
		GameState.current_room = null
		GameState.current_room_id = ""
		HeightMap.clear()
		# 切关时把暗房遮罩复位为亮，避免上个关的暗房效果残留到新关。
		var darkness := get_tree().get_first_node_in_group("darkness")
		if darkness != null:
			darkness.darkness = 0.0

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
	current_room_scene = target_scene

	# 3. 进入新房（标记访问、恢复状态、相机边界）
	if new_room.has_method("enter"):
		new_room.enter()

	# 4. 定位玩家到目标入口
	var pos := Vector2.ZERO
	if _resume_at_checkpoint:
		pos = GameState.checkpoint_pos
		_resume_at_checkpoint = false
	elif new_room.has_method("get_entrance_position"):
		pos = new_room.get_entrance_position(target_entrance)
	player.global_position = pos
	if player is CharacterBody2D:
		player.velocity = Vector2.ZERO
	_restore_companion()
	_ensure_safe_arrival(new_room)

	room_entered.emit(new_room.get("room_id"))
	room_changed.emit(new_room.get("room_id"))


## 新房碰撞需等物理同步后才能查询；也修复旧存档里落在机关内的位置。
func _ensure_safe_arrival(room: Node) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(room) or current_room != room or not is_instance_valid(player):
		return
	if not player.has_method("is_safe_respawn_position") or player.is_safe_respawn_position(player.global_position):
		return
	var spawn: Vector2 = room.get_entrance_position("spawn")
	if not player.is_safe_respawn_position(spawn):
		return
	player.global_position = spawn
	if player is CharacterBody2D:
		player.velocity = Vector2.ZERO
	_restore_companion()


func _restore_companion() -> void:
	if not GameState.companion_recruited:
		return
	var companion: Node = null
	for candidate in get_tree().get_nodes_in_group("companion"):
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			companion = candidate
			break
	if companion == null:
		companion = preload("res://prefabs/creatures/companion.tscn").instantiate()
		room_container.add_child(companion)
	elif companion.state == Companion.State.TASK:
		return  # 正常切关时不覆盖仍在结算的吸色/上色任务。
	companion.restore_following()
