extends "res://multiplayer/scripts/user scripts/MP_UserPermissions.gd"
# BRMod: a drunk player cannot pick up the shotgun while they still have beer.

func SetPermission_Shotgun(state : bool):
	var b = get_node_or_null("/root/BRMod")
	if state and b and b.items.shotgun_blocked(properties):
		state = false
	super(state)

func SetItemPermissions(state : bool, for_all_items_on_table : bool = false):
	super(state, for_all_items_on_table)
	var b = get_node_or_null("/root/BRMod")
	if !b or !state: return
	var gs = intermediary.game_state
	for socket in gs.MAIN_inventory_by_socket.size():
		if (socket != properties.socket_number) != for_all_items_on_table: continue
		for d in gs.MAIN_inventory_by_socket[socket]:
			if d == {} or !is_instance_valid(d.item_instance): continue
			var allowed : bool = b.items.can_use_instance(gs, properties, d.item_instance, for_all_items_on_table)
			var branch = d.item_instance.get_child(1)
			var indicator = d.item_instance.get_child(0)
			branch.interactionInvalid = !allowed
			indicator.interactionInvalid = !allowed
			indicator.lerping_on_hover = allowed
