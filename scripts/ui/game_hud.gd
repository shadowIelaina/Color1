extends CanvasLayer
## HUD：显示当前颜色、持有的钥匙、当前房间、提示文字。

@onready var color_label: Label = $ColorLabel
@onready var keys_label: Label = $KeysLabel
@onready var room_label: Label = $RoomLabel
@onready var hint_label: Label = $HintLabel

var _hint_t := 0.0


func _ready() -> void:
	GameState.key_added.connect(_on_keys_changed)
	GameState.key_used.connect(_on_keys_changed)
	GameState.hint.connect(_show_hint)
	SceneManager.room_entered.connect(_on_room_entered)
	call_deferred("_bind_player")
	_on_keys_changed("")
	_on_room_entered("")


func _bind_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.color_changed.connect(_on_color_changed)
		_on_color_changed(player.selected_color, player.selected_color_name)


func _on_color_changed(c: Color, color_name: String) -> void:
	color_label.text = "颜色：%s" % color_name
	color_label.modulate = c


func _on_keys_changed(_key_id: String) -> void:
	var keys: Array = GameState.inventory.keys()
	keys_label.text = "钥匙：%s" % ("、".join(keys) if not keys.is_empty() else "无")


func _on_room_entered(room_id: String) -> void:
	room_label.text = "房间：%s" % room_id


func _show_hint(text: String) -> void:
	hint_label.text = text
	_hint_t = 2.0


func _process(delta: float) -> void:
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0:
			hint_label.text = ""
