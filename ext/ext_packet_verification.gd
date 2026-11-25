extends "res://multiplayer/scripts/global scripts/MP_PacketVerification.gd"
# BRMod (host side): validate mod rules, build item packets with host-decided randomness, UNO SWAP.

func _br():
	return get_node_or_null("/root/BRMod")

func VerifyPacket(packet_data):
	var verified = super(packet_data)
	var b = _br()
	if b == null or !(verified is Dictionary) or verified == {}: return verified
	var pid = packet_data.get("packet_id", -1)
	var props = game_state.GetSocketProperties(packet_data.get("sent_from_socket", -1))
	if props == null: return verified
	if pid == 22:
		var owner : int = packet_data.item_socket_number
		if packet_data.stealing_item == (owner == props.socket_number): return {}
		var item : Dictionary = b.items.slot_item(game_state, owner, packet_data.get("local_grid_index", -1))
		var id : int = packet_data.item_id
		if item == {} or item.item_id != id or !is_instance_valid(item.item_instance): return {}
		if !b.items.can_use_instance(game_state, props, item.item_instance, packet_data.stealing_item): return {}
		if !b.items.item_in_chaos(item.item_instance):
			if b.items.target_kind(id) != "" and !(packet_data.get("brmod_target", -1) in b.items.valid_targets(props, id)):
				print("[BRMod] rejected item ", id, ": bad target ", packet_data.get("brmod_target", -1))
				return {}
	elif pid == 24:
		var target = game_state.GetSocketProperties(packet_data.get("item_selected_socket_number", -1))
		if packet_data.get("item_id") != b.ID_JAMMER or !b.items.jammer_can_target(props, target): return {}
	elif pid == 19:
		var slot : int = packet_data.get("local_grid_index", -1)
		if slot < 0 or slot >= props.user_inventory.size() or props.user_inventory[slot] != {}: return {}
	elif pid == 10:
		if b.items.shotgun_blocked(props):
			print("[BRMod] rejected shotgun pickup: drunk with beer left (socket %d)" % props.socket_number)
			return {}
	return verified

func PacketSort(dict : Dictionary):
	var b = _br()
	if b:
		var alias = dict.values()[1]
		if alias == "interact with item request":
			b.items.host_item_packet(self, dict)
			return
		if alias == "shoot user request":
			var seq : Array = game_state.MAIN_active_sequence_dict.sequence_in_shotgun
			if seq.is_empty(): return
			if seq[0] == b.shells.BLACK:
				_send_black_shot(b, dict, seq.size() - 1)
				return
			b.items.host_apply_uno_yellow(game_state, dict.sent_from_socket, dict.socket_to_shoot)
		if alias == "grab item request":
			var p = GetSocketProperties(dict.sent_from_socket)
			var id = game_state.GetItemToGrab(p, true)
			if id == null: return
			var enchant : int = b.ENCHANT_NONE
			if randf() < b.enchant_chance: enchant = b.items.roll_enchant()
			_broadcast({
				"packet category": "MP_UserInstanceProperties",
				"packet alias": "grab item",
				"sent_from": "host",
				"packet_id": 18,
				"socket_number": p.socket_number,
				"item_id": id,
				"brmod_enchant": enchant,
			})
			return
	super(dict)

func _send_black_shot(b, dict : Dictionary, remaining : int) -> void:
	var shooter : int = dict.sent_from_socket
	var target : int = dict.socket_to_shoot
	var outcome : String = b.shells.black_outcome()
	_broadcast({
		"packet category": "MP_UserInstanceProperties",
		"packet alias": "shoot user",
		"sent_from": "host",
		"packet_id": 13,
		"shooter_socket_self": shooter,
		"shooter_socket_target": target,
		"shooter_shell": b.shells.BLACK,
		"shooter_sequence_length_after_eject": remaining,
		"shooter_socket_target_direction": roundManager.GetDirection(shooter, target),
		"barrel_sawed_off": game_state.MAIN_barrel_sawed_off,
		"sent_from_socket": shooter,
		"ending_turn_after_shot": game_state.CheckIfShooterEndingTurnAfterShot(target, shooter, outcome, game_state.MAIN_barrel_sawed_off, remaining),
		"brmod_black_outcome": outcome,
	})

func _broadcast(packet : Dictionary) -> void:
	packets.send_p2p_packet(0, packet)
	packets.PipeData(packet)
