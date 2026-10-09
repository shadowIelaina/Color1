# 关卡搭建 / 物品摆放手册

> 摆物品的「少踩坑」指南。系统字段详见 [`level-system-usage.md`](level-system-usage.md)，房分区见 [`room-system.md`](room-system.md)，体检见 [`level_lint.gd`](../scripts/tools/level_lint.gd)。

## 0. 网格吸附（先做一次）

tile 是 **256px**，物品手拖容易对不齐。在 2D 视图顶部工具栏 →「Transform」→ 打开**网格吸附**，并把吸附网格设成 **256×256**（半格用 128）。这样树/草/箱/陷阱落地即对齐，不用手补坐标。

> 吸附是编辑器全局偏好（存在用户目录，不进 git），所以这里只记录步骤，不能随项目提交。

## 1. 命名规范

- 同类型多件：`<类型>_<两位序号>`，如 `Tree_01`、`Grass_01`、`Trap_01`、`Ember_01`。
- 系统/功能节点用语义名：`spawn`、`to_level_2`、`OneWayGate`、`DarkRoom`。
- **别用** Ctrl+D 复制产生的自动编号名（`Tree2` / `Tree12` / `Tree5` 这种乱序名），看不出谁是谁。

## 2. 物品清单 & 要配的字段

| prefab / 节点 | 脚本 | 需配字段 |
|---|---|---|
| `tree.tscn` | `colorable_static` | 无（可选 `light_radius`/`light_offset` 做光源） |
| `grass_1.tscn` | `Grass.gd` | 无 |
| `grass_big.tscn` | — | 无 |
| `box.tscn` | `pushable_box` | 无 |
| `ice_block.tscn` / `ice_wall.tscn` | `ice_block` | 无 |
| `ember.tscn` | `ember` | `seed_amount`（默认 3） |
| `trap.tscn` | `trap` | `fire_interval` / `aim_at_player` / `fixed_direction` |
| `goal.tscn` | `goal` | `unlock_door_ids` / `is_final` |
| 自建 `StaticBody2D` | `room_door` | `door_id` / `unlock_options` / `unlock_side` |
| 自建 `Area2D` | `door` | `target_scene` / `target_entrance` / `unlock_options` |
| `Marker2D` | `entrance` | `entrance_id` |
| 自建 `Area2D` | `room_zone` | `room_name` / `dark` |
| 自建 `Node2D` | `key` | `key_id` |
| 自建 `Node2D` | `item_pickup` | `prop_id` |

## 3. 接线清单（id 配对，最容易错）

| 关系 | 配对 |
|---|---|
| Goal 开哪扇门 | `Goal.unlock_door_ids` → `RoomDoor.door_id`（**同场景**） |
| 切关落在哪 | `Door.target_entrance` → 目标场景里的 `Entrance.entrance_id` |
| 钥匙锁 | `unlock_options=["key:xxx"]` → 某处 `Key.key_id` |
| 道具锁 | `unlock_options=["item:xxx"]` → 某处 `ItemPickup.prop_id` |
| 元素锁 | `unlock_options=["element:burn"/"freeze"/"grow"]` |

`unlock_options` 是 **OR** 列表，满足任意一条即开；留空 = 无锁直接开。

## 4. 搭一间房（最短流程）

1. 画地面/水 `TileMapLayer`。
2. 摆内容：树、草、箱、冰、火种、陷阱……（网格吸附 + 规范命名）。
3. 末尾放 `Goal`，填 `unlock_door_ids`。
4. 通道口放 `RoomDoor`，填 `door_id`。
5. 盖 `RoomZone` 锁相机（暗房勾 `dark`）。
6. 最后一房 `Goal` 勾 `is_final = true`。

## 5. 摆完跑一遍体检

`scripts/tools/level_lint.gd`：FileSystem 里选中 → 右键 → **Run**（或 Ctrl+Shift+X）。
把「错误」清零；「警告/提示」逐条确认是否有意。

## 6. 常见坑（浓缩）

- 跑 **`scenes/game.tscn`（F5）**，别直接 F6 跑 `level_x.tscn`（后者没有 Player/Camera/HUD）。
- 改 `.tscn` 用编辑器或 MCP，别手改磁盘（autosave 会冲掉）。
- **每间房放自己的元素来源**：要蓝放冰闸门、要红放火种，否则跨房预算软锁。
- `RoomZone` 与碰撞盒**别缩放/旋转**。
- `unlock_side` 指向**能开的那侧**，不是挡的那侧。
