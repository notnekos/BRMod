extends Node
# BRMod offline harness: 4 debug bots, F-keys, and a scripted end-to-end test ([BRMod][TEST] in the log).

var core
var fails := 0
var passes := 0

func _init(c):
	core = c
	name = "test"

func start() -> void:
	var gv = get_node("/root/GlobalVariables")
	var gs = get_node("/root/GlobalSteam")
	gv.mp_debugging = true
	gv.mp_debug_keys_enabled = !core.bot_mode
	gv.skipping_intro = true
	var d : Dictionary = gv.debug_match_customization.duplicate(true)
	if core.autotest or core.regression_test:
		for r in d.round_property_array:
			for s in r.shell_load_properties:
				s.number_of_items = 2 if (r.round_index == 0 and s.sequence_index == 0) else 0
				s.number_of_lives = 3
				s.number_of_blanks = 5
	gv.active_match_customization_dictionary = d
	if core.regression_test:
		core.settings_autograb = true
		core.test_autograb_all = true
		core.enchant_chance = 1.0
	gs.STEAM_ID = 1234
	print("[BRMod] OFFLINE TEST: loading mp_main with debug bots")
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://multiplayer/scenes/mp_main.tscn")
	await get_tree().create_timer(0.5).timeout
	if core.bot_mode:
		core.test_autograb_all = true
		bot_loop()
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		DisplayServer.window_set_position(Vector2i(40, 40))
	if core.regression_test:
		await run_regression()
		print("[BRMod][TEST] REGRESSION DONE: %d passed, %d failed" % [passes, fails])
		get_tree().quit(0 if fails == 0 else 1)
		return
	if core.autotest:
		if core.get("autotest_quick"): run_quick()
		else: run()

# ------------------------------------------------------------------ dumb bots (play_with_bots.bat)

var _bot_busy := false

func bot_loop() -> void:
	while true:
		await get_tree().create_timer(0.5).timeout
		if I() == null or I().intermed_properties == null or _bot_busy: continue
		var gs = G()
		if gs.MAIN_shotgun_loading_in_progress or gs.MAIN_running_win_routine or gs.MAIN_item_grabbing_in_progress: continue
		var cur = P(gs.MAIN_active_current_turn_socket)
		if cur == null or cur.is_active or !cur.has_turn or cur.health_current <= 0 or cur.is_interacting_with_item: continue
		_bot_busy = true
		await bot_act(cur)
		_bot_busy = false

func bot_act(p) -> void:
	var gs = G()
	await w(1.5)
	if gs.MAIN_active_current_turn_socket != p.socket_number or !p.has_turn or p.is_interacting_with_item: return
	if core.items.shotgun_blocked(p):
		var slot : int = core.find_slot(gs, p.socket_number, core.ID_BEER)
		if slot != -1:
			p.item_interaction.brmod_request(gs.MAIN_inventory_by_socket[p.socket_number][slot].item_instance, false, -1)
			await w(5.0)
		return
	if !p.is_holding_shotgun:
		I().packets.PipeData({"packet category": "MP_PacketVerification", "packet alias": "pickup shotgun request", "sent_from": "client", "packet_id": 10, "sent_from_socket": p.socket_number})
		await w(4.0)
	if !p.is_holding_shotgun or gs.MAIN_active_current_turn_socket != p.socket_number: return
	var target : int = p.socket_number
	var opp := others(p)
	if !opp.is_empty() and randf() > 0.25: target = opp.pick_random().socket_number
	p.look_manager.LookAtDirection(p.shotgun.GetDirection(p.socket_number, target))
	await w(0.1)
	p.shotgun.Shoot(null, target)
	await w(6.0)

var _bot_item_idx := 0
func bot_mode_key(keycode : int) -> bool:
	var M = me()
	if M == null: return false
	match keycode:
		KEY_F5:
			var ids : Array = core.MOD_IDS + [core.ID_PILLS]
			give(M, ids[_bot_item_idx % ids.size()])
			_bot_item_idx += 1
			M.permissions.SetItemPermissions(M.has_turn and G().MAIN_active_current_turn_socket == M.socket_number)
		KEY_F6:
			clear_items(M)
		KEY_F7: set_shell("hidden")
		KEY_F8: set_shell("heal")
		KEY_F9:
			for p in props():
				if p.health_current > 0:
					p.health_current = p.health_on_round_start
					p.health_counter.UpdateDisplay()
		KEY_F10: core.force_specials = true
		_: return false
	return true

