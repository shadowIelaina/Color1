extends RefCounted
## 保留拾取物的实际贴图，不复制其发光材质或世界节点。

static func register_item(kind: String, id: String, title: String, visual: Node, icon: Texture2D = null) -> Dictionary:
	if icon == null and visual is Sprite2D:
		icon = visual.texture
	if icon == null and visual != null:
		for child in visual.find_children("*", "Sprite2D", true, false):
			if child.texture != null:
				icon = child.texture
				break
	var entry := {"kind": kind, "id": id, "title": title, "texture": icon.resource_path if icon != null else ""}
	GameState.item_art[kind + ":" + id] = entry
	return entry

static func announce(kind: String, id: String, detail: String = "已收好") -> void:
	var entry: Dictionary = GameState.item_art.get(kind + ":" + id, {}).duplicate()
	if entry.is_empty(): return
	entry["detail"] = detail
	GameState.pickup_presented.emit(entry)
