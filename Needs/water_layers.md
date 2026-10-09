# 水层改动说明

## 目的

把水拆成三种用途，避免整图铺水时生成大量 `WaterCell` 导致卡顿，同时保留“深水挡路、浅水可行走、纯视觉背景水”三种情况。

## 三个 Water TileMapLayer

### 1. WaterVisual（纯视觉背景水）

- 节点：`Level1 / WaterVisual`
- 类型：`TileMapLayer`
- 脚本：无
- `z_index = -4`
- `tile_set = TileSet_water`
- 作用：只显示水面贴图，不生成 `WaterCell`，不参与碰撞，性能最好。
- 用法：整张地图铺水时画在这一层。

### 2. Water（深水，挡路）

- 节点：`Level1 / Water`
- 类型：`TileMapLayer`
- 脚本：`res://color_change/water_spawner.gd`
- `z_index = -3`
- `shallow = false`
- `spawn_cells = true`
- `render_water_from_tilemap = true`
- 作用：深水。每个水格生成 `WaterCell`，会挡路，需要涂“蓝”结冰后才能通过。
- 用法：只画在真正需要“深水/可结冰挡路”的区域。

### 3. WaterShallow（浅水，可行走）

- 节点：`Level1 / WaterShallow`
- 类型：`TileMapLayer`
- 脚本：`res://color_change/water_spawner.gd`
- `z_index = -1`
- `shallow = true`
- `spawn_cells = true`
- `render_water_from_tilemap = true`
- 作用：浅水。玩家可以直接走在上面，但仍保留 `WaterCell`，可以参与结冰等玩法。
- 用法：画在需要“能走进去但又是水”的区域。

## 使用方式

1. 在 `level_1.tscn` 的场景树里选中对应水层。
2. 打开 `TileMap` 面板，选择水 tile。
3. 只在你选中的这一层上画水。
4. 三个层各自独立，互不影响。

## 层级顺序

从下到上：

1. `WaterVisual`：`z_index = -4`
2. `Water`：`z_index = -3`
3. `Ground`：`z_index = -2`
4. `WaterShallow`：`z_index = -1`

这样背景水在最下面，地面盖在背景水上，浅水显示在地面之上。

## 相关脚本改动

### `color_change/water_spawner.gd`

- 新增 `render_water_from_tilemap`，默认 `true`。开启时保留 tilemap 水面，不再清掉 tile。
- 新增 `spawn_cells`，默认 `true`。关闭时本层变成纯视觉水面，不生成 `WaterCell`。

### `color_change/water_cell.gd`

- 新增 `draw_water`。使用 tilemap 水面时设为 `false`，只保留碰撞、结冰、预览逻辑。
- `_fade_to()` 支持 `from_vis` 或 `to_vis` 为空，避免 tilemap 水面下结冰/融化报错。

### `scripts/player.gd`

- `_update_water_wade()` 改为用碰撞盒中心采样，而不是玩家节点原点，避免不同方向进水时判定不一致。

## 注意事项

- 水层节点本身的 `position` 应保持 `(0, 0)`，不要用移动节点的方式去摆水，否则会和 `HeightMap` 的格子对不上。
- 三个层可以共用同一个 `TileSet_water`，但每个层都要单独画自己的 tile。
- 如果某一层只做背景，不要挂 `water_spawner.gd`，或者把 `spawn_cells` 关掉。