const _BLOCKED_DEBUG_ACTIONS := ["8", "2", "debug_q", "debug_e", "-", ",", ".", "end"]
func _input(event):
	if !core.bot_mode or !(event is InputEventKey) or !event.pressed: return
	for a in _BLOCKED_DEBUG_ACTIONS:
		if InputMap.has_action(a) and event.is_action(a):
			get_viewport().set_input_as_handled()
			return

# ------------------------------------------------------------------ helpers

func _result(line : String) -> void:
	var dir : String = core.mod_dir.path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("results.txt")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()

func check(cond : bool, what : String) -> void:
	_result(("PASS " if cond else "FAIL ") + what)
	if cond:
		passes += 1
		print("[BRMod][TEST] PASS ", what)
	else:
		fails += 1
		print("[BRMod][TEST] FAIL ", what)

func shot(n : String) -> void:
	if DisplayServer.get_name() == "headless": return
	var dir : String = core.mod_dir.path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img: img.save_png(dir.path_join(n + ".png"))
	print("[BRMod][TEST] screenshot ", n)

func w(s : float) -> void:
	await get_tree().create_timer(s, false).timeout

func I():
	return core.inter()

func G():
	return core.inter().game_state

func P(socket : int):
	return G().GetSocketProperties(socket)

func props() -> Array:
	return I().instance_handler.instance_property_array

func me():
	return I().intermed_properties

func others(p) -> Array:
	return props().filter(func(q): return q != p and q.health_current > 0)

func idle() -> bool:
	var gs = G()
	if gs.MAIN_shotgun_loading_in_progress or gs.MAIN_running_win_routine or gs.MAIN_item_grabbing_in_progress: return false
	for p in props():
		if p.is_interacting_with_item or p.is_holding_shotgun or p.is_shooting and false: return false
	return true

func wait_idle(max_s := 25.0) -> bool:
	var t := 0.0
	var holding_for := 0.0
	while t < max_s:
		await w(0.25)
		t += 0.25
		var gs = G()
		var cur = P(gs.MAIN_active_current_turn_socket)
		# a bot left holding the shotgun (e.g. taped hands) -> let it shoot so the game goes on
		if cur and !cur.is_active and cur.is_holding_shotgun and !gs.MAIN_shotgun_loading_in_progress:
			holding_for += 0.25
			if holding_for > 2.5:
				holding_for = 0.0
				var opp := others(cur)
				var tgt : int = opp.pick_random().socket_number if !opp.is_empty() else cur.socket_number
				print("[BRMod][TEST] bot %s was left holding the shotgun, shooting %d" % [cur.user_name, tgt])
				cur.shotgun.Shoot(null, tgt)
				await w(8.0)
				t = 0.0
			continue
		holding_for = 0.0
		if idle() and cur and cur.has_turn:
			await w(0.8)
			return true
	print("[BRMod][TEST] timeout waiting for idle")
	return false

func force_turn(p) -> void:
	await wait_idle()
	if G().MAIN_active_current_turn_socket != p.socket_number:
		G().round_manager.MainRoutine_PassTurn(p.socket_number)
		await w(1.5)
	await wait_idle()

func give(p, id : int) -> int:
	for i in 8:
		if G().MAIN_inventory_by_socket[p.socket_number][i] == {}:
			core.items.spawn_item(p, id, i)
			print("[BRMod][TEST] gave %d to %s slot %d" % [id, p.user_name, i])
			return i
	return -1

func clear_items(p) -> void:
	for i in 8:
		var d = G().MAIN_inventory_by_socket[p.socket_number][i]
		if d != {}:
			var inst = d.item_instance
			p.item_interaction.RemoveItemFromInventory(i, p.socket_number)
			if inst: inst.queue_free()

func item_count(p) -> int:
	var n := 0
	for d in G().MAIN_inventory_by_socket[p.socket_number]:
		if d != {}: n += 1
	return n

func use(p, id : int, target = -1, wait_s := 12.0) -> bool:
	var slot : int = core.find_slot(G(), p.socket_number, id)
	if slot == -1:
		slot = give(p, id)
	var inst = G().MAIN_inventory_by_socket[p.socket_number][slot].item_instance
	print("[BRMod][TEST] %s uses %d (target %s)" % [p.user_name, id, str(target)])
	p.item_interaction.brmod_request(inst, false, target)
	await w(0.5)
	var t := 0.0
	while p.is_interacting_with_item and t < wait_s:
		await w(0.25)
		t += 0.25
	await w(0.6)
	return true

