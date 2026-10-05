@tool
extends Node2D

## 一次完整循环的时长(秒):收缩+爆开+间隔
@export var cycle_duration := 3.2

var _cycle_time := 0.0

func _ready() -> void:
	_cycle_time = cycle_duration

func _process(delta: float) -> void:
	_cycle_time += delta
	if _cycle_time >= cycle_duration:
		_cycle_time = 0.0
		play()

func play() -> void:
	$Ring.restart()
