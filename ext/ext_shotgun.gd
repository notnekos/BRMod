extends "res://multiplayer/scripts/user scripts/MP_ShotgunInteraction.gd"
# BRMod: special shells, extra barrels (hit every opponent), totem + last-hit tracking, UNO SWAP trigger.

func _br():
	return get_node_or_null("/root/BRMod")

func ReceivePacket_Shoot(packet_dictionary : Dictionary = {}):
	if packet_dictionary.sent_from_socket == properties.socket_number:
		var b = _br()
		if b: b.items.on_shot_fired(properties, packet_dictionary.shooter_socket_self, packet_dictionary.shooter_socket_target, packet_dictionary.shooter_shell)
	if packet_dictionary.shooter_shell == "black":
		var outcome := packet_dictionary.duplicate()
		outcome.shooter_shell = packet_dictionary.brmod_black_outcome
		super(outcome)
		intermediary.game_state.MAIN_shell_to_eject = "black"
	else:
		super(packet_dictionary)

func _blood_on(target_socket : int):
	var inst = null
	for p in intermediary.instance_handler.instance_property_array:
		if p.socket_number == target_socket: inst = p
	if inst == null: return
	var rot := Vector3.ZERO
	match GetDirection(target_socket, active_shooter_socket_self):
		"left": rot = Vector3(0, 47, 0)
		"right": rot = Vector3(0, -55, 0)
	inst.particles_shooting.SpawnBlood(rot)

func ShootingOutcome():
	await get_tree().create_timer(.1, false).timeout
	var b = _br()
	var gs = intermediary.game_state
	var shell : String = gs.MAIN_shooter_shell
	if gs.MAIN_sequence_length_on_outcome == 1:
		for property in intermediary.instance_handler.instance_property_array: property.running_fast_revival = true
	var self_shot := active_shooter_socket_target == active_shooter_socket_self
	var backfire := shell == "hidden" and !self_shot
	var bang := shell == "live" or shell == "heal" or backfire
	var targets := [active_shooter_socket_target]
	if b and b.st.triple and !self_shot:
		targets = []
		for p in intermediary.instance_handler.instance_property_array:
			if p.socket_number != active_shooter_socket_self and p.health_current > 0: targets.append(p.socket_number)
	if !self_shot:
		for p in intermediary.instance_handler.instance_property_array:
			if p.socket_number in targets:
				p.brmod_last_shooter = active_shooter_socket_self
				p.brmod_last_shot_shell = shell
				p.brmod_last_shot_damage = active_shooter_shotgun_damage if shell == "live" else 0
				p.brmod_last_shot_damage_taken = 0

	if bang:
		PlaySound_LiveFire()
		anim_light_muzzle.play("flash")
		MuzzleFlashPlane()
		intermediary.anim_pp_muzzle_flash.play("pp muzzle flash")
		if !properties.is_active: anim_recoil_thirdperson.play("recoil third person")
		else: anim_recoil_firstperson.play("recoil first person")
		if properties.is_active: cam_shaker.Shake()
		for property in intermediary.instance_handler.instance_property_array:
			if property.socket_number in targets: property.cam_shaker.Shake()
		anim_muzzle_cone.play("flash cone")
		SmokeParticles()
		if shell == "live":
			for t in targets: _blood_on(t)
	else:
		PlaySound_BlankFire()

	if shell == "live":
		properties.stat_damage_dealt += active_shooter_shotgun_damage * targets.size()
		if self_shot: properties.stat_number_of_times_shot_self_with_live += 1

	if self_shot:
		if shell == "live":
			if properties.is_active:
				animator_shotgun.play("RESET")
				properties.oscillator_manager.LerpToOriginal("shotgun")
				ShotgunBarrel_Grow()
			else:
				animator_shotgun_thirdperson.play("user shoot self transition_live thirdperson")
				FailsafeAfterSelfShot()
		else:
			if properties.is_active:
				PlaySound_ShotgunFoley(true, "transition")
				animator_shotgun.play("user shoot self transition_blank")
			else:
				PlaySound_ShotgunFoley(false, "transition")
				animator_shotgun_thirdperson.play("user shoot self transition_blank thirdperson")

	if shell == "live":
		for instance in intermediary.instance_handler.instance_property_array:
			if instance.socket_number in targets:
				print("death request on instance: ", instance.user_name)
				if b:
					var dealt : int = b.deal_damage(instance, active_shooter_socket_self, active_shooter_shotgun_damage)
					if !self_shot: instance.brmod_last_shot_damage_taken = dealt
				else:
					instance.health_current = max(0, instance.health_current - active_shooter_shotgun_damage)
				instance.death.DeathRequest(GetDirection(instance.socket_number, active_shooter_socket_self))
	elif shell == "heal" and b:
		for instance in intermediary.instance_handler.instance_property_array:
			if instance.socket_number in targets:
				b.shells.heal(instance, active_shooter_shotgun_damage)
	elif backfire and b:
		print("[BRMod] hidden shell backfires on ", properties.user_name)
		b.notify(b.t("Скрытый патрон! Урон получил стрелявший — %s", "Hidden shell! The shooter takes the hit — %s") % properties.user_name, 4.0, Color(1, 0.85, 0.2))
		b.deal_damage(properties, active_shooter_socket_self, active_shooter_shotgun_damage)
		properties.death.DeathRequest("forward")
	if b and shell == "hidden" and self_shot:
		b.notify(b.t("Скрытый патрон в себя — сработал как холостой", "Hidden shell at yourself — counts as a blank"), 3.0, Color(1, 0.85, 0.2))

	RemoveFirstShellFromSequence()
	if b and b.st.triple: b.items.end_triple()
	CheckIfFinalShot()

func CheckIfEndingTurn(packet_dictionary : Dictionary):
	var ending_turn = true
	var handing_turn_over = true
	var sequence_empty = false
	var user_has_won_with_socket = CheckIfUserHasWon()
	var blank_like = active_shooter_shell == "blank" or active_shooter_shell == "hidden"
	if active_shooter_socket_target == active_shooter_socket_self && blank_like: ending_turn = false; handing_turn_over = false
	if active_shooter_sequence_length_after_eject == 0: ending_turn = true; sequence_empty = true
	if user_has_won_with_socket != -1: ending_turn = true
	if !packet_dictionary.ending_turn_after_shot:
		properties.FreeLookCameraForUser_Enable()
		GlobalVariables.cursor_state_after_toggle = true
		cursor.SetCursor(true, true)
		properties.permissions.SetMainPermission(true)
		properties.SetTurnControllerPrompts(true)
		properties.has_turn = true
	else:
		if (GlobalSteam.STEAM_ID == GlobalSteam.HOST_ID) or GlobalVariables.mp_debugging:
			intermediary.roundManager.UserEndTurn_Packet(active_shooter_socket_self, handing_turn_over, sequence_empty, user_has_won_with_socket)
