extends RefCounted
# BRMod: item rules (validity, targets), the host-side item packet, and item effects on every client.

var core

func _init(c):
	core = c

func wait(s : float) -> Signal:
	return core.get_tree().create_timer(s, false).timeout

# ------------------------------------------------------------------ targets

func target_kind(id : int) -> String:
	match id:
		core.ID_SHOT, core.ID_PLUS4: return "any"
		core.ID_BLINDFOLD, core.ID_HEADPHONES, core.ID_TAPE: return "other"
		core.ID_STORM: return "number"
	return ""

func valid_targets(user, id : int) -> Array:
	var kind := target_kind(id)
	var out := []
	if kind == "number":
		return [1, 2, 3, 4, 5, 6]
	if kind == "": return out
	for p in user.intermediary.instance_handler.instance_property_array:
		if p.health_current <= 0: continue
		if kind == "other":
			if p.socket_number == user.socket_number: continue
			if id == core.ID_BLINDFOLD and p.brmod_blind: continue
			if id == core.ID_HEADPHONES and p.brmod_deaf: continue
			if id == core.ID_TAPE and (p.brmod_tape or p.brmod_tape_active): continue
		out.append(p.socket_number)
	return out

func target_options(user, id : int) -> Array:
	var opts := []
	if target_kind(id) == "number":
		for n in [1, 2, 3, 4, 5, 6]: opts.append([str(n), n])
		return opts
	for s in valid_targets(user, id):
		var p = core.get_props(user, s)
		var label : String = p.user_name
		if s == user.socket_number: label = core.t("СЕБЯ", "YOURSELF")
		opts.append([label, s])
	return opts

func target_title(id : int) -> String:
	match id:
		core.ID_STORM: return core.t("ГРОЗА: через сколько использований предметов?", "STORM: after how many item uses?")
		core.ID_SHOT: return core.t("ШОТ ВИСКИ: чьи предметы споить?", "WHISKEY SHOT: whose items?")
		core.ID_PLUS4: return core.t("УНО +4: кому превратить предметы в пиво?", "UNO +4: whose items become beer?")
		core.ID_BLINDFOLD: return core.t("ПОВЯЗКА: кому завязать глаза?", "BLINDFOLD: who?")
		core.ID_HEADPHONES: return core.t("НАУШНИКИ: на кого надеть?", "HEADPHONES: who?")
		core.ID_TAPE: return core.t("ИЗОЛЕНТА: кому связать руки?", "TAPE: whose hands?")
	return core.item_name(id)

# ------------------------------------------------------------------ validity (host and clients use the same rules)

func uno_red_valid(user) -> bool:
	if user.brmod_last_shot_shell not in ["live", "blank"]: return false
	var shooter = core.get_props(user, user.brmod_last_shooter)
	return shooter != null and shooter.health_current > 1

func jammer_can_target(user, target) -> bool:
	return target != null and target != user and target.health_current > 0 and !target.is_jammed and !target.brmod_jammer_immune

func slot_item(gs, socket : int, slot : int) -> Dictionary:
	if socket < 0 or socket >= gs.MAIN_inventory_by_socket.size(): return {}
	var inv : Array = gs.MAIN_inventory_by_socket[socket]
	if slot < 0 or slot >= inv.size(): return {}
	return inv[slot]

func enchant_of(inst) -> int:
	return inst.get_meta("brmod_enchant", core.ENCHANT_NONE) if is_instance_valid(inst) else core.ENCHANT_NONE

func roll_enchant() -> int:
	return randi_range(core.ENCHANT_BUNKER, core.ENCHANT_CODING)

func set_enchant(inst : Node3D, enchant : int) -> void:
	if enchant == core.ENCHANT_NONE and !inst.has_meta("brmod_enchant"): return
	var indicator = inst.get_child(0)
	if !inst.has_meta("brmod_base_description"):
		inst.set_meta("brmod_base_description", indicator.itemDescription)
	indicator.itemDescription = inst.get_meta("brmod_base_description")
	inst.set_meta("brmod_enchant", enchant)
	var detail := enchant_description(enchant)
	if !detail.is_empty(): indicator.itemDescription += "\n\n" + detail
	set_enchant_glint(inst, enchant)

func enchant_description(enchant : int) -> String:
	match enchant:
		core.ENCHANT_BUNKER:
			return core.t("Бункер\nПереживает взрыв ядерного гриба.", "Bunker\nSurvives the nuke.")
		core.ENCHANT_DOPAMINE:
			return core.t("Дофамин\nАдреналином этот предмет не украсть.", "Dopamine\nAdrenaline cannot steal this item.")
		core.ENCHANT_CODING:
			return core.t("Кодировка\nСохраняет свою способность под виски.", "Encoding\nKeeps its original effect under whiskey.")
	return ""

