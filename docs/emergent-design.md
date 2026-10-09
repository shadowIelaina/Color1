# 涌现式设计 —— 代码结构说明

## 一句话

玩法不再靠「对象与对象之间硬连线」（这个钥匙开这扇门），而是靠**少量颜色元素 + 共享接口 + 状态机**，让交互从元素语义里**自发涌现**。

## 旧思路 vs 新思路

### 旧思路（脚本式解谜，已清理/遗留）

`scripts/door.gd` / `key.gd` / `lever.gd` / `gate.gd` / `reachability.gd` / `stateful_object.gd` —— 每个机关显式引用另一个机关：`key → door`、`lever → gate`。每加一个新谜题都要写新的配对逻辑，扩展靠堆代码。

### 新思路（涌现式，当前方向）

- 定义**元素**（红=燃烧、蓝=冻结、绿=生长），集中在 `element_rules.gd` 一张数据表里。
- 任何物体只要实现**四个方法**并加入 `"colorable"` group，就能参与系统。
- 玩法从「元素 × 元素」「玩家 × 元素」的相互作用中涌现，不写死配对。

## 分层结构

```
scripts/element/
  element_rules.gd      ← 数据单一来源（颜色名→元素 id；元素 id→行为配置）
  element_behavior.gd   ← 元素行为组件（状态机 + VFX + 蔓延 + 烧尽碎裂）

color_change/
  colorable_sprite.gd   ← 可上色物体（Sprite2D 版，石头）
  colorable_object.gd   ← 可上色物体（Polygon2D 版，箱子）
  ice_block.gd          ← 冰块闸门（预先赋蓝的挡路物）
  water_cell.gd         ← 单个水格（赋予蓝 → 结冰；吸收蓝 → 融回水）
  water_spawner.gd      ← 把 Water 层每个水 tile 铺成 WaterCell 网格
  hud.gd                ← HUD 显示颜色库与当前选中

scripts/player.gd       ← 吸收/赋予/描边（唯一直接操作元素系统的入口）

shaders/                ← 上色（color_fill*）、描边（outline）、碎裂（shatter）
effects/                ← 元素 VFX（flame_spread / freeze_spread / shatter …）
prefabs/items/…         ← 冰块等预制体
```

附注：另有独立的**通行性地图**（`HeightMap` autoload：`scripts/height_map.gd`，每格 256px），只存「可站 / 不可站」——深水不可站、浅水可站、冰可站，驱动「冻结水面过河」，和颜色涌现层正交。深/浅水怎么画见 [`water-system.md`](water-system.md)。

## 涌现怎么发生：四个机制

### 1. 单一数据源（element_rules.gd）

颜色名 → 元素 id → 行为配置，全在 `ELEMENTS` 表里：

- `"红" → "burn"`：持续燃烧 + 提供暖橙照明；被「蓝」冻结则**摧毁**（不蔓延、半径 1120 预留）。
- `"蓝" → "freeze"`：不蔓延、半径 880（预留）。
- `"绿" → "grow"`：搁置（已注释）。

**加新元素 = 加一行表**，行为代码不用动。颜色语义靠**中文颜色名**穿线：`apply_color(color, color_name)` → `element_for_color_name(color_name)` → 元素 id。

### 2. 组件化行为（element_behavior.gd）

`ElementBehavior` 是一个挂在可上色物体下的 `Node2D` 组件，只做**元素效果**（状态、VFX、蔓延、碎裂），**不管上色**——上色由父节点的 fill shader 负责。视觉与行为分离。

它的状态机就是涌现的温床：

- `apply("freeze")` 作用在**燃烧中**的物体 → 熄灭并**摧毁**（freeze × burn → 销毁交互）。
- `apply("burn")` 作用在**冻结中**的物体 → 先解冻再燃烧（burn × freeze 交互）。
- burn 的 `spreads=true` → 定时查找 `"colorable"` group 半径内邻居，重新 `apply_color` → **燃烧连锁蔓延**，火势从几何上涌现。（当前 `spreads` 暂设为 `false`，先不蔓延。）

这些交互不是手写的配对，而是**元素状态机之间互相调用**自然产生的结果。

### 3. 接口契约（鸭子类型，而非继承）

玩家不关心目标是石头、箱子还是冰块，只认**四个方法**：

