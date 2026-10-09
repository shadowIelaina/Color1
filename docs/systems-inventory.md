# Color1 系统功能全量清单

> 生成于 2026-10-09。遍历游戏本体（`scripts/`、`color_change/`、`shaders/`、`effects/`、`prefabs/`、`scenes/`）整理。
> 架构为元气骑士式：**关（大场景）用多场景切换，房（小场景）用单场景 RoomZone 分区**。

---

## 0. 顶层：Autoload 单例（3 游戏 + 1 插件）

| 单例 | 职责 |
|---|---|
| `GameState` | 全局状态 + 持久化 + 统一条件查询 + 切场景作用域 |
| `SceneManager` | 大场景（关）切换 |
| `HeightMap` | 通行性网格，256px/格（可站/不可站） |
| `_mcp_game_helper` | MCP 插件（非游戏内容） |

## 1. 场景生命周期系统

| 脚本 | 类型 | 职责 |
|---|---|---|
| `game_container.gd` | 常驻根 `GameContainer` (Node2D) | 持 Player + RoomContainer，启动时 `SceneManager.setup()` + `change_room(start)` |
| `scene_manager.gd` | Autoload | 卸载旧房→加载新房→定位入口；`SAFE_POS` 防瞬移拾取；`call_deferred` 防 "flushing queries"；0.4s 切关冷却 |
| `room.gd` | 大场景根 | entrance 查找、enter/exit、状态 save/restore、`_is_descendant` 作用域样板 |
| `entrance.gd` | 入口标记 | 供 `get_entrance_position` 定位 |
| `door.gd` | `SceneExit` (Area2D) | 大场景出口门，触发切关，`consume_key` 消耗钥匙 |
| `room_zone.gd` | `RoomZone` (Area2D) | 房分区：相机锁 + 暗房压黑/渐亮 + 房名 |
| `room_door.gd` | `RoomDoor` (StaticBody2D) | 物理门：`unlock_options`(OR 条件)/`unlock_side`(单向锁死)/`starts_open`/`consume_on_open`；子节点 Collision/Visual/Trigger |

## 2. 状态 / 持久化系统

| 脚本 | 职责 |
|---|---|
| `game_state.gd` | 信号 `item_collected/key_added/key_used/prop_added/gate_opened/hint/room_state_changed`；背包 `inventory/used_keys/switches/abilities/props/elements`；统一条件 `has_flag/meets_flag/consume_flag`（key/item/switch/ability/element）；`is_in_current_scene(node)` 切关作用域过滤 |
| `stateful_object.gd` | 持久化基类（`stateful` group + `state_id`，`save_state/restore_state`） |
| `key.gd` | 钥匙拾取（`key_id`） |
| `item_pickup.gd` | 关键道具拾取（`prop_id` → `GameState.props`，供道具门） |
| `breakable_wall.gd` | 可破坏墙（触碰即破，白盒占位） |

## 3. 玩家系统

| 脚本/资源 | 职责 |
|---|---|
| `player.gd` (`Player`, CharacterBody2D) | 8 向移动(WASD/方向键)、跑(Shift)、跳(视觉 hop, Space)、旋转(R)；输入是 `_ready` 里动态 `InputMap` 注册的自定义 action（非 `ui_*`）；右键吸收、左键赋予、滚轮切色；推箱、踩水、飞行物击退、微光照亮 |
| `player.tscn` | Player 实例 + Camera(zoom 0.25) |
| `player_sprite_frames.tres` | 22 组动画（idle/run/walk/jump/rotate 各方向） |
| `character_shadow.gd` + `.gdshader` | 角色投影剪影（图集帧逐帧喂 region） |

## 4. 颜色 / 元素系统（核心玩法）

| 脚本/资源 | 职责 |
|---|---|
| `element_rules.gd` | 元素数据表（单一数据源）：红=burn、蓝=freeze，绿=grow 已搁置；`spreads=false`（蔓延当前关闭） |
| `element_behavior.gd` | 元素行为组件：燃烧/冻结 VFX、生成光斑、蔓延链、碎裂销毁 |
| `colorable_base.gd` | 可上色基类契约（`apply_color/has_color/absorb_color/contains_point` + 视觉钩子） |
| `colorable_object.gd` | 箱子（Polygon2D 双面 fill shader） |
| `colorable_sprite.gd` | 贴图版（无碰撞，自建 behavior） |
| `colorable_static.gd` | 带碰撞静态物（树/木条） |
| `ember.gd` | 火种：开局带红挡路，吸收红→破碎放行（`seed_amount=3`） |
| `ice_block.gd` | 冰块/冰墙（`ice_block.tscn` + `ice_wall.tscn` 共用） |
| `color_fill.gdshader` / `color_fill_texture.gdshader` | 颜色从赋予源径向扩散 |
| `shatter.gdshader` + `effects/shatter/shatter.gd` | 网格碎片破碎 |

