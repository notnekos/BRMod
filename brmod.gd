extends Node
# BRMod — новые предметы и патроны для мультиплеера Buckshot Roulette.
# Autoload через override.cfg. Мод должен стоять у ВСЕХ игроков в лобби.

const VERSION := "2.1.1"

const ID_SAW := 1
const ID_GLASS := 2
const ID_JAMMER := 3
const ID_BEER := 5
const ID_PHONE := 6
const ID_PILLS := 7
const ID_ADRENALINE := 8
const ID_INVERTER := 9
const ID_UNO_RED := 11
const ID_UNO_YELLOW := 12
const ID_TOTEM := 13
const ID_WHISKEY := 14
const ID_SHOT := 15
const ID_NUKE := 16
const ID_SMOKE := 17
const ID_STORM := 18
const ID_PLUS4 := 19
const ID_BARRELS := 20
const ID_BLINDFOLD := 21
const ID_HEADPHONES := 22
const ID_TAPE := 23
const ID_ADRENALINE_ZERO := 24
const ID_PILL_JAR := 25
const MOD_IDS := [11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]
const BASE_ITEM_ID := 4 # cigarettes: template for scene/resource/hands
const ENCHANT_NONE := 0
const ENCHANT_BUNKER := 1
const ENCHANT_DOPAMINE := 2
const ENCHANT_CODING := 3

const MP := "res://multiplayer/scripts/"
const EXTENSIONS := {
	"global scripts/MP_GameStateManager.gd": "ext/ext_game_state.gd",
	"global scripts/MP_PacketVerification.gd": "ext/ext_packet_verification.gd",
	"global scripts/MP_RoundManager.gd": "ext/ext_round_manager.gd",
	"global scripts/MP_ShellBranch.gd": "ext/ext_shell_branch.gd",
	"user scripts/MP_ShotgunInteraction.gd": "ext/ext_shotgun.gd",
	"user scripts/MP_ItemInteraction.gd": "ext/ext_item_interaction.gd",
	"user scripts/MP_UserInstanceProperties.gd": "ext/ext_user_properties.gd",
	"user scripts/MP_ItemManager.gd": "ext/ext_item_manager.gd",
	"user scripts/MP_UserPermissions.gd": "ext/ext_permissions.gd",
	"user scripts/MP_BurnerPhone.gd": "ext/ext_burner_phone.gd",
	"user scripts/MP_Jammer.gd": "ext/ext_jammer.gd",
}

# key, default enabled, per player, on table
const ITEM_DEFAULTS := {
	7: ["pills", true, 1, 2],
	11: ["uno_red", true, 1, 2],
	12: ["uno_yellow", true, 1, 2],
	13: ["totem", true, 1, 1],
	14: ["whiskey", true, 1, 1],
	15: ["whiskey_shot", true, 1, 2],
	16: ["nuke", true, 1, 1],
	17: ["smoke", true, 1, 1],
	18: ["storm", true, 1, 1],
	19: ["uno_plus4", true, 1, 1],
	20: ["barrels", true, 1, 1],
	21: ["blindfold", true, 1, 2],
	22: ["headphones", true, 1, 2],
	23: ["tape", true, 1, 1],
	24: ["adrenaline_zero", true, 1, 1],
	25: ["pill_jar", true, 1, 4],
}

var mod_dir := ""
var cfg := {}
var shell_hidden_chance := 0.25
var shell_heal_chance := 0.25
var shell_black_chance := 0.18
var enchant_chance := 0.12
var beer_drunk_chance := 0.10
var tail_names := ["sergkomp"]
var autograb_key := KEY_G
var offline_test := false
var autotest := false
var settings_autograb := false
var round_intro := false
# test hooks
var test_autograb_all := false
var debug_force := {}
var debug_last_effect := -1
var force_specials := false
var bot_mode := false
var regression_test := false
var autotest_quick := false
var marker_out := 1.0

var assets
var fx
var ui
var items
var shells
var use_anim
var test

# game-wide synced state (every client keeps the same copy)
var st := {}

# ---------------------------------------------------------------- boot