| 方法 | 语义 | 谁实现 |
| --- | --- | --- |
| `apply_color(color, color_name, from_pos)` | 被上色 / 种元素 | colorable_sprite / colorable_object |
| `absorb_color()` | 被抽走元素，返回颜色信息 | 同上 + ice_block |
| `has_color()` | 是否当前带色 | 同上 + ice_block |
| `contains_point(world_pos)` | 鼠标点是否落在物体上（点击命中） | 同上 + ice_block |

加入 `"colorable"` group 的**任意**节点（Sprite2D 石头 / StaticBody2D 冰块 / Polygon2D 箱子）都能进入系统。玩家用 `has_method()` + `call()` 鸭子类型地调用，**不依赖具体类**。所以冰块不需要继承任何「可染色基类」，只要实现契约 + 进 group 即可。

### 4. 吸收 / 赋予 + 颜色库 + 种子守恒

玩家持有一个**颜色库**（`_inventory`：元素 id → 数量），并有一个**当前选中**的元素（`_selected_element`），开局为空：

- **吸收**（鼠标右键）：从鼠标指向的带色物体 `absorb_color()` 抽走元素，`+1` 存入颜色库，并自动选中它。
- **赋予**（鼠标左键）：把**当前选中**的元素 `apply_color()` 种到鼠标指向的可上色物体，消耗一颗种子；归零后自动切到库中下一种。
- **切换**（鼠标滚轮）：在颜色库里循环切换当前选中，决定赋予时种下哪种颜色。

元素**种子守恒**：颜色不会凭空出现，必须从世界里的初始色源（如冰块闸门）吸收，再搬到别处。谜题因此涌现——「先找哪里有色、再决定搬到哪」。

## 一个具体例子：冰块闸门（ice_block.gd）

1. 冰块是 `StaticBody2D`，开局 `_has_blue = true`，用碰撞挡住玩家。
2. 它实现 `has_color()` / `absorb_color()` 并进 `"colorable"` group，于是**自动**进入玩家的吸收/描边视野。
3. 玩家右键点击冰块 → `absorb_color()` → 玩家获得蓝、冰块 `collision` 禁用 + shatter 破碎 + 1.4s 后 `queue_free` → 玩家通行。

整个流程里，玩家代码**不知道冰块的存在**，只知道「鼠标指向一个能 `has_color` / `absorb_color` 的 colorable」。冰块和石头对玩家一视同仁。

## 视觉 / 行为分离

- **上色**：`shaders/color_fill_texture.gdshader`（Sprite 版）与 `color_fill.gdshader`（Polygon2D 版）负责颜色填充 + 从玩家侧扩散；物体 `modulate` 保持白，避免双重叠加。
- **元素效果**：`ElementBehavior` 播 VFX、处理蔓延、碎裂（`effects/shatter`）。
- **描边**：`shaders/outline.gdshader` 在可交互物体周围画虚线；玩家用当前选中颜色上色描边。描边统一挂在目标「贴图」上——目标本身是 Sprite2D（石头）直接用，否则取其 `Visual` 子节点（冰块）。

## 黑暗与照明（CanvasModulate + PointLight2D）

「有些关卡是暗房」用 Godot 2D 光照实现：

- **全局变暗**：场景根下有一个 `CanvasModulate`（`"darkness"` group）。`RoomZone` 勾 `dark` 的房，玩家进入时把它 `color` 渐变成暗色；亮房/默认渐变回白。
- **光源**（`PointLight2D` 径向光池，暗处照出亮圈）：
  - **玩家微光**：玩家自带一圈暖白小光，能看清自己和脚边。
  - **燃烧发光**：物体被赋予「红」燃烧时，`ElementBehavior` 挂一个暖橙 `PointLight2D`（火苗般微闪）；吸收红熄灭或加蓝摧毁时光随之消失。
- **不做阴影遮挡**：MVP 不用 `LightOccluder`，光池直接叠加在暗背景上，够用且便宜。

详细搭法见 [`lighting.md`](lighting.md)。

## 延伸：加新元素 / 新物体怎么加

- **新元素**：在 `element_rules.gd` 加一行（颜色名 → 元素 id → 配置），再在 `element_behavior.gd` 的 `apply()` 里加一个 `elif` 分支处理行为。
- **新可上色物体**：实现 `apply_color` / `absorb_color` / `has_color` / `contains_point` + 挂 `ElementBehavior` + 进 `"colorable"` group。玩家与蔓延逻辑无需改动。
