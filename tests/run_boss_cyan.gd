extends SceneTree
## CLI entry: godot --headless --path . --script tests/run_boss_cyan.gd

func _initialize() -> void:
	var runner := McpTestRunner.new()
	var suite := preload("res://tests/test_boss_cyan.gd").new()
	runner.run_suite(suite)
	var result := runner.get_results(true)
	print("BOSS_CYAN_RESULTS: ", JSON.stringify(result))
	quit(0 if result.failed == 0 else 1)
