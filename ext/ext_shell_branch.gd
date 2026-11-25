extends "res://multiplayer/scripts/global scripts/MP_ShellBranch.gd"
# BRMod: colours for the yellow (hidden) and pink (heal) shells.

func SetState(type : String):
	if type in ["hidden", "heal", "black"]:
		var b = get_node_or_null("/root/BRMod")
		if b:
			shell.set_surface_override_material(1, b.shells.material(type, mat_live_default, false))
			return
		type = "live"
	super(type)

func SetState_Inspecting(type : String):
	if type in ["hidden", "heal", "black"]:
		var b = get_node_or_null("/root/BRMod")
		if b:
			shell.set_surface_override_material(1, b.shells.material(type, mat_inspecting_live_default, true))
			return
		type = "live"
	super(type)
