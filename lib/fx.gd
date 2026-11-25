extends Node
# BRMod: visual / audio effects, local-player overlays (blindfold, headphones, drunk wobble).

var core
var _players := []
var _deaf_muted := []
var _wobble_t := 0.0

const COLOR_RED := Color(0.9, 0.12, 0.1)
const COLOR_YELLOW := Color(1.0, 0.85, 0.15)
const COLOR_GOLD := Color(1.0, 0.78, 0.25)
const COLOR_PINK := Color(1.0, 0.4, 0.75)
const COLOR_GREEN := Color(0.3, 1.0, 0.35)

func _init(c):
	core = c
	name = "fx"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(key : String, volume_db := 0.0, pitch := 1.0) -> void:
	var s : AudioStream = core.assets.sound(key)
	if s == null: return
	var best : AudioStreamPlayer = _players[0]
	for p in _players:
		if !p.playing:
			best = p
			break
	best.stream = s
	best.volume_db = volume_db
	best.pitch_scale = pitch
	best.bus = &"interactions" if AudioServer.get_bus_index(&"interactions") != -1 else &"Master"
	best.play()

func scene_root() -> Node:
	return get_tree().current_scene

func flash(pos : Vector3, color : Color, dur := 1.0, energy := 6.0, rng := 9.0) -> void:
	var root := scene_root()
	if root == null: return
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = rng
	light.light_energy = 0.0
	root.add_child(light)
	light.global_position = pos + Vector3(0, 1.5, 0)
	var t := light.create_tween()
	t.tween_property(light, "light_energy", energy, dur * 0.2)
	t.tween_property(light, "light_energy", 0.0, dur * 0.8)
	t.tween_callback(light.queue_free)

# Minecraft-style "pixel" burst: little glowing cubes swirling up around a point.
func burst(pos : Vector3, colors : Array, amount := 90, up := 6.0, spread := 2.2, life := 1.6, size := 0.12) -> void:
	var root := scene_root()
	if root == null: return
	var p := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = false
	box.material = m
	p.mesh = box
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread * 0.5
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = up * 0.5
	p.initial_velocity_max = up
	p.gravity = Vector3(0, -up * 0.6, 0)
	p.orbit_velocity_min = 0.3
	p.orbit_velocity_max = 0.8
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([colors[0], colors[1] if colors.size() > 1 else colors[0]])
	p.color_initial_ramp = g
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1)); fade.add_point(Vector2(0.7, 1)); fade.add_point(Vector2(1, 0))
	p.scale_amount_curve = fade
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5, false).timeout.connect(p.queue_free)

func smoke_cloud(pos : Vector3, radius := 6.0, life := 3.0) -> void:
	var root := scene_root()
	if root == null: return
	var p := CPUParticles3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0; s.height = 2.0; s.radial_segments = 8; s.rings = 4
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material = m
	p.mesh = s
	p.amount = 40
	p.one_shot = true
	p.explosiveness = 0.7
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.3, 0)
	p.scale_amount_min = radius * 0.25
	p.scale_amount_max = radius * 0.45
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(0.7, 0.7, 0.7, 0.0), Color(0.75, 0.75, 0.72, 0.85), Color(0.6, 0.6, 0.6, 0.0)])
	p.color_ramp = g
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5, false).timeout.connect(p.queue_free)

func shake_all() -> void:
	var inter = core.inter()
	if inter == null: return
	for p in inter.instance_handler.instance_property_array:
		if p.cam_shaker: p.cam_shaker.Shake()

func table_center() -> Vector3:
	var inter = core.inter()
	if inter and inter.globalparent_shotgun: return inter.globalparent_shotgun.global_position
	return Vector3.ZERO

func lightning() -> void:
	var c := table_center()
	play("thunder", 2.0)
	for i in 3:
		flash(c + Vector3(randf_range(-3, 3), 6, randf_range(-3, 3)), Color(0.75, 0.8, 1.0), 0.25, 16.0, 40.0)
		await get_tree().create_timer(randf_range(0.08, 0.2), false).timeout
	shake_all()

# ------------------------------------------------------------------ item "pop" visuals

func poof_item(inst : Node3D, color : Color, rise := 2.0) -> void:
	if inst == null or !is_instance_valid(inst): return
	if inst.get_child_count() > 0 and inst.get_child(0).get("lerpEnabled") != null:
		inst.get_child(0).lerpEnabled = false
	var t := inst.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(inst, "position:y", inst.position.y + rise, 0.6)
	t.parallel().tween_property(inst, "rotation_degrees:y", inst.rotation_degrees.y + 360.0, 0.6)
	t.tween_property(inst, "scale", Vector3.ONE * 0.01, 0.25)
	t.tween_callback(inst.queue_free)
	flash(inst.global_position, color, 0.6, 3.0, 5.0)

