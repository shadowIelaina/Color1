extends Node2D
## 燃烧火焰粒子效果（fire.tscn）：替换旧的 flame_spread，作为「烧毁(burn)」元素的 VFX。
## 持续向上喷出火焰粒子；宿主物体被清除元素时由 ElementBehavior._clear_vfx 统一销毁。

## 兼容 ElementBehavior._spawn_vfx 里的 set("loop", false)（旧 flame_spread 用它表示「只播一次」）。
## 本效果设计为持续燃烧，故忽略该值，仅保留属性避免 set 报错。
@export var loop := true
