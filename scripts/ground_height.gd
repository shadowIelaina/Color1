extends TileMapLayer
## 挂到地面 TileMapLayer：_ready 时把它的 custom data「height」喂给全局高度图。
## 水/冰等动态地形由 WaterCell 自己注册并覆盖这里的地面高度。

func _ready() -> void:
	HeightMap.load_from_tilemap(self)