func totem_pop_fp(props) -> void:
	# the saved local player sees the totem fly into their face, like the classic block game
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var mi := MeshInstance3D.new()
	mi.mesh = core.assets._meshes.get(core.ID_TOTEM)
	if mi.mesh == null: return
	scene_root().add_child(mi)
	var f := -cam.global_transform.basis.z
	var up := cam.global_transform.basis.y
	var right := cam.global_transform.basis.x
	var a : AABB = mi.mesh.get_aabb()
	var center_off := a.get_center()
	var start_pos := cam.global_position + f * 9.0 - up * 4.0
	var end_pos := cam.global_position + f * 4.2
	var b := Basis(right, -f, -up) # flat totem: face towards the camera
	mi.global_transform = Transform3D(b, start_pos - b * center_off)
	mi.scale = Vector3.ONE * 0.3
	var t := mi.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(_totem_step.bind(mi, b, up, start_pos, end_pos, center_off), 0.0, 1.0, 0.9)
	t.tween_interval(0.5)
	t.tween_property(mi, "transparency", 1.0, 0.4)
	t.tween_callback(mi.queue_free)

func _totem_step(k : float, mi : MeshInstance3D, b : Basis, up : Vector3, start_pos : Vector3, end_pos : Vector3, center_off : Vector3) -> void:
	if !is_instance_valid(mi): return
	var bb := b.rotated(up, sin(k * PI * 3.0) * 0.5 * (1.0 - k)).scaled(Vector3.ONE * lerp(0.3, 1.0, k))
	mi.global_transform = Transform3D(bb, start_pos.lerp(end_pos, k) - bb * center_off)

# ------------------------------------------------------------------ head props (blindfold / headphones)

func _head_node(props) -> Node3D:
	var root = props.get_node_or_null("../..")
	if root == null: return null
	return root.get_node_or_null("user third person view/user model upper parent/user model kickback parent/user model main parent/user model secondary parent/user model look parent/placeholder visual model")

func _head_box(head : Node3D) -> AABB:
	var best := AABB()
	var found := false
	for c in head.get_children():
		if c is MeshInstance3D and c.visible and c.mesh:
			var a : AABB = c.transform * c.mesh.get_aabb()
			best = a if !found else best.merge(a)
			found = true
	if !found: best = AABB(Vector3(-0.3, -0.3, -0.3), Vector3(0.6, 0.6, 0.6))
	return best

func set_head_prop(props, key : String, on : bool) -> void:
	var head := _head_node(props)
	if head == null: return
	var old := head.get_node_or_null("brmod_" + key)
	if old: old.queue_free()
	if !on: return
	var box := _head_box(head)
	var r : float = max(box.size.x, box.size.z) * 0.5
	var mi := MeshInstance3D.new()
	mi.name = "brmod_" + key
	if key == "blindfold":
		mi.mesh = core.assets.blindfold_band(r)
		mi.position = box.get_center() + Vector3(0, box.size.y * 0.12, 0)
	else:
		mi.mesh = core.assets.headphones_head(r)
		mi.position = box.get_center() + Vector3(0, box.size.y * 0.05, 0)
	head.add_child(mi)

# ------------------------------------------------------------------ local-player conditions

func _process(delta):
	var inter = core.inter()
	if inter == null or inter.intermed_properties == null: return
	var me = inter.intermed_properties
	if me.get("brmod_drunk_active") == null: return
	var cam = me.cam.cam if me.cam else null
	if cam == null: return
	if me.brmod_drunk_active:
		_wobble_t += delta
		cam.h_offset = sin(_wobble_t * 1.3) * 0.35
		cam.v_offset = sin(_wobble_t * 0.9 + 1.0) * 0.18
	elif _wobble_t != 0.0:
		_wobble_t = 0.0
		cam.h_offset = 0.0
		cam.v_offset = 0.0

func set_deaf(on : bool) -> void:
	if on:
		for i in AudioServer.bus_count:
			if i == 0: continue
			var n := String(AudioServer.get_bus_name(i))
			if n.findn("music") == -1 and !AudioServer.is_bus_mute(i):
				AudioServer.set_bus_mute(i, true)
				_deaf_muted.append(i)
	else:
		for i in _deaf_muted:
			if i < AudioServer.bus_count: AudioServer.set_bus_mute(i, false)
		_deaf_muted.clear()
