extends RefCounted
# BRMod: special shells.
#   "hidden" (yellow): at an opponent -> the SHOOTER takes the damage; at yourself -> acts as a blank.
#                      Magnifying glass / phone show it as live. Inverter -> live.
#   "heal"   (pink):   heals whoever it hits by 1 (2 with the saw). Inverter -> live.

const HIDDEN := "hidden"
const HEAL := "heal"
const BLACK := "black"
const COLOR_HIDDEN := Color(1.0, 0.82, 0.08)
const COLOR_HEAL := Color(1.0, 0.42, 0.78)

var core
var _mats := {}

func _init(c):
	core = c

# host, right after the vanilla sequence was generated
func add_specials(gs) -> void:
	var d : Dictionary = gs.MAIN_active_sequence_dict
	if !d.has("sequence"): return
	var changed := false
	var force : bool = core.force_specials
	core.force_specials = false
	if force:
		if d.sequence.count("blank") >= 1: _replace(d, "blank", HIDDEN)
		if d.sequence.count("live") >= 1: _replace(d, "live", HEAL)
		changed = true
	elif randf() < core.shell_hidden_chance and d.sequence.count("blank") >= 2:
		_replace(d, "blank", HIDDEN)
		changed = true
	if !force and randf() < core.shell_heal_chance and d.sequence.count("live") >= 2:
		_replace(d, "live", HEAL)
		changed = true
	if force or randf() < core.shell_black_chance:
		# Only replace a surplus shell so both ordinary types remain available.
		var candidates := []
		for kind in ["blank", "live"]:
			if d.sequence.count(kind) >= 2: candidates.append(kind)
		if !candidates.is_empty():
			_replace(d, candidates.pick_random(), BLACK)
			changed = true
	if changed:
		var send : Dictionary = d.duplicate(true)
		send.erase("sequence_in_shotgun")
		gs.MAIN_active_sequence_dict_send = send
		print("[BRMod] special shells: visible ", d.sequence_visible)

func black_outcome() -> String:
	return core.debug_force.get("black_outcome", "live" if randf() < 0.5 else "blank")

func _replace(d : Dictionary, from : String, to : String) -> void:
	for key in ["sequence", "sequence_visible"]:
		var a : Array = d[key]
		var i := a.find(from)
		if i != -1: a[i] = to
	var g : Array = d.sequence_in_shotgun
	var idx := []
	for i in g.size():
		if g[i] == from: idx.append(i)
	if !idx.is_empty(): g[idx.pick_random()] = to

func material(kind : String, base : StandardMaterial3D, inspecting : bool) -> StandardMaterial3D:
	var key := kind + ("_i" if inspecting else "")
	if _mats.has(key): return _mats[key]
	var m : StandardMaterial3D = base.duplicate() if base else StandardMaterial3D.new()
	# the grey colour-blind shell texture keeps the paper/print detail; tint it
	var grey_path := "res://multiplayer/textures/mp_shell live colorblind.png"
	if ResourceLoader.exists(grey_path):
		m.albedo_texture = load(grey_path)
		m.albedo_color = Color(0.95, 0.72, 0.05) if kind == HIDDEN else Color(1.0, 0.38, 0.72)
	else:
		m.albedo_texture = null
		m.albedo_color = Color(0.7, 0.52, 0.02) if kind == HIDDEN else Color(0.75, 0.25, 0.5)
	if kind == BLACK:
		m.albedo_color = Color(0.12, 0.12, 0.14)
		m.metallic = 0.0
	m.emission_enabled = inspecting
	if inspecting:
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.25
	_mats[key] = m
	return m

func heal(target, amount : int) -> int:
	var before : int = target.health_current
	if before <= 0: return 0
	target.health_current = min(before + amount, 6)
	var healed : int = target.health_current - before
	print("[BRMod] pink shell heals socket %d by %d" % [target.socket_number, healed])
	_heal_fx(target, healed)
	return healed

func _heal_fx(target, healed : int) -> void:
	core.fx.play("heal")
	if target.instance_root:
		var pos : Vector3 = target.instance_root.global_position + Vector3(0, 4, 0)
		core.fx.burst(pos, [COLOR_HEAL, Color.WHITE], 50, 4.0, 2.0, 1.3, 0.1)
		core.fx.flash(pos, COLOR_HEAL, 1.0, 5.0, 8.0)
	await core.get_tree().create_timer(0.7, false).timeout
	if healed > 0:
		target.health_counter.healing_health = true
	target.health_counter.UpdateDisplay()
