extends "res://multiplayer/scripts/user scripts/MP_Jammer.gd"

func SetValidTargets():
	super()
	for i in target_direction_strings.size():
		var socket : int = properties.GetSocketFromDirection(properties.socket_number, target_direction_strings[i])
		var p = properties.GetSocketProperties(socket)
		if p and p.brmod_jammer_immune:
			valid_target_array[i] = false

func Jammer_Enable():
	if !properties.brmod_jammer_immune:
		super()
