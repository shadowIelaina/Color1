class_name DarknessOverlay
extends Polygon2D
## 暗房遮罩：一整块盖住世界的黑色多边形，shader 在光源处挖透明圆洞（塞尔达式迷宫光照）。
## - RoomZone 通过 tween darkness（0 = 亮 / 1 = 全黑）控制某间房是否暗。
## - 本脚本每帧把 light_source 组里的位置 + 半径喂给 shader。
## 约定：polygon 顶点直接用世界坐标覆盖整个地图；喂给 shader 的光源位置用 to_local 转成
## 遮罩本地坐标，与 shader 里的 VERTEX 同空间，因此本节点可放在任意位置/带 transform。

const MAX_LIGHTS := 16

@export var dark_color := Color(0.0, 0.0, 0.0, 1.0)
@export_range(0.0, 0.5, 0.01) var softness := 0.18
@export_range(0.0, 1.0) var darkness: float = 0.0:
	set(value):
		darkness = value
		_apply_darkness()


func _ready() -> void:
	add_to_group("darkness")
	if polygon.is_empty():
		# 兜底：场景里没配 polygon 时自动盖住一大片世界（否则遮罩画不出来）。
		var half := 20000.0
		polygon = PackedVector2Array([
			Vector2(-half, -half),
			Vector2(half, -half),
			Vector2(half, half),
			Vector2(-half, half),
		])
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("dark_color", dark_color)
		mat.set_shader_parameter("softness", softness)
	_apply_darkness()


func _process(_delta: float) -> void:
	if darkness == 0.0:
		return  # 全亮时遮罩全透明，无需每帧喂光源。
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var pos := PackedVector2Array()
	var rad := PackedFloat32Array()
	pos.resize(MAX_LIGHTS)
	rad.resize(MAX_LIGHTS)
	var count := 0
	for src in get_tree().get_nodes_in_group("light_source"):
		if count >= MAX_LIGHTS:
			break
		if not (src is LightSource):
			continue
		if not _is_relevant(src):
			continue
		var ls := src as LightSource
		pos[count] = to_local(ls.global_position)
		rad[count] = ls.radius
		count += 1
	# Godot 4 里 set_shader_parameter("arr[i]", v) 单元素设置不会上传到 GPU（CPU 侧 readback
	# 会变，但 shader 仍读到旧值），必须一次性把整个数组喂进去。resize 已把剩余槽位填成 0/(0,0)。
	mat.set_shader_parameter("light_pos", pos)
	mat.set_shader_parameter("light_radius", rad)
	mat.set_shader_parameter("light_count", count)


## 光源是否参与当前关的遮罩：属于当前大场景，或是玩家自带的微光（常驻房外）。
func _is_relevant(src: Node) -> bool:
	if GameState.is_in_current_scene(src):
		return true
	var cur: Node = src.get_parent()
	while cur != null:
		if cur.is_in_group("player"):
			return true
		cur = cur.get_parent()
	return false


func _apply_darkness() -> void:
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("darkness", darkness)
