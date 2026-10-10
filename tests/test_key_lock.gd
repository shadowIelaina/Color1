@tool
extends McpTestSuite
## KeyLock 单元测试：只覆盖纯逻辑（是否需要钥匙 / 判定 / 文案），
## 不触碰 GameState，故可在编辑器内安全运行。

const KeyLockScript := preload("res://scripts/key_lock.gd")


func suite_name() -> String:
	return "key"


func test_decide_not_needed() -> void:
	assert_eq(KeyLockScript.decide("", false), KeyLockScript.Result.NOT_NEEDED, "未配置钥匙 = 不需要")
	assert_eq(KeyLockScript.decide("", true), KeyLockScript.Result.NOT_NEEDED, "未配置钥匙恒为不需要")


func test_decide_unlocked() -> void:
	assert_eq(KeyLockScript.decide("silver", true), KeyLockScript.Result.UNLOCKED, "持有钥匙应可解锁")


func test_decide_no_key() -> void:
	assert_eq(KeyLockScript.decide("silver", false), KeyLockScript.Result.NO_KEY, "缺钥匙应返回 NO_KEY")


func test_needed_flag() -> void:
	assert_true(KeyLockScript.new("silver").needed(), "配置了钥匙应 needed")
	assert_false(KeyLockScript.new("").needed(), "未配置钥匙不应 needed")


func test_pickup_message() -> void:
	assert_eq(KeyLockScript.pickup_message("银钥匙"), "拾取了钥匙：银钥匙", "拾取文案")


func test_use_message() -> void:
	assert_eq(KeyLockScript.use_message("银钥匙"), "用「银钥匙」打开了门", "使用文案")


func test_need_message() -> void:
	assert_eq(KeyLockScript.need_message("银钥匙"), "门锁住了，需要「银钥匙」", "缺钥匙文案")
