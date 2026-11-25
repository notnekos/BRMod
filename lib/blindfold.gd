extends ColorRect
# This viewport only receives static scenery, the local briefcase, and the local inventory.

const SCENE_MESHES := [
	"tabletop blockout/tabletop frame new/tabletop wood frame new1",
	"tabletop blockout/tabletop main parent_001/tabletop main padding2",
	"tabletop blockout/tabletop main parent_001/tabletop inner padding_001",
	"interior environment main1/interior environment parent/interior wall main2",
	"interior environment main1/interior environment parent/ceiling beams",
	"interior environment main1/interior environment parent/pipes",
	"interior environment main1/interior environment parent/tabletop lower wood frame",
]
const SCENERY := 0
const BRIEFCASE := 1
const ITEM := 2

var core
var _view : SubViewport
var _camera : Camera3D
var _copies := {}
var _scan_materials : Array[ShaderMaterial] = []
var _slots : HBoxContainer
var _slot_buttons : Array[Button] = []
var _manager

func _init(c):
	core = c

func _ready() -> void:
	color = Color.BLACK
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.gui_disable_input = true
	add_child(_view)
	_camera = Camera3D.new()
	_view.add_child(_camera)
	var buffer_shader : Shader = load(core.mod_dir.path_join("shaders/lidar_buffer.gdshader"))
	for role in ITEM + core.ENCHANT_CODING + 1:
		var surface := ShaderMaterial.new()
		surface.shader = buffer_shader
		surface.set_shader_parameter("scan_class", Vector3(role & 1, (role >> 1) & 1, (role >> 2) & 1))
		_scan_materials.append(surface)

	var picture := TextureRect.new()
	picture.texture = _view.get_texture()
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var lidar := ShaderMaterial.new()
	lidar.shader = load(core.mod_dir.path_join("shaders/lidar_view.gdshader"))
	picture.material = lidar
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	move_child(picture, 0)
	var slot_area := CenterContainer.new()
	slot_area.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	slot_area.offset_top = -77
	slot_area.offset_bottom = -36
	slot_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot_area)
	_slots = HBoxContainer.new()
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots.add_theme_constant_override("separation", 6)
	slot_area.add_child(_slots)
	var caption := Label.new()
	caption.text = core.t("Куда положить предмет", "Place item in slot")
	_slots.add_child(caption)
	for i in 8:
		var button := Button.new()
		button.text = str(i + 1)
		button.custom_minimum_size = Vector2(28, 28)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_place_in_slot.bind(i))
		_slots.add_child(button)
		_slot_buttons.append(button)
	set_active(false)

func set_active(on : bool) -> void:
	visible = on
	set_process(on)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		_process(0.0)
	else:
		_manager = null
		_slots.hide()
		for copy in _copies.values():
			copy.hide()
			copy.queue_free()
		_copies.clear()

func _place_in_slot(slot : int) -> void:
	if is_instance_valid(_manager): _manager.PlaceItemRequest(slot)

func _process(_delta) -> void:
	var inter = core.inter()
	if inter == null or !is_instance_valid(inter.intermed_properties):
		set_active(false)
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var player = inter.intermed_properties
	var manager = player.item_manager
	_manager = manager
	var view_size := Vector2i(get_viewport().get_visible_rect().size)
	if view_size.x > 1 and view_size.y > 1:
		_view.size = view_size
	_camera.global_transform = camera.global_transform
	_camera.projection = camera.projection
	_camera.keep_aspect = camera.keep_aspect
	_camera.fov = camera.fov
	_camera.size = camera.size
	_camera.near = camera.near
	_camera.far = camera.far
	_camera.h_offset = camera.h_offset
	_camera.v_offset = camera.v_offset
	_camera.frustum_offset = camera.frustum_offset
	var sources := {}
	var scene := get_tree().current_scene
	if scene:
		for path in SCENE_MESHES:
			var mesh := scene.get_node_or_null(path) as MeshInstance3D
			# Register these exact meshes. Some have gameplay objects as children.
			if mesh and mesh.is_visible_in_tree(): _add_mesh(mesh, sources, SCENERY)
	for item in player.user_inventory_instance_array:
		if is_instance_valid(item):
			_collect(item, sources, ITEM + core.items.enchant_of(item))
	if player.is_grabbing_items:
		_collect(manager.intbranch_intake.get_parent(), sources, BRIEFCASE)
		if player.is_holding_item_to_place and is_instance_valid(manager.active_instance):
			_collect(manager.active_instance, sources, ITEM + core.items.enchant_of(manager.active_instance))
	var has_open_slot := false
	for i in _slot_buttons.size():
		var branch = manager.intbranch_grid_colliders[i]
		_slot_buttons[i].disabled = !branch.interactionAllowed
		has_open_slot = has_open_slot or branch.interactionAllowed
	_slots.visible = player.is_grabbing_items and player.is_holding_item_to_place and has_open_slot
	for id in _copies.keys():
		if !sources.has(id):
			var copy : Node3D = _copies[id]
			copy.hide()
			copy.queue_free()
			_copies.erase(id)
	for id in sources:
		var source : MeshInstance3D = sources[id][0]
		var role : int = sources[id][1]
		if !_copies.has(id):
			var copy := MeshInstance3D.new()
			copy.mesh = source.mesh
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_view.add_child(copy)
			_copies[id] = copy
		var replica : MeshInstance3D = _copies[id]
		if replica.material_override != _scan_materials[role]:
			replica.material_override = _scan_materials[role]
		replica.global_transform = source.global_transform

func _add_mesh(mesh : MeshInstance3D, sources : Dictionary, role : int) -> void:
	if mesh.mesh and mesh.layers != 0:
		sources[mesh.get_instance_id()] = [mesh, role]

func _collect(root : Node3D, sources : Dictionary, role : int) -> void:
	if !root.is_visible_in_tree(): return
	if root is MeshInstance3D:
		_add_mesh(root, sources, role)
	for child in root.get_children():
		if child is Node3D: _collect(child, sources, role)