func set_enchant_glint(root : Node3D, enchant : int) -> void:
	var glint : ShaderMaterial = core.assets.enchant_glint(enchant)
	if root is MeshInstance3D:
		root.material_overlay = glint
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = glint

func item_in_chaos(inst) -> bool:
	return core.chaos_for(inst.get_child(1).socket_number) and enchant_of(inst) != core.ENCHANT_CODING

func can_use_instance(gs, user, inst, stealing : bool) -> bool:
	var branch = inst.get_child(1)
	if user.brmod_tape_active: return false
	if stealing:
		if branch.socket_number == user.socket_number or enchant_of(inst) == core.ENCHANT_DOPAMINE: return false
		if branch.item_id == core.ID_ADRENALINE: return false
	if branch.item_id == core.ID_ADRENALINE: return has_stealable_item(gs, user)
	if branch.item_id == core.ID_JAMMER: return gs.CheckIfJammerHasEligibleTargets(user)
	return item_in_chaos(inst) or !effect_invalid(gs, user, branch.item_id)

func has_stealable_item(gs, user) -> bool:
	for p in gs.instance_handler.instance_property_array:
		if p.socket_number == user.socket_number: continue
		for d in gs.MAIN_inventory_by_socket[p.socket_number]:
			if d != {} and can_use_instance(gs, user, d.item_instance, true): return true
	return false

func effect_invalid(gs, user, id : int) -> bool:
	match id:
		core.ID_SAW, core.ID_BARRELS: return gs.MAIN_barrel_sawed_off or core.st.triple
		core.ID_JAMMER: return !gs.CheckIfJammerHasEligibleTargets(user)
		core.ID_UNO_RED: return !uno_red_valid(user)
		core.ID_UNO_YELLOW: return user.brmod_uno_yellow
		core.ID_TOTEM: return true
		core.ID_STORM: return core.st.storm_pending
		core.ID_PILL_JAR: return user.brmod_jammer_immune
	if target_kind(id) != "": return valid_targets(user, id).is_empty()
	return false

func invalid_array(gs, user) -> Array:
	var a := []
	for id in 50:
		a.append(user.brmod_tape_active or effect_invalid(gs, user, id))
	a[core.ID_ADRENALINE] = user.is_stealing_item or !has_stealable_item(gs, user)
	return a

# host: will reflecting leave only one player alive? (then the turn ends with a win)
func uno_red_would_win(gs, socket : int) -> bool:
	var me = gs.GetSocketProperties(socket)
	if me == null or !uno_red_valid(me): return false
	var shooter = gs.GetSocketProperties(me.brmod_last_shooter)
	var victim = me if me.brmod_last_shot_shell == "blank" else shooter
	var damage : int = 1 if victim == me else me.brmod_last_shot_damage
	if victim.health_current > damage or core.has_totem(gs, victim.socket_number): return false
	var alive := 0
	for p in gs.instance_handler.instance_property_array:
		if p.health_current > 0 and p != victim: alive += 1
	return alive <= 1

func shotgun_blocked(p) -> bool:
	if p == null or !p.brmod_drunk_active: return false
	return core.has_item(p.intermediary.game_state, p.socket_number, core.ID_BEER)

# ------------------------------------------------------------------ host: build the "interact with item" packet

