extends Node2D
## 常驻根节点（GameContainer）：持有玩家与房间容器。
## 启动时初始化 SceneManager 并进入起始房间。玩家常驻，不放在房间内。

@export var start_room: String = "res://scenes/level_1.tscn"
@export var start_entrance: String = "spawn"
@export var show_main_menu := true

@export_group("调试")
## Boss 测试：跳过主菜单，直接进入 level_4；预置三颗心、跟班、无限三色，不挂弹反。
@export var debug_boss_test := false

@export_group("主菜单美术")
## 完整标题图（含「失色 / 招领处」），推荐透明 PNG；留空时显示文字占位。
@export var menu_title_texture: Texture2D
## 标题图片在菜单中的显示区域，等比缩放，不拉伸。
@export var menu_title_size := Vector2(280, 160)
## 菜单统一字体；可替换为其他已获授权的中文手写字体。
@export var menu_font: Font = preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf")

@onready var player: Node2D = $Player
@onready var room_container: Node2D = $RoomContainer
@onready var pcam: PhantomCamera2D = $MainPCam as PhantomCamera2D
var menu_has_save := false
var launch_action := ""


func _enter_tree() -> void:
	if debug_boss_test:
		_prepare_debug_boss_test()
		return
	GameState.debug_save_disabled = false
	if not show_main_menu:
		return
	launch_action = GameState.menu_launch_action
	GameState.menu_launch_action = ""
	# 必须在 Player._ready 和关卡实例化前读档，确保背包、血量和房间一致。
	if launch_action == "new":
		GameState.new_game()
	else:
		menu_has_save = GameState.continue_game()
		if not menu_has_save:
			GameState.reset()
			launch_action = ""  # 存档失效时回到菜单，不误开启新游戏。


func _ready() -> void:
	add_child(preload("res://scripts/pause_menu.gd").new())
	if debug_boss_test:
		_start_debug_boss_test()
		return
	if show_main_menu:
		var menu := preload("res://scripts/main_menu.gd").new()
		add_child(menu)
		menu.prepare(self)
	SceneManager.setup(player, room_container)
	add_child(preload("res://scripts/opening_guide.gd").new())
	if pcam != null:
		pcam.follow_target = player
	if show_main_menu and menu_has_save:
		SceneManager.resume_from_checkpoint()
	else:
		SceneManager.change_room(start_room, start_entrance)


## Boss 测试模式：在 Player._ready 之前预置三颗心，让玩家以 4 颗心出生。
func _prepare_debug_boss_test() -> void:
	GameState.reset()
	GameState.menu_launch_action = ""
	GameState.health_upgrades = {
		"heart:debug_blue": 1,
		"heart:debug_red": 1,
		"heart:debug_green": 1,
	}
	GameState.health_upgrade_names = {
		"heart:debug_blue": "蓝心",
		"heart:debug_red": "红心",
		"heart:debug_green": "绿心",
	}
	GameState.companion_recruited = true
	GameState.debug_save_disabled = true


## Boss 测试模式：直接进 level_4，给无限三色与跟班，不加弹反。
func _start_debug_boss_test() -> void:
	SceneManager.setup(player, room_container)
	if pcam != null:
		pcam.follow_target = player
	player.set("infinite_elements", true)
	if player.has_method("_seed_infinite_elements"):
		player.call("_seed_infinite_elements")
	var parry := player.get_node_or_null("Parry")
	if parry != null:
		parry.queue_free()
	SceneManager.change_room("res://scenes/level_4.tscn", "spawn")
