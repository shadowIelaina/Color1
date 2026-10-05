@tool
class_name Shatter
extends Node2D

## 需要破碎的目标(默认父节点; 父节点不是 CanvasItem 时请手动指定)
@export var target: CanvasItem
## 破碎时长(秒)
@export var duration := 1.2
## 碎片行列数
@export var shards := Vector2(4, 4)
## 随机种子: 每个物体给不同值, 碎裂姿态就不同
@export var seed_value := 0.0
## 是否循环播放(编辑器预览建议开; 实际触发时设 false 或直接调 shatter())
@export var loop := true
## 一次完整循环的时长(秒)
@export var cycle_duration := 3.0

const SHATTER_SHADER_PATH := "res://shaders/shatter.gdshader"

var _material: ShaderMaterial
var _cycle_time := 0.0

func _ready() -> void:
	if target == null:
		target = get_parent() as CanvasItem
	_material = ShaderMaterial.new()
	_material.shader = load(SHATTER_SHADER_PATH)
	if target != null:
		target.material = _material
	_cycle_time = cycle_duration

func _process(delta: float) -> void:
	_cycle_time += delta
	if _cycle_time >= cycle_duration:
		_cycle_time = 0.0
		if not loop:
			set_process(false)
	_material.set_shader_parameter("shards", shards)
	_material.set_shader_parameter("seed_value", seed_value)
	_material.set_shader_parameter("progress", clampf(_cycle_time / duration, 0.0, 1.0))

## 触发一次破碎
func shatter() -> void:
	_cycle_time = 0.0
	if not loop:
		set_process(true)
