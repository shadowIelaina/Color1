class_name Colorable
extends Node2D
## 可上色实体基类。
## - 默认 modulate 染色（适合 Sprite 类）。
## - 自动按颜色语义记录特性到 traits（strength/stability/grow/hide）。
## - 子类可覆写 _on_color_applied 实现各自效果（复制/破碎/冻结等）。

signal color_applied(color: Color)

@export var supported_colors: Array[String] = ["red", "blue", "green", "black", "white"]
@export var duplicatable: bool = false   # 绿色时是否朝玩家方向复制一份
@export var shatterable: bool = false    # 红→白 时是否破碎消失

var current_color: Color = Color.WHITE
var current_color_name: String = ""
var previous_color_name: String = ""
var traits: Dictionary = {}   # 当前激活特性，如 {"strength": true, "stability": true}
var _spawned_copies: Array = []   # 自己复制出的副本列表，白色时收回


func apply_color(color: Color, color_name: String = "", direction: Vector2 = Vector2.ZERO) -> bool:
	if color_name != "" and color_name not in supported_colors:
		return false
	previous_color_name = current_color_name
	current_color = color
	current_color_name = color_name
	if color_name == "white":
		_retract_copies()
	_on_color_applied(color, color_name, direction)
	color_applied.emit(color)
	EventBus.emit("color_applied", {"target": self, "color": color, "color_name": color_name})
	return true


func reset_color() -> void:
	current_color = Color.WHITE
	current_color_name = ""
	previous_color_name = ""
	traits.clear()
	_on_reset()


## 根据颜色语义记录特性。白 = 重置，会清空已有特性。
func record_trait(color_name: String) -> void:
	var semantic := ColorManager.get_semantic(color_name)
	if semantic == "reset":
		traits.clear()
	elif semantic != "":
		traits[semantic] = true


func _on_color_applied(color: Color, color_name: String = "", _direction: Vector2 = Vector2.ZERO) -> void:
	if color_name == "white" and shatterable and previous_color_name == "red":
		shatter()
		return
	record_trait(color_name)
	modulate = color
	if color_name == "green" and duplicatable and previous_color_name != "green":
		duplicate_in_direction(_direction)


func _on_reset() -> void:
	modulate = Color.WHITE


## 朝 direction 方向复制一份自身，返回副本（副本已重置为未上色状态）。
func duplicate_in_direction(direction: Vector2, offset: float = 32.0) -> Colorable:
	var parent := get_parent()
	if parent == null:
		return null
	var copy := duplicate() as Colorable
	if copy == null:
		return null
	copy._spawned_copies = []
	for child in copy.get_children():
		if child.name == "HighlightOutline":
			copy.remove_child(child)
			child.queue_free()
	parent.add_child(copy)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	copy.global_position = global_position + direction.normalized() * offset
	copy.reset_color()
	copy.modulate = Color.WHITE
	_spawned_copies.append(copy)
	return copy


## 收回自己复制出的所有副本。
func _retract_copies() -> void:
	for copy in _spawned_copies:
		if is_instance_valid(copy):
			copy.queue_free()
	_spawned_copies.clear()


## 破碎：广播事件后销毁自身（粒子等表现后续由 EffectSpawner 接）。
func shatter() -> void:
	EventBus.emit("colorable_shattered", {"target": self})
	queue_free()
