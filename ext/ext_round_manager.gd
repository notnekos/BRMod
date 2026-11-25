extends "res://multiplayer/scripts/global scripts/MP_RoundManager.gd"
# BRMod: per-round reset, per-turn effects (expiry, drunk, tape...), special shells.

var _starting_round := false

func _br():
	return get_node_or_null("/root/BRMod")

func PacketSort(dict : Dictionary):
	var b = _br()
	if b and dict.values()[1] == "first round routine":
		_starting_round = true
		b.items.reset_round(game_state)
	super(dict)

func PassTurn(to_socket : int):
	var b = _br()
	if b:
		var previous : int = -1 if _starting_round else game_state.MAIN_active_current_turn_socket
		_starting_round = false
		b.items.on_turn_start(game_state, to_socket, previous)
	super(to_socket)

func GenerateRandomSequence():
	super()
	var b = _br()
	if b: b.shells.add_specials(game_state)
