class_name PushableBody
extends CharacterBody2D
## 可推箱的物理体：由玩家在真实顶住箱面时调用 push()。
## 箱子只在被推时同步 move_and_collide，不与玩家互相推挤，避免黏在玩家身上。

@export_range(0.0, 3000.0, 5.0) var push_speed := 1280.0


func push(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO or delta <= 0.0:
		return
	move_and_collide(dir.normalized() * push_speed * delta)