func set_shell(shell : String) -> void:
	var seq : Array = G().MAIN_active_sequence_dict.sequence_in_shotgun
	if seq.size() < 3:
		seq.clear()
		for i in 6: seq.append("blank")
	seq[0] = shell

func shoot(p, target_socket : int, shell := "", snap := "") -> void:
	if shell != "": set_shell(shell)
	print("[BRMod][TEST] %s shoots socket %d (%s)" % [p.user_name, target_socket, shell])
	I().packets.PipeData({"packet category": "MP_PacketVerification", "packet alias": "pickup shotgun request", "sent_from": "client", "packet_id": 10, "sent_from_socket": p.socket_number})
	await w(4.0)
	if !p.is_holding_shotgun:
		print("[BRMod][TEST] pickup was refused for ", p.user_name)
		return
	p.look_manager.LookAtDirection(p.shotgun.GetDirection(p.socket_number, target_socket))
	await w(0.1)
	p.shotgun.Shoot(null, target_socket)
	if snap != "":
		await w(2.4)
		await shot(snap + "_a")
		await w(0.8)
		await shot(snap + "_b")
		await w(5.3)
	else:
		await w(8.5)

func look_at_player(p) -> void:
	var dir : String = me().GetDirection(me().socket_number, p.socket_number)
	me().cam.BeginLerp("home" if dir == "self" else "opponent " + dir)
	await w(1.2)

func revive_all(hp := 4) -> void:
	for p in props():
		if p.health_current <= 0:
			p.health_current = hp
			p.death.UserDeath_Revive(true)
		p.health_current = hp
		p.health_on_round_start = max(p.health_on_round_start, hp)
		p.health_counter.UpdateDisplay()

func wait_until(test_condition : Callable, seconds := 10.0) -> bool:
	for i in int(seconds / 0.05):
		if test_condition.call(): return true
		await w(0.05)
	return false

