class_name BreakableWall
extends StatefulObject
## 可破坏墙：玩家触碰破坏（白盒占位，后续可接颜色/能力破坏）。
## 破坏状态会被保存/恢复。

@export var wall_id: String = ""

@export_group("剧情")
## 破坏时播放的主线剧情段落（prologue.dialogue 的 cue）；空 = 不播。
@export var story_cue: String = ""
## 整局唯一标识，防止重复播放；空 = 每次破坏都播。
@export var story_id: String = ""

var broken: bool = false

@onready var _break_area: Area2D = $BreakArea
@onready var _collision: CollisionShape2D = $Body/CollisionShape2D
@onready var _visual: Node2D = $Visual


func _ready() -> void:
	super._ready()
	if wall_id == "":
		wall_id = name
	_break_area.body_entered.connect(_on_body_entered)
	_apply_visual()


func _on_body_entered(body: Node) -> void:
	if broken:
		return
	if body.is_in_group("player"):
		break_wall()


func break_wall() -> void:
	broken = true
	_collision.set_deferred("disabled", true)
	_apply_visual()
	StoryPort.play(self, story_cue, story_id)


func _apply_visual() -> void:
	if _visual is CanvasItem:
		_visual.visible = not broken


func save_state() -> Dictionary:
	return {"broken": broken}


func restore_state(data: Dictionary) -> void:
	broken = data.get("broken", false)
	if broken:
		_collision.set_deferred("disabled", true)
	_apply_visual()
