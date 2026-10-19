class_name IceBlock
extends StaticBody2D
## 带蓝的冰块：吸收其蓝色后破碎、返还蓝并消失。
## - 作为「蓝色种子闸门」（ice_block.tscn，seed_amount=3）：挡路 + 开局被赋蓝，吸收后放行并给 3 量蓝。
## - 作为「冰墙」（ice_wall.tscn，seed_amount=1）：冻水上再点一下生成的可融墙，吸收后融化返还 1 蓝。

const Rules := preload("res://scripts/element/element_rules.gd")
const SHATTER := preload("res://effects/shatter/shatter.gd")

## 破碎动画结束后销毁本节点（秒）。
@export var shatter_delay := 1.4

## 吸收后返还的蓝色数量。默认 3（蓝色种子闸门）；冰墙复用设 1（融化返还 1 蓝）。
@export var seed_amount := 3

@export_group("剧情")
## 吸收蓝色时播放的主线剧情段落（prologue.dialogue 的 cue）；空 = 不播。
@export var story_cue: String = ""
## 整局唯一标识，防止重复播放；空 = 每次吸收都播。
@export var story_id: String = ""

@onready var visual: Sprite2D = $Visual
@onready var collision: CollisionShape2D = $Collision

var _has_blue := true


func _ready() -> void:
	add_to_group("colorable")


func has_color() -> bool:
	return _has_blue


## 点击命中：世界坐标点是否落在 Visual 贴图矩形内。
func contains_point(world_pos: Vector2) -> bool:
	return visual.get_rect().has_point(visual.to_local(world_pos))


## 吸收蓝色：返回元素信息，同时冰块破碎放行。
func absorb_color() -> Dictionary:
	if not _has_blue:
		return {"element": "", "color": Color.WHITE, "color_name": ""}
	_has_blue = false
	# 用玩家作为对话来源：本节点破碎后 1.4s 会 queue_free，不能作为 StoryDirector 的 source。
	var talker := get_tree().get_first_node_in_group("player") as Node
	StoryPort.play(talker if talker != null else self, story_cue, story_id)
	_break()
	return {
		"element": "freeze",
		"color": Rules.config("freeze")["color"],
		"color_name": Rules.config("freeze")["color_name"],
		"amount": seed_amount,
	}


## 破碎并放行：先移除碰撞（立刻可通行），再播破碎动画，最后销毁。
func _break() -> void:
	AudioManager.play_ice_break()
	collision.set_deferred("disabled", true)
	var shatter := SHATTER.new()
	shatter.target = visual
	shatter.loop = false
	shatter.seed_value = randf() * 100.0
	add_child(shatter)
	shatter.shatter()
	get_tree().create_timer(shatter_delay).timeout.connect(queue_free)