func _init():
	mod_dir = get_script().resource_path.get_base_dir()
	print("[BRMod] v%s loading from %s" % [VERSION, mod_dir])
	for rel in EXTENSIONS:
		var child : Script = load(mod_dir.path_join(EXTENSIONS[rel]))
		if child == null:
			push_error("[BRMod] failed to load extension " + EXTENSIONS[rel])
			continue
		child.take_over_path(MP + rel)
	print("[BRMod] %d script extensions installed" % EXTENSIONS.size())

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	_load_settings()
	var gv = get_node("/root/GlobalVariables")
	gv.version_to_check += "-brmod" + VERSION
	gv.currentVersion += "  +BRMod " + VERSION
	print("[BRMod] lobby version tag: ", gv.version_to_check)
	assets = load(mod_dir.path_join("lib/assets.gd")).new(self)
	items = load(mod_dir.path_join("lib/items.gd")).new(self)
	shells = load(mod_dir.path_join("lib/shells.gd")).new(self)
	use_anim = load(mod_dir.path_join("lib/use_anim.gd")).new(self)
	fx = load(mod_dir.path_join("lib/fx.gd")).new(self)
	add_child(fx)
	ui = load(mod_dir.path_join("lib/ui.gd")).new(self)
	add_child(ui)
	reset_state()
	get_tree().node_added.connect(_on_node_added)
	bot_mode = OS.get_cmdline_user_args().has("--brmod-bots")
	regression_test = OS.get_cmdline_user_args().has("--brmod-regression")
	if bot_mode:
		autotest = false
	if offline_test or bot_mode or regression_test:
		test = load(mod_dir.path_join("lib/test.gd")).new(self)
		add_child(test)
		test.start.call_deferred()

func _on_node_added(n : Node) -> void:
	if n.name == "mp_main" and n.get_parent() == get_tree().root:
		reset_state()
		ui.set_blind(false)
		fx.set_deaf(false)
		round_intro = true

func _intro_hint() -> void:
	await get_tree().create_timer(3.0).timeout
	notify(t("BRMod %s: [%s] или кнопка внизу слева — автодоставание предметов из ящика (сейчас %s)", "BRMod %s: [%s] or the button bottom-left — auto item grab (now %s)") % [VERSION, autograb_key_name(), t("ВКЛ", "ON") if settings_autograb else t("ВЫКЛ", "OFF")], 8.0)
	ui.flash_autograb()

func _load_config():
	for id in ITEM_DEFAULTS:
		var d : Array = ITEM_DEFAULTS[id]
		cfg[id] = {"key": d[0], "enabled": d[1], "max_per_player": d[2], "max_on_table": d[3]}
	var c := ConfigFile.new()
	if c.load(mod_dir.path_join("config.cfg")) != OK:
		print("[BRMod] no config.cfg, using defaults")
		return
	for id in cfg:
		var k : String = cfg[id].key
		cfg[id].enabled = c.get_value(k, "enabled", cfg[id].enabled)
		cfg[id].max_per_player = c.get_value(k, "max_per_player", cfg[id].max_per_player)
		cfg[id].max_on_table = c.get_value(k, "max_on_table", cfg[id].max_on_table)
	shell_hidden_chance = c.get_value("shells", "hidden_chance", shell_hidden_chance)
	shell_heal_chance = c.get_value("shells", "heal_chance", shell_heal_chance)
	shell_black_chance = c.get_value("shells", "black_chance", shell_black_chance)
	enchant_chance = c.get_value("enchantments", "grab_chance", enchant_chance)
	beer_drunk_chance = c.get_value("beer", "drunk_chance", beer_drunk_chance)
	tail_names = Array(c.get_value("easter", "tail_names", tail_names)).map(func(s): return str(s).to_lower())
	var key_name : String = c.get_value("controls", "autograb_key", "G")
	var kc := OS.find_keycode_from_string(key_name)
	if kc != KEY_NONE: autograb_key = kc
	offline_test = c.get_value("debug", "offline_test", false)
	autotest = c.get_value("debug", "autotest", false)
	autotest_quick = c.get_value("debug", "autotest_quick", false)

func _settings_path() -> String:
	return "user://brmod_settings.cfg"

func _load_settings():
	var c := ConfigFile.new()
	if c.load(_settings_path()) == OK:
		settings_autograb = c.get_value("player", "autograb", false)

func _save_settings():
	var c := ConfigFile.new()
	c.set_value("player", "autograb", settings_autograb)
	c.save(_settings_path())

func autograb_key_name() -> String:
	return OS.get_keycode_string(autograb_key)