func run_regression() -> void:
	if !await wait_until(func(): return I() != null and me() != null):
		check(false, "multiplayer scene loaded")
		return
	var M = me()
	var A = others(M)[0]
	var B = others(M)[1]
	var gs = G()
	var manager = M.item_manager
	if !await wait_until(func(): return M.is_grabbing_items and manager.intbranch_intake.interactionAllowed, 40.0):
		check(false, "initial briefcase opens")
		return
	core.ui.set_blind(true)
	manager.GrabItemRequest()
	check(!core.settings_autograb, "manual grab cancels scheduled automatic grab")
	if !await wait_until(func(): return manager.intbranch_grid_colliders[0].interactionAllowed):
		check(false, "manual grab reaches the placement grid")
		return
	await w(0.1)
	await shot("v211_blindfold_grab")
	check(core.ui._blind._slots.visible, "blindfold exposes the placement controls")
	core.set_autograb(true)
	core.ui._blind._slot_buttons[0].pressed.emit()
	check(!core.settings_autograb, "manual placement cancels an automatic placement")
	check(!manager.intbranch_intake.interactionAllowed, "briefcase waits for placement animation before accepting another grab")
	if !await wait_until(func(): return manager.intbranch_intake.interactionAllowed):
		check(false, "briefcase returns control after the placement animation")
		return
	manager.GrabItemRequest()
	if !await wait_until(func(): return manager.intbranch_grid_colliders[1].interactionAllowed):
		check(false, "manual grab continues after placing an item")
		return
	await w(0.1)
	core.ui._blind._slot_buttons[1].pressed.emit()
	core.ui.set_blind(false)
	check(await wait_idle(40), "manual and automatic distribution finish together")
	for p in props():
		check(item_count(p) == 2, "exactly two items placed for " + p.user_name)
		for d in gs.MAIN_inventory_by_socket[p.socket_number]:
			if d != {}: check(core.items.enchant_of(d.item_instance) > 0, "drawn item keeps the host's enchantment")
	for p in props(): clear_items(p)
	revive_all()
	await force_turn(M)
	set_shell("blank")
	var own_slot := give(M, core.ID_PILL_JAR)
	var opponent_slot := give(A, core.ID_BEER)
	var own : Node3D = gs.MAIN_inventory_by_socket[M.socket_number][own_slot].item_instance
	var opponent : Node3D = gs.MAIN_inventory_by_socket[A.socket_number][opponent_slot].item_instance
	core.items.set_enchant(opponent, core.ENCHANT_DOPAMINE)
	check(!core.items.has_stealable_item(gs, M), "adrenaline disabled with only Dopamine targets")
	check(!core.items.can_use_instance(gs, M, opponent, true), "Dopamine rejects the specific steal")
	check(core.items.can_use_instance(gs, A, opponent, false), "Dopamine permits use by the owner")
	core.items.set_enchant(own, core.ENCHANT_CODING)
	core.st.chaos[M.socket_number] = A.socket_number
	check(!core.items.item_in_chaos(own), "Encoding keeps the effect under whiskey")
	core.st.chaos.clear()
	var zero_slot := give(M, core.ID_ADRENALINE_ZERO)
	var beer_slot := give(M, core.ID_BEER)
	var zero : Node3D = gs.MAIN_inventory_by_socket[M.socket_number][zero_slot].item_instance
	var beer : Node3D = gs.MAIN_inventory_by_socket[M.socket_number][beer_slot].item_instance
	core.items.set_enchant(zero, core.ENCHANT_BUNKER)
	core.items.set_enchant(beer, core.ENCHANT_DOPAMINE)
	var owned_mesh : MeshInstance3D = own.find_children("*", "MeshInstance3D", true, false)[0]
	var opponent_mesh : MeshInstance3D = opponent.find_children("*", "MeshInstance3D", true, false)[0]
	check(own.get_node_or_null("Enchant") == null and owned_mesh.material_overlay == core.assets.enchant_glint(core.ENCHANT_CODING), "enchantment uses a surface glint with no floating label")
	check(own.get_child(0).itemDescription.ends_with(core.items.enchant_description(core.ENCHANT_CODING)), "tooltip explains the enchantment")
	await look_at_player(M)
	await shot("v211_enchant_glints")
	await w(0.7)
	await shot("v211_enchant_glints_second_frame")
	core.ui.set_blind(true)
	await w(0.2)
	check(core.ui._blind._copies.has(owned_mesh.get_instance_id()) and !core.ui._blind._copies.has(opponent_mesh.get_instance_id()), "blindfold scan contains the local item and omits the opponent's item")
	await shot("v211_blindfold_items")
	core.ui.set_blind(false)
	core.debug_force.zero_sugar_destroy = false
	await use(M, core.ID_ADRENALINE_ZERO)
	check(core.items.enchant_of(own) > 0 and core.items.enchant_of(opponent) > 0, "Zero Sugar enchants both players' remaining items")
	clear_items(M)
	core.debug_force.zero_sugar_destroy = true
	await use(M, core.ID_ADRENALINE_ZERO)
	check(item_count(A) == 0, "Zero Sugar failure destroys one item")
	core.debug_force.clear()
	own_slot = give(M, core.ID_PILL_JAR)
	own = gs.MAIN_inventory_by_socket[M.socket_number][own_slot].item_instance
	core.items.set_enchant(own, core.ENCHANT_BUNKER)
	give(A, core.ID_BEER)
	await use(M, core.ID_NUKE)
	check(item_count(M) == 1 and item_count(A) == 0, "Nuke spares Bunker and destroys ordinary items")
	await use(M, core.ID_PILL_JAR)
	check(M.brmod_jammer_immune and !core.items.jammer_can_target(A, M), "Pill Jar grants jammer immunity")
	for p in others(A): p.brmod_jammer_immune = true
	check(!gs.CheckIfJammerHasEligibleTargets(A), "Jammer disabled when all opponents are immune")
	var active_jammer = A.item_interaction.jammer
	active_jammer.SetValidTargets()
	check(!active_jammer.valid_target_array.has(true), "Jammer selector excludes immune targets")
	await force_turn(A)
	await force_turn(M)
	check(!M.brmod_jammer_immune, "Pill Jar expires on the owner's next turn")
	for p in props(): p.brmod_jammer_immune = false

	await force_turn(A)
	core.debug_force.black_outcome = "live"
	set_shell("black")
	await use(A, core.ID_INVERTER)
	check(gs.MAIN_active_sequence_dict.sequence_in_shotgun[0] == "black", "inverter keeps a black shell opaque")
	await shoot(A, B.socket_number, "black")
	check(B.health_current == 3 and B.brmod_last_shooter == A.socket_number and B.brmod_last_shot_shell == "live", "black live outcome is applied and recorded")
	check(gs.MAIN_shell_visible_to_eject == "black", "fired black shell ejects in black")
	await force_turn(B)
	A.health_current = 1
	check(!core.items.uno_red_valid(B), "red UNO disabled when last shooter has one HP")
	A.health_current = 4
	await use(B, core.ID_UNO_RED)
	check(B.health_current == 4 and A.health_current == 3, "red UNO heals and reflects the live shot")

	await force_turn(A)
	await shoot(A, B.socket_number, "live")
	await force_turn(M)
	core.debug_force.black_outcome = "blank"
	await shoot(M, B.socket_number, "black")
	check(B.brmod_last_shooter == M.socket_number and B.brmod_last_shot_shell == "blank", "later blank replaces the previous shooter's live shot")
	await force_turn(B)
	var target_hp : int = B.health_current
	var shooter_hp : int = M.health_current
	await use(B, core.ID_UNO_RED)
	check(B.health_current == target_hp - 1 and M.health_current == shooter_hp and A.health_current == 3, "red UNO on a blank hurts the card user")
	core.debug_force.clear()

