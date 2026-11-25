extends "res://multiplayer/scripts/user scripts/MP_ItemManager.gd"
# BRMod: optional automatic grabbing of items from the briefcase (local player only).

var _auto_scheduled := false
var _request_pending := false
var _held_enchant := 0
var _placing_enchants := {}

func _br():
	return get_node_or_null("/root/BRMod")

func _auto_on() -> bool:
	var b = _br()
	if b == null: return false
	if properties.is_active: return b.settings_autograb
	return b.test_autograb_all

func BeginItemGrabbing():
	_request_pending = false
	_held_enchant = 0
	properties.is_holding_item_to_place = false
	await super()
	brmod_autograb_kick()

func brmod_autograb_kick(delay := 0.35) -> void:
	if !_auto_on() or _auto_scheduled or _request_pending or !properties.is_grabbing_items: return
	_auto_scheduled = true
	await get_tree().create_timer(delay, false).timeout
	_auto_scheduled = false
	if !_auto_on() or _request_pending or !properties.is_grabbing_items: return
	if properties.is_holding_item_to_place:
		for i in properties.user_inventory.size():
			if properties.user_inventory[i] == {} and (!properties.is_active or intbranch_grid_colliders[i].interactionAllowed):
				PlaceItemRequest(i, true)
				return
	elif intbranch_intake.interactionAllowed or !properties.is_active:
		GrabItemRequest(true)

func _manual_override(automatic : bool) -> void:
	if !automatic and properties.is_active and _auto_on():
		_br().set_autograb(false)

func GrabItemRequest(automatic := false):
	_manual_override(automatic)
	if _request_pending or !properties.is_grabbing_items or properties.is_holding_item_to_place: return
	if properties.is_active and !intbranch_intake.interactionAllowed: return
	_request_pending = true
	super()

func PlaceItemRequest(on_grid_index, automatic := false):
	_manual_override(automatic)
	if _request_pending or !properties.is_grabbing_items or !properties.is_holding_item_to_place: return
	if on_grid_index < 0 or on_grid_index >= properties.user_inventory.size(): return
	if properties.user_inventory[on_grid_index] != {}: return
	if properties.is_active and !intbranch_grid_colliders[on_grid_index].interactionAllowed: return
	_request_pending = true
	super(on_grid_index)

func PlaceItem(on_local_index : int, is_last_item : bool = false):
	super(on_local_index, is_last_item)
	if is_last_item: return
	# The same packet starts a placement animation on the other players' screens.
	# Leave the intake closed until that animation has released the previous item.
	SetIntakeCollider(false)
	await get_tree().create_timer(properties.hands.lerp_duration_item_grabbing * 2.0 + 0.05, false).timeout
	if properties.is_grabbing_items and !_request_pending and !properties.is_holding_item_to_place:
		SetIntakeCollider(true)
		brmod_autograb_kick()

func SetGridColliders(enabling : bool):
	super(enabling)
	if enabling: brmod_autograb_kick(0.08)

func brmod_take_placement_enchant(slot : int) -> int:
	var enchant : int = _placing_enchants.get(slot, 0)
	_placing_enchants.erase(slot)
	return enchant

func ReceivePacket_GrabItem(dict : Dictionary):
	if dict.socket_number != properties.socket_number: return
	_held_enchant = dict.get("brmod_enchant", 0)
	_request_pending = false
	super(dict)
	if properties.is_active:
		_br().items.set_enchant(active_instance, _held_enchant)
		brmod_autograb_kick(active_separate_lerp.dur + 0.08)
	else:
		brmod_autograb_kick(0.75)

func ReceivePacket_PlaceItem(dict : Dictionary):
	if dict.socket_number == properties.socket_number:
		_placing_enchants[dict.local_grid_index] = _held_enchant
		_held_enchant = 0
		_request_pending = false
		if dict.is_last_item: properties.is_grabbing_items = false
	super(dict)
	if dict.socket_number == properties.socket_number and !dict.is_last_item:
		brmod_autograb_kick(0.80)