func toggle_autograb() -> void:
	set_autograb(!settings_autograb)

func set_autograb(on : bool) -> void:
	if settings_autograb == on: return
	settings_autograb = on
	_save_settings()
	ui.flash_autograb()
	notify(t("Автодоставание предметов: %s", "Auto item grab: %s") % (t("ВКЛ", "ON") if settings_autograb else t("ВЫКЛ", "OFF")), 2.5)
	var inter = inter()
	if settings_autograb and inter and inter.intermed_properties:
		inter.intermed_properties.item_manager.brmod_autograb_kick()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and !event.echo and event.keycode == autograb_key:
		if inter() != null and ui.autograb_phase():
			toggle_autograb()
			get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- shared helpers

func t(ru_text : String, en_text : String) -> String:
	return ru_text if ru() else en_text

func ru() -> bool:
	var l := TranslationServer.get_locale().to_lower()
	return l.begins_with("ru") or l.begins_with("ua") or l.begins_with("uk")

func notify(text : String, secs := 4.0, color := Color(0.95, 0.92, 0.85)) -> void:
	if ui: ui.notify(text, secs, color)

var _gs_hint = null
func inter():
	var sc = get_tree().current_scene
	if sc == null or sc.name != "mp_main":
		if _gs_hint != null and is_instance_valid(_gs_hint): return _gs_hint.round_manager.intermed
		return null
	return sc.get_node_or_null("standalone managers/interactions/interaction intermediary")

func is_host() -> bool:
	var gs = get_node("/root/GlobalSteam")
	return gs.STEAM_ID == gs.HOST_ID or get_node("/root/GlobalVariables").mp_debugging

func is_mod_item(id : int) -> bool:
	return id in MOD_IDS

func is_custom_flow(id : int) -> bool:
	return id == ID_PILLS or is_mod_item(id)

func get_props(any_props, socket : int):
	if socket < 0 or any_props == null: return null
	for p in any_props.intermediary.instance_handler.instance_property_array:
		if p.socket_number == socket: return p
	return null

func all_props() -> Array:
	var i = inter()
	if i == null: return []
	return i.instance_handler.instance_property_array

func res(id : int):
	var i = inter()
	if i == null: return null
	for r in i.game_state.MAIN_item_resource_array:
		if r.id == id: return r
	return null

func reset_state() -> void:
	st = {
		"chaos": {},          # table socket -> owner socket (whiskey)
		"storm_pending": false,
		"storm_left": 0,      # host counter (also mirrored to clients for display)
		"triple": false,      # extra barrels mounted
	}

func chaos_for(socket : int) -> bool:
	return st.chaos.has(socket)

func user_name_of(p) -> String:
	return p.user_name if p else "?"

const VANILLA_NAMES := {
	1: ["НОЖОВКА", "HAND SAW"], 2: ["ЛУПА", "MAGNIFYING GLASS"], 3: ["ГЛУШИЛКА", "JAMMER"], 4: ["СИГАРЕТЫ", "CIGARETTES"],
	5: ["ПИВО", "BEER"], 6: ["ТЕЛЕФОН", "BURNER PHONE"], 7: ["ТАБЛЕТКИ", "PILLS"], 8: ["АДРЕНАЛИН", "ADRENALINE"],
	9: ["ИНВЕРТОР", "INVERTER"], 10: ["ПУЛЬТ", "REMOTE"],
}

func item_name(id : int) -> String:
	match id:
		ID_UNO_RED: return t("УНО: ВОЗВРАТ", "UNO: REVERSE")
		ID_UNO_YELLOW: return t("УНО: ПОДМЕНА", "UNO: SWAP")
		ID_TOTEM: return t("ТОТЕМ БЕССМЕРТИЯ", "TOTEM OF UNDYING")
		ID_WHISKEY: return t("БУТЫЛКА ВИСКИ", "WHISKEY BOTTLE")
		ID_SHOT: return t("ШОТ ВИСКИ", "WHISKEY SHOT")
		ID_NUKE: return t("ЯДЕРНЫЙ ГРИБ", "NUKE")
		ID_SMOKE: return t("ДЫМОВУХА", "SMOKE GRENADE")
		ID_STORM: return t("ГРОЗОВАЯ ТУЧА", "STORM CLOUD")
		ID_PLUS4: return t("УНО: +4", "UNO: +4")
		ID_BARRELS: return t("ДОП. СТВОЛЫ", "EXTRA BARRELS")
		ID_BLINDFOLD: return t("ПОВЯЗКА", "BLINDFOLD")
		ID_HEADPHONES: return t("НАУШНИКИ", "HEADPHONES")
		ID_TAPE: return t("СИНЯЯ ИЗОЛЕНТА", "BLUE TAPE")
		ID_ADRENALINE_ZERO: return "ADRENALINE ZERO SUGAR"
		ID_PILL_JAR: return t("БАНКА ТАБЛЕТОК", "PILL JAR")
	if VANILLA_NAMES.has(id): return t(VANILLA_NAMES[id][0], VANILLA_NAMES[id][1])
	return "?"