func host_item_packet(verifier, dict : Dictionary) -> void:
	var gs = verifier.game_state
	var socket : int = dict.sent_from_socket
	var user = gs.GetSocketProperties(socket)
	var real_id : int = dict.item_id
	var effect := real_id
	var b := {"real_id": real_id, "target": dict.get("brmod_target", -1)}
	var inst = gs.MAIN_inventory_by_socket[dict.item_socket_number][dict.local_grid_index].item_instance
	if item_in_chaos(inst):
		effect = chaos_effect(gs, user, dict.stealing_item)
		b.chaos = true
		var tg := valid_targets(user, effect)
		b.target = tg.pick_random() if !tg.is_empty() else -1
	match effect:
		core.ID_BEER: b.drunk = core.debug_force.get("drunk", randf() < core.beer_drunk_chance)
		core.ID_PILLS: b.pills = core.debug_force.get("pills", "heal" if randf() < 0.5 else "hurt")
		core.ID_SMOKE: b.smoke = smoke_plan(gs, dict.item_socket_number, dict.local_grid_index)
		core.ID_PLUS4: b.plus4 = plus4_plan(gs, int(b.target), dict.item_socket_number, dict.local_grid_index)
		core.ID_ADRENALINE_ZERO: b.zero_sugar = zero_sugar_plan(gs, dict.item_socket_number, dict.local_grid_index)
	# storm: count every item use after the cloud was set
	if effect == core.ID_STORM:
		core.st.storm_left = int(b.target)
	elif core.st.storm_left > 0:
		core.st.storm_left -= 1
		b.storm_left = core.st.storm_left
		if core.st.storm_left == 0:
			gs.MAIN_active_sequence_dict.sequence_in_shotgun.shuffle()
			b.storm_trigger = true
			print("[BRMod] STORM shuffled the shells")
	var ending : bool = gs.CheckIfEndingTurnAfterItemUse(effect, socket)
	if effect == core.ID_PILLS and b.pills == "hurt" and user.health_current - 1 <= 0 and !core.has_totem(gs, socket):
		ending = true
	var seq : Array = gs.MAIN_active_sequence_dict.sequence_in_shotgun
	var shell : String = seq[0] if !seq.is_empty() else "blank"
	if effect == core.ID_GLASS and shell == "hidden": shell = "live"
	var packet := {
		"packet category": "MP_UserInstanceProperties",
		"packet alias": "interact with item",
		"sent_from": "host",
		"packet_id": 23,
		"item_socket_number": dict.item_socket_number,
		"local_grid_index": dict.local_grid_index,
		"item_id": effect,
		"socket_number": socket,
		"stealing_item": dict.stealing_item,
		"ending_turn_after_item_use": ending,
		"current_shell_in_chamber": shell if effect in [core.ID_GLASS, core.ID_BEER] else "",
		"phone_verbal_shell": "",
		"phone_verbal_index": "",
		"brmod": b,
	}
	print("[BRMod] host item packet: real %d -> effect %d, brmod %s" % [real_id, effect, b])
	if b.get("chaos", false): core.debug_last_effect = effect
	var packets = verifier.packets
	if effect != core.ID_PHONE:
		packets.send_p2p_packet(0, packet)
		packets.PipeData(packet)
		return
	var custom_packet := packet.duplicate(true)
	custom_packet.phone_verbal_index = gs.GetBurnerPhone_VerbalIndex()
	custom_packet.phone_verbal_shell = gs._GetBurnerPhone_Shell(custom_packet.phone_verbal_index)
	var custom_id = gs.GetSocketID(socket)
	for p in verifier.instance_handler.instance_property_array:
		if p.user_id != custom_id and p.user_id != core.get_node("/root/GlobalSteam").HOST_ID:
			packets.send_p2p_packet(p.user_id, packet)
	if custom_id != core.get_node("/root/GlobalSteam").HOST_ID:
		packets.send_p2p_packet(custom_id, custom_packet)
	packets.PipeData(custom_packet)

func chaos_effect(gs, user, stealing : bool) -> int:
	var inv := invalid_array(gs, user)
	var pool := []
	for r in gs.MAIN_item_resource_array:
		var id : int = r.id
		if !r.distribution_enabled and !core.is_custom_flow(id): continue
		if id == core.ID_TOTEM: continue
		if stealing and id == core.ID_ADRENALINE: continue
		if id in core.debug_force.get("chaos_exclude", []): continue
		if inv[id]: continue
		if target_kind(id) != "" and valid_targets(user, id).is_empty(): continue
		pool.append(id)
	if pool.is_empty(): return 4
	return pool.pick_random()

func smoke_plan(gs, used_socket : int, used_slot : int) -> Array:
	var src := []
	for p in gs.instance_handler.instance_property_array:
		for i in 8:
			if p.socket_number == used_socket and i == used_slot: continue
			if gs.MAIN_inventory_by_socket[p.socket_number][i] != {}: src.append([p.socket_number, i])
	var dst := src.duplicate()
	dst.shuffle()
	var plan := []
	for k in src.size(): plan.append([src[k][0], src[k][1], dst[k][0], dst[k][1]])
	return plan

func plus4_plan(gs, target : int, used_socket : int, used_slot : int) -> Array:
	if target < 0 or target > 3: return []
	var slots := []
	for i in 8:
		if target == used_socket and i == used_slot: continue
		if gs.MAIN_inventory_by_socket[target][i] != {}: slots.append(i)
	slots.shuffle()
	return slots.slice(0, 4)

func zero_sugar_plan(gs, used_socket : int, used_slot : int) -> Dictionary:
	var slots := []
	for p in gs.instance_handler.instance_property_array:
		for i in 8:
			if p.socket_number == used_socket and i == used_slot: continue
			if gs.MAIN_inventory_by_socket[p.socket_number][i] != {}:
				slots.append([p.socket_number, i])
	if core.debug_force.get("zero_sugar_destroy", randf() < 0.05):
		return {"destroy": slots.pick_random() if !slots.is_empty() else []}
	for entry in slots:
		entry.append(roll_enchant())
	return {"enchant": slots}

# ------------------------------------------------------------------ host: UNO SWAP before a shot

