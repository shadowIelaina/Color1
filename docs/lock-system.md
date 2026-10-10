# 门与锁系统 —— 使用与设计说明

> 面向「加一扇锁门 / 一把钥匙 / 一个道具 / 一个开关」的实操手册，以及框架的维护约定。
> 关与房的层级概念见 [`level-system-usage.md`](level-system-usage.md)，房分区见 [`room-system.md`](room-system.md)。

## 一句话

门的解锁分**两套并列机制**，每扇门通常只用一种：

1. **`unlock_options`（OR 锁）**：`Array[String]`，每条是 `"kind:id"`，**满足任意一条即解锁（OR）**；判定 / 校验在 `scripts/lock_condition.gd`（`LockCondition`）。**不消耗**任何持有物（道具/开关/能力/元素满足即永久）。
2. **`required_key_id`（1:1 钥匙门）**：指向唯一一把钥匙，**开门时消耗销毁**；逻辑与文案在 `scripts/key_lock.gd`（`KeyLock`）。

两者都留空 = 无锁，直接开；同时配置时**钥匙优先**（`level_lint` 会给出提示）。

## 条件模型（unlock_options）

| kind | 含义 | 由谁提供 | 是否消耗 |
| --- | --- | --- | --- |
| `item` | 关键道具 | `item_pickup.gd`（`prop_id`） | 否 |
| `switch` | 开关 | `switch.gd`（`switch_id`） | 否 |
| `ability` | 能力 | `ability_pickup.gd`（`ability_id`） | 否 |
| `element` | 玩家持有元素 | 玩家颜色库（自动同步到 `GameState.elements`） | 否 |

写法：

```
unlock_options = []                                # 无锁，直接可开
unlock_options = ["item:torch"]                    # 需要道具 torch
unlock_options = ["switch:bridge"]                 # 需要开关 bridge 已开
unlock_options = ["ability:dash"]                  # 需要能力 dash
unlock_options = ["element:burn"]                  # 玩家持有「红」即可
unlock_options = ["item:torch", "switch:bridge"]   # 道具 torch 或 开关 bridge，满足其一
```

## 钥匙门（required_key_id，1:1）

一把钥匙开一扇门，**开门时钥匙被消耗销毁**。钥匙与门用 id 一一对应：

- **钥匙**：`scripts/key.gd`（`class_name Key`），结构 `Node2D` + `PickupArea`(Area2D) + `Visual`。字段 `key_id`（唯一键）/ `key_name`（显示名）。碰到即拾取，左上角记录「拾取了钥匙：<名>」，随后从世界消失。
- **门**：`Door` / `RoomDoor` 填 `required_key_id`（= 某把钥匙的 `key_id`）。碰门时：
  - 有钥匙 → 消耗（销毁）该钥匙 + 左上记录「用「<名>」打开了门」→ 开门/传送；
  - 无钥匙 → 居中提示「门锁住了，需要「<名>」」；
  - 门不需要钥匙（`required_key_id` 空）→ 走 `unlock_options` / 无锁逻辑。

钥匙全局携带、**用过不再刷新**（`GameState.used_keys` 记录）；门的开启状态持久化（`Door` → `opened_gates`，`RoomDoor` → `stateful`）。

写法：

```
required_key_id = ""          # 不用钥匙
required_key_id = "silver"    # 需要 key_id 为 silver 的钥匙
```

> 文案集中在 `KeyLock`（`MSG_PICKUP` / `MSG_USE` / `MSG_NEED`），要改文案只改一处。

## 三种通行结构

| | `Door`（关与关之间） | `RoomDoor`（房内物理门） | `OneWayGate`（单向通道） |
| --- | --- | --- | --- |
| 脚本 | `scripts/door.gd` | `scripts/room_door.gd` | `scripts/one_way_gate.gd` |
| 节点 | `Area2D` | `StaticBody2D` | `StaticBody2D` |
| 效果 | `SceneManager.change_room()` 切大场景 | 原地取消碰撞 + 贴图淡出 | 只能朝 `pass_dir` 穿过一次，反向永久封堵 |
| 子节点 | `CollisionShape2D` + 可选 `Visual` | `Visual`/`Collision`/`Trigger`（Trigger 可选） | `Visual`/`Collision` |
| 持久化 | 是（`opened_gates`：解锁后重进此关保持开的判定） | 是（`stateful`：离开再回来保持开） | 否（每次进场重新封堵） |

