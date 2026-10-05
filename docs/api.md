# 系统接口文档（v0.3）

> 给关卡 / 实体程序对接用。所有方法名、事件名、常量以此文档为准。
> 全局单例直接用名字访问，例如 `EventBus.emit(...)`、`GameState.inventory`。

## 1. Autoload 单例

| 名称 | 作用 | 状态 |
|---|---|---|
| EventBus | 事件总线，模块间通信 | 可用 |
| GameState | 全局运行时状态（房间/钥匙/机关/颜色进度） | 可用 |
| ColorManager | 颜色系统（调色板 + 语义） | 可用 |
| SaveManager | 存档读写 | 可用 |
| SceneManager | 房间切换 | 可用 |
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
| `colorable_shattered` | `{ target: Node }` | 某个 Colorable 破碎（红→白） |
| `puzzle_solved` | `{ puzzle_id: String }` | 某个谜题完成 |

## 3. 上色反馈接口（涌出/粒子/音效等）

上色成功的**统一入口**是 EventBus 的 `color_applied` 事件。需要做「涌出 / 粒子 / 音效」等反馈的模块，订阅它即可，不要改 `Colorable` 内部。

```gdscript
func _ready() -> void:
    EventBus.subscribe("color_applied", _on_color_applied)
    EventBus.subscribe("colorable_shattered", _on_shattered)

func _on_color_applied(payload) -> void:
    var node: Node2D = payload["target"]
    var color: Color = payload["color"]
    var color_name: String = payload["color_name"]
    # 在 node.global_position 生成涌出/粒子效果

func _on_shattered(payload) -> void:
    var node: Node2D = payload["target"]
    # 在 node.global_position 播放破碎动画/粒子
```

取值约定：

- 位置：`payload["target"].global_position`
- 颜色：`payload["color"]`
- 语义：`ColorManager.get_semantic(payload["color_name"])`

## 4. ColorManager

### 颜色语义表

| 颜色名 | 语义 | 常量 |
|---|---|---|
| red | strength（强度） | `ColorManager.RED` |
| blue | stability（稳定） | `ColorManager.BLUE` |
| green | grow（生长/复制） | `ColorManager.GREEN` |
| black | hide（隐藏） | `ColorManager.BLACK` |
| white | reset（重置） | `ColorManager.WHITE` |

> 调色板在 `ColorManager.PALETTE`（顺序对应数字键 1~5）。新增颜色时往 PALETTE 追加即可，选色键自动扩展。

### 公开成员

```gdscript
ColorManager.current_color       # 当前选中色
ColorManager.current_color_name  # 当前选中色名（"red" 等）
ColorManager.select_color(color, color_name)
ColorManager.select_color_by_index(index)   # 0~4
ColorManager.get_semantic(color_name)       # 返回 "strength" 等
signal color_selected(color: Color, color_name: String)
```

## 5. Colorable 基类

路径：`res://scripts/color/colorable.gd`，`class_name Colorable`，继承 `Node2D`。

### 两种定制方式

| 需求 | 怎么做 |
|---|---|
| 额外反馈（涌出/粒子/音效） | 订阅 `EventBus` 的 `color_applied` / `colorable_shattered`，不改变色 |
| 替换变色本身 | 继承 `Colorable`，覆写 `_on_color_applied` / `_on_reset` |

### 已实现的颜色特性（基类默认行为）

| 颜色 | 行为 |
|---|---|
| 红 red | 记录 `traits["strength"]`；默认 modulate 变红（变硬/重） |
| 蓝 blue | 记录 `traits["stability"]`；默认 modulate 变蓝（敌人/落石据此冻结） |
| 绿 green | 记录 `traits["grow"]`；若 `duplicatable=true` 且之前不是绿，朝玩家方向复制一份 |
| 白 white | 收回该物体复制出的副本；若 `shatterable=true` 且之前是红，则破碎消失 |
| 黑 black | 记录 `traits["hide"]`（隐身表现暂未实现） |

> 敌人/机关通过读 `traits` 来消费特性，例如小鸟 AI 用 `colorable.traits.get("stability", false)` 判断是否冻结。

### 替换变色本身

继承 `Colorable`，只覆写钩子。`apply_color` 仍负责 `current_color`、`supported_colors` 检查、发信号和 EventBus 事件。