func host_apply_uno_yellow(gs, shooter_socket : int, target_socket : int) -> void:
	if shooter_socket == target_socket: return
	var target = gs.GetSocketProperties(target_socket)
	if target == null or !target.brmod_uno_yellow: return
	var seq : Array = gs.MAIN_active_sequence_dict.sequence_in_shotgun
	if seq.is_empty(): return
	if seq[0] == core.shells.BLACK: return
	seq[0] = "blank" if seq[0] == "live" else "live"
	print("[BRMod] UNO SWAP inverted shell to ", seq[0], " (socket %d -> %d)" % [shooter_socket, target_socket])

# every client, when the shot packet arrives (from the shooter's instance only)
func on_shot_fired(any_props, shooter_socket : int, target_socket : int, shell : String) -> void:
	if shooter_socket == target_socket: return
	var target = core.get_props(any_props, target_socket)
	if target == null or !target.brmod_uno_yellow: return
	target.brmod_uno_yellow = false
	await wait(1.0)
	core.fx.play("uno")
	var marker = target.get_meta("brmod_marker") if target.has_meta("brmod_marker") else null
	if marker != null and is_instance_valid(marker):
		core.fx.flash(marker.global_position, core.fx.COLOR_YELLOW, 1.0)
		var t : Tween = marker.create_tween()
		t.tween_property(marker, "position:y", marker.position.y + 1.5, 0.5)
		t.parallel().tween_property(marker, "rotation_degrees:z", 180.0, 0.5)
		t.tween_property(marker, "scale", Vector3.ONE * 0.01, 0.3)
		t.tween_callback(marker.queue_free)
	if target.has_meta("brmod_marker"): target.remove_meta("brmod_marker")
	var text : String = core.t("УНО: ПОДМЕНА у %s сработала — патрон перевёрнут!", "%s's UNO SWAP triggered — the shell was flipped!")
	if shell == core.shells.BLACK:
		text = core.t("УНО: ПОДМЕНА у %s израсходована на чёрный патрон", "%s's UNO SWAP was spent on a black shell")
	core.notify(text % target.user_name, 4.0, core.fx.COLOR_YELLOW)

func show_marker(props) -> void:
	clear_marker(props)
	var parent : Node3D = props.item_manager.item_spawn_parent_local
	var base = core.res(core.BASE_ITEM_ID)
	var center := Vector3.ZERO
	for p in base.pos_grid_offset_array_local: center += p
	center /= max(1, base.pos_grid_offset_array_local.size())
	var mi := MeshInstance3D.new()
	mi.name = "brmod_marker"
	mi.mesh = core.assets._meshes.get(core.ID_UNO_YELLOW)
	parent.add_child(mi)
	# the HP indicator sits in the middle of the grid: put the card further out, in the free zone below it
	var out : Vector3 = center - parent.to_local(core.fx.table_center())
	out.y = 0.0
	out = out.normalized() if out.length() > 0.001 else Vector3.ZERO
	var reach := 0.0
	for p in base.pos_grid_offset_array_local: reach = max(reach, (p - center).dot(out))
	mi.position = center + out * reach * core.marker_out + Vector3(0, 0.25, 0)
	props.set_meta("brmod_marker", mi)

func clear_marker(props) -> void:
	var m = props.get_meta("brmod_marker") if props.has_meta("brmod_marker") else null
	if m != null and is_instance_valid(m): m.queue_free()
	if props.has_meta("brmod_marker"): props.remove_meta("brmod_marker")

# ------------------------------------------------------------------ turn / round hooks (every client)

func on_turn_start(gs, to_socket : int, prev_socket : int) -> void:
	var props_arr = gs.instance_handler.instance_property_array
	for p in props_arr:
		if p.socket_number != to_socket:
			p.brmod_tape_active = false
			p.brmod_drunk_active = false
	if to_socket == prev_socket: return
	var p = gs.GetSocketProperties(to_socket)
	if p == null: return
	p.brmod_jammer_immune = false
	if p.brmod_uno_yellow:
		p.brmod_uno_yellow = false
		clear_marker(p)
		core.notify(core.t("УНО: ПОДМЕНА у %s закончилась", "%s's UNO SWAP expired") % p.user_name, 3.0)
	var expired := []
	for s in core.st.chaos:
		if core.st.chaos[s] == to_socket: expired.append(s)
	for s in expired: core.st.chaos.erase(s)
	if !expired.is_empty():
		core.notify(core.t("Виски выветрился — предметы снова в порядке", "The whiskey wore off — items are back to normal"), 3.5)
	if p.brmod_blind:
		p.brmod_blind = false
		core.fx.set_head_prop(p, "blindfold", false)
		if p.is_active: core.ui.set_blind(false)
	if p.brmod_deaf:
		p.brmod_deaf = false
		core.fx.set_head_prop(p, "headphones", false)
		if p.is_active: core.fx.set_deaf(false)
	if p.brmod_drunk_pending:
		p.brmod_drunk_pending = false
		p.brmod_drunk_active = true
		core.fx.play("hic")
		if p.is_active:
			core.notify(core.t("Ты пьян! Пока не выпьешь всё своё пиво — стрелять нельзя", "You're drunk! Drink all your beer before you can shoot"), 6.0, Color(1, 0.8, 0.3))
		else:
			core.notify(core.t("%s пьян и должен допить всё пиво", "%s is drunk and must finish all the beer") % p.user_name, 4.0)
	if p.brmod_tape:
		p.brmod_tape = false
		p.brmod_tape_active = true
		core.notify(core.t("У %s связаны руки — только выстрел", "%s's hands are tied — shooting only") % p.user_name, 4.0, Color(0.5, 0.7, 1))
		_tape_autopickup(gs, p)

