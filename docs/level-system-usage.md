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

## 3. 门（三种，复用一个锁模型）

锁模型统一为 `unlock_options`：一个 `String` 数组，每条是 `"kind:id"`，**满足任意一条即开**（OR）。`kind ∈ key / item / switch / ability / element`。留空数组 = 无锁，直接开。

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
| `unlock_options` | 锁条件 OR 列表，如 `["key:bronze","item:torch"]` |
| `unlock_side` | 单向法线（见 §3c） |
| `starts_open` | 开局就开 |
| `consume_on_open` | 开门时消耗钥匙（只消耗 `key` 类，道具/开关/能力/元素不消耗） |
| `open_fade` | 开门淡出时长 |

门是 `stateful` 的：**离开这关再回来，开合状态会保持**（Room 进出场自动 save/restore）。

### 3b. Door —— 关与关之间（切场景出口）

节点：`Area2D` + `door.gd`，可选 `Visual` 子节点（门贴图，锁时发红/可开时发绿）。

| 字段 | 作用 |
|---|---|
| `target_scene` | 目标大场景路径，如 `res://scenes/level_2.tscn` |
| `target_entrance` | 目标场景里 `Entrance.entrance_id`（如 `spawn`） |
| `unlock_options` / `unlock_side` | 同上 |
| `required_key_id` / `consume_key` | **旧字段**（等价 `["key:<id>"]`），新关别用了 |

玩家踩上 → 检查锁 → `SceneManager.change_room(target_scene, target_entrance)` 切关。

### 3c. 单向门（`unlock_side`）

`unlock_side` 是一个**单位向量，指向「能开门的那一侧」**。判定 `(玩家位置 - 门位置).dot(unlock_side) > 0`。

- 出生点门「只能从外面/右边开」→ `unlock_side = Vector2(1, 0)`。
- 只能从左边开 → `Vector2(-1, 0)`。
- `Vector2.ZERO`（默认）= 双向都能开。

`level_1` 里的 `OneWayGate` 是现成例子：`unlock_side = Vector2(1, 0)`，从左边靠近提示「这扇门只能从对面开启」。

---

## 4. 通关触发：Goal

节点：`Area2D` + `goal.gd`，子节点要有个 `Visual`（做脉冲动画）。

| 字段 | 作用 |
|---|---|
| `unlock_door_ids` | 踩上后要开的门 id 列表（匹配 `RoomDoor.door_id`，可多扇 = 分叉/多出口） |
| `is_final` | `true` → HUD「过关！」；`false` → 「门已解锁」 |

流程：踩上 → `RoomEffects.unlock` 遍历当前关内 `room_door` 组、按 `door_id` 匹配并 `open()`，再 `RoomEffects.notify` 给 HUD 反馈。Goal 只管「踩上」这个条件；以后换成元素门/收集门，写个新触发源调同样的 `RoomEffects` 即可。

---

## 5. 钥匙 / 道具 / 元素门

| 节点 | 脚本 | 字段 | 结构 |
|---|---|---|---|
| 钥匙 | `key.gd` | `key_id` | `Node2D` + `PickupArea`(Area2D) + `Visual` |
| 关键道具 | `item_pickup.gd` | `prop_id` | 同上 |

两者都是碰到即拾取进 `GameState`；被消耗的钥匙重进关会重新出现（防软锁）。

锁条件写法：

```
unlock_options = ["key:level2_key"]      # 需要某把钥匙
unlock_options = ["item:torch"]          # 需要某关键道具
unlock_options = ["element:burn"]        # 玩家持有「红」元素即可
unlock_options = ["key:a", "item:b"]     # 钥匙 或 道具，满足其一
```

---

## 6. 完整最小示例（level_1 ↔ level_2 现有接线）

```
scenes/game.tscn                    ← 常驻容器，run/main_scene，不动
  └─ GameContainer (start_room="res://scenes/level_1.tscn", start_entrance="spawn")

scenes/level_1.tscn  (根 Room, room_id="level_1")
  ├─ spawn (Entrance, entrance_id="spawn")
  ├─ … 内容：水/树/箱/冰/陷阱/火种 + DarkRoom(RoomZone, dark=true) …
  ├─ OneWayGate (RoomDoor, unlock_side=(1,0))   ← 房内单向门示例
  └─ to_level_2 (Door, target_scene="res://scenes/level_2.tscn", target_entrance="spawn")

scenes/level_2.tscn  (根 Room, room_id="level_2")
  ├─ spawn (Entrance)
  ├─ level2_key (Key, key_id="level2_key")
  └─ to_level_1 (Door, target_scene="res://scenes/level_1.tscn",
                 unlock_options=["key:level2_key"], consume_key=true)
```

`level_2` 没钥匙时 `to_level_1` 提示「门锁住了」，捡了 `level2_key` 才能开回 `level_1`。

---

## 7. 注意事项 / 坑

- **运行跑 `scenes/game.tscn`（F5）**，不要直接 F6 跑某个 `level_x.tscn`——后者没有 Player/Camera/HUD/Darkness 常驻层。
- **改 `.tscn` 要在编辑器里改**（或先 `force_reload`），否则下次 autosave 用内存态冲掉磁盘手改。
- **切关自动 `HeightMap.clear()`**、玩家先挪到 `SAFE_POS` 防瞬移拾取，关卡侧无需处理。
- **单向门方向别填错**：`unlock_side` 指向「能开的那侧」，不是「挡的那侧」。
- **颜色跨房全局、种子不恢复**：每间房要放自己的元素来源（蓝→冰闸门、红→火种），否则跨房预算会软锁。
- **软锁自查**：`scripts/reachability.gd` 的 `test_graph()` 维护一份关卡图（房/门/钥匙），加关后更新它并跑 `self_test()`。
