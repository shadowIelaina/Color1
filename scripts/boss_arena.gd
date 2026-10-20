extends Node2D
## Boss 场地阶段反馈：Boss 血线 / 状态驱动中央符文、暗角和四座方尖碑。

const COLORS := {
	"red": Color(1.0, 0.18, 0.12, 1.0),
	"blue": Color(0.2, 0.45, 1.0, 1.0),
	"green": Color(0.15, 1.0, 0.3, 1.0),
	"cyan": Color(0.1, 0.95, 1.0, 1.0),
}

@onready var rune: Polygon2D = get_node_or_null("Rune") as Polygon2D
@onready var vignette: ColorRect = get_node_or_null("Vignette") as ColorRect
@onready var obelisks := {
	"red": get_node_or_null("ObeliskRed"),
	"blue": get_node_or_null("ObeliskBlue"),
	"green": get_node_or_null("ObeliskGreen"),
	"cyan": get_node_or_null("ObeliskCyan"),
}

var _boss: Node
var _rune_mat: ShaderMaterial
var _vignette_mat: ShaderMaterial
var _phase := ""
var _phase_tween: Tween
var _rune_pulse: Tween


func _ready() -> void:
	_rune_mat = rune.material as ShaderMaterial if rune != null else null
	_vignette_mat = vignette.material as ShaderMaterial if vignette != null else null
	# BossEncounter 可能在本节点之后才 _ready 入组，延后一帧再连接。
	_connect_boss.call_deferred()


func _connect_boss() -> void:
	if GameState.is_switch_on("boss_defeated"):
		play_victory(true)
		return
	_boss = get_tree().get_first_node_in_group("boss")
	if _boss != null:
		if _boss.has_signal("health_changed"):
			_boss.health_changed.connect(_on_health_changed)
		if _boss.has_signal("state_changed"):
			_boss.state_changed.connect(_on_state_changed)
		if _boss.has_signal("charge_crashed"):
			_boss.charge_crashed.connect(_on_charge_crashed)
	_apply_phase(_health_phase(), true)


func _on_health_changed(_current: float, _max_health: float) -> void:
	_apply_phase(_health_phase())


func _on_state_changed(state: int) -> void:
	match state:
		Boss.State.HEAL_WINDUP, Boss.State.HEAL:
			_apply_phase("green")
		Boss.State.CYAN_CHARGE, Boss.State.STUNNED:
			_apply_phase("cyan")
		Boss.State.CHASE, Boss.State.RING_CAST, Boss.State.ICE_CAST:
			_apply_phase(_health_phase())
		_:
			pass


func _on_charge_crashed() -> void:
	var room := get_parent()
	if room != null and room.has_method("shake"):
		room.call("shake", 14.0)


func _health_phase() -> String:
	if _boss == null or not is_instance_valid(_boss):
		return "red"
	var max_health := float(_boss.get("max_health"))
	if max_health <= 0.0:
		return "red"
	var ratio := float(_boss.get("health")) / max_health
	if ratio > 0.66:
		return "red"
	if ratio > 0.34:
		return "blue"
	return "green"


func _apply_phase(phase: String, instant := false) -> void:
	if not COLORS.has(phase):
		return
	if phase == _phase and not instant:
		return
	_phase = phase
	var color: Color = COLORS[phase]
	_set_glow_phase(phase, instant)
	if instant:
		if _rune_mat != null: _rune_mat.set_shader_parameter("rune_color", color)
		if _vignette_mat != null: _vignette_mat.set_shader_parameter("edge_color", _edge_color(color))
		return
	if _rune_mat == null and _vignette_mat == null:
		return
	if _phase_tween != null and _phase_tween.is_valid():
		_phase_tween.kill()
	_phase_tween = create_tween().set_parallel(true)
	if _rune_mat != null:
		var from_rune: Color = _rune_mat.get_shader_parameter("rune_color")
		_phase_tween.tween_method(func(c: Color): _rune_mat.set_shader_parameter("rune_color", c), from_rune, color, 0.55)
	if _vignette_mat != null:
		var from_edge: Color = _vignette_mat.get_shader_parameter("edge_color")
		_phase_tween.tween_method(func(c: Color): _vignette_mat.set_shader_parameter("edge_color", c), from_edge, _edge_color(color), 0.55)
	_pulse_rune()


func _set_glow_phase(phase: String, instant: bool) -> void:
	for key in obelisks:
		var obelisk: Node = obelisks[key]
		if obelisk != null and obelisk.has_method("set_active"):
			obelisk.call("set_active", key == phase, instant)


func _edge_color(color: Color) -> Color:
	return Color(color.r * 0.18, color.g * 0.18, color.b * 0.22, 0.85)


func _pulse_rune() -> void:
	if rune == null:
		return
	if _rune_pulse != null and _rune_pulse.is_valid():
		_rune_pulse.kill()
	_rune_pulse = create_tween()
	_rune_pulse.tween_property(rune, "scale", Vector2(1.06, 1.06), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rune_pulse.tween_property(rune, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Boss 胜利：所有方尖碑亮起，符文变金白并扩散一下。
func play_victory(instant := false) -> void:
	_phase = "victory"
	var gold := Color(1.0, 0.86, 0.42, 1.0)
	for key in obelisks:
		var obelisk: Node = obelisks[key]
		if obelisk != null and obelisk.has_method("set_active"):
			obelisk.call("set_active", true, instant)
	if _rune_mat == null and _vignette_mat == null:
		return
	if instant:
		if _rune_mat != null: _rune_mat.set_shader_parameter("rune_color", gold)
		if _vignette_mat != null: _vignette_mat.set_shader_parameter("edge_color", _edge_color(gold))
		return
	var t := create_tween().set_parallel(true)
	if _rune_mat != null:
		var from_rune: Color = _rune_mat.get_shader_parameter("rune_color")
		t.tween_method(func(c: Color): _rune_mat.set_shader_parameter("rune_color", c), from_rune, gold, 0.7)
	if _vignette_mat != null:
		var from_edge: Color = _vignette_mat.get_shader_parameter("edge_color")
		t.tween_method(func(c: Color): _vignette_mat.set_shader_parameter("edge_color", c), from_edge, _edge_color(gold), 0.7)
	_pulse_rune()
