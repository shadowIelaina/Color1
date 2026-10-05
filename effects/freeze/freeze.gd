@tool
extends Node2D

## 是否循环播放(编辑器预览建议开;实际施法触发时设 false 或直接调 play())
@export var loop := true

## 一次完整冻结动画的时长(秒)
@export var cycle_duration := 3.0

var _cycle_time := 0.0

func _ready() -> void:
	_cycle_time = cycle_duration

func _process(delta: float) -> void:
	_cycle_time += delta
	if _cycle_time >= cycle_duration:
		_cycle_time = 0.0
		play()
		if not loop:
			set_process(false)

func play() -> void:
	$Frost.restart()
	$IceRing.restart()
