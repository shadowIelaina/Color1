# 房间系统 —— 关卡结构与使用说明

## 一句话

关卡 = **单个大场景里的多个「房间分区」**：不切场景、不加载，所有房间并排摆在同一张地图里。每间房末尾放一个 `Goal`，玩家踩上即按 `door_id` 解锁下一间房的门。玩家的颜色种子（蓝/红）随单场景**全程全局携带**、跨房间保留。

> 通关标准（目前是「踩上 goal」）与「可选房间/收集门」等方案暂未最终敲定，所以代码把**「通关条件」和「通关效果」拆开了**——以后换标准只加触发源，不改效果逻辑。见文末「未来扩展」。

## 脚本清单

| 脚本 | class_name | 作用 |
| --- | --- | --- |
| `scripts/room_door.gd` | `RoomDoor` | 挡路的门（层 2），被 `open()` 后淡出放行，一次性 |
| `scripts/room_zone.gd` | `RoomZone` | 盖在每间房上的分区，玩家进入即把相机锁到该房范围 |
| `scripts/room_effects.gd` | `RoomEffects` | 通关效果的**统一出口**：开门 + HUD 反馈 |
| `scripts/goal.gd` | `Goal` | 「踩上即通关」这一种触发源 |
| `color_change/hud.gd` | — | HUD 的 `show_hint(text)` / `show_win()` |

## 核心概念

- **门**（`RoomDoor`）：属于 `"room_door"` group，带一个 `door_id`。`open()` 幂等，只开一次。
- **触发源**（`Goal`）：满足自身条件（玩家踏入）后调用 `RoomEffects.unlock/notify`。
- **效果出口**（`RoomEffects`）：所有触发源共用的「开门 + 提示」逻辑。
- **接线 = id 配对**：`Goal.unlock_door_ids` 里填上要开的门的 `door_id` 即可，无需代码。

```
Goal(踩上)  ──解锁──▶  RoomEffects.unlock(ids)  ──▶  打开 door_id 匹配的 RoomDoor
   └────────提示──▶  RoomEffects.notify(is_final, …)  ──▶  HUD
```

## 搭一间房：五步

1. **摆内容 + 末尾放 Goal**：房里放好谜题（水、树、冰闸门…），末尾放一个 `goal.tscn` 实例（或任意 `Area2D` 挂 `goal.gd`）。
2. **放下一间房的门**：两房通道口放 `StaticBody2D`，挂 `room_door.gd`，给两个子节点 `Visual`(Sprite2D 门贴图) + `Collision`(CollisionShape2D 矩形，挡住通道)，并填 `door_id`（如 `"room2_door"`）。
3. **接线**：把上一间房 Goal 的 `unlock_door_ids` 数组里加一项 `"room2_door"`。
4. **盖 RoomZone 锁相机**：在房上放 `Area2D` 挂 `room_zone.gd`，一个矩形 `CollisionShape2D` **框住整间房**（含门洞一侧边界）。可选填 `room_name`。
5. **最后一房勾 `is_final`**：最后一房的 Goal 勾 `is_final = true`（显示「过关！」）；中间房不勾（显示「门已解锁」）。

## 各节点导出字段

**`RoomDoor`**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `door_id` | String | 门 id，Goal 靠它配对 |
| `open_fade` | float | 开门淡出时长（秒，默认 0.3） |

**`Goal`**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `unlock_door_ids` | Array[String] | 触发后要开的门 id 列表，可多扇（分叉/多出口） |
| `is_final` | bool | 最后一房 = true，显示「过关！」 |

**`RoomZone`**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `room_name` | String | 进入时 HUD 顶部短暂提示的房间名 |
| `dark` | bool | 暗房：进入时把全局 CanvasModulate 压暗，靠燃烧/玩家微光照亮 |
| `dark_color` | Color | 暗房底色（默认近黑偏蓝） |
| `light_color` | Color | 亮房/默认底色（白） |
| `fade_time` | float | 明暗渐变时长（秒，默认 0.6） |

## 最小两房示例

```
Node2D (整个大场景)
├─ RoomZone1 (Area2D, room_zone.gd, room_name="第一间", 矩形=房1范围)
├─ … 房1内容：冰闸门(蓝来源)、水、树 …
├─ Goal1 (goal.gd, unlock_door_ids=["door2"])
├─ Door2 (StaticBody2D, room_door.gd, door_id="door2")   ← 房1→房2通道
│   ├─ Visual (Sprite2D)
│   └─ Collision (CollisionShape2D)
├─ RoomZone2 (Area2D, room_zone.gd, 矩形=房2范围)
├─ … 房2内容 …
├─ Goal2 (goal.gd, is_final=true)   ← 最后一房
└─ HUD / Player(带 Camera2D)
```

## 注意事项

1. **相机必须可用**：玩家身上的 `Camera2D` 要 `enabled`（当前 `scenes/game.tscn` 已是）。`RoomZone` 只是改它的 `limit_left/top/right/bottom`。
2. **RoomZone 别缩放/旋转**：用矩形碰撞盒算边界，需轴对齐、scale=1。
3. **颜色跨房全局**：蓝/红全程带着、种子用掉就没了。**每间房要放自己的元素来源**（需要蓝就在房里放冰闸门、需要红就放火种），否则跨房预算会软锁。
4. **门是一次性的**：开了不关。玩家可自由回退到前面的房间（对回头取资源有用）。
5. **「上锁的门」可用元素当门**：下一间门口放一片水（冻了才过）或一棵树（烧了才通），与 `RoomDoor` 混用不冲突。

## 可选房间 / 分叉

- **侧房** = 从主线门洞岔出去的一条死路，里面一个可选谜题 + 奖励，出口**常开**（不摆门，直接走回来）。
- **奖励** = 额外颜色种子来源（多一块冰闸门 = 更多蓝、多一个火种 = 更多红）。
- **分叉**：一个 Goal 的 `unlock_door_ids` 里填多扇门，就能同时开多个方向。

## 暗房（黑暗关卡）

把某间房做成暗房 = 给它的 `RoomZone` 勾 `dark = true`（可选改 `dark_color`）。玩家进入时全局暗房遮罩 `DarknessOverlay` 变暗，只有光源能照亮：

- **玩家微光**（自动）：自带一圈小光，能看清自己和脚边。
- **燃烧发光**：给可燃物（树/木条）赋予「红」→ 持续燃烧照亮一片；吸收红熄灭（物体不销毁），燃烧中加蓝才销毁。

所以暗房要**放火种（Ember）**当红色来源；暗房遮罩 `DarknessOverlay` 已在 `scenes/game.tscn` 里，无需手动加。

> 完整参数与调光见 [`lighting.md`](lighting.md)。

## 未来换通关标准（触发源约定）

目前「通关」= 玩家踩上 Goal。将来要换成元素门 / 收集门时，**效果逻辑一行不用动**：

1. 写一个新的触发源脚本（例如 `ColorGate`：被赋予足够颜色就触发）。
2. 它满足条件后，调**同样的** `RoomEffects.unlock(self, ids)` + `RoomEffects.notify(self, is_final, did_unlock)`。

`RoomEffects` 就是为此抽出来的「通关效果统一出口」。

## 与场景切换（关）的关系

`rooms/room_a.tscn`/`room_b.tscn`（旧多房间示例）已于 2026-10-09 删除。现在 `scenes/game.tscn`（常驻容器）+ `SceneManager`/`GameState` 承载「关（大场景）」的切换与持久化；本房间系统（`RoomZone`/`RoomDoor`/`Goal`）在单个大场景内部做「房」的分区，两者正交、互不冲突。
