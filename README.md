# Color

2026 聚光灯 GameJam 参赛项目。2.5D 俯视角（3/4 视）像素风小游戏。

核心思路是**涌现式设计（Emergent Design）**：不再手写「这个钥匙开这扇门」式的脚本谜题，而是定义少量**颜色元素**（红=燃烧、蓝=冻结、绿=生长），让玩法从元素之间的相互作用中**自发涌现**。玩家通过「吸收 / 赋予」在世界里搬运元素种子，解开障碍。

## 当前进度

已实现（可玩闭环）：

- **玩家控制器** `scripts/player.gd`：8 方向移动、idle/walk/run/jump/rotate 动画状态机、推箱子。
- **元素系统**（涌现层）：
  - `scripts/element/element_rules.gd` —— 元素数据表（单一数据源）
  - `scripts/element/element_behavior.gd` —— 元素行为组件（燃烧/冻结/蔓延/冻结摧毁/燃烧照明）
  - `color_change/colorable_sprite.gd`（石头）/ `colorable_object.gd`（箱子）—— 可上色物体
  - `color_change/ice_block.gd` —— 冰块闸门（预先赋蓝、挡路，吸收后破碎放行）
- **吸收 / 赋予**：鼠标右键吸收、左键赋予、滚轮切换颜色；颜色库（元素 id → 数量）+ 种子守恒。
- **蓝色（冻结）**：已完整接通——冻结结冰可过水；对燃烧中的物体加蓝会**熄灭并摧毁**它；冰块闸门是蓝色的初始来源。
- **红色（燃烧）**：已接通——赋予红使可燃物（树/木条）**持续燃烧并发出暖橙光照明**；吸收红熄灭、物体不销毁，燃烧中加蓝才销毁。火种 `color_change/ember.gd` 是红色来源。
- **水面（水格）**：`color_change/water_cell.gd` + `water_spawner.gd` —— 水面自动铺成平面 2D 网格，鼠标左键对单格赋予蓝使其结冰（冰块填满格、可通行）；吸收蓝色则冰融回水。冻结/融化有 0.2s 淡入淡出。**分深/浅水**：深水（默认）挡路、需结冰才能过；浅水（`shallow=true`）可直接行走——两者都能结冰，仅贴图/颜色不同以区分。
- **描边提示**：鼠标指向可交互物体时，用玩家当前选中的颜色画虚线描边。
- **通行性地形**：`HeightMap` autoload（每格 256px）只存「可站 / 不可站」——深水不可站、浅水可站、冰可站，是「冻结水面过河」的通行判定。
- **黑暗与照明**：`DarknessOverlay`（Polygon2D 遮罩 + `darkness.gdshader` 挖洞）——暗房靠玩家微光 + 燃烧照明；`RoomZone` 勾 `dark` 即把该房压黑。

待接：红色蔓延（`spreads` 暂设为 false）、绿色（生长，搁置）。

## 操作

| 按键 | 作用 |
| --- | --- |
| WASD / 方向键 | 移动 |
| Shift | 奔跑 |
| Space | 跳跃 |
| R | 旋转 |
| 鼠标右键 | 吸收（抽走物体颜色） |
| 鼠标左键 | 赋予（把持有的颜色种到物体） |
| 鼠标滚轮 | 在颜色库中切换选中的颜色 |

## 代码结构

涌现设计如何落地到代码，详见 [`docs/emergent-design.md`](docs/emergent-design.md)。

关卡/房间怎么搭（Goal 解锁门、RoomZone 锁相机、跨房颜色），详见 [`docs/room-system.md`](docs/room-system.md)。

完整上手手册（新建关卡/房/门/钥匙/道具的字段与步骤），详见 [`docs/level-system-usage.md`](docs/level-system-usage.md)。

水面深/浅怎么画（深水挡路、浅水可走 + 美术区分），详见 [`docs/water-system.md`](docs/water-system.md)。

黑暗关卡/照明怎么搭（暗房 + 玩家微光 + 燃烧照明），详见 [`docs/lighting.md`](docs/lighting.md)。

## 运行

`project.godot` 的 `run/main_scene` 指向 `res://scenes/game.tscn`（常驻容器，启动后进入 `level_1`），F5 即可。
