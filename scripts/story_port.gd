class_name StoryPort
extends RefCounted
## 事件型剧情端口：Goal / 门 / 拾取 / 破墙等脚本在「关键事件」发生时，
## 只需填 story_cue（主线剧情段落）即可触发对话，排队与去重统一在这里处理。
## 与 DialogueTrigger（位置型：进区域 / 按键）互补，二者都走 StoryDirector 队列。

## 主线剧情文件 prologue.dialogue 的 UID（跟随编辑器移动，不 preload 未导入的文案）。
const PROLOGUE_UID := "uid://cebv03je3jibq"

static var _prologue: DialogueResource


## 懒加载主线剧情资源。
static func prologue() -> DialogueResource:
	if _prologue == null:
		_prologue = load(PROLOGUE_UID) as DialogueResource
	return _prologue


## 播放一段主线剧情。cue 为空、资源缺失、或 story_id 已播过则跳过并返回 false。
## story_id：整局唯一标识（对应 GameState.played_story），留空 = 每次事件都播。
static func play(source: Node, cue: String, story_id: String = "", on_finished: Callable = Callable()) -> bool:
	if cue == "":
		return false
	if story_id != "" and GameState.played_story.has(story_id):
		return false
	var res := prologue()
	if res == null or not res.cues.has(cue):
		return false
	var started := func() -> void:
		if story_id != "":
			GameState.played_story[story_id] = true
	# 同一段剧情若被多个来源同时入队，也只在真正开播时标记一次。
	var can_start := func() -> bool:
		return story_id == "" or not GameState.played_story.has(story_id)
	return StoryDirector.request(source, res, cue, started, on_finished, Callable(), can_start)