func _tape_autopickup(gs, p) -> void:
	await wait(1.7)
	if !p.brmod_tape_active or gs.MAIN_active_current_turn_socket != p.socket_number or !p.has_turn or p.is_holding_shotgun: return
	if p.is_active:
		p.shotgun.PickupShotgun()
	elif core.get_node("/root/GlobalVariables").mp_debugging:
		p.intermediary.packets.PipeData({"packet category": "MP_PacketVerification", "packet alias": "pickup shotgun request", "sent_from": "client", "packet_id": 10, "sent_from_socket": p.socket_number})

func reset_round(gs) -> void:
	core.st.chaos.clear()
	core.st.storm_pending = false
	core.st.storm_left = 0
	if core.st.triple: end_triple()
	_remove_storm_cloud()
	for p in gs.instance_handler.instance_property_array:
		p.brmod_last_shooter = -1
		p.brmod_last_shot_shell = ""
		p.brmod_last_shot_damage = 0
		p.brmod_last_shot_damage_taken = 0
		p.brmod_uno_yellow = false
		p.brmod_deaf = false
		p.brmod_tape = false
		p.brmod_tape_active = false
		p.brmod_drunk_pending = false
		p.brmod_drunk_active = false
		clear_marker(p)
		core.fx.set_head_prop(p, "headphones", false)
	core.fx.set_deaf(false)

# ------------------------------------------------------------------ every item packet (all clients)

func on_any_item(ii, packet : Dictionary) -> void:
	var b : Dictionary = packet.get("brmod", {})
	var user = ii.properties
	var id : int = packet.item_id
	if b.get("chaos", false):
		core.notify(core.t("%s: предмет под виски сработал как «%s»", "%s: the drunk item worked as \"%s\"") % [user.user_name, core.item_name(id)], 4.0, Color(0.95, 0.7, 0.3))
	elif core.is_custom_flow(id):
		core.notify(core.t("%s использует «%s»", "%s uses \"%s\"") % [user.user_name, core.item_name(id)], 3.0)
	if b.has("storm_left") and !b.get("storm_trigger", false) and core.st.storm_pending:
		core.notify(core.t("Гроза: перемешивание через %d", "Storm: shuffle in %d") % b.storm_left, 2.5, Color(0.7, 0.8, 1))
	if b.get("storm_trigger", false):
		core.st.storm_pending = false
		core.st.storm_left = 0
		_storm_strike()
	if id == core.ID_BEER and b.get("drunk", false):
		user.brmod_drunk_pending = true
		_drunk_notice(user)

func _drunk_notice(user) -> void:
	await wait(1.5)
	core.fx.play("hic")
	core.notify(core.t("%s опьянел! В свой следующий ход должен допить всё пиво", "%s got drunk! Next turn: finish all the beer first") % user.user_name, 4.5, Color(1, 0.8, 0.3))

# ------------------------------------------------------------------ item effects (ChangeGameStateWithItem for custom ids)

