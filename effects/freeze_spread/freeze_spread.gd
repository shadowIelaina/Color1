@tool
extends Node2D

## 是否循环播放(编辑器预览建议开;实际施法触发时设 false 或直接调 play())
@export var loop := true

## 一次完整冻结动画的时长(秒)
@export var cycle_duration := 3.0

## "颜色扩散出去"到"物体被冰冻住"之间的延迟(秒), 用于表现先后时序
@export var frost_delay := 0.2

var _cycle_time := 0.0
var _frost_timer := 0.0
var _frost_queued := false

func _ready() -> void:
	_cycle_time = cycle_duration

func _process(delta: float) -> void:
	if _frost_queued:
		_frost_timer += delta
		if _frost_timer >= frost_delay:
			_frost_queued = false
			$Frost.restart()
	_cycle_time += delta
	if _cycle_time >= cycle_duration:
		_cycle_time = 0.0
		play()
		if not loop:
			set_process(false)

## 触发一次: 点上蓝色 -> 颜色扩散出去 -> 物体被冰冻住
func play() -> void:
	$Core.restart()   # 蓝色点
	$Spread.restart() # 颜色扩散出去
	_frost_timer = 0.0
	_frost_queued = true # 延迟后结冰
