# 系统接口文档（v0.1）

> 给关卡 / 实体程序对接用。所有方法名、事件名、常量以此文档为准。
> 全局单例直接用名字访问，例如 `EventBus.emit(...)`、`GameState.flags`。

## 1. Autoload 单例

| 名称 | 作用 | 状态 |
|---|---|---|
| EventBus | 事件总线，模块间通信 | 可用 |
| GameState | 全局运行时状态 | 可用 |
| ColorManager | 颜色系统（调色板 + 语义） | 可用 |
| SaveManager | 存档读写 | 可用 |
| SceneManager | 房间切换 | 接口占位 |
| AudioManager | 音频 | 接口占位 |

## 2. 事件（EventBus）

回调函数接收 **1 个参数**（payload，可为 null）。

```gdscript
EventBus.subscribe("color_applied", _on_color_applied)

func _on_color_applied(payload) -> void:
	var color: Color = payload["color"]
```

### 事件表

| 事件名 | payload | 触发时机 |
|---|---|---|
| `color_selected` | `{ color: Color, color_name: String }` | 切换选中颜色 |
| `color_applied` | `{ target: Node, color: Color, color_name: String }` | 某个 Colorable 被上色成功 |
| `puzzle_solved` | `{ puzzle_id: String }` | 某个谜题完成 |
| `game_state_changed` | `{ key: String, value }` | 全局状态改变 |

## 3. ColorManager

### 颜色语义表

| 颜色名 | 语义 | 常量 |
|---|---|---|
| red | strength（强度） | `ColorManager.RED` |
| blue | stability（稳定） | `ColorManager.BLUE` |
| green | grow（生长/复制） | `ColorManager.GREEN` |
| black | hide（隐藏） | `ColorManager.BLACK` |
| white | reset（重置） | `ColorManager.WHITE` |

### 公开成员

```gdscript
ColorManager.current_color       # 当前选中色
ColorManager.current_color_name  # 当前选中色名（"red" 等）
ColorManager.select_color(color, color_name)
ColorManager.select_color_by_index(index)   # 0~4，对应调色板顺序
ColorManager.get_semantic(color_name)       # 返回 "strength" 等
```

## 4. Colorable 基类

路径：`res://scripts/color/colorable.gd`，`class_name Colorable`，继承 `Node2D`。

### 子类必须覆写

```gdscript
func _on_color_applied(color: Color, color_name: String = "") -> void:
	match color_name:
		"red":
			pass   # 变强
		"blue":
			pass   # 稳定
		"green":
			pass   # 生长/复制
		"black":
			pass   # 隐藏
		"white":
			pass   # 重置
```

### 公开成员

```gdscript
var current_color: Color
var supported_colors: Array[String]   # 该物体支持哪些颜色

func apply_color(color: Color, color_name: String = "") -> bool
func reset_color() -> void
signal color_applied(color: Color)
```

## 5. Puzzle 基类

路径：`res://scripts/puzzle/puzzle.gd`，`class_name Puzzle`，继承 `Node`。

状态机：`INACTIVE → ACTIVE → SOLVED`。

### 子类用法

满足条件后调用 `mark_solved()`，框架会自动发 `solved` 信号和 `puzzle_solved` 事件。

```gdscript
func _on_color_applied(payload) -> void:
	if 满足条件:
		mark_solved()
```

### 公开成员

```gdscript
var puzzle_id: String
var state: int          # INACTIVE / ACTIVE / SOLVED

func activate() -> void
func mark_solved() -> void
func is_solved() -> bool
signal solved(puzzle_id: String)
```

## 6. GameState

```gdscript
GameState.current_room_id: String
GameState.unlocked_colors: Array[String]
GameState.week_count: int
GameState.flags: Dictionary

GameState.set_flag(key, value)
GameState.get_flag(key, default)
GameState.to_dict()          # 打包成可存档字典
GameState.from_dict(data)    # 从存档字典还原
```

## 7. SaveManager

```gdscript
SaveManager.save(data: Dictionary) -> bool
SaveManager.load() -> Dictionary
```

存档只存纯数据，不存节点引用。

## 8. SceneManager（接口占位）

```gdscript
SceneManager.change_room(room_scene: PackedScene)
SceneManager.reload_current_room()
SceneManager.current_room_id
```

> 具体实现等「房间容器 / 出生点 / 玩家归属」约定后再补。

## 9. AudioManager（接口占位）

```gdscript
AudioManager.play_bgm(stream)
AudioManager.play_sfx(stream)
```

## 10. 物理层常量

路径：`res://scripts/core/collision_layers.gd`，`class_name CollisionLayers`。

| 常量 | 值 | 含义 |
|---|---|---|
| `CollisionLayers.PLAYER` | 1 | 玩家 |
| `CollisionLayers.WORLD` | 2 | 墙/地面/障碍 |
| `CollisionLayers.PUSHABLE` | 4 | 可推物体 |
| `CollisionLayers.TRIGGER` | 8 | 交互/判定区域 |
