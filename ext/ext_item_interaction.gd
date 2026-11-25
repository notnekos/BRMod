extends "res://multiplayer/scripts/user scripts/MP_ItemInteraction.gd"
# BRMod: target picking, effect-id remap (whiskey), custom use flow for the new items.

var brmod_effect_id := -1

func _br():
	return get_node_or_null("/root/BRMod")

func _custom(id : int) -> bool:
	var b = _br()
	return b != null and b.is_custom_flow(id)

# ---- client: clicking an item

func InteractWithItemRequest(item_object_parent : Node3D, stealing_item : bool = false):
	var b = _br()
	brmod_effect_id = -1
	if b == null:
		return super(item_object_parent, stealing_item)
	var branch = item_object_parent.get_child(1)
	var id : int = branch.item_id
	if !b.items.can_use_instance(properties.intermediary.game_state, properties, item_object_parent, stealing_item): return
	if b.items.target_kind(id) != "" and !b.items.item_in_chaos(item_object_parent):
		# block the table but keep the cursor visible for the menu
		properties.permissions.SetPermission_Shotgun(false)
		properties.permissions.SetItemPermissions(false, stealing_item)
		properties.SetTurnControllerPrompts(false)
		properties.cursor.SetCursor(true, false)
		properties.cursor.SetCursorImage("point")
		var opts : Array = b.items.target_options(properties, id)
		b.ui.pick(b.items.target_title(id), opts, _on_target_picked.bind(item_object_parent, stealing_item))
		return
	brmod_request(item_object_parent, stealing_item, -1)

func _on_target_picked(value, item_object_parent : Node3D, stealing_item : bool):
	if value == null or !is_instance_valid(item_object_parent):
		if stealing_item:
			properties.permissions.SetMainPermission_Stealing()
		else:
			properties.permissions.SetMainPermission(true)
			properties.SetTurnControllerPrompts(true)
		return
	brmod_request(item_object_parent, stealing_item, value)

func brmod_request(item_object_parent : Node3D, stealing_item : bool, target):
	properties.permissions.SetMainPermission(false)
	GetItemVariables(item_object_parent)
	var packet = {
		"packet category": "MP_PacketVerification",
		"packet alias": "interact with item request",
		"sent_from": "client",
		"packet_id": 22,
		"item_socket_number": active_interaction_branch.socket_number,
		"local_grid_index": active_interaction_branch.local_grid_index,
		"item_id": active_id,
		"stealing_item": stealing_item,
		"sent_from_socket": properties.socket_number,
		"brmod_target": target,
	}
	properties.intermediary.packets.send_p2p_packet_directly_to_host(GlobalSteam.STEAM_ID, packet)
	if GlobalVariables.mp_debugging: properties.intermediary.packets.PipeData(packet)

# ---- every client: the host's result

func ReceivePacket_InteractWithItem(packet : Dictionary):
	if packet.socket_number == properties.socket_number:
		brmod_effect_id = packet.item_id
	super(packet)

func GetItemVariables(item_object_parent : Node3D):
	super(item_object_parent)
	if brmod_effect_id != -1:
		active_id = brmod_effect_id
		active_item_has_secondary_interaction = active_id == 3 or active_id == 8

func InteractWithItem_FirstPerson(packet : Dictionary):
	if !_custom(packet.item_id):
		super(packet)
		return
	properties.permissions.SetMainPermission(false)
	if packet.stealing_item:
		properties.SetAdrenalineControllerPrompts(false)
		properties.permissions.SetItemPermissions(false, true)
		properties.is_stealing_item = false
		properties.is_on_secondary_interaction = false
	var local_grid_index = packet.local_grid_index
	var item_object : Node3D = properties.intermediary.game_state.MAIN_inventory_by_socket[packet.item_socket_number][local_grid_index].item_instance
	RemoveItemFromInventory(local_grid_index, packet.item_socket_number)
	GetItemVariables(item_object)
	ChangeGameStateWithItem(active_id, packet)
	if !packet.stealing_item:
		animator_items_firstperson.play("RESET")
	else:
		properties.intermediary.filter.PanLowPass_In()
		PanCameraBack()
	await _br().use_anim.first_person(self, item_object, active_id)
	await get_tree().create_timer(.2, false).timeout
	EndItemInteraction(packet)

func InteractWithItem_ThirdPerson(packet : Dictionary):
	if !_custom(packet.item_id):
		super(packet)
		return
	var local_grid_index = packet.local_grid_index
	var item_object : Node3D = properties.intermediary.game_state.MAIN_inventory_by_socket[packet.item_socket_number][local_grid_index].item_instance
	if packet.stealing_item:
		properties.is_stealing_item = false
		properties.is_on_secondary_interaction = false
	RemoveItemFromInventory(local_grid_index, packet.item_socket_number)
	GetItemVariables(item_object)
	ChangeGameStateWithItem(active_id, packet)
	animator_items_thirdperson.play("RESET")
	await(hands.Hand_PickupItem(local_grid_index, active_id, active_interaction_branch.which_hand_to_grab_with, item_object))
	await _br().use_anim.third_person(self, active_id)
	await get_tree().create_timer(.2, false).timeout
	EndItemInteraction(packet)

func ChangeGameStateWithItem(item_id : int, packet : Dictionary = {}):
	var b = _br()
	if b: b.items.on_any_item(self, packet)
	if b == null or !_custom(active_id):
		if b and active_id == b.ID_INVERTER and b.is_host():
			var seq : Array = properties.intermediary.game_state.MAIN_active_sequence_dict.sequence_in_shotgun
			if !seq.is_empty() and seq[0] == b.shells.BLACK:
				properties.stat_number_of_items_used += 1
				return
		super(item_id, packet)
		return
	properties.stat_number_of_items_used += 1
	b.items.apply_effect(self, active_id, packet)

func EndItemInteraction(with_packet : Dictionary):
	brmod_effect_id = -1
	if _custom(with_packet.item_id) and with_packet.ending_turn_after_item_use:
		# the item may have killed someone (reverse / pills): end the turn like a shot would
		properties.is_interacting_with_item = false
		if GlobalSteam.STEAM_ID == GlobalSteam.HOST_ID or GlobalVariables.mp_debugging:
			var shotgun_empty = properties.intermediary.game_state.MAIN_active_sequence_dict.sequence_in_shotgun.size() == 0
			var winner = shotgun.CheckIfUserHasWon()
			properties.intermediary.roundManager.UserEndTurn_Packet(properties.socket_number, true, shotgun_empty, winner)
		return
	super(with_packet)