```gdscript
class_name MyColorable
extends Colorable

func _on_color_applied(color: Color, color_name: String = "", direction: Vector2 = Vector2.ZERO) -> void:
    # 自定义变色；不要调用 super._on_color_applied()，否则会叠加默认 modulate
    pass

func _on_reset() -> void:
    # 恢复默认外观
    pass
```

真实示例：`res://color_change/colorable_object.gd`（`ColorableObject`）覆写钩子改 Front/Top 多边形颜色。

### 公开成员

```gdscript
@export var supported_colors: Array[String]
@export var duplicatable: bool    # 绿色时是否复制
@export var shatterable: bool     # 红→白是否破碎

var current_color: Color
var current_color_name: String
var previous_color_name: String
var traits: Dictionary            # {"strength": true, "stability": true, ...}

func apply_color(color, color_name = "", direction = Vector2.ZERO) -> bool
func reset_color() -> void
func record_trait(color_name) -> void
func duplicate_in_direction(direction, offset = 32.0) -> Colorable
func shatter() -> void
func _retract_copies() -> void

signal color_applied(color: Color)
```

## 6. Puzzle 基类

路径：`res://scripts/puzzle/puzzle.gd`，`class_name Puzzle`，继承 `Node`。

状态机：`INACTIVE → ACTIVE → SOLVED`。

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

## 7. GameState

```gdscript
# 状态容器
GameState.rooms: Dictionary        # room_id -> RoomMeta
GameState.inventory: Dictionary     # 当前持有钥匙 key_id -> true
GameState.used_keys: Dictionary     # 消耗过的钥匙
GameState.switches: Dictionary      # switch_id -> bool
GameState.abilities: Dictionary     # ability_id -> bool
GameState.current_room_id: String
GameState.current_room: Node
GameState.unlocked_colors: Array[String]   # 已解锁颜色，默认 ["red"]

# 房间
GameState.get_room_meta(room_id) -> RoomMeta
GameState.mark_room_visited(room_id)
GameState.mark_room_cleared(room_id)
GameState.add_item(room_id, item_id)
GameState.has_item(room_id, item_id) -> bool

# 钥匙
GameState.add_key(key_id)
GameState.has_key(key_id) -> bool
GameState.consume_key(key_id) -> bool
GameState.was_key_used(key_id) -> bool

# 开关 / 能力
GameState.set_switch(switch_id, value)
GameState.is_switch_on(switch_id) -> bool
GameState.set_ability(ability_id)
GameState.has_ability(ability_id) -> bool

# 存档
GameState.to_dict()          # 打包成可存档字典
GameState.from_dict(data)    # 从存档字典还原
GameState.reset()            # 清空所有状态

# 信号
item_collected / key_added / key_used / gate_opened / hint / room_state_changed
```

## 8. SaveManager

```gdscript
SaveManager.save(data: Dictionary) -> bool
SaveManager.load() -> Dictionary
```

配合 GameState：

```gdscript
SaveManager.save(GameState.to_dict())
GameState.from_dict(SaveManager.load())
```

## 9. SceneManager

```gdscript
SceneManager.setup(player: Node2D, room_container: Node)
SceneManager.change_room(target_scene: String, target_entrance: String)
SceneManager.is_busy() -> bool
SceneManager.current_room: Node

# 信号
room_changed / room_entered / room_exited
```

## 10. AudioManager（接口占位）

```gdscript
AudioManager.play_bgm(stream)
AudioManager.play_sfx(stream)
```

## 11. 物理层常量

路径：`res://scripts/core/collision_layers.gd`，`class_name CollisionLayers`。

| 常量 | 值 | 含义 |
|---|---|---|
| `CollisionLayers.PLAYER` | 1 | 玩家 |
| `CollisionLayers.WORLD` | 2 | 墙/地面/障碍 |
| `CollisionLayers.PUSHABLE` | 4 | 可推物体 |
| `CollisionLayers.TRIGGER` | 8 | 交互/判定区域 |
| `CollisionLayers.ENEMY` | 16 | 敌人（不挡玩家） |

> 敌人用 `ENEMY` 层，物理上不撞玩家；要检测「敌人碰到玩家」请给敌人加 `Area2D`（mask 指向 `PLAYER`），用 `body_entered` 判定。
