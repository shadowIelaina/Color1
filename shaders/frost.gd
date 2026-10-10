@tool
extends Node2D
## 冰霜粒子（frost.tscn）：作为「冻结(freeze)」元素的 VFX，只播一次。
## 由 ElementBehavior._spawn_vfx 实例化并 set("loop", false)（见 element_rules.gd 的 freeze.vfx）。
## 保留 loop 属性仅为兼容该 set 调用；loop=true 留给编辑器预览（粒子默认持续循环）。

@export var loop := true


func _ready() -> void:
	if loop:
		return
	for child in get_children():
		if child is CPUParticles2D:
			child.one_shot = true
			child.restart()
