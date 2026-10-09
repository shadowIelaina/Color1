# 黑暗与照明 —— 使用说明

## 一句话

某些房间可以做成「暗房」：玩家进入后画面一片漆黑（塞尔达式迷宫光照），只有两类光源能**挖出**可见区域——**玩家自带微光**和**燃烧物体发出的光**。玩家靠「红」点燃可燃物来照明。

## 原理（塞尔达式挖洞，不是加法光晕）

- `DarknessOverlay`（`scripts/darkness_overlay.gd`，挂在根下 `Polygon2D`，`"darkness"` group）：一整块盖满世界的黑色多边形，覆盖一个 canvas_item shader（`shaders/darkness.gdshader`）。
- shader 每帧接收一串「光源位置 + 半径」，在黑色遮罩上 `smoothstep` 挖出透明圆洞：**洞内露出正常亮度的场景，洞外纯黑**。
- `LightSource`（`scripts/light_source.gd`，Node2D 标记，`"light_source"` group）：只存「位置 + 半径」，不发光；`DarknessOverlay._process()` 每帧把它喂给 shader。

> 和旧的 `CanvasModulate + PointLight2D` 不同：旧方案是「整体压暗 + 叠加光斑」，暗处仍透出底色、亮处只是暖光晕；新方案是「黑幕挖洞」，洞内是**原样场景**，洞外**纯黑**。

## 搭一间暗房：三步

1. 给这间房的 `RoomZone` 勾 `dark = true`。
2. 房里放**火种 `Ember`** 当红色来源（否则玩家没红可点）。
3. 房里摆几棵可烧的树/木条（`prefabs/items/static prop/tree.tscn`、`prefabs/items/interaction/wood.tscn`，已带 `colorable_static.gd`）。

玩家进房 → 变黑 → 吸收火种拿红 → 左键点燃树 → 树持续燃烧、在周围挖出一片可见区域。走出暗房自动恢复明亮（`RoomZone` 的 `body_exited`）。

## 光源明细

| 光源 | 谁挂的 | 半径 | 说明 |
| --- | --- | --- | --- |
| 玩家微光 | `player.gd` `_setup_light()` | 384px（约 1.5 格） | 自动、常亮，看清自己和脚边 |
| 燃烧发光 | `element_behavior.gd` `_spawn_light()` | `light_radius`（默认 352px） | 点燃才亮；圆心对准燃烧物**视觉中心** |

## 红 / 蓝在燃烧物上的规则

- **赋予红** → 点燃，持续燃烧 + 发光（**不再自动烧尽**）。
- **吸收红** → 熄灭、物体**不销毁**（拿回红，光消失）。
- **燃烧中加蓝** → 熄灭并**摧毁**（物体碎裂消失，红也随之消失）。

## 可调参数

| 文件 | 参数 | 默认 | 作用 |
| --- | --- | --- | --- |
| `colorable_static.gd`（转发给 `element_behavior.gd`） | `light_radius` | 352（px） | 燃烧光斑半径（256px ≈ 1 格），在树/木条实例 Inspector 上调 |
| `player.gd` `_setup_light` | `l.radius` | 384 | 玩家微光半径（相机 zoom 0.25，太小屏幕上几乎看不见） |
| `darkness_overlay.gd` | `dark_color` | 纯黑 | 遮罩底色（要纯黑就是 `#000000`） |
| `darkness_overlay.gd` | `softness` | 0.18 | 光斑边缘软化（占半径比例） |
| `darkness_overlay.gd` | `darkness` | 0 | 当前明暗（0=亮 / 1=全黑），由 `RoomZone` tween 控制 |
| `room_zone.gd` | `fade_time` | 0.6 | 明暗渐变时长（秒） |

## 注意

- 遮罩是**世界层**的 `Polygon2D`（`z_index = 100`），盖住所有世界物体；HUD（`CanvasLayer`）在它之上，UI 始终可读。
- 没有阴影遮挡：光是「圆洞」直接挖，能照过墙（MVP，够用）。以后要「墙挡光」得改成按遮蔽物分块遮罩，非简单圆洞。
- 相机本就锁房间范围，所以「全局变黑」只影响当前看到的这一间房，不会误伤别房。
- `MAX_LIGHTS = 16`：遮罩 shader 最多支持 16 个光源，超出会忽略（够用；要更多改 `darkness_overlay.gd` 的 `MAX_LIGHTS` 与 shader 数组大小）。

## 相关

- 房间 / 门 / Goal 搭法：[`room-system.md`](room-system.md)
- 元素涌现原理：[`emergent-design.md`](emergent-design.md)