func apply_effect(ii, id : int, packet : Dictionary) -> void:
	var me = ii.properties
	var gs = me.intermediary.game_state
	var b : Dictionary = packet.get("brmod", {})
	var target := int(b.get("target", -1))
	match id:
		core.ID_UNO_RED: await _uno_red(me)
		core.ID_UNO_YELLOW:
			me.brmod_uno_yellow = true
			await wait(1.2)
			show_marker(me)
		core.ID_TOTEM: pass
		core.ID_WHISKEY:
			for p in gs.instance_handler.instance_property_array: core.st.chaos[p.socket_number] = me.socket_number
			await wait(1.0)
			core.fx.play("drink")
			for p in gs.instance_handler.instance_property_array:
				core.fx.flash(p.item_manager.item_spawn_parent_local.global_position, Color(0.9, 0.55, 0.15), 1.4, 5.0, 10.0)
			core.notify(core.t("ВИСКИ: на круг все предметы на столе работают случайно!", "WHISKEY: for one lap every item on the table works randomly!"), 5.0, Color(0.95, 0.7, 0.3))
		core.ID_SHOT:
			var tp = core.get_props(me, target)
			if tp == null: return
			core.st.chaos[target] = me.socket_number
			await wait(1.0)
			core.fx.play("drink")
			core.fx.flash(tp.item_manager.item_spawn_parent_local.global_position, Color(0.9, 0.55, 0.15), 1.4, 5.0, 10.0)
			core.notify(core.t("ШОТ ВИСКИ: предметы %s на круг работают случайно!", "WHISKEY SHOT: %s's items work randomly for one lap!") % tp.user_name, 5.0, Color(0.95, 0.7, 0.3))
		core.ID_NUKE: await _nuke(me, gs)
		core.ID_SMOKE: await _smoke(gs, b.get("smoke", []))
		core.ID_STORM:
			core.st.storm_pending = true
			core.st.storm_left = target
			await wait(1.0)
			_spawn_storm_cloud()
			core.fx.play("thunder", -8.0, 1.4)
			core.notify(core.t("ГРОЗА: патроны перемешаются через %d использований предметов", "STORM: the shells will be shuffled after %d item uses") % target, 5.0, Color(0.7, 0.8, 1))
		core.ID_PLUS4: await _plus4(me, gs, target, b.get("plus4", []))
		core.ID_PILLS: await _pills(me, b.get("pills", "heal"))
		core.ID_ADRENALINE_ZERO: _zero_sugar(gs, b.get("zero_sugar", {}))
		core.ID_PILL_JAR:
			me.brmod_jammer_immune = true
		core.ID_BARRELS:
			core.st.triple = true
			await wait(1.4)
			set_barrels_visual(true)
			core.notify(core.t("Следующий выстрел %s в соперника заденет всех!", "%s's next shot at an opponent hits everyone!") % me.user_name, 4.0)
		core.ID_BLINDFOLD:
			var tp = core.get_props(me, target)
			if tp == null: return
			tp.brmod_blind = true
			await wait(1.2)
			core.fx.set_head_prop(tp, "blindfold", tp.brmod_blind)
			if tp.is_active and tp.brmod_blind: core.ui.set_blind(true)
			core.notify(core.t("%s завязали глаза до его хода", "%s is blindfolded until their turn") % tp.user_name, 4.0)
		core.ID_HEADPHONES:
			var tp = core.get_props(me, target)
			if tp == null: return
			tp.brmod_deaf = true
			await wait(1.2)
			core.fx.set_head_prop(tp, "headphones", tp.brmod_deaf)
			if tp.is_active and tp.brmod_deaf: core.fx.set_deaf(true)
			core.notify(core.t("%s слышит только музыку до своего хода", "%s hears only music until their turn") % tp.user_name, 4.0)
		core.ID_TAPE:
			var tp = core.get_props(me, target)
			if tp == null: return
			tp.brmod_tape = true
			await wait(1.0)
			core.fx.play("tape")
			core.notify(core.t("%s связали руки изолентой: в свой ход только выстрел", "%s's hands are taped: shooting only on their turn") % tp.user_name, 4.0, Color(0.5, 0.7, 1))

func _uno_red(me) -> void:
	if !uno_red_valid(me): return
	var shooter = core.get_props(me, me.brmod_last_shooter)
	var victim = me if me.brmod_last_shot_shell == "blank" else shooter
	var damage : int = 1 if victim == me else me.brmod_last_shot_damage
	var healed : int = clamp(6 - me.health_current, 0, me.brmod_last_shot_damage_taken) if victim == shooter else 0
	me.brmod_last_shooter = -1
	me.brmod_last_shot_shell = ""
	me.brmod_last_shot_damage = 0
	me.brmod_last_shot_damage_taken = 0
	me.health_current += healed
	var dealt : int = core.deal_damage(victim, me.socket_number, damage)
	if victim == shooter: me.stat_damage_dealt += dealt
	print("[BRMod] UNO REVERSE: socket %d heals %d, socket %d takes %d" % [me.socket_number, healed, victim.socket_number, dealt])
	await wait(1.5)
	core.fx.play("uno")
	core.fx.flash(victim.instance_root.global_position, core.fx.COLOR_RED, 1.2)
	victim.death.DeathRequest("forward" if victim == me else shooter.GetDirection(shooter.socket_number, me.socket_number))
	if healed > 0:
		me.health_counter.healing_health = true
		me.health_counter.UpdateDisplay()
	_final_shot_check(me)

func _final_shot_check(me) -> void:
	var alive := 0
	for p in me.intermediary.instance_handler.instance_property_array:
		if p.health_current > 0: alive += 1
	if alive == 1: me.shotgun.CheckIfFinalShot()

