extends Node2D
## 融化滴水特效：一次性蓝色水滴往下坠，播完自动 free。
## 由 ElementBehavior 在自然解冻时 spawn（不存 _vfx，独立生命周期）。

func _ready() -> void:
	get_tree().create_timer(2.0).timeout.connect(queue_free)
