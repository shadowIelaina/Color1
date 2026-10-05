@tool
extends Node2D

## 是否循环播放(编辑器预览建议开;实际施法触发时设 false 或直接调 play())
@export var loop := true

## 一次完整火焰动画的时长(秒)
@export var cycle_duration := 3.0

## "热量扩散"到"火焰升起"之间的延迟(秒), 用于表现先后时序
@export var ember_delay := 0.2

var _cycle_time := 0.0
var _ember_timer := 0.0
var _ember_queued := false

func _ready() -> void:
	_cycle_time = cycle_duration

func _process(delta: float) -> void:
	if _ember_queued:
		_ember_timer += delta
		if _ember_timer >= ember_delay:
			_ember_queued = false
			$Embers.restart()
	_cycle_time += delta
	if _cycle_time >= cycle_duration:
		_cycle_time = 0.0
		play()
		if not loop:
			set_process(false)

## 触发一次: 点火 -> 热量扩散出去 -> 火焰升起
func play() -> void:
	$Core.restart()    # 点火
	$Spread.restart()  # 热量扩散出去
	_ember_timer = 0.0
	_ember_queued = true # 延迟后火焰升起