`Door` / `RoomDoor` 共用字段：

| 字段 | 作用 |
| --- | --- |
| `door_id` | 唯一 id（留空回退为节点名） |
| `required_key_id` | 1:1 钥匙门：需要该 id 的钥匙，开门时消耗销毁；留空 = 不用钥匙 |
| `unlock_options` | 非钥匙 OR 锁条件列表 |
| `unlock_side` | 单向法线，指向**能开的那一侧**；`Vector2.ZERO` = 双向 |
| `starts_open`（RoomDoor） | 开局即开 |
| `block_scale`（RoomDoor） | 自动阻挡区域：阻挡碰撞尺寸 = 门的 `Visual` 宽高 × `block_scale`。`Vector2.ZERO`（默认）= 关闭、用场景里手动配的 `Collision`。用于「点小、区域大」，防止玩家从旁边绕过。 |
| `trigger_pad`（RoomDoor） | 触发区外扩（世界像素，单边）：触发区 = 阻挡区四边各外扩 `trigger_pad`。**放大阻挡后必须 > 0**，否则触发区被阻挡包住，玩家先撞墙、永远进不了触发区 → 门打不开。 |

`Door` 是**出口传送门**：`required_key_id` 与 `unlock_options` 都留空 = 纯传送点，踩上即切场景；填了条件则满足后才传送。
它按「是否可开」做明暗反馈（未满足整体调暗，拿到钥匙/满足条件后恢复正常，开门后淡出），颜色本身不表达额外含义。

## 单向通道（OneWayGate）

`one_way_gate.gd` 是**真正单向**的通道闸（区别于 `unlock_side` 的「单向可开、开后双向通行」）：

- `pass_dir`：允许穿过的方向（单位向量，通常 `(1,0)`/`(-1,0)`/`(0,1)`/`(0,-1)`）。
- 玩家在**入口侧**、对齐门洞并靠近时自动放行；完全穿到**出口侧**后自动重新封堵。
- 从**出口侧**靠近不会开门 → 反向永远走不过去。
- `block_scale`：同 `RoomDoor`，阻挡区按 `Visual` 宽高放大（点保持小）。
- `open_reach` / `close_clearance` 须大于玩家碰撞盒半宽（玩家盒 `128×41`，半宽 64）。
- 不持久化：每次进入大场景都从「封堵」开始。

例：`level_1` 的 `OneWayGate`（橙点 `64×96`，`block_scale=(4,9)` → 阻挡 `256×864`）位于一处 256×768 的门洞，`pass_dir=(1,0)` = 只能从左往右穿过，穿过即封死。

## 放大阻挡区域（防止玩家绕过去）

机关门如果只有 `Visual` 那么小，玩家会从旁边绕过去。给 `RoomDoor` / `OneWayGate` 设 `block_scale` 即可让**阻挡区域按 `Visual` 宽高放大**（点保持小）：

- `block_scale = Vector2(4, 9)` → 阻挡区 = `Visual` 宽高 × (4, 9)。例：`Visual` `64×96` → 阻挡 `256×864`。
- `RoomDoor` 另有 `trigger_pad = 64` → 触发区 = 阻挡区四边各外扩 64px（保证先触发、后撞墙）。

`_apply_region()` 会**新建** `RectangleShape2D` 再赋给 `Collision`（不原地改共享的 shape），所以同一场景里复用同一 `SubResource` 的其它门不会受影响。

## 提供条件的节点

| 条件 | 节点/脚本 | 关键字段 | 结构 |
| --- | --- | --- | --- |
| 钥匙 | `scripts/key.gd` | `key_id` / `key_name` | `Node2D` + `PickupArea`(Area2D) + `Visual` |
| 道具 | `scripts/item_pickup.gd` | `prop_id` | `Node2D` + `PickupArea`(Area2D) + `Visual` |
| 能力 | `scripts/ability_pickup.gd` | `ability_id` | 同上 |
| 开关 | `scripts/switch.gd` | `switch_id` / `toggle` / `one_shot` / `starts_on` | `Area2D` + 可选 `Visual`，碰撞盒用自身 |

钥匙被钥匙门**消耗销毁**（用过不再刷新）；`item`/`ability` 都是「碰到即拾取到 `GameState`」并隐藏自身，永久保留（`unlock_options` 锁不消耗它们）。

