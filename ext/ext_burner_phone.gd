extends "res://multiplayer/scripts/user scripts/MP_BurnerPhone.gd"
# BRMod: the phone can announce a pink (healing) shell. Hidden shells are reported as live by the host.

func GetBurnerPhoneString(verbal_index : int, verbal_shell : String):
	if verbal_shell not in ["heal", "black"]:
		return super(verbal_index, verbal_shell)
	var s : String = super(verbal_index, "live")
	var b = get_node_or_null("/root/BRMod")
	var detail := "PINK."
	if b:
		detail = b.t("ЧЁРНЫЙ (тип неизвестен).", "BLACK (unknown).") if verbal_shell == "black" else b.t("РОЗОВЫЙ (лечит).", "PINK (heals).")
	var lines := s.split("\n")
	if lines.size() >= 2:
		return lines[0] + "\n... " + detail
	return s