# ------------------------------------------------------------------ the scenario

func run_quick() -> void:
	while I() == null or I().intermed_properties == null:
		await w(0.5)
	core.settings_autograb = true
	core.test_autograb_all = true
	await wait_idle(90)
	var M = me()
	var A = others(M)[0]
	var B = others(M)[1]
	revive_all()
	for p in props(): clear_items(p)
	await force_turn(M)
	var start : int = M.health_on_round_start
	# ---- cigarettes: never above the round start hp
	M.health_current = start
	await use(M, 4)
	await w(4.0)
	check(M.health_current == start, "cigarettes at full hp: no heal (%d/%d)" % [M.health_current, start])
	M.health_current = start - 1
	await use(M, 4)
	await w(4.0)
	check(M.health_current == start, "cigarettes heal up to the round start (%d/%d)" % [M.health_current, start])
	# ---- pills: over the limit, max 6
	core.debug_force = {"pills": "heal"}
	M.health_current = 5
	await use(M, core.ID_PILLS)
	check(M.health_current == 6, "pills 5 -> 6 (cap 6): %d" % M.health_current)
	await use(M, core.ID_PILLS)
	check(M.health_current == 6, "pills at 6 stay 6: %d" % M.health_current)
	core.debug_force = {}
	# cigarettes when over the limit
	await use(M, 4)
	await w(4.0)
	check(M.health_current == 6, "cigarettes over the limit do nothing: %d" % M.health_current)
	# ---- pink shell: over the limit, max 6
	await force_turn(A)
	B.health_current = B.health_on_round_start
	var bs : int = B.health_current
	await shoot(A, B.socket_number, "heal")
	check(B.health_current == min(bs + 1, 6), "pink at round max goes over the limit (%d -> %d)" % [bs, B.health_current])
	revive_all()
	await force_turn(A)
	B.health_current = 6
	await shoot(A, B.socket_number, "heal")
	check(B.health_current == 6, "pink at 6 stays 6: %d" % B.health_current)
	# ---- UNO SWAP card position (below the HP indicator)
	revive_all()
	await force_turn(M)
	await use(M, core.ID_UNO_YELLOW)
	M.cam.BeginLerp("home")
	await w(1.5)
	await shot("q_swap_marker")
	# ---- picker keeps the mouse cursor
	give(M, core.ID_BLINDFOLD)
	M.permissions.SetMainPermission(true)
	var sl : int = core.find_slot(G(), M.socket_number, core.ID_BLINDFOLD)
	M.item_interaction.InteractWithItemRequest(G().MAIN_inventory_by_socket[M.socket_number][sl].item_instance, false)
	await w(1.0)
	check(core.ui.picker_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "picker open with a visible cursor (mode %d)" % Input.mouse_mode)
	await shot("q_picker")
	core.ui._picked(null)
	await w(0.5)
	# ---- drunk hint for the local player
	give(M, core.ID_BEER)
	M.brmod_drunk_pending = true
	await w(0.5)
	await shot("q_drunk_pending")
	await force_turn(A)
	await force_turn(M)
	check(M.brmod_drunk_active and core.ui.status_text() != "", "drunk hint shown: " + core.ui.status_text())
	await shot("q_drunk_hint")
	print("[BRMod][TEST] DONE: %d passed, %d failed" % [passes, fails])
	_result("DONE %d passed, %d failed" % [passes, fails])
	await w(1.0)
	get_tree().quit()

