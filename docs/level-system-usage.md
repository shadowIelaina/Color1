# 关卡系统使用手册

> 生成于 2026-10-09。字段名均按当前代码核过。
> 配套总览见 [`systems-inventory.md`](systems-inventory.md)，暗房见 [`lighting.md`](lighting.md)，房间分区见 [`room-system.md`](room-system.md)。

## 0. 先分清两个概念（最容易混）

| 层级 | 载体 | 切不切场景 | 用什么门 |
|---|---|---|---|
| **关**（大场景） | 一个 `.tscn`，根挂 `room.gd` | **切**（SceneManager 卸载/加载） | `door.gd`（SceneExit，Area2D） |
| **房**（房间分区） | 同一关 `.tscn` 内的一个 `RoomZone` | **不切**，只是锁相机/压暗房 | `room_door.gd`（物理门，StaticBody2D 原地开） |

一句话：**关内分房用 RoomZone + RoomDoor，关与关之间用 Door。**

---

## 1. 新建一关（最小步骤）

1. 编辑器新建场景，根节点选 `Node2D`，改名（如 `Level3`）。
2. 根挂脚本 `scripts/room.gd`，设 `room_id = "level_3"`（不填则用节点名）。
3. 放一个入口：`Marker2D` 挂 `scripts/entrance.gd`，`entrance_id = "spawn"`。
4. 铺关卡内容（TileMapLayer 地面、机关、可上色物等）。
5. 若要通往下一关：放一个 `Area2D` 挂 `scripts/door.gd`（见 §3b）。
6. 存到 `scenes/level_3.tscn`。

关的根（`Room`）不用写任何逻辑，它自动负责进出场标记、相机边界、遍历 `stateful` 组存/读状态。

`Room` 字段：`room_id` / `start_entrance` / `camera_limits`（Rect2，大场景兜底相机边界）/ `y_sort_on`（默认 true）。

---

## 2. 房分区（RoomZone）

在每个「房」上盖一个 `Area2D` + `room_zone.gd`，子节点放一个**矩形 `CollisionShape2D` 框住整间房**：

| 字段 | 作用 |
|---|---|
| `room_name` | 进入时 HUD 顶部短暂显示房名（留空不显示） |
| `dark` | `true` = 暗房，进入压黑、靠燃烧/玩家微光照亮 |
| `fade_time` | 明暗渐变时长（默认 0.6s） |

约定：RoomZone 与碰撞盒**不缩放、不旋转**（轴对齐矩形，脚本靠矩形尺寸算相机边界）。玩家一进入就把相机锁到本房，走到下一间由下一间接管。

---

## 3. 门

门的解锁分**两套并列机制**，每扇门通常只用一种：

- `required_key_id`（**1:1 钥匙门**）：需要一把对应钥匙，**开门即消耗销毁**（见 §3e）。
- `unlock_options`（**条件 OR 锁**）：`String` 数组，每条是 `"kind:id"`，**满足任意一条即开**（OR），`kind ∈ item / switch / ability / element`；满足即永久、**不消耗**。

两者都留空 = 无锁，直接开；同时配置时**钥匙优先**。

### 3a. RoomDoor —— 房与房之间（原地开，不切场景）

节点：`StaticBody2D` + `room_door.gd`。**子节点**：

```
RoomDoor (StaticBody2D + room_door.gd)
├─ Visual     (CanvasItem，门贴图)       ← 开门时淡出
├─ Collision  (CollisionShape2D，矩形)   ← 挡路，开门时禁用
└─ Trigger    (Area2D，检测玩家靠近)      ← 可选；没有就只能被 Goal 程序 open()
```

| 字段 | 作用 |
|---|---|
| `door_id` | 唯一 id，供 `Goal.unlock_door_ids` 匹配 |
| `required_key_id` | 1:1 钥匙门：需要该 id 的钥匙，开门时消耗销毁；留空 = 不用钥匙 |
| `unlock_options` | 条件 OR 列表，如 `["item:torch","switch:bridge"]` |
| `unlock_side` | 单向法线（见 §3c） |
| `starts_open` | 开局就开 |
| `open_fade` | 开门淡出时长 |