## 5. 水系统

| 脚本/资源 | 职责 |
|---|---|
| `water_cell.gd` | 水格：深水挡路(layer 2)/浅水可走；赋蓝→结冰通行；吸蓝→冰融回水；冰上再点蓝→生成可融冰墙 |
| `water_spawner.gd` | TileMapLayer 上画的水 tile → 实例化成 `WaterCell` |
| `water.gdshader` / `water_bw.gdshader` | 写实/黑白水面（高度场+法线+光照） |
| `HeightMap` | 冻结/融化实时 `set_walkable` 更新通行性 |

## 6. 光照 / 暗房系统（黑幕挖洞，非加法光晕）

| 脚本/资源 | 职责 |
|---|---|
| `light_source.gd` | 光源标记（只存位置+半径）；玩家微光 384、燃烧物 352 |
| `darkness_overlay.gd` | Polygon2D 遮罩，每帧收集 `light_source` 组、`to_local` 转坐标、整包喂 `light_pos/light_radius/light_count` 给 shader |
| `darkness.gdshader` + `darkness_material.tres` | `smoothstep` 挖透明圆洞，洞内原样/洞外纯黑 |
| `room_zone.gd` 的 `dark` | 进暗房 tween `darkness→1`，出暗房 `→0` |

## 7. 机关 / 物理

| 脚本/预制体 | 职责 |
|---|---|
| `trap.gd` + `trap.tscn` | 周期发射飞行物（`aim_at_player`/`fixed_direction`） |
| `projectile.gd` + `projectile.tscn` | 直线飞行物，撞玩家→`knockback` |
| `pushable_box.gd` + `pushable_body.gd` + `box.tscn` | 推箱（逻辑壳 `$Body` 物理体） |
| `goal.gd` + `room_effects.gd` | 踩上触发：`RoomEffects.unlock` 按 `door_id` 匹配 `room_door` group 开门 + HUD 反馈 |

## 8. 生物 / 静态装饰

| 预制体 | 状态 |
|---|---|
| `bird.tscn` / `squirrel.tscn` | CharacterBody2D，目前无脚本（碰撞体+贴图占位，AI 未实现） |
| `tree.tscn` | `colorable_static`（可上色/可燃烧发光）+ `tree_shadow.gdshader` 投影 |
| `grass_1.tscn` | `shaders/Grass.gd` + `Grass_act.gdshader`（风动 + 踩踏弯曲） |

## 9. 特效（GPUParticles2D，共用 glow_soft 光斑）

| 场景 | 效果 |
|---|---|
| `flame_spread` | 火焰扩散（Core→Spread→Embers） |
| `freeze` / `freeze_spread` | 冻结霜雾 / 冻结扩散 |
| `life_ring` / `life_ringback` | 生命之环扩散 / 回收爆开 |
| `shatter` | 破碎（套 `shatter.gdshader`） |

## 10. HUD

| 脚本 | 职责 |
|---|---|
| `color_change/hud.gd` | 唯一 HUD：颜色库存显示 + `show_hint`/`show_win` + `GameState.hint` 连接 |

## 11. 设计期工具

| 脚本 | 职责 |
|---|---|
| `reachability.gd` | BFS 软锁检查（`test_graph` 对应 level_1/level_2） |
| `room_meta.gd` | 房间元数据 |

---

## 关键约定与现状提示

- **碰撞层**：玩家 1 / 障碍 2 / 箱子 3 / 飞行物 mask 7。
- **坐标系**：大坐标 + 256px 瓦片 + 物体 scale 16 + Camera zoom 0.25。
- **切关正确性**：`element_behavior`(蔓延)、`darkness_overlay`(光源)、`player`(拾取/冻结预览)、`room_effects`(开门) 四处全局搜索都已收敛到 `GameState.is_in_current_scene`；`SceneManager` 切关前 `HeightMap.clear()`。
- **现状（非缺陷）**：① 元素蔓延 `spreads=false` 关闭中；② 绿元素 `grow` 注释搁置；③ 鸟/松鼠无 AI 脚本。
