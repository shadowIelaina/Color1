class_name LockCondition
extends RefCounted
## 统一锁模型：把门/闸的「条件判定、单向开锁、校验」集中到一处。
##
## 锁条件是一串 "kind:id"（kind ∈ item/switch/ability/element），**满足任意一条即解锁**（OR）。
##   ["item:torch"]                需要关键道具 torch
##   ["item:torch", "switch:bridge"]  道具 torch 或 开关 bridge，满足其一
##   []                            无锁，直接可开
##
## Door（切场景出口）与 RoomDoor（房内物理门）都组合一个 LockCondition，
## 避免各自重复实现条件/方向逻辑；level_lint 与测试也复用同一份 KINDS/parse，杜绝口径漂移。
##
## 状态读写仍由 GameState 单一负责（meets_flag），本类只管「条件列表的语义」。
## 注：锁不消耗任何持有物（道具/开关/能力/元素满足即永久生效）。

const KIND_ITEM := "item"
const KIND_SWITCH := "switch"
const KIND_ABILITY := "ability"
const KIND_ELEMENT := "element"
## 合法条件类型。新增一种锁 = 这里加一项 + GameState.has_flag 加一个分支。
const KINDS: Array[String] = [KIND_ITEM, KIND_SWITCH, KIND_ABILITY, KIND_ELEMENT]

## 条件列表（"kind:id"，OR）。
var options: Array[String] = []
## 单向法线：指向「能开的那一侧」；Vector2.ZERO = 双向都能开。
var side := Vector2.ZERO


func _init(p_options: Array[String] = [], p_side := Vector2.ZERO) -> void:
	options = p_options
	side = p_side


## 解析 "kind:id" → {kind, id}；格式非法或 kind 未知返回 {}。
static func parse(spec: String) -> Dictionary:
	var i := spec.find(":")
	if i <= 0 or i >= spec.length() - 1:
		return {}
	var kind := spec.substr(0, i)
	if not KINDS.has(kind):
		return {}
	return {"kind": kind, "id": spec.substr(i + 1)}


static func is_valid(spec: String) -> bool:
	return not parse(spec).is_empty()


## 条件是否满足：空列表 = 无锁，直接可开；否则满足任意一条即 true。
func is_met() -> bool:
	if options.is_empty():
		return true
	for opt in options:
		if GameState.meets_flag(opt):
			return true
	return false


## 玩家是否在可开的一侧（side 为零向量 = 双向都能开）。
func on_unlock_side(body: Node2D, door_pos: Vector2) -> bool:
	if side == Vector2.ZERO:
		return true
	return (body.global_position - door_pos).dot(side) > 0.0


## 返回所有格式非法的 "kind:id"（供 level_lint / 体检使用）。
func invalid_specs() -> Array[String]:
	var bad: Array[String] = []
	for opt in options:
		if not is_valid(opt):
			bad.append(opt)
	return bad


## 人类可读描述（供 HUD / 调试 / 日志）。
func describe() -> String:
	if options.is_empty():
		return "无锁"
	var parts: Array[String] = []
	for opt in options:
		var p := parse(opt)
		if p.is_empty():
			parts.append(opt)
		else:
			parts.append("%s:%s" % [p["kind"], p["id"]])
	return " 或 ".join(parts)