func _pills(me, roll : String) -> void:
	if roll == "heal":
		me.health_current = min(me.health_current + 2, 6)
		await wait(1.6)
		core.fx.play("heal")
		core.fx.burst(me.instance_root.global_position + Vector3(0, 4, 0), [core.fx.COLOR_GREEN, Color.WHITE], 40, 4.0, 2.0, 1.2, 0.1)
		me.health_counter.healing_health = true
		me.health_counter.UpdateDisplay()
	else:
		core.deal_damage(me, me.socket_number, 1)
		await wait(1.6)
		core.fx.play("pills_bad")
		me.death.DeathRequest("forward")
		_final_shot_check(me)

func _nuke(me, gs) -> void:
	var victims := []
	for p in gs.instance_handler.instance_property_array:
		for i in 8:
			var d = gs.MAIN_inventory_by_socket[p.socket_number][i]
			if d == {} or enchant_of(d.item_instance) == core.ENCHANT_BUNKER: continue
			victims.append(d.item_instance)
			p.item_interaction.RemoveItemFromInventory(i, p.socket_number)
	await wait(1.0)
	core.fx.play("nuke", 3.0)
	var c : Vector3 = core.fx.table_center()
	core.fx.flash(c, Color(1.0, 0.6, 0.2), 2.5, 25.0, 60.0)
	core.fx.burst(c + Vector3(0, 2, 0), [Color(1, 0.6, 0.1), Color(0.3, 0.28, 0.25)], 160, 14.0, 4.0, 2.5, 0.3)
	core.fx.shake_all()
	for inst in victims:
		core.fx.poof_item(inst, Color(1, 0.5, 0.1), 4.0)
	core.notify(core.t("ЯДЕРНЫЙ ГРИБ: уничтожено предметов — %d", "NUKE: %d items destroyed") % victims.size(), 4.0, Color(1, 0.6, 0.3))

func _zero_sugar(gs, plan : Dictionary) -> void:
	for entry in plan.get("enchant", []):
		var d := slot_item(gs, entry[0], entry[1])
		if d != {}: set_enchant(d.item_instance, entry[2])
	var victim : Array = plan.get("destroy", [])
	if victim.is_empty(): return
	var d := slot_item(gs, victim[0], victim[1])
	if d == {}: return
	gs.GetSocketProperties(victim[0]).item_interaction.RemoveItemFromInventory(victim[1], victim[0])
	core.fx.poof_item(d.item_instance, Color(0.85, 0.9, 1.0), 1.4)

func _smoke(gs, plan : Array) -> void:
	var moving := []
	for e in plan:
		var d = gs.MAIN_inventory_by_socket[e[0]][e[1]]
		if d == {} or d.item_instance == null: continue
		moving.append([d, e[2], e[3]])
	for e in plan:
		_clear_slot(gs, e[0], e[1])
	for m in moving:
		_place(gs, m[0].item_instance, m[0].item_id, m[1], m[2])
	core.fx.play("smoke")
	core.fx.smoke_cloud(core.fx.table_center() + Vector3(0, 1, 0), 14.0, 3.0)
	await wait(0.6)
	for m in moving:
		var inst : Node3D = m[0].item_instance
		var r = core.res(m[0].item_id)
		if inst == null or !is_instance_valid(inst) or r == null: continue
		var t := inst.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(inst, "position", r.pos_grid_offset_array_local[m[2]], 1.0)
		t.parallel().tween_property(inst, "rotation_degrees", r.rot_grid_offset_array_local[m[2]], 1.0)
	core.notify(core.t("ДЫМ: предметы перемешались между игроками!", "SMOKE: items were shuffled between players!"), 4.0)
	await wait(1.0)

func _clear_slot(gs, socket : int, slot : int) -> void:
	var d = gs.MAIN_inventory_by_socket[socket][slot]
	if d == {}: return
	var p = gs.GetSocketProperties(socket)
	if p:
		p.user_inventory_count_by_item_id[d.item_id] -= 1
		p.user_inventory[slot] = {}
		p.user_inventory_instance_array[slot] = null
	gs.MAIN_inventory_by_socket[socket][slot] = {}

func _place(gs, inst : Node3D, id : int, socket : int, slot : int) -> void:
	var p = gs.GetSocketProperties(socket)
	if p == null or inst == null: return
	gs.MAIN_inventory_by_socket[socket][slot] = {"item_name": inst.get_child(1).itemName, "item_instance": inst, "item_id": id}
	p.user_inventory[slot] = {"item_id": id, "item_local_grid_index": slot}
	p.user_inventory_instance_array[slot] = inst
	p.user_inventory_count_by_item_id[id] += 1
	inst.get_child(1).socket_number = socket
	inst.get_child(1).local_grid_index = slot
	var parent : Node3D = p.item_manager.item_spawn_parent_local
	if inst.get_parent() != parent:
		var gt := inst.global_transform
		inst.get_parent().remove_child(inst)
		parent.add_child(inst)
		inst.global_transform = gt

