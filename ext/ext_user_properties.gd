extends "res://multiplayer/scripts/user scripts/MP_UserInstanceProperties.gd"
# BRMod: per-player state for the new items + hand meshes for new item ids + the tail easter egg.

var brmod_last_shooter : int = -1
var brmod_last_shot_shell : String = ""
var brmod_last_shot_damage : int = 0
var brmod_last_shot_damage_taken : int = 0
var brmod_jammer_immune := false
var brmod_uno_yellow : bool = false     # UNO: SWAP armed (until this player's next turn)
var brmod_blind : bool = false          # blindfolded until own turn
var brmod_deaf : bool = false           # headphones until own turn
var brmod_tape : bool = false           # hands will be taped on the next own turn
var brmod_tape_active : bool = false    # hands taped right now (this turn)
var brmod_drunk_pending : bool = false  # got drunk: next own turn must drink all beer first
var brmod_drunk_active : bool = false

func _ready():
	super()
	var b = get_node_or_null("/root/BRMod")
	if b == null: return
	b.extend_user_arrays(self)
	if b.is_tail_user(user_name):
		b.attach_tail.call_deferred(self)