func item_desc(id : int) -> String:
	match id:
		ID_UNO_RED: return t("Возвращает последний боевой выстрел в тебя.\nХолостой: ты теряешь 1 заряд. При 1 HP у стрелка карта недоступна.", "Reflects the last live shot fired at you.\nBlank: you lose 1 charge. Unavailable if the shooter has 1 HP.")
		ID_UNO_YELLOW: return t("Следующий выстрел соперника в тебя меняет патрон\n(боевой / холостой). Действует 1 круг.", "The next shot an opponent fires at you is inverted\n(live / blank). Lasts one lap.")
		ID_TOTEM: return t("Пассивный. Спасает от смерти,\nоставляя 1 заряд.", "Passive. Saves you from death,\nleaving 1 charge.")
		ID_WHISKEY: return t("На 1 круг все предметы на столе\nработают как случайные.", "For one lap every item on the table\nworks as a random item.")
		ID_SHOT: return t("На 1 круг предметы выбранного игрока\nработают как случайные.", "For one lap the chosen player's items\nwork as random items.")
		ID_NUKE: return t("Уничтожает предметы всех игроков.\nБункер защищает предмет.", "Destroys every player's items.\nBunker protects the item.")
		ID_SMOKE: return t("Перемешивает предметы\nвсех игроков между собой.", "Shuffles the items\nof all players between them.")
		ID_STORM: return t("Выбери число 1-6: через столько использований\nпредметов патроны перемешаются.", "Pick 1-6: after that many item uses\nthe shells get shuffled.")
		ID_PLUS4: return t("До 4 предметов выбранного игрока\nпревращаются в пиво.", "Up to 4 items of the chosen player\nturn into beer.")
		ID_BARRELS: return t("Следующий выстрел в соперника бьёт\nвсех соперников. Не вместе с ножовкой.", "The next shot at an opponent hits\nevery opponent. Not with the saw.")
		ID_BLINDFOLD: return t("До своего хода игрок видит только контуры.\nИз предметов видны свои и ящик при раздаче.", "Until their turn, the player sees only outlines.\nOnly their items and briefcase are visible.")
		ID_HEADPHONES: return t("Надеть на игрока наушники:\nдо его хода он слышит только музыку.", "Put headphones on a player:\nonly music until their turn.")
		ID_TAPE: return t("Связать руки: в свой ход игрок\nне может брать предметы и сразу стреляет.", "Tie a player's hands: on their turn\nno items, straight to shooting.")
		ID_PILLS: return t("50%: +2 заряда (можно выше лимита).\n50%: -1 заряд.", "50%: +2 charges (can exceed the limit).\n50%: -1 charge.")
		ID_ADRENALINE_ZERO: return t("95%: зачаровать все предметы на столе.\n5%: уничтожить один случайный предмет.", "95%: enchant every item on the table.\n5%: destroy one random item.")
		ID_PILL_JAR: return t("До твоего следующего хода\nглушилка не может заблокировать твой ход.", "The jammer cannot block your turn\nuntil your next turn.")
	return ""

# ---------------------------------------------------------------- item registration (called from GameStateManager._ready)