func spawn_item(p, id : int, slot : int) -> Node3D:
	var gs = p.intermediary.game_state
	var r = core.res(id)
	if r == null: return null
	var inst : Node3D = r.instance.instantiate()
	p.item_manager.item_spawn_parent_local.add_child(inst)
	inst.transform.origin = r.pos_grid_offset_array_local[slot]
	inst.rotation_degrees = r.rot_grid_offset_array_local[slot]
	inst.get_child(1).local_grid_index = slot
	inst.get_child(1).socket_number = p.socket_number
	gs.Global_AddItemToInventory(p.socket_number, inst, id, slot)
	p.user_inventory[slot] = {"item_id": id, "item_local_grid_index": slot}
	p.user_inventory_instance_array[slot] = inst
	p.user_inventory_count_by_item_id[id] += 1
	gs.global_item_count_on_table_by_id[id] += 1
	return inst

func _plus4(me, gs, target : int, slots : Array) -> void:
	var tp = gs.GetSocketProperties(target)
	if tp == null: return
	var old := []
	var new_items := []
	for s in slots:
		var d = gs.MAIN_inventory_by_socket[target][s]
		if d == {}: continue
		old.append(d.item_instance)
		tp.item_interaction.RemoveItemFromInventory(s, target)
		var inst := spawn_item(tp, core.ID_BEER, s)
		if inst:
			inst.visible = false
			new_items.append(inst)
	await wait(1.2)
	core.fx.play("uno")
	for inst in old: core.fx.poof_item(inst, Color(0.9, 0.9, 0.9), 1.0)
	await wait(0.6)
	for inst in new_items:
		if !is_instance_valid(inst): continue
		inst.visible = true
		inst.scale = Vector3.ONE * 0.01
		inst.create_tween().tween_property(inst, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	core.notify(core.t("УНО +4: у %s %d предмет(а) стали пивом!", "UNO +4: %d of %s's items became beer!") % ([tp.user_name, new_items.size()] if core.ru() else [new_items.size(), tp.user_name]), 4.0)

# ------------------------------------------------------------------ storm cloud visual

func _spawn_storm_cloud() -> void:
	_remove_storm_cloud()
	var root : Node = core.get_tree().current_scene
	if root == null: return
	var mi := MeshInstance3D.new()
	mi.name = "brmod_storm_cloud"
	mi.mesh = core.assets._meshes.get(core.ID_STORM)
	root.add_child(mi)
	mi.global_position = core.fx.table_center() + Vector3(0, 7.0, 0)
	mi.scale = Vector3.ONE * 2.2
	var t := mi.create_tween().set_loops()
	t.tween_property(mi, "rotation_degrees:y", 360.0, 12.0).from(0.0)

func _remove_storm_cloud() -> void:
	var root : Node = core.get_tree().current_scene
	if root == null: return
	var old := root.get_node_or_null("brmod_storm_cloud")
	if old: old.queue_free()

func _storm_strike() -> void:
	await wait(1.6)
	_remove_storm_cloud()
	core.fx.lightning()
	core.notify(core.t("ГРОЗА: патроны в дробовике перемешаны!", "STORM: the shells were shuffled!"), 4.5, Color(0.7, 0.8, 1))

# ------------------------------------------------------------------ extra barrels

func set_barrels_visual(on : bool) -> void:
	var inter = core.inter()
	if inter == null: return
	var segs := [inter.globalparent_shotgun_cut_segment]
	for p in inter.instance_handler.instance_property_array:
		segs.append(p.shotgun.localparent_shotgun_cut_segment)
	for seg in segs:
		if seg == null: continue
		var parent : Node3D = seg.get_parent()
		for n in ["brmod_barrel_a", "brmod_barrel_b"]:
			var old = parent.get_node_or_null(n)
			if old: old.queue_free()
		if !on: continue
		var mesh_node := _first_geometry(seg)
		var side := Vector3.RIGHT
		var thick := 0.3
		if mesh_node and mesh_node is MeshInstance3D and mesh_node.mesh:
			var ga : AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
			var sz := ga.size
			if sz.x >= sz.z: side = Vector3(0, 0, 1)
			else: side = Vector3(1, 0, 0)
			thick = min(sz.y, min(sz.x, sz.z)) * 1.15
		var k := 0
		for n in ["brmod_barrel_a", "brmod_barrel_b"]:
			var d : Node3D = seg.duplicate()
			d.name = n
			d.visible = true
			parent.add_child(d)
			d.transform = seg.transform
			var off_g : Vector3 = side * thick * (1.0 if k == 0 else -1.0)
			d.position += parent.global_transform.basis.inverse() * off_g
			k += 1

func _first_geometry(n : Node) -> Node:
	if n is GeometryInstance3D: return n
	for c in n.get_children():
		var r = _first_geometry(c)
		if r: return r
	return null

func end_triple() -> void:
	core.st.triple = false
	set_barrels_visual(false)
