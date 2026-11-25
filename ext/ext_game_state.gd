extends "res://multiplayer/scripts/global scripts/MP_GameStateManager.gd"
# BRMod: registers the new items, widens id-indexed arrays, validity + turn-ending rules.

func _br():
	return get_node_or_null("/root/BRMod")

func _ready():
	var b = _br()
	if b: b.register_items(self)
	super()

func SetupEmptyGlobalItemCount():
	global_item_count_on_table_by_id = []
	for item_id in 50:
		global_item_count_on_table_by_id.append(0)

func SetItemDistributionVariablesFromCustomization(for_round_index : int):
	super(for_round_index)
	var b = _br()
	if b: b.apply_item_config(self)

func CheckIfEndingTurnAfterItemUse(item_id : int, for_socket_number : int):
	var ending = super(item_id, for_socket_number)
	var b = _br()
	if !ending and b and item_id == b.ID_UNO_RED:
		return b.items.uno_red_would_win(self, for_socket_number)
	return ending

func Global_AddItemToInventory(socket_number : int, instance : Node3D, item_id : int, local_grid_index : int):
	super(socket_number, instance, item_id, local_grid_index)
	var b = _br()
	var p = GetSocketProperties(socket_number)
	if b and p:
		b.items.set_enchant(instance, p.item_manager.brmod_take_placement_enchant(local_grid_index))

func CheckIfJammerHasEligibleTargets(user_properties : MP_UserInstanceProperties):
	var b = _br()
	if !b: return super(user_properties)
	for p in instance_handler.instance_property_array:
		if b.items.jammer_can_target(user_properties, p): return true
	return false

func GetPropertyInvalidItems(user_properties : MP_UserInstanceProperties):
	var b = _br()
	if b: return b.items.invalid_array(self, user_properties)
	return super(user_properties)

func _GetBurnerPhone_Shell(with_verbal_index : int):
	var s = super(with_verbal_index)
	return "live" if s == "hidden" else s
