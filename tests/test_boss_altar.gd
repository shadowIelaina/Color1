@tool
extends McpTestSuite
## BossAltar 交互门控：未点亮可点亮，点亮后可再领取一次赐福，领取后不再可交互。

const Altar := preload("res://scripts/boss_altar.gd")


func suite_name() -> String:
	return "boss_altar"


func test_unlit_altar_is_interactable() -> void:
	var a := Altar.new()
	assert_true(a.can_interact(), "未点亮的圣坛应允许跟班交互")
	a.free()


func test_lit_altar_allows_one_reward_claim() -> void:
	var a := Altar.new()
	a.is_open = true
	assert_true(a.can_interact(), "点亮但未领取赐福时应允许第二次交互")
	a.reward_claimed = true
	assert_false(a.can_interact(), "已领取赐福后不应再允许交互")
	a.free()