> 拾取区约定：`PickupArea` 要覆盖玩家**脚部**碰撞盒（玩家碰撞盒中心约在原点下方 43px），建议矩形 ≥ 128×96 且中心下移到脚部高度，否则玩家走过的同一 y 会漏检。

`switch` 有三种模式：

- `toggle = true`：拉杆，每次进入翻转开/关。
- `toggle = false, one_shot = true`（默认）：锁存触发，进入一次即永久开。
- `toggle = false, one_shot = false`：压力板，站上去开、离开即关。

## 运行时流程与提示

**房内物理门（RoomDoor）**

```
玩家进入 Trigger
  ├─ on_unlock_side 不满足 → 提示「只能从对面开启」
  ├─ required_key_id 已配置：
  │    ├─ 有钥匙 → 消耗销毁 + 左上「用「X」打开了门」 → open()
  │    └─ 无钥匙 → 居中提示「门锁住了，需要「X」」
  └─ 否则：is_met() 满足 → open()；不满足 → 提示「门锁住了」
```

**出口门（Door，切场景）**

```
玩家进入 Area
  ├─ 若已解锁过(GameState.opened_gates) → 直接传送
  ├─ on_unlock_side 不满足 → 提示「只能从对面开启」
  ├─ required_key_id 已配置：
  │    ├─ 有钥匙 → 消耗销毁 + 左上「用「X」打开了门」 → 延迟后切场景
  │    └─ 无钥匙 → 居中提示「门锁住了，需要「X」」
  └─ 否则：unlock_options 为空 → 直接传送
           满足 → 记录已开 + 左上「门被解锁了」 → 延迟后切场景
```

**单向通道（OneWayGate）**

```
每物理帧比较玩家与门的相对位置
  ├─ 入口侧靠近 → 取消碰撞，放行
  ├─ 完全穿到出口侧 → 重新封堵
  └─ 出口侧靠近 → 保持封堵（反向不可入）
```

提示分两处：

- 左上角**瞬时消息行**（`GameState.notice`）：拾取钥匙「拾取了钥匙：<名>」、用钥匙开门「用「<名>」打开了门」、条件解锁「门被解锁了」。
- 左上角**常驻持有行**（HUD `status_label`）：持有的「钥匙：X；道具：Y；能力：Z」，用掉后消失。
- 居中 `GameState.hint`：错误类提示（门锁住、缺钥匙、单向门）。

## 加一扇门：四步

1. 放门：`StaticBody2D` 挂 `room_door.gd`（房内）或 `Area2D` 挂 `door.gd`（切关），填 `door_id`。
2. 给子节点：`Visual`（贴图）、`Collision`（矩形）、可选 `Trigger`。
3. 选一种解锁方式：
   - **钥匙门**：填 `required_key_id`，并在场景里放一把 `key.gd` 的钥匙，`key_id` 与之一致。
   - **条件门**：填 `unlock_options`（如 `["item:torch"]`），并在世界里放对应提供者（道具/能力/开关/元素）。
   - **无锁**：两者都留空。

## 设计约定（维护者看这里）

- **单一事实源（条件锁）**：条件语法 `"kind:id"`、合法 kind 全在 `LockCondition`（`KINDS` / `parse`）。加一种锁 = `KINDS` 加一项 + `GameState.has_flag` 加一个 `match` 分支。
- **单一事实源（钥匙）**：`required_key_id` 的判定/消耗/文案全在 `KeyLock`（`scripts/key_lock.gd`）。改钥匙文案只改 `MSG_*`。
- **状态仍在 GameState**：`LockCondition`/`KeyLock` 都不做状态存储，只调 `GameState.*`。锁的「读」与「写」不能分家。
- **门不含重复逻辑**：`Door` 与 `RoomDoor` 都组合一个 `LockCondition` + 一个 `KeyLock`，不各自实现条件/方向/钥匙判定。
- **提交前体检**：`scripts/tools/level_lint.gd` 复用 `LockCondition.parse` 校验 `unlock_options`，并检查 `switch_id`/`ability_id` 空/重复；钥匙检查 `key_id` 空/重复、同一钥匙被多扇门引用（违反 1:1）、门同时配钥匙与 options。
- **单测**：`tests/test_lock_condition.gd`（条件锁）+ `tests/test_key_lock.gd`（钥匙判定/文案）覆盖纯逻辑。
