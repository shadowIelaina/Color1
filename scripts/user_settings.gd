extends Node
## 与游戏进度分开保存，开始新游戏不会清空偏好。
const PATH := "user://settings.cfg"
var volume := 1.0
var fullscreen := false
var _dirty := false
var _save_timer: Timer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.2
	add_child(_save_timer)
	_save_timer.timeout.connect(save_now)
	reload_settings()

func reload_settings() -> void:
	var config := ConfigFile.new()
	volume = 1.0
	fullscreen = false
	if config.load(PATH) == OK:
		var saved_volume: Variant = config.get_value("audio", "volume", 1.0)
		if (saved_volume is float or saved_volume is int) and is_finite(float(saved_volume)):
			volume = clampf(float(saved_volume), 0.0, 1.0)
		var saved_fullscreen: Variant = config.get_value("display", "fullscreen", false)
		if saved_fullscreen is bool: fullscreen = saved_fullscreen
	AudioServer.set_bus_volume_linear(0, volume)
	_apply_display()

func set_volume(value: float) -> void:
	if not is_finite(value): return
	volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_linear(0, volume)
	_queue_save()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display()
	_queue_save()

func _apply_display() -> void:
	if DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _queue_save() -> void:
	_dirty = true
	_save_timer.start()

func save_now() -> void:
	if not _dirty: return
	var config := ConfigFile.new()
	config.set_value("audio", "volume", volume)
	config.set_value("display", "fullscreen", fullscreen)
	var error := config.save(PATH)
	if error == OK: _dirty = false
	else: push_warning("设置保存失败：%s" % error_string(error))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: save_now()

func _exit_tree() -> void:
	save_now()
