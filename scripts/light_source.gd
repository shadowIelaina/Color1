class_name LightSource
extends Node2D
## 光照标记：以自身为圆心、radius 为半径的光斑，供暗房遮罩 shader 在其上挖透明圆洞。
## 本身不发光，只是「位置 + 半径」数据；挖洞由 darkness_overlay.gd 每帧收集 light_source 组完成。

@export_range(8.0, 4096.0, 8.0) var radius := 160.0


func _ready() -> void:
	add_to_group("light_source")
