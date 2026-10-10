## 2.5D 俯视深度排序：把「脚底世界 Y」映射到 z_index（越大越靠前、越靠屏幕下方）。
## 玩家与所有「高」障碍物（树 / 木条 / 箱子 / 岩石）共用同一映射，二者在同一画布内按脚底 Y
## 正确互相遮挡——玩家走到物体后（北）侧时被挡住，走到前（南）侧时挡在物体前。
##
## 深度带 [0, 4000]（10 世界像素一档，zoom 0.25 下 ≈ 2.5 屏幕像素，肉眼不可察）：
##   · 地面/水面贴图 layer(-4..-1) 始终在 0 之下，正常垫底；
##   · 暗房遮罩 Darkness 抬高到 4096，始终盖在深度带之上。
## 世界 Y 范围约 [-20000, 20000]（level_1 camera_limits），实际内容约 [-10000, 8000]。

const WORLD_TOP := -20000.0
const SCALE := 10.0
const DEPTH_MIN := 0
const DEPTH_MAX := 4000


static func z_for(y: float) -> int:
	return clampi(int((y - WORLD_TOP) / SCALE), DEPTH_MIN, DEPTH_MAX)