门是 `stateful` 的：**离开这关再回来，开合状态会保持**（Room 进出场自动 save/restore）。

### 3b. Door —— 关与关之间（切场景出口）

节点：`Area2D` + `door.gd`，可选 `Visual` 子节点（门贴图，未满足锁时整体调暗，可开后恢复正常）。

| 字段 | 作用 |
|---|---|
| `target_scene` | 目标大场景路径，如 `res://scenes/level_2.tscn` |
| `target_entrance` | 目标场景里 `Entrance.entrance_id`（如 `spawn`） |
| `required_key_id` | 1:1 钥匙门（见 §3e）；留空 = 不用钥匙 |
| `unlock_options` / `unlock_side` | 条件锁 / 单向（同上）；全留空 = 纯传送点 |

玩家踩上 → 检查锁（无锁直接传送）→ `SceneManager.change_room(target_scene, target_entrance)` 切关。

### 3c. 单向可开（`unlock_side`）

`unlock_side` 是一个**单位向量，指向「能开门的那一侧」**。判定 `(玩家位置 - 门位置).dot(unlock_side) > 0`。

- 出生点门「只能从外面/右边开」→ `unlock_side = Vector2(1, 0)`。
- 只能从左边开 → `Vector2(-1, 0)`。
- `Vector2.ZERO`（默认）= 双向都能开。

注意：这控制的是「从哪侧能**开**」，门一旦打开即双向通行。若要真正只能朝一个方向穿过，用 §3d。

### 3d. 真正单向通道（`OneWayGate`）

节点：`StaticBody2D` + `one_way_gate.gd`。子节点 `Visual`（橙点贴图）+ `Collision`（矩形）。

| 字段 | 作用 |
|---|---|
| `pass_dir` | 允许穿过的方向（单位向量，如 `Vector2(1, 0)`） |
| `block_scale` | 阻挡区 = `Visual` 宽高 × 此值（`Vector2.ZERO` = 用手配的 `Collision`） |
| `open_reach` / `close_clearance` | 入口探测距离 / 穿过后重新封堵的余量（须 > 玩家碰撞盒半宽 64） |

玩家只能沿 `pass_dir` 穿过一次：从入口侧靠近自动放行，穿到出口侧后自动封堵；从出口侧靠近不开门 → 反向进不去。

`level_1` 里的 `OneWayGate` 是现成例子：`pass_dir = Vector2(1, 0)`（只能从左往右过）。

### 3e. 钥匙门（`required_key_id`，1:1）

一把钥匙开一扇门，**开门时钥匙被消耗销毁**。

- **钥匙**：`Node2D` 挂 `key.gd`，子节点 `PickupArea`(Area2D) + `Visual`。字段 `key_id`（唯一键，门的 `required_key_id` 与之一致）/ `key_name`（显示名）。
- 碰钥匙 → 左上记录「拾取了钥匙：<名>」，钥匙从世界消失（**用过不再刷新**）。
- 碰钥匙门 → 有钥匙：消耗销毁 + 左上「用「<名>」打开了门」+ 开门/传送；无钥匙：居中提示「门锁住了，需要「<名>」」。
- 门的开启状态持久化：`Door` 记 `opened_gates`，`RoomDoor` 走 `stateful`。

> 钥匙与门**一一对应**；`level_lint` 会检查同一钥匙是否被多扇门引用、门是否同时配了钥匙与 `unlock_options`。文案集中在 `KeyLock`。

---

## 4. 通关触发：Goal

节点：`Area2D` + `goal.gd`，子节点要有个 `Visual`（做脉冲动画）。

| 字段 | 作用 |
|---|---|
| `unlock_door_ids` | 踩上后要开的门 id 列表（匹配 `RoomDoor.door_id`，可多扇 = 分叉/多出口） |
| `is_final` | `true` → HUD「过关！」；`false` → 「门已解锁」 |