func register_items(game_state) -> void:
	_gs_hint = game_state
	var arr = game_state.MAIN_item_resource_array.duplicate()
	var base_res = null
	for r in arr:
		if r.id == BASE_ITEM_ID: base_res = r
	if base_res == null:
		push_error("[BRMod] base item resource not found")
		return
	for id in MOD_IDS:
		var exists := false
		for r in arr:
			if r.id == id: exists = true
		if exists: continue
		var r = base_res.duplicate()
		r.id = id
		r.name = cfg[id].key
		r.instance = _make_item_scene(id, base_res.instance)
		arr.append(r)
	game_state.MAIN_item_resource_array = arr
	apply_item_config(game_state)
	# pills: keep the original model, give it our name/description
	for r in arr:
		if r.id == ID_PILLS and !r.has_meta("brmod_pills"):
			var r2 = r.duplicate()
			r2.set_meta("brmod_pills", true)
			r2.instance = _relabel_scene(r.instance, ID_PILLS)
			arr[arr.find(r)] = r2
			break
	game_state.MAIN_item_resource_array = arr
	apply_item_config(game_state)
	print("[BRMod] item resources: ", arr.map(func(x): return x.id))

func apply_item_config(game_state) -> void:
	for r in game_state.MAIN_item_resource_array:
		if cfg.has(r.id):
			r.distribution_enabled = cfg[r.id].enabled
			r.max_amount_on_table = cfg[r.id].max_per_player
			r.max_amount_on_table_global = cfg[r.id].max_on_table

func _make_item_scene(id : int, base_scene : PackedScene) -> PackedScene:
	var root : Node3D = base_scene.instantiate()
	root.name = "item parent_brmod_%d" % id
	var ind = root.get_child(0)
	ind.itemName = item_name(id)
	ind.itemDescription = item_desc(id)
	var br = root.get_child(1)
	br.itemName = cfg[id].key
	br.item_id = id
	var mi : MeshInstance3D = root.get_node("mesh_cigarettes")
	mi.mesh = assets.get_mesh(id, mi.mesh.get_aabb())
	var ps := PackedScene.new()
	if ps.pack(root) != OK: push_error("[BRMod] pack failed for %d" % id)
	root.free()
	return ps

func _relabel_scene(scene : PackedScene, id : int) -> PackedScene:
	var root : Node3D = scene.instantiate()
	root.get_child(0).itemName = item_name(id)
	root.get_child(0).itemDescription = item_desc(id)
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps

func extend_user_arrays(props) -> void:
	var base_mesh_R : Node3D = props.user_item_array_mesh_R[BASE_ITEM_ID]
	var base_mesh_L : Node3D = props.user_item_array_mesh_L[BASE_ITEM_ID]
	var max_id : int = MOD_IDS.max()
	while props.user_item_array_hand_R.size() <= max_id: props.user_item_array_hand_R.append(props.user_item_array_hand_R[BASE_ITEM_ID])
	while props.user_item_array_hand_L.size() <= max_id: props.user_item_array_hand_L.append(props.user_item_array_hand_L[BASE_ITEM_ID])
	while props.user_item_array_mesh_R.size() <= max_id: props.user_item_array_mesh_R.append(base_mesh_R)
	while props.user_item_array_mesh_L.size() <= max_id: props.user_item_array_mesh_L.append(base_mesh_L)
	while props.user_item_array_offset_y.size() <= max_id: props.user_item_array_offset_y.append(props.user_item_array_offset_y[BASE_ITEM_ID])
	for id in MOD_IDS:
		props.user_item_array_mesh_R[id] = _clone_hand_mesh(base_mesh_R, id)
		props.user_item_array_mesh_L[id] = _clone_hand_mesh(base_mesh_L, id)

func _clone_hand_mesh(base : Node3D, id : int) -> Node3D:
	var m : MeshInstance3D = base.duplicate()
	m.name = "mesh_brmod_%d" % id
	if base is MeshInstance3D:
		m.mesh = assets.get_mesh(id, (base as MeshInstance3D).mesh.get_aabb())
	m.visible = false
	base.get_parent().add_child(m)
	return m

# ---------------------------------------------------------------- totem / damage (every client)

func find_slot(game_state, socket : int, id : int) -> int:
	var inv = game_state.MAIN_inventory_by_socket[socket]
	for i in inv.size():
		if inv[i] != {} and inv[i].item_id == id: return i
	return -1

func has_totem(game_state, socket : int) -> bool:
	return find_slot(game_state, socket, ID_TOTEM) != -1

func has_item(game_state, socket : int, id : int) -> bool:
	return find_slot(game_state, socket, id) != -1

