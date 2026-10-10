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

## 浅水流向（每格把玩家冲走）

### 一句话

浅水可以带流向：在**箭头标记层**上画箭头，玩家站到那一格就被往箭头方向冲；**结冰的那格不推人**。

### 使用步骤

1. 选中关卡里的 **`WaterFlow`** 层（`TileMapLayer`，已挂 `flow_marker_spawner.gd`，与浅水层同原点、同 256 格）。
2. 用箭头 tile 在**浅水格**上画流向，atlas 约定：`(0,0)=→` `(1,0)=↓` `(2,0)=←` `(3,0)=↑`。
3. 完成。箭头只用于编辑器里标记，进游戏自动隐藏；玩家站上去就被往箭头方向冲。

### 规则

- 结冰格不推人（冰可站、该格水流失效）。
- 只有 4 个正交方向，没有斜向流。
- 推力大小：`player.gd` 的 `flow_strength`（默认 600 px/s）。

### 占位贴图

`art/else/flow_arrows.png` 是临时黄箭头，方便先测试。正式图替换它即可（保持四张一行：→↓←↑），或在 `flow_marker_spawner.gd` 的 export 里改四个 atlas 坐标（`atlas_right/down/left/up`）。

### 代码位置

- `scripts/flow_marker_spawner.gd` —— 箭头层生成器，`_ready` 把箭头 tile 读成流向写进 `HeightMap`，然后 `visible=false`。
- `scripts/height_map.gd` —— `set_flow` / `flow_at`（编码 0=无 1=右 2=下 3=左 4=上）。
- `scripts/player.gd` —— `_flow_vector()` + `flow_strength`，脚下采样 `HeightMap.flow_at` 得推力。

## 代码位置

- `color_change/water_cell.gd` —— `@export var shallow := false` 决定单格深/浅；`_ready` / `absorb_color` 按它设碰撞层与 `HeightMap` 通行性。
- `color_change/water_spawner.gd` —— `@export var shallow := false`，复制给本层每个水格。
- 通行判定见 `scripts/height_map.gd`（autoload `HeightMap`）。
