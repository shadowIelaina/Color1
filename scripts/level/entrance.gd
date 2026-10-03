class_name Entrance
extends Marker2D
## 房间入口标记：Door 切房后，玩家会定位到 matching entrance_id 的入口位置。

@export var entrance_id: String = ""


func _ready() -> void:
	add_to_group("entrance")
	if entrance_id == "":
		entrance_id = name