func deal_damage(target, from_socket : int, dmg : int) -> int:
	var new_hp : int = target.health_current - dmg
	if new_hp <= 0 and consume_totem(target):
		new_hp = 1
	new_hp = max(new_hp, 0)
	var dealt : int = target.health_current - new_hp
	target.health_current = new_hp
	print("[BRMod] damage: socket %d -> %d, dmg %d, dealt %d, hp now %d" % [from_socket, target.socket_number, dmg, dealt, new_hp])
	return dealt

func consume_totem(target) -> bool:
	var gs = target.intermediary.game_state
	var slot := find_slot(gs, target.socket_number, ID_TOTEM)
	if slot == -1: return false
	var inst : Node3D = gs.MAIN_inventory_by_socket[target.socket_number][slot].item_instance
	target.item_interaction.RemoveItemFromInventory(slot, target.socket_number)
	print("[BRMod] TOTEM saved socket ", target.socket_number)
	_totem_effect(target, inst)
	return true

func _totem_effect(target, inst : Node3D) -> void:
	await get_tree().create_timer(0.35, false).timeout
	fx.play("totem", 2.0)
	var pos : Vector3 = target.instance_root.global_position if target.instance_root else Vector3.ZERO
	if inst and is_instance_valid(inst):
		pos = inst.global_position
		fx.poof_item(inst, fx.COLOR_GOLD, 2.5)
	var head := pos
	if target.instance_root: head = target.instance_root.global_position + Vector3(0, 4.5, 0)
	fx.burst(head, [Color(1.0, 0.95, 0.3), Color(0.35, 1.0, 0.3)], 120, 7.0, 3.0, 1.8, 0.14)
	fx.burst(head, [Color(0.4, 1.0, 0.4), Color(1.0, 0.9, 0.2)], 60, 4.0, 4.0, 2.2, 0.1)
	fx.flash(head, fx.COLOR_GOLD, 1.6, 8.0, 12.0)
	if target.is_active:
		fx.totem_pop_fp(target)
	notify(t("%s спасён ТОТЕМОМ БЕССМЕРТИЯ!", "%s was saved by the TOTEM OF UNDYING!") % target.user_name, 4.0, Color(1, 0.9, 0.4))

# ---------------------------------------------------------------- easter egg

func is_tail_user(n : String) -> bool:
	return n.to_lower() in tail_names

func attach_tail(props) -> void:
	var root = props.get_node_or_null("../..")
	if root == null: return
	var body : Node3D = root.get_node_or_null("user third person view/user model upper parent/user model kickback parent/user model main parent")
	var head : Node3D = root.get_node_or_null("user third person view/user model upper parent/user model kickback parent/user model main parent/user model secondary parent/user model look parent/placeholder visual model")
	if body == null or head == null or body.get_node_or_null("brmod_tail"): return
	var tail : MeshInstance3D = assets.tail_node()
	if tail == null: return
	body.add_child(tail)
	var hb : AABB = fx._head_box(head)
	var head_g : Vector3 = head.global_transform * hb.get_center()
	var hsize : float = (head.global_transform.basis * hb.size).length() / 1.732
	# "back" = away from the table centre (the shotgun lies in the middle of the table)
	var centre := Vector3.ZERO
	var it = inter()
	if it and it.globalparent_shotgun: centre = it.globalparent_shotgun.global_position
	var to_center := centre - head_g
	to_center.y = 0
	var back := -to_center.normalized() if to_center.length() > 0.01 else Vector3.BACK
	# the tail sticks out from below the mask, to the side and up (players sit close to the walls)
	var side := back.cross(Vector3.UP).normalized()
	var dir := (side * 0.85 + Vector3.UP * 0.5 + back * 0.2).normalized()
	var z_axis := -dir
	var y_axis := (Vector3.UP - z_axis * Vector3.UP.dot(z_axis)).normalized()
	var x_axis := y_axis.cross(z_axis)
	var s := hsize * 2.4 / 1.2
	var b := Basis(x_axis, y_axis, z_axis).scaled(Vector3.ONE * s)
	var attach := head_g - Vector3.UP * hsize * 1.9 + back * hsize * 0.2 + side * hsize * 0.3
	tail.global_transform = Transform3D(b, attach - b * Vector3(0, 0.98, -0.04))
	print("[BRMod] tail attached to ", props.user_name, " head size ", hsize)
