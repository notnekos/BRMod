extends CanvasLayer
# BRMod: on-screen UI — notifications, target picker, auto-grab toggle, blindfold overlay.

var core
var font : Font
var _notes : VBoxContainer
var _picker : PanelContainer
var _picker_cb : Callable
var _auto_btn : Button
var _blind : ColorRect
var _auto_flash := 0.0
var _status : Label

func _init(c):
	core = c
	name = "ui"
	layer = 90

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in ["res://fonts/fonts language/Fake Receipt Cyrillic.otf", "res://fonts/Fake Receipt Cyr Ver2_2.ttf"]:
		if ResourceLoader.exists(p):
			font = load(p)
			break
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_blind = load(core.mod_dir.path_join("lib/blindfold.gd")).new(core)
	_blind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blind.visible = false
	var bl := _label(core.t("ПОВЯЗКА · ДО ТВОЕГО ХОДА", "BLINDFOLDED UNTIL YOUR TURN"), 18)
	bl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bl.position.y = 20
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.modulate = Color(0.82, 0.82, 0.82)
	_blind.add_child(bl)
	root.add_child(_blind)

	_notes = VBoxContainer.new()
	_notes.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notes.position = Vector2(-300, 14)
	_notes.size = Vector2(600, 10)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notes.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_notes)

	_status = _label("", 20)
	_status.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1.0, 0.82, 0.35)
	_status.visible = false
	root.add_child(_status)

	_auto_btn = Button.new()
	_auto_btn.focus_mode = Control.FOCUS_NONE
	_auto_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_auto_btn.position = Vector2(12, -44)
	_auto_btn.size = Vector2(10, 30)
	if font: _auto_btn.add_theme_font_override("font", font)
	_auto_btn.add_theme_font_size_override("font_size", 15)
	_auto_btn.pressed.connect(func(): core.toggle_autograb())
	_auto_btn.visible = false
	root.add_child(_auto_btn)

	_picker = PanelContainer.new()
	_picker.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.92)
	sb.border_color = Color(0.75, 0.7, 0.6)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	_picker.add_theme_stylebox_override("panel", sb)
	_picker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.add_child(_picker)

func _label(text : String, size := 18) -> Label:
	var l := Label.new()
	l.text = text
	if font: l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func notify(text : String, secs := 4.0, color := Color(0.95, 0.92, 0.85)) -> void:
	# release build: no on-screen event log, only the game log
	print("[BRMod] event: ", text.replace("
", " "))

func set_blind(on : bool) -> void:
	_blind.set_active(on)

# ------------------------------------------------------------------ picker

# options: Array of [label, value]. cb(value) — value null when cancelled.
func pick(title : String, options : Array, cb : Callable) -> void:
	for c in _picker.get_children(): c.free()
	_picker_cb = cb
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var tl := _label(title, 20)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var grid := GridContainer.new()
	grid.columns = 3 if options.size() > 4 else max(1, options.size())
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for o in options:
		var b := Button.new()
		b.text = str(o[0])
		b.custom_minimum_size = Vector2(150, 40)
		b.focus_mode = Control.FOCUS_NONE
		if font: b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_picked.bind(o[1]))
		grid.add_child(b)
	v.add_child(grid)
	var cancel := Button.new()
	cancel.text = core.t("ОТМЕНА", "CANCEL")
	cancel.focus_mode = Control.FOCUS_NONE
	if font: cancel.add_theme_font_override("font", font)
	cancel.pressed.connect(_picked.bind(null))
	v.add_child(cancel)
	_picker.add_child(v)
	_picker.visible = true
	_picker.reset_size()
	_picker.position = (get_viewport().get_visible_rect().size - _picker.size) * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func picker_open() -> bool:
	return _picker.visible

func _picked(value) -> void:
	_picker.visible = false
	var cb := _picker_cb
	_picker_cb = Callable()
	if cb.is_valid(): cb.call(value)

# ------------------------------------------------------------------ auto-grab button

func autograb_phase() -> bool:
	# only during the intro and while the local player is taking items out of the briefcase
	var inter = core.inter()
	if inter == null: return false
	var rm = inter.game_state.round_manager
	if rm and !rm.intro_finished: return true
	var me = inter.intermed_properties
	return me != null and me.is_grabbing_items

func status_text() -> String:
	# explains to the local player why an action is blocked (not an event log)
	var inter = core.inter()
	if inter == null or inter.intermed_properties == null: return ""
	var me = inter.intermed_properties
	if me.get("brmod_drunk_active") == null or me.health_current <= 0: return ""
	if me.brmod_jammer_immune:
		return core.t("Банка таблеток защищает от глушилки до твоего хода", "The pill jar protects you from the jammer until your turn")
	if me.brmod_tape_active:
		return core.t("РУКИ СВЯЗАНЫ ИЗОЛЕНТОЙ — в этот ход только выстрел", "YOUR HANDS ARE TAPED — shooting only this turn")
	if me.brmod_drunk_active and core.items.shotgun_blocked(me):
		return core.t("ТЫ ПЬЯН — нельзя стрелять, пока не выпьешь всё своё пиво", "YOU'RE DRUNK — drink all your beer before you can shoot")
	if me.brmod_drunk_pending:
		return core.t("Ты опьянел: в следующий ход сначала придётся выпить всё пиво", "You got drunk: next turn you must drink all your beer first")
	return ""

func _process(_delta):
	var st := status_text()
	_status.visible = st != "" and !_blind.visible
	if _status.visible:
		_status.text = st
		var vs := get_viewport().get_visible_rect().size
		_status.size = Vector2(vs.x - 80, 10)
		_status.position = Vector2(40, vs.y - 110)
	if _picker.visible:
		# the game hides the cursor when permissions drop — keep it while choosing
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_auto_btn.visible = autograb_phase()
	if _auto_btn.visible:
		var on : bool = core.settings_autograb
		_auto_btn.text = core.t("Автодоставание предметов: %s  [%s]", "Auto item grab: %s  [%s]") % [core.t("ВКЛ", "ON") if on else core.t("ВЫКЛ", "OFF"), core.autograb_key_name()]
		_auto_btn.modulate = Color(0.6, 1.0, 0.6) if on else Color(1, 1, 1, 0.85)

func flash_autograb() -> void:
	pass
