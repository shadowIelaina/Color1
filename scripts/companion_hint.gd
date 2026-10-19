@tool
class_name CompanionHint
extends Node2D
## 跟班提醒点：玩家（带跟班）走进 radius 内，跟班主动说一句 cue。
## 放法：关卡里加一个 Node2D，挂本脚本，填 cue（指向 companion.dialogue 里的 ~ 标题）。
## 默认一次性触发；要在场景里反复提醒可另接逻辑（当前不需要）。

## 对话文件；默认使用跟班文案，也可以拖入另一个 .dialogue 文件。
@export var dialogue_resource: DialogueResource:
	set(value):
		dialogue_resource = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
			update_configuration_warnings()
## 从所选对话文件的段落中选择；空值不触发。
@export var cue: String = "":
	set(value):
		cue = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
## 整局唯一标识（对应 GameState.hints）；填了则整局只播一次，重进场景/读档不再复播。
@export var hint_id: String = ""
## 填钥匙 id：已持有或已用掉该钥匙则不提醒。
@export var required_key_id: String = ""
## 触发距离，以世界像素计算；编辑器中的圆圈显示实际范围。
@export_range(1.0, 4096.0, 1.0, "or_greater") var radius: float = 96.0:
	set(value):
		radius = value
		queue_redraw()

var _triggered := false
var _editor_elapsed := 0.0
var _editor_cues := PackedStringArray()


func _ready() -> void:
	_ensure_dialogue_resource()
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint():
		queue_redraw()
		return
	add_to_group("companion_hint")


func _ensure_dialogue_resource() -> void:
	# 用 UID 跟随编辑器移动，且不在编译期 preload 尚未导入的文案。
	if dialogue_resource == null and ResourceLoader.exists("uid://cs4tg8k8wjy13"):
		dialogue_resource = load("uid://cs4tg8k8wjy13") as DialogueResource


func _process(delta: float) -> void:
	# 对话插件重新导入资源后，刷新段落菜单与配置警告。
	_editor_elapsed += delta
	if _editor_elapsed < 0.5:
		return
	_editor_elapsed = 0.0
	var cues := _available_cues()
	if cues != _editor_cues:
		_editor_cues = cues
		notify_property_list_changed()
		update_configuration_warnings()


func _available_cues() -> PackedStringArray:
	return dialogue_resource.get_cues() if dialogue_resource != null else PackedStringArray()


func _validate_property(property: Dictionary) -> void:
	if property.name == "cue":
		var options := PackedStringArray([""])
		options.append_array(_available_cues())
		# 保留已失效的选择，以便警告提示策划修复，避免悄悄改播其他段落。
		if cue != "" and not options.has(cue):
			options.append(cue)
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(options)


func _get_configuration_warnings() -> PackedStringArray:
	if dialogue_resource == null:
		return PackedStringArray(["请选择对话文件（Dialogue Resource）。"])
	if cue == "":
		return PackedStringArray(["请选择要播放的对话段落（Cue）。"])
	if not _available_cues().has(cue):
		return PackedStringArray(["对话文件中没有段落「%s」，请重新选择 Cue。" % cue])
	return PackedStringArray()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# 运行时使用世界距离，抵消父节点缩放让编辑器预览与实际判定一致。
	if absf(global_transform.determinant()) < 0.00001:
		return
	draw_set_transform_matrix(global_transform.affine_inverse() * Transform2D(0.0, global_position))
	draw_circle(Vector2.ZERO, radius, Color(0.3, 0.85, 1.0, 0.08))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.3, 0.85, 1.0, 0.8), 2.0, true)
	draw_line(Vector2(-12, 0), Vector2(12, 0), Color(0.3, 0.85, 1.0), 2.0)
	draw_line(Vector2(0, -12), Vector2(0, 12), Color(0.3, 0.85, 1.0), 2.0)


func can_trigger() -> bool:
	if dialogue_resource == null or not dialogue_resource.cues.has(cue) or _triggered:
		return false
	if hint_id != "" and GameState.hints.has(hint_id):
		return false
	if required_key_id != "" and (GameState.has_key(required_key_id) or GameState.was_key_used(required_key_id)):
		return false
	return true


func trigger() -> String:
	_triggered = true
	if hint_id != "":
		GameState.hints[hint_id] = true
	return cue
