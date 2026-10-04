class_name Gate
extends StatefulObject
## 门控障碍：支持 key / ability / switch 三种解锁条件。
## 条件满足即开启（锁存：一旦打开不再关闭，避免软锁）。

@export var gate_id: String = ""
@export_enum("none", "key", "ability", "switch") var gate_type: String = "none"
@export var required_id: String = ""   # key_id / ability_id / switch_id
@export var starts_open: bool = false

var is_open: bool = false

@onready var _collision: CollisionShape2D = $Body/CollisionShape2D
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if gate_id == "":
		gate_id = name
	if starts_open:
		_apply_open(true)


func _physics_process(_delta: float) -> void:
	if not is_open and _condition_met():
		_apply_open(false)


func _condition_met() -> bool:
	match gate_type:
		"key":
			return GameState.has_key(required_id)
		"switch":
			return GameState.is_switch_on(required_id)
		"ability":
			return GameState.has_ability(required_id)
		_:
			return true


func _apply_open(initial: bool) -> void:
	is_open = true
	if _collision:
		_collision.set_deferred("disabled", true)
	if _visual is CanvasItem:
		_visual.visible = false
	if not initial:
		GameState.gate_opened.emit(gate_id)


func save_state() -> Dictionary:
	return {"is_open": is_open}


func restore_state(data: Dictionary) -> void:
	is_open = data.get("is_open", starts_open)
	if is_open:
		_apply_open(true)
