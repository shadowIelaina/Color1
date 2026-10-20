class_name BaoXiang
extends StatefulObject
## 宝箱：玩家鼠标在工作圈内悬停到宝箱上时点左键，小跟班飞过来打开宝箱，
## 关闭图层切到开启图层，并掉落一件物品（默认钥匙）。开启后不可重复触发。
## 开启状态持久化；若掉落的物品未被拾取，重进房间时会重新掉落（避免物品丢失）。
##
## 结构：Node2D（本脚本）+ Open/Close（两张 Sprite2D 图层）+ Area2D/CollisionShape2D（交互碰撞盒）。
## 命中检测用 CollisionShape2D 的矩形（世界坐标），不依赖 Area2D 的 body_entered 信号。

@onready var open_sprite: Sprite2D = $Open
@onready var close_sprite: Sprite2D = $Close
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D

@export_group("Drop")
## 开箱掉落的物品场景（默认钥匙）。留空 = 不掉落。
@export var drop_scene: PackedScene = preload("res://prefabs/items/interaction/key.tscn")
## 掉落物的唯一 id：钥匙=key_id、道具=prop_id、能力=ability_id。留空则用物品节点名。
@export var drop_id: String = ""
## 掉落物显示名；留空沿用物品自身配置。
@export var drop_name: String = ""
## 掉落物的拾取说明；留空沿用物品自身配置。
@export_multiline var drop_description: String = ""
## 掉落物相对宝箱的出生落点（世界坐标，y 向下，掉到宝箱脚边）。
@export var drop_offset: Vector2 = Vector2(0, 90)

## 是否已开启（公开给玩家做命中过滤，避免对已开宝箱重复派遣跟班）。
var is_open := false


func _ready() -> void:
	super._ready()
	add_to_group("chest")
	_refresh()


## 关闭/开启图层切换。
func _refresh() -> void:
	close_sprite.visible = not is_open
	open_sprite.visible = is_open


## 由小跟班飞过来时调用：打开宝箱并掉落物品（幂等，已开则不做任何事）。
func interact() -> void:
	if is_open:
		return
	is_open = true
	_refresh()
	var base_scale := open_sprite.scale
	open_sprite.scale = base_scale * Vector2(1.08, 0.9)
	var opening := create_tween()
	opening.tween_property(open_sprite, "scale", base_scale, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_drop()


## 玩家鼠标命中检测：点是否落在宝箱交互碰撞盒内（世界坐标，忽略旋转缩放）。
func contains_point(point: Vector2) -> bool:
	var shape := collision_shape.shape as RectangleShape2D
	if shape == null:
		return false
	var half := shape.size * 0.5
	var d := point - collision_shape.global_position
	return absf(d.x) <= half.x and absf(d.y) <= half.y


## —— 掉落物 ——

func _spawn_drop() -> void:
	if drop_scene == null:
		return
	var item := drop_scene.instantiate() as Node2D
	if item == null:
		push_warning("BaoXiang '%s' 的 drop_scene 无法实例化为 Node2D" % name)
		return
	_configure_drop(item)
	item.position = get_parent().to_local(global_position)
	get_parent().add_child(item)
	_pop_drop(item)


## 把 drop_id / drop_name 填到对应拾取脚本的字段上（必须在 add_child 触发 _ready 之前完成）。
func _configure_drop(item: Node2D) -> void:
	# 文案独立于唯一 ID，自动生成 ID 的心之容器也能使用宝箱上的设置。
	if item is KeyItem:
		if drop_name != "": item.key_name = drop_name
		if drop_description != "": item.item_description = drop_description
	elif item is ItemPickup:
		if drop_name != "":
			item.item_name = drop_name
			if item is HeartPickup: item.display_name = drop_name
		if drop_description != "": item.item_description = drop_description
	if item is HeartPickup and drop_id == "":
		item.prop_id = _heart_drop_id()
		return
	if drop_id == "":
		return
	if item is KeyItem:
		item.key_id = drop_id
		if drop_name != "":
			item.key_name = drop_name
	elif item is ItemPickup:
		item.prop_id = drop_id
	elif item is AbilityPickup:
		item.ability_id = drop_id


## 掉落物从宝箱中心弹出到落点，scale 从小到大（back 回弹）。
func _pop_drop(item: Node2D) -> void:
	var start := global_position
	var end := global_position + drop_offset
	item.global_position = start
	var base_scale := item.scale
	item.scale = base_scale * 0.4
	var tween := create_tween().set_parallel(true)
	tween.tween_method(func(t: float): item.global_position = start.lerp(end, t) + Vector2(0, -sin(t * PI) * 110), 0.0, 1.0, 0.4)
	tween.tween_property(item, "scale", base_scale, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## —— 持久化 ——

func save_state() -> Dictionary:
	return {"open": is_open}


func restore_state(data: Dictionary) -> void:
	is_open = bool(data.get("open", false))
	_refresh()
	# 已开启但掉落物还没被捡走（离开房间时没拿）：重新掉落一次，避免物品永久丢失。
	if is_open and not _drop_claimed():
		_spawn_drop()


## 掉落物是否已被拾取/消耗（已捡走，或钥匙已用掉，就不再重复掉落）。
func _drop_claimed() -> bool:
	if drop_id == "":
		if drop_scene != null:
			var sample := drop_scene.instantiate()
			var is_heart := sample is HeartPickup
			sample.free()
			if is_heart:
				return GameState.has_prop(_heart_drop_id())
		return true
	return GameState.has_key(drop_id) or GameState.was_key_used(drop_id) \
		or GameState.has_prop(drop_id) or GameState.has_ability(drop_id)


func _heart_drop_id() -> String:
	return "heart:%s" % get_path()