func run() -> void:
	while I() == null or I().intermed_properties == null:
		await w(0.5)
	core.settings_autograb = true
	core.test_autograb_all = true
	var gs = G()
	check(gs.MAIN_item_resource_array.size() == 23, "23 item resources registered (%d)" % gs.MAIN_item_resource_array.size())
	# ---- auto grab (all 4 players grab 2 items each automatically)
	var t := 0.0
	while !gs.MAIN_item_grabbing_in_progress and t < 60.0:
		await w(0.5); t += 0.5
	await w(2.0)
	await shot("00_autograb")
	t = 0.0
	while gs.MAIN_item_grabbing_in_progress and t < 60.0:
		await w(0.5); t += 0.5
	check(!gs.MAIN_item_grabbing_in_progress, "autograb: item distribution finished by itself")
	var counts := props().map(func(p): return item_count(p))
	check(counts.all(func(c): return c == 2), "autograb: everybody got 2 items %s" % str(counts))
	if !await wait_idle(60): return
	var M = me()
	var A = others(M)[0]
	var B = others(M)[1]
	var C = others(M)[2]

	# ---- table display of every new item
	for p in props(): clear_items(p)
	var k := 0
	for id in core.MOD_IDS + [core.ID_PILLS]:
		give(props()[k % 4], id)
		k += 1
	await w(0.6)
	await shot("01_all_items_table")

	# ---- picker UI on the local player (storm cloud, 2 uses)
	await force_turn(M)
	for p in props(): clear_items(p)
	give(M, core.ID_STORM)
	M.permissions.SetMainPermission(true)
	var storm_slot : int = core.find_slot(gs, M.socket_number, core.ID_STORM)
	M.item_interaction.InteractWithItemRequest(gs.MAIN_inventory_by_socket[M.socket_number][storm_slot].item_instance, false)
	await w(0.5)
	check(core.ui.picker_open(), "picker opened for the storm cloud")
	await shot("02_picker")
	core.ui._picked(2)
	await w(1.0)
	await shot("03_storm_use_fp")
	t = 0.0
	while M.is_interacting_with_item and t < 12: await w(0.25); t += 0.25
	await w(1.0)
	check(core.st.storm_pending and core.st.storm_left == 2, "storm armed for 2 uses (%s, %d)" % [core.st.storm_pending, core.st.storm_left])
	await shot("04_storm_cloud")
	await use(M, 4)
	check(core.st.storm_pending, "storm still pending after 1 use")
	await use(M, 4)
	await w(2.5)
	check(!core.st.storm_pending, "storm triggered after 2 uses")
	await shot("05_storm_strike")

	# ---- yellow + pink shells must be visible when the shotgun is loaded
	await wait_idle()
	core.force_specials = true
	G().round_manager.MainRoutine_LoadShotgun()
	await w(2.6)
	await shot("05b_reload_special_shells")
	var vis : Array = G().MAIN_active_sequence_dict.sequence_visible
	check(vis.has("hidden") and vis.has("heal"), "reload shows yellow + pink shells %s" % str(vis))
	await wait_idle()

	# ---- totem
	revive_all()
	await force_turn(A)
	clear_items(B)
	give(B, core.ID_TOTEM)
	B.health_current = 1
	await shoot(A, B.socket_number, "live", "06_totem")
	check(B.health_current == 1 and !core.has_totem(gs, B.socket_number), "totem: survives with 1 hp and burns (%d)" % B.health_current)
	check(B.brmod_last_shooter == A.socket_number, "totem: last shot recorded")
	await shot("06_after_totem")

	# ---- uno red (reverse) on B: reflect A's shot
	await force_turn(B)
	var a_hp : int = A.health_current
	await use(B, core.ID_UNO_RED)
	check(A.health_current == a_hp - 1, "reverse: shooter took the damage (%d -> %d)" % [a_hp, A.health_current])

	# ---- uno yellow: next opponent shot flips; expires at own next turn
	revive_all()
	await force_turn(C)
	await use(C, core.ID_UNO_YELLOW)
	check(C.brmod_uno_yellow, "swap: armed")
	await shot("07_swap_marker")
	await force_turn(A)
	var c_hp : int = C.health_current
	await shoot(A, C.socket_number, "blank")
	check(C.health_current == c_hp - 1 and !C.brmod_uno_yellow, "swap: blank became live (%d -> %d)" % [c_hp, C.health_current])
	await force_turn(C)
	await use(C, core.ID_UNO_YELLOW)
	await force_turn(A)
	await force_turn(C)
	check(!C.brmod_uno_yellow, "swap: expires when the lap comes back")

	# ---- hidden shell
	revive_all()
	await force_turn(A)
	var hp_a : int = A.health_current
	var hp_b : int = B.health_current
	await shoot(A, B.socket_number, "hidden", "08_hidden")
	check(A.health_current == hp_a - 1 and B.health_current == hp_b, "hidden at opponent: shooter hurt (%d->%d), target fine (%d->%d)" % [hp_a, A.health_current, hp_b, B.health_current])
	await shot("08_hidden_backfire")
	revive_all()
	await force_turn(B)
	hp_b = B.health_current
	await shoot(B, B.socket_number, "hidden")
	check(B.health_current == hp_b, "hidden at self: no damage")
	check(G().MAIN_active_current_turn_socket == B.socket_number, "hidden at self: turn continues like a blank")

	# ---- heal shell (+saw stacking not tested here)
	revive_all()
	await force_turn(A)
	B.health_current = 2
	await shoot(A, B.socket_number, "heal", "09_heal")
	check(B.health_current == 3, "pink shell heals 1 (2 -> %d)" % B.health_current)
	await shot("09_heal_shell")

	# ---- pills (forced rolls)
	revive_all()
	await force_turn(M)
	core.debug_force = {"pills": "heal"}
	M.health_current = M.health_on_round_start
	var before : int = M.health_current
	await use(M, core.ID_PILLS)
	check(M.health_current == min(before + 2, 6), "pills heal +2 over the limit (%d -> %d)" % [before, M.health_current])
	core.debug_force = {"pills": "hurt"}
	before = M.health_current
	await use(M, core.ID_PILLS)
	check(M.health_current == before - 1, "pills hurt -1 (%d -> %d)" % [before, M.health_current])
	core.debug_force = {}

	# ---- whiskey (all tables) and whiskey shot (one table)
	revive_all()
	await force_turn(A)
	for p in props(): clear_items(p)
	await use(A, core.ID_WHISKEY)
	check(core.st.chaos.size() == props().size(), "whiskey: chaos on every table")
	give(A, 4); give(A, 9); give(A, 2)
	core.debug_last_effect = -1
	core.debug_force = {"chaos_exclude": [3, 8, 23, 16, 17, 19]}
	await use(A, 4)
	core.debug_force = {}
	check(core.debug_last_effect != -1, "whiskey: item use was remapped (cigarettes -> %d)" % core.debug_last_effect)
	await shot("10_whiskey")
	await force_turn(B)
	await force_turn(A)
	check(core.st.chaos.is_empty(), "whiskey: wears off when the lap comes back")
	await use(A, core.ID_SHOT, B.socket_number)
	check(core.st.chaos.size() == 1 and core.st.chaos.has(B.socket_number), "whiskey shot: only the chosen table")
	core.st.chaos.clear()

	# ---- uno +4
	await force_turn(M)
	for p in props(): clear_items(p)
	for id in [1, 2, 4, 6, 9]: give(B, id)
	await use(M, core.ID_PLUS4, B.socket_number)
	var beers := 0
	for d in gs.MAIN_inventory_by_socket[B.socket_number]:
		if d != {} and d.item_id == core.ID_BEER: beers += 1
	check(beers == 4 and item_count(B) == 5, "+4: 4 of 5 items became beer (%d beer, %d items)" % [beers, item_count(B)])
	await shot("11_plus4")

	# ---- smoke
	for p in props(): clear_items(p)
	give(A, 1); give(A, 2); give(B, 4); give(C, 6); give(C, 9)
	var cnt_before := props().map(func(p): return item_count(p))
	await use(M, core.ID_SMOKE)
	var cnt_after := props().map(func(p): return item_count(p))
	check(cnt_before == cnt_after, "smoke: each player keeps the item count %s -> %s" % [str(cnt_before), str(cnt_after)])
	var consistent := true
	for p in props():
		for i in 8:
			var d = gs.MAIN_inventory_by_socket[p.socket_number][i]
			if d != {} and (d.item_instance.get_child(1).socket_number != p.socket_number or p.user_inventory_instance_array[i] != d.item_instance): consistent = false
	check(consistent, "smoke: inventories consistent after the shuffle")
	await shot("12_smoke")

	# ---- nuke
	give(M, 4); give(A, 5)
	await use(M, core.ID_NUKE)
	var total := 0
	for p in props(): total += item_count(p)
	check(total == 0, "nuke: no items left (%d)" % total)
	await shot("13_nuke")

	# ---- extra barrels: one shot hits every opponent
	revive_all()
	await force_turn(M)
	await use(M, core.ID_BARRELS)
	check(core.st.triple, "barrels mounted")
	await shot("14_barrels")
	var hps := others(M).map(func(p): return p.health_current)
	await shoot(M, A.socket_number, "live", "14b_barrels_shot")
	var hps2 := others(M).map(func(p): return p.health_current)
	check(hps2 == hps.map(func(h): return h - 1), "barrels: every opponent lost 1 hp %s -> %s" % [str(hps), str(hps2)])
	check(!core.st.triple, "barrels consumed")

	# ---- blindfold + headphones + tape
	revive_all()
	await force_turn(M)
	await use(M, core.ID_BLINDFOLD, A.socket_number)
	await use(M, core.ID_HEADPHONES, B.socket_number)
	await use(M, core.ID_TAPE, C.socket_number)
	check(A.brmod_blind and B.brmod_deaf and C.brmod_tape, "blind/deaf/tape applied")
	await look_at_player(A)
	await shot("15_blindfold")
	await look_at_player(B)
	await shot("15_headphones")
	me().cam.BeginLerp("home")
	give(C, 4)
	await wait_idle()
	G().round_manager.MainRoutine_PassTurn(C.socket_number)
	await w(1.0)
	check(C.brmod_tape_active, "tape: active on the victim's turn")
	await w(3.0)
	check(C.is_holding_shotgun, "tape: shotgun picked up automatically")
	if C.is_holding_shotgun:
		C.shotgun.Shoot(null, M.socket_number)
		await w(8.5)
	await force_turn(A)
	check(!A.brmod_blind, "blindfold removed on own turn")
	await force_turn(B)
	check(!B.brmod_deaf, "headphones removed on own turn")

	# ---- drunk beer: forced roll
	revive_all()
	await force_turn(A)
	for p in props(): clear_items(p)
	set_shell("blank")
	core.debug_force = {"drunk": true}
	give(A, core.ID_BEER); give(A, core.ID_BEER)
	await use(A, core.ID_BEER)
	core.debug_force = {}
	check(A.brmod_drunk_pending, "beer: got drunk")
	await force_turn(B)
	await force_turn(A)
	check(A.brmod_drunk_active, "drunk on the next own turn")
	I().packets.PipeData({"packet category": "MP_PacketVerification", "packet alias": "pickup shotgun request", "sent_from": "client", "packet_id": 10, "sent_from_socket": A.socket_number})
	await w(2.0)
	check(!A.is_holding_shotgun, "drunk: shotgun refused while beer is left")
	set_shell("blank")
	await use(A, core.ID_BEER)
	I().packets.PipeData({"packet category": "MP_PacketVerification", "packet alias": "pickup shotgun request", "sent_from": "client", "packet_id": 10, "sent_from_socket": A.socket_number})
	await w(4.0)
	check(A.is_holding_shotgun, "drunk: shotgun allowed after the last beer")
	if A.is_holding_shotgun:
		A.shotgun.Shoot(null, B.socket_number)
		await w(8.5)

	# ---- tail easter egg on a bot
	core.attach_tail(A)
	await force_turn(M)
	await look_at_player(A)
	await shot("16_tail_a")
	await w(1.0)
	await shot("16_tail_b")

	print("[BRMod][TEST] DONE: %d passed, %d failed" % [passes, fails])

# ------------------------------------------------------------------ manual keys

func _unhandled_input(event):
	if !(event is InputEventKey) or !event.pressed or event.echo: return
	if I() == null: return
	if core.bot_mode:
		if bot_mode_key(event.keycode): get_viewport().set_input_as_handled()
		return
	var cur = P(G().MAIN_active_current_turn_socket)
	if cur == null: return
	match event.keycode:
		KEY_F5: give(cur, core.ID_UNO_RED)
		KEY_F6: give(cur, core.ID_UNO_YELLOW)
		KEY_F7: give(cur, core.ID_TOTEM)
		KEY_F8:
			for id in core.MOD_IDS: give(cur, id)
		KEY_F10:
			for p in props():
				print("[BRMod][debug] %s s%d hp %d/%d items %s" % [p.user_name, p.socket_number, p.health_current, p.health_on_round_start, G().MAIN_inventory_by_socket[p.socket_number].map(func(d): return d.item_id if d != {} else 0)])
