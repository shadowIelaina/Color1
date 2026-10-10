@tool
extends McpTestSuite
## LockCondition 单元测试：只覆盖纯逻辑（解析 / 校验 / 描述 / 空锁 / 单向），
## 不触碰 GameState，故可在编辑器内安全运行。

const Lock := preload("res://scripts/lock_condition.gd")


func suite_name() -> String:
	return "lock"


func test_parse_valid() -> void:
	var p := Lock.parse("item:torch")
	assert_eq(p.get("kind"), "item", "kind 应为 item")
	assert_eq(p.get("id"), "torch", "id 应为 torch")


func test_parse_rejects_malformed() -> void:
	assert_true(Lock.parse("torch").is_empty(), "缺冒号应非法")
	assert_true(Lock.parse("item:").is_empty(), "空 id 应非法")
	assert_true(Lock.parse(":torch").is_empty(), "空 kind 应非法")


func test_parse_rejects_unknown_kind() -> void:
	assert_true(Lock.parse("magic:x").is_empty(), "未知 kind 应非法")


func test_kinds_cover_documented_set() -> void:
	for k in ["item", "switch", "ability", "element"]:
		assert_true(Lock.KINDS.has(k), "KINDS 应包含 %s" % k)


func test_empty_options_is_unlocked() -> void:
	var empty: Array[String] = []
	assert_true(Lock.new(empty).is_met(), "空条件 = 无锁，应满足")


func test_invalid_specs_reports_bad_entries() -> void:
	var opts: Array[String] = ["item:a", "bogus", "item:"]
	var bad := Lock.new(opts).invalid_specs()
	assert_eq(bad.size(), 2, "应有 2 条非法")
	assert_true(bad.has("bogus"), "应含 bogus")
	assert_true(bad.has("item:"), "应含 item:")


func test_describe_empty() -> void:
	var empty: Array[String] = []
	assert_eq(Lock.new(empty).describe(), "无锁")


func test_side_zero_is_bidirectional() -> void:
	var empty: Array[String] = []
	assert_true(Lock.new(empty, Vector2.ZERO).on_unlock_side(null, Vector2.ZERO), "零向量应双向可开")


func test_side_directional() -> void:
	var body := Node2D.new()
	body.global_position = Vector2(10, 0)
	track(body)
	var opts: Array[String] = []
	assert_true(Lock.new(opts, Vector2(1, 0)).on_unlock_side(body, Vector2.ZERO), "右侧应可开")
	assert_false(Lock.new(opts, Vector2(-1, 0)).on_unlock_side(body, Vector2.ZERO), "左侧应不可开")
