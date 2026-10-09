# 水面系统 —— 深水 / 浅水使用说明

## 一句话

水格（`water_cell.gd`）分两种：

- **深水**（默认）：挡路、玩家不能走，需「蓝」冻结成冰才能通过。
- **浅水**（`shallow=true`）：不挡路，玩家可直接在上面行走。

两者都能结冰（赋予蓝）与融化（吸收蓝），也都能在冻水上再点一下生成冰墙；差别只在通行性与美术。

## 深 / 浅水对照

| | 深水 | 浅水 |
| --- | --- | --- |
| `shallow` | `false`（默认） | `true` |
| 碰撞层 | layer 2（挡玩家） | layer 0（不挡） |
| 通行性 | 不可站 | 可站 |
| 结冰 | 冰块可通行 | 冰块可通行（同左） |
| 融化 | 恢复深水（不可站） | 恢复浅水（可站） |

> 注意：浅水 `collision_layer=0`，所以**不挡飞行物**（飞行物 mask 7 含层 2）；深水与冰墙才挡飞行物。

## 在场景里怎么画（两层 TileMapLayer）

深水和浅水**各用一层** `TileMapLayer`，都挂 `water_spawner.gd`：

1. **深水层**：新建 `TileMapLayer`，挂 `water_spawner.gd`，`shallow` 留 `false`，用现在的水贴图；在它上面画不能走的水。
2. **浅水层**：再新建一层 `TileMapLayer`，挂 `water_spawner.gd`，勾 `shallow = true`，用**更浅 / 半透明**的水贴图；在它上面画能直接走的水。
3. 两层各自 `water_texture` / `water_color` / `ice_texture` / `ice_color` 独立配置，靠贴图区分深浅。

（`water_spawner.gd` 会把本层每个画出的 tile 换成一个 `WaterCell` 节点，并按本层的 `shallow` 设成深/浅，然后清掉标记 tile——所以画水就是「像画地面一样刷 tile」。）

## 美术区分建议

- **深水**：现有偏深的蓝（`water_color` ≈ `#2185a3`，或深色贴图）。
- **浅水**：更浅、更亮、**半透明**（贴图带 alpha），让玩家一眼看出「这里能走」。
- 冰块贴图可共用，也可给浅水单独一套更薄的冰。

## 行为细节

- **冻结**：鼠标左键对任意未结冰水格（深/浅）赋予蓝 → 结冰可通行，0.2s 淡入。
- **融化**：右键吸收冰格 → 深水恢复挡路、浅水恢复可走（玩家正站在冰上时禁止吸收，避免掉进深水）。
- **冰墙**：对已结冰的水格再点一下 → 生成可融冰墙（消耗 1 蓝）。

## 代码位置

- `color_change/water_cell.gd` —— `@export var shallow := false` 决定单格深/浅；`_ready` / `absorb_color` 按它设碰撞层与 `HeightMap` 通行性。
- `color_change/water_spawner.gd` —— `@export var shallow := false`，复制给本层每个水格。
- 通行判定见 `scripts/height_map.gd`（autoload `HeightMap`）。
