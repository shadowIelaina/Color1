extends Room
## Boss 房：监听 Boss 阵亡，显示胜利并开启返回 level_4 的传送门。

@export var defeated_switch := "boss_defeated"
@export var victory_text := "BOSS 已击败"

@onready var boss: Node = get_node_or_null("BossEncounter/Boss")
@onready var nav_baker: NavigationRegion2D = get_node_or_null("RuntimeNav")

var _shake_noise: PhantomCameraNoise2D
var _shake_tween: Tween


func _ready() -> void:
	super._ready()
	_bake_navigation.call_deferred()
	if GameState.is_switch_on(defeated_switch):
		_remove_boss()
	elif boss != null and boss.has_signal("died"):
		boss.died.connect(_on_boss_died)


func enter() -> void:
	super.enter()
	_set_camera_zoom(0.30, 0.5)
	_setup_shake()


func exit() -> void:
	_restore_camera()
	super.exit()
	var hud := _global_hud()
	if hud == null:
		return
	var label := hud.get_node_or_null("WinLabel")
	if label is Label:
		(label as Label).visible = false
	if hud.has_method("hide_boss_victory"):
		hud.call("hide_boss_victory")


## BossEncounter 自带的 Nav 会在进入 Room 后被释放；这里显式烘焙本房导航。
func _bake_navigation() -> void:
	if nav_baker == null:
		return
	var zone := get_node_or_null("RoomZone") as RoomZone
	var bounds := zone.get_rect() if zone != null else Rect2(-4800, -3900, 9600, 7800)
	nav_baker.call("setup", self, bounds, 150.0, 32.0, 256.0)


func _on_boss_died() -> void:
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	GameState.set_switch(defeated_switch, true)
	# 战斗完成后立即保存，避免尚未碰到下个存档点就退出导致胜利记录丢失。
	GameState.save_game()
	var arena := get_node_or_null("Arena")
	if arena != null and arena.has_method("play_victory"):
		arena.call("play_victory")
	GameState.notice.emit("返回传送门已开启")
	_show_victory()


func _remove_boss() -> void:
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
		boss = null


func _show_victory() -> void:
	var hud := _global_hud()
	if hud == null:
		return
	if hud.has_method("show_boss_victory"):
		hud.call("show_boss_victory", victory_text, "归途传送门已开启", 3.0)
	elif hud.has_method("show_win"):
		hud.show_win()


## Boss 房自带一个 HUD 实例（默认隐藏），这里只操作常驻根节点下的全局 HUD。
func _global_hud() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("HUD")


# —— 镜头 ——

func _set_camera_zoom(value: float, duration: float) -> void:
	var cam := get_tree().get_first_node_in_group("main_camera")
	if cam == null:
		return
	var t := get_tree().create_tween()
	t.tween_property(cam, "zoom", Vector2(value, value), duration)


func _setup_shake() -> void:
	var cam := get_tree().get_first_node_in_group("main_camera")
	if cam == null:
		return
	_shake_noise = PhantomCameraNoise2D.new()
	_shake_noise.amplitude = 0.0
	_shake_noise.frequency = 9.0
	_shake_noise.positional_noise = true
	_shake_noise.rotational_noise = false
	cam.set("noise", _shake_noise)


## 供场地脚本调用：撞墙 / 阶段冲击时短暂震屏。
func shake(amount: float) -> void:
	if _shake_noise == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_property(_shake_noise, "amplitude", amount, 0.05)
	_shake_tween.tween_property(_shake_noise, "amplitude", 0.0, 0.3)


func _restore_camera() -> void:
	_set_camera_zoom(0.25, 0.35)
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	if _shake_noise != null:
		_shake_noise.amplitude = 0.0
		var cam := get_tree().get_first_node_in_group("main_camera")
		if cam != null:
			cam.set("noise", null)
		_shake_noise = null
