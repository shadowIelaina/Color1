extends Node2D
## 常驻根节点（GameContainer）：持有玩家与房间容器。
## 启动时初始化 SceneManager 并进入起始房间。玩家常驻，不放在房间内。

@export var start_room: String = "res://scenes/level_1.tscn"
@export var start_entrance: String = "spawn"

@onready var player: Node2D = $Player
@onready var room_container: Node2D = $RoomContainer


func _ready() -> void:
	SceneManager.setup(player, room_container)
	SceneManager.change_room(start_room, start_entrance)