流程：踩上 → `RoomEffects.unlock` 遍历当前关内 `room_door` 组、按 `door_id` 匹配并 `open()`，再 `RoomEffects.notify` 给 HUD 反馈。Goal 只管「踩上」这个条件；以后换成元素门/收集门，写个新触发源调同样的 `RoomEffects` 即可。

---

## 5. 钥匙 / 道具 / 能力 / 开关 / 元素门

| 节点 | 脚本 | 字段 | 结构 |
|---|---|---|---|
| 钥匙 | `key.gd` | `key_id` / `key_name` | `Node2D` + `PickupArea`(Area2D) + `Visual` |
| 关键道具 | `item_pickup.gd` | `prop_id` | 同上 |
| 能力 | `ability_pickup.gd` | `ability_id` | 同上 |
| 开关 | `switch.gd` | `switch_id` / `toggle` / `one_shot` / `starts_on` | `Area2D` + 可选 `Visual` |

钥匙被钥匙门消耗销毁（见 §3e）；道具/能力碰到即拾取进 `GameState`，永久保留；开关是触发区，玩家进入即置位（模式见 [`lock-system.md`](lock-system.md)）。`unlock_options` 锁不消耗任何持有物。

锁条件写法（`LockCondition` 统一模型，详见 [`lock-system.md`](lock-system.md)）：

```
unlock_options = ["item:torch"]          # 需要某关键道具
unlock_options = ["ability:dash"]        # 需要某能力
unlock_options = ["switch:bridge"]       # 需要某开关已开
unlock_options = ["element:burn"]        # 玩家持有「红」元素即可
unlock_options = ["item:torch", "switch:bridge"]  # 道具 或 开关，满足其一
```

---

## 6. 完整最小示例（level_1 ↔ level_2 现有接线）

```
scenes/game.tscn                    ← 常驻容器，run/main_scene，不动
  └─ GameContainer (start_room="res://scenes/level_1.tscn", start_entrance="spawn")

scenes/level_1.tscn  (根 Room, room_id="level_1")
  ├─ spawn (Entrance, entrance_id="spawn")
  ├─ … 内容：水/树/箱/冰/陷阱/火种 + DarkRoom(RoomZone, dark=true) …
  ├─ OneWayGate (OneWayGate, pass_dir=(1,0))   ← 真正单向通道示例
  └─ to_level_2 (Door, target_scene="res://scenes/level_2.tscn", target_entrance="spawn")

scenes/level_2.tscn  (根 Room, room_id="level_2")
  ├─ spawn (Entrance)
  └─ to_level_1 (Door, target_scene="res://scenes/level_1.tscn", target_entrance="spawn")
```

两个出口门均无锁：`level_1` 的 `to_level_2` 与 `level_2` 的 `to_level_1` 都是纯传送点，踩上即切关。

---

## 7. 注意事项 / 坑

- **运行跑 `scenes/game.tscn`（F5）**，不要直接 F6 跑某个 `level_x.tscn`——后者没有 Player/Camera/HUD/Darkness 常驻层。
- **改 `.tscn` 要在编辑器里改**（或先 `force_reload`），否则下次 autosave 用内存态冲掉磁盘手改。
- **切关自动 `HeightMap.clear()`**、玩家先挪到 `SAFE_POS` 防瞬移拾取，关卡侧无需处理。
- **单向方向别填错**：`unlock_side` 指向「能开的那侧」（不是挡的那侧）；`OneWayGate.pass_dir` 指向「允许穿过的方向」。
- **颜色跨房全局、种子不恢复**：每间房要放自己的元素来源（蓝→冰闸门、红→火种），否则跨房预算会软锁。
- **软锁自查**：`scripts/reachability.gd` 的 `test_graph()` 维护一份关卡图（房/门），加关后更新它并跑 `self_test()`。
