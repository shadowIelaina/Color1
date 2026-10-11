class_name ElementRules
extends RefCounted

## 元素系统数据表（单一数据源）。
## 颜色名 -> 元素 id；元素 id -> 行为配置。
## 策划调整只改这里，不动行为代码。

const COLOR_NAME_TO_ELEMENT := {
	"红": "burn",
	"蓝": "freeze",
	# "绿": "grow",  # 搁置
}

const ELEMENTS := {
	"burn": {
		"color_name": "红",
		"color": Color(1.0, 0.3, 0.3),
		"vfx": "res://shaders/fire.tscn",
		"spreads": false,
		"spread_radius": 1120.0,
		"spread_delay": 0.9,
	},
	"freeze": {
		"color_name": "蓝",
		"color": Color(0.3, 0.55, 1.0),
		"vfx": "res://effects/freeze_spread/freeze_spread.tscn",
		"melt_vfx": "res://effects/melt_drip/melt_drip.tscn",
		"spreads": false,
		"spread_radius": 880.0,
		"spread_delay": 0.7,
	},
}

## 物质 -> 该物质对各元素的专属反应（「按物质分表」数据源，覆盖/补充 ELEMENTS 全局默认）。
## burn_spreads: 红(燃烧)是否向邻近物体蔓延；burn_light: 燃烧光斑半径；
## burn_x_freeze: 红+蓝 交叉反应结果 —— "shatter"=碎裂销毁(木头)、"fade"=烧毁/枯萎淡出(石头/草)。
## melt_time: 冻结自然融化时长(秒)，物质越「存冷」越久；0 或负值 = 永不自然融化。
const MATERIALS := {
	"wood":  {"burn_spreads": true,  "burn_light": 352.0, "burn_x_freeze": "shatter", "melt_time": 12.0},
	"stone": {"burn_spreads": false, "burn_light": 288.0, "burn_x_freeze": "fade",    "melt_time": 30.0},
	"grass": {"burn_spreads": true,  "burn_light": 256.0, "burn_x_freeze": "fade",    "melt_time": 6.0},
}


static func element_for_color_name(color_name: String) -> String:
	return str(COLOR_NAME_TO_ELEMENT.get(color_name, ""))


static func config(element_id: String) -> Dictionary:
	return ELEMENTS.get(element_id, {})


static func has(element_id: String) -> bool:
	return ELEMENTS.has(element_id)


## 物质专属配置（未登记物质返回空表，走全局默认）。
static func material_config(material_id: String) -> Dictionary:
	return MATERIALS.get(material_id, {})


## 红+蓝 交叉反应结果（默认碎裂）。
static func cross_reaction(material_id: String) -> String:
	return str(MATERIALS.get(material_id, {}).get("burn_x_freeze", "shatter"))
