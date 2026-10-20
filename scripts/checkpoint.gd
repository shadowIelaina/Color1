class_name Checkpoint
extends Area2D
## 存档点：玩家进入触发区，即把「当前场景 + 本节点位置」写入存档。
## 死亡后复活会优先回到最近的存档点；主菜单「继续游戏」也从这里进入。

@export var checkpoint_id: String = ""
@export var show_marker := false


func _ready() -> void:
	add_to_group("checkpoint")
	collision_layer = 0
	collision_mask = 1   # 只检测玩家（层 1）
	body_entered.connect(_on_body_entered)
	# 占位色块只在编辑器里可见，游戏运行时隐藏。
	var visual := get_node_or_null("Visual")
	if visual != null:
		visual.visible = show_marker
	if show_marker:
		z_index = 4090
		if visual is Polygon2D:
			visual.color = Color(0.72, 0.65, 0.48, 0.55)
			visual.polygon = PackedVector2Array([Vector2(-72, 0), Vector2(0, -96), Vector2(72, 0), Vector2(0, 96)])
		var label := Label.new()
		label.text = "存档点"
		label.add_theme_font_override("font", preload("res://art/fonts/LXGWWenKaiLite-Regular.ttf"))
		label.add_theme_font_size_override("font_size", 64)
		label.add_theme_color_override("font_color", Color("6b604c"))
		label.add_theme_constant_override("outline_size", 8)
		label.add_theme_color_override("font_outline_color", Color("f5f3ed"))
		label.position = Vector2(-96, -520)
		add_child(label)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_activate(body)


func _activate(body: Node2D = null) -> void:
	if body == null: body = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(body) or not GameState.is_in_current_scene(self): return
	if not body.is_safe_respawn_position(body.global_position): return
	body.reclaim_placed_colors()
	# 保存实际经过的安全位置，不能把触发区边缘的玩家传到节点中心。
	GameState.set_checkpoint(SceneManager.current_room_scene, body.global_position)
	GameState.notice.emit("已记录存档点")
