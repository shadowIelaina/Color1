class_name KeyLock
extends RefCounted
## 1:1 钥匙锁：一把钥匙开一扇门，开门时钥匙被「消耗销毁」。
##
## 与 unlock_options（道具/开关/能力/元素的 OR 锁，满足即永久）是两套并列机制：
##   - 钥匙门：门填 required_key_id，指向唯一 Key.key_id；开门即消耗该钥匙。
##   - 其它锁：门填 unlock_options。
## 一扇门通常只选一种；同时配置时钥匙优先（level_lint 会给出提示）。
##
## 本类集中「是否需要钥匙 / 纯判定 / 消耗 / 全部提示文案」，Door 与 RoomDoor 共用，
## 避免各自重复实现，也让钥匙相关文案只有一处来源。状态读写仍由 GameState 负责。

enum Result { NOT_NEEDED, UNLOCKED, NO_KEY }

## 钥匙系统全部文案（单一来源）。
const MSG_PICKUP := "拾取了钥匙：%s"
const MSG_USE := "用「%s」打开了门"
const MSG_NEED := "门锁住了，需要「%s」"

## 需要的钥匙 id（空 = 这扇门不用钥匙）。
var required_key_id: String


func _init(p_required_key_id: String = "") -> void:
	required_key_id = p_required_key_id


## 这扇门是否配置了钥匙。
func needed() -> bool:
	return required_key_id != ""


## 纯判定（不碰 GameState，便于单测）：给定「是否持有钥匙」返回结果。
static func decide(required_id: String, has_key: bool) -> Result:
	if required_id == "":
		return Result.NOT_NEEDED
	return Result.UNLOCKED if has_key else Result.NO_KEY


static func pickup_message(key_name: String) -> String:
	return MSG_PICKUP % key_name


static func use_message(key_name: String) -> String:
	return MSG_USE % key_name


static func need_message(key_name: String) -> String:
	return MSG_NEED % key_name


## 执行一次开锁尝试：
##   无钥匙   → 发居中提示并返回 NO_KEY（门不应打开）；
##   有钥匙   → 消耗（销毁）该钥匙、发左上消息并返回 UNLOCKED；
##   未配置钥匙 → NOT_NEEDED（不发任何消息，门走自己的逻辑）。
func try_unlock() -> Result:
	var r := decide(required_key_id, GameState.has_key(required_key_id))
	match r:
		Result.NO_KEY:
			GameState.hint.emit(need_message(GameState.key_display(required_key_id)))
		Result.UNLOCKED:
			GameState.consume_key(required_key_id)
			GameState.notice.emit(use_message(GameState.key_display(required_key_id)))
	return r
