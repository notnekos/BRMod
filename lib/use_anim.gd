extends RefCounted
# BRMod: generic "use" animations for items that have no animation in the game.

var core

func _init(c):
	core = c

func _hold(id : int) -> float:
	match id:
		core.ID_UNO_RED: return 2.4
		core.ID_NUKE, core.ID_SMOKE, core.ID_PLUS4: return 1.9
		core.ID_PILLS, core.ID_PILL_JAR, core.ID_ADRENALINE_ZERO: return 1.8
		core.ID_WHISKEY, core.ID_SHOT, core.ID_STORM, core.ID_BARRELS: return 1.0
	return 0.5

func _color(id : int) -> Color:
	match id:
		core.ID_UNO_RED: return core.fx.COLOR_RED
		core.ID_UNO_YELLOW: return core.fx.COLOR_YELLOW
		core.ID_WHISKEY, core.ID_SHOT: return Color(0.95, 0.6, 0.2)
		core.ID_NUKE: return Color(1, 0.5, 0.1)
		core.ID_STORM, core.ID_TAPE: return Color(0.5, 0.65, 1)
		core.ID_PILLS: return Color(0.4, 1, 0.4)
	return Color(0.9, 0.9, 0.85)

func _is_card(id : int) -> bool:
	return id in [core.ID_UNO_RED, core.ID_UNO_YELLOW, core.ID_PLUS4]

func first_person(ii, item : Node3D, id : int) -> void:
	var props = ii.properties
	var r = core.res(id)
	if r:
		props.item_manager.speaker_fp_grab_item_on_table.stream = r.sound_pick_up_fp
		props.item_manager.speaker_fp_grab_item_on_table.play()
	item.get_child(0).lerpEnabled = false
	var gt := item.global_transform
	item.get_parent().remove_child(item)
	ii.pos_pickup_item.get_parent().add_child(item)
	item.global_transform = gt
	var cam : Camera3D = core.get_viewport().get_camera_3d()
	var show_xf := gt
	var up := Vector3.UP
	if cam:
		var f : Vector3 = -cam.global_transform.basis.z
		up = cam.global_transform.basis.y
		var right : Vector3 = cam.global_transform.basis.x
		var b : Basis
		if _is_card(id):
			b = Basis(right, -f, -up) # card face towards the camera, top of texture up
		else:
			b = Basis(right, up, -f).rotated(right, 0.35)
		show_xf = Transform3D(b, cam.global_position + f * 6.5 - up * 0.9 - b * _local_center(item))
	var from_xf := item.global_transform
	var t := item.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_lerp_xf.bind(item, from_xf, show_xf), 0.0, 1.0, 0.6)
	await t.finished
	await _flourish(item, id, up)

func _mesh_center(item : Node3D) -> Vector3:
	return item.global_position

func _local_center(item : Node3D) -> Vector3:
	for c in item.get_children():
		if c is MeshInstance3D and c.mesh:
			return c.transform * c.mesh.get_aabb().get_center()
	return Vector3.ZERO

func _lerp_xf(k : float, item : Node3D, a : Transform3D, b : Transform3D) -> void:
	if is_instance_valid(item): item.global_transform = a.interpolate_with(b, k)

func _spin(k : float, item : Node3D, base : Transform3D, axis : Vector3, pivot : Vector3) -> void:
	if !is_instance_valid(item): return
	var rb := base.basis.rotated(axis, k * TAU) * Basis.from_scale(Vector3.ONE * (1.0 + 0.25 * sin(k * PI)))
	item.global_transform = Transform3D(rb, pivot - rb * (base.basis.inverse() * (pivot - base.origin)))

func _flourish(item : Node3D, id : int, axis : Vector3) -> void:
	var snd := "uno_use"
	if id in [core.ID_WHISKEY, core.ID_SHOT]: snd = "drink"
	elif id in [core.ID_PILLS, core.ID_PILL_JAR]: snd = "pills"
	elif id == core.ID_ADRENALINE_ZERO: snd = "drink"
	core.fx.play(snd, -4.0)
	var center : Vector3 = item.global_transform * _local_center(item)
	core.fx.flash(center, _color(id), 0.9)
	var base := item.global_transform
	var t := item.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(_spin.bind(item, base, axis, center), 0.0, 1.0, 0.9)
	await t.finished
	await core.get_tree().create_timer(_hold(id), false).timeout
	if !is_instance_valid(item): return
	var t2 := item.create_tween()
	t2.tween_property(item, "scale", Vector3.ONE * 0.01, 0.25)
	await t2.finished
	if is_instance_valid(item): item.queue_free()

func third_person(ii, id : int) -> void:
	var hands = ii.hands
	var mesh : Node3D = hands.active_mesh
	if mesh:
		core.fx.flash(mesh.global_position, _color(id), 0.9)
		var rot := mesh.rotation_degrees
		var t := mesh.create_tween()
		t.tween_property(mesh, "rotation_degrees:y", rot.y + 360.0, 0.9)
		await t.finished
		if is_instance_valid(mesh): mesh.rotation_degrees = rot
	await core.get_tree().create_timer(_hold(id) + 0.2, false).timeout
	if hands.active_hand: hands.active_hand.visible = false
	if mesh: mesh.visible = false
	if hands.active_hand_default: hands.active_hand_default.visible = true
