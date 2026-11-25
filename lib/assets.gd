extends RefCounted
# BRMod: meshes, textures, GLB models and sounds. Everything is built at runtime (Godot 4.1 API).

var core
var _meshes := {}
var _tex := {}
var _sounds := {}
var _glb_cache := {}
var _enchant_glints := {}

const ENCHANT_COLORS := {
	1: [Color("#d78423"), Color("#ffd673")],
	2: [Color("#aa52f0"), Color("#ff85db")],
	3: [Color("#1bbde5"), Color("#c2fffc")],
}

func _init(c):
	core = c

func path(rel : String) -> String:
	return core.mod_dir.path_join(rel)

func enchant_glint(enchant : int) -> ShaderMaterial:
	if !ENCHANT_COLORS.has(enchant): return null
	if !_enchant_glints.has(enchant):
		var colors : Array = ENCHANT_COLORS[enchant]
		var glint := ShaderMaterial.new()
		glint.shader = load(path("shaders/enchant_glint.gdshader"))
		glint.set_shader_parameter("enchantment", enchant)
		glint.set_shader_parameter("tint", colors[0])
		glint.set_shader_parameter("highlight", colors[1])
		_enchant_glints[enchant] = glint
	return _enchant_glints[enchant]

# ------------------------------------------------------------------ generic mesh helpers

func add_prim(am : ArrayMesh, prim : PrimitiveMesh, xf : Transform3D, mat : Material) -> void:
	var arrays := prim.get_mesh_arrays()
	add_arrays(am, arrays, xf, mat)

func add_arrays(am : ArrayMesh, arrays : Array, xf : Transform3D, mat : Material) -> void:
	var v : PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size(): v[i] = xf * v[i]
	arrays[Mesh.ARRAY_VERTEX] = v
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var n : PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var nb := xf.basis.inverse().transposed()
		for i in n.size(): n[i] = (nb * n[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TANGENT] = null
	for k in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		arrays[k] = null
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(am.get_surface_count() - 1, mat)

func mat(color : Color, metallic := 0.0, rough := 0.6, emit := 0.0, tex : Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if tex:
		m.albedo_texture = tex
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
		if tex:
			m.emission = Color.WHITE
			m.emission_texture = tex
	return m

func aabb_of(am : ArrayMesh) -> AABB:
	return am.get_aabb()

# Re-bakes a mesh so that it fits a box of target size, standing on ref floor, centred on ref.
func fit_mesh(src : ArrayMesh, ref : AABB, max_w : float, max_h : float, extra : Transform3D = Transform3D()) -> ArrayMesh:
	var tmp := ArrayMesh.new()
	for i in src.get_surface_count():
		add_arrays(tmp, src.surface_get_arrays(i), extra, src.surface_get_material(i))
	var a := tmp.get_aabb()
	var s : float = min(max_w / max(a.size.x, a.size.z, 0.0001), max_h / max(a.size.y, 0.0001))
	var c := a.get_center()
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	xf.origin = Vector3(ref.get_center().x - c.x * s, ref.position.y - a.position.y * s, ref.get_center().z - c.z * s)
	var out := ArrayMesh.new()
	for i in tmp.get_surface_count():
		add_arrays(out, tmp.surface_get_arrays(i), xf, tmp.surface_get_material(i))
	return out

# ------------------------------------------------------------------ GLB

# Loads a .glb and merges all its meshes (with node transforms) into one ArrayMesh.
func load_glb_mesh(rel : String) -> ArrayMesh:
	if _glb_cache.has(rel): return _glb_cache[rel]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path(rel), state)
	if err != OK:
		push_error("[BRMod] GLB load failed %s: %d" % [rel, err])
		return null
	var scene : Node = doc.generate_scene(state)
	if rel == "assets/pill_jar.glb":
		var cap := scene.find_child("Plane", true, false) as Node3D
		if cap: cap.position.y = 0.44
	var out := ArrayMesh.new()
	_collect(scene, Transform3D(), out)
	scene.free()
	print("[BRMod] GLB %s: %d surfaces, aabb %s" % [rel, out.get_surface_count(), out.get_aabb()])
	_glb_cache[rel] = out
	return out

func _collect(n : Node, parent_xf : Transform3D, out : ArrayMesh) -> void:
	var xf := parent_xf
	if n is Node3D: xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var m : Mesh = mi.mesh
		for i in m.get_surface_count():
			var mt : Material = mi.get_surface_override_material(i)
			if mt == null: mt = m.surface_get_material(i)
			add_arrays(out, m.surface_get_arrays(i), xf, mt)
	for c in n.get_children():
		_collect(c, xf, out)

# ------------------------------------------------------------------ textures

# Loads a user texture and nudges it towards the game's grimy look.
func card_texture(rel : String) -> Texture2D:
	if _tex.has(rel): return _tex[rel]
	var img := Image.load_from_file(path(rel))
	if img == null:
		push_error("[BRMod] texture load failed " + rel)
		return null
	img.convert(Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.01: continue
			var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			var sep := Color(lum * 1.07, lum * 0.95, lum * 0.78)
			var o := c.lerp(sep, 0.18) * 0.86
			var grain := rng.randf_range(-0.035, 0.035)
			img.set_pixel(x, y, Color(clamp(o.r + grain, 0, 1), clamp(o.g + grain, 0, 1), clamp(o.b + grain, 0, 1), c.a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[rel] = t
	return t

# ------------------------------------------------------------------ item meshes

func get_mesh(id : int, ref : AABB) -> ArrayMesh:
	if _meshes.has(id): return _meshes[id]
	var m : ArrayMesh = null
	match id:
		core.ID_UNO_RED: m = _card("assets/uno_red.webp", ref)
		core.ID_UNO_YELLOW: m = _card("assets/uno_yellow.webp", ref)
		core.ID_PLUS4: m = _card("assets/uno_plus4.webp", ref)
		core.ID_TOTEM: m = _glb_item("assets/totem.glb", ref, ref.size.x * 0.85, 2.4) # lies flat, like a card
		core.ID_WHISKEY: m = _glb_item("assets/whiskey.glb", ref, 1.0, 2.6)
		core.ID_SHOT: m = _glb_item("assets/whiskey_shot.glb", ref, 1.1, 1.2)
		core.ID_NUKE: m = _nuke(ref)
		core.ID_SMOKE: m = _smoke(ref)
		core.ID_STORM: m = _storm(ref)
		core.ID_BARRELS: m = _barrels(ref)
		core.ID_BLINDFOLD: m = _blindfold(ref)
		core.ID_HEADPHONES: m = _headphones(ref)
		core.ID_TAPE: m = _tape(ref)
		core.ID_ADRENALINE_ZERO: m = _adrenaline_zero(ref)
		core.ID_PILL_JAR: m = _pill_jar(ref)
	if m == null:
		m = ArrayMesh.new()
		add_prim(m, BoxMesh.new(), Transform3D(Basis(), ref.get_center()), mat(Color.MAGENTA))
	_meshes[id] = m
	return m

func _adrenaline_zero(ref : AABB) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var metal := mat(Color(0.64, 0.67, 0.72), 0.45, 0.35)
	add_prim(mesh, _cyl(0.44, 0.44, 1.82), Transform3D(Basis(), Vector3(0, 0.98, 0)), metal)
	add_prim(mesh, _cyl(0.37, 0.44, 0.12), Transform3D(Basis(), Vector3(0, 1.95, 0)), metal)
	var rim := mat(Color(0.28, 0.31, 0.36), 0.5, 0.4)
	add_prim(mesh, _cyl(0.39, 0.39, 0.06), Transform3D(Basis(), Vector3(0, 2.04, 0)), rim)
	add_prim(mesh, _cyl(0.42, 0.39, 0.08), Transform3D(Basis(), Vector3(0, 0.04, 0)), rim)
	_wrap_label(mesh, "assets/adrenaline_zero.png", 0.445, 0.1, 1.89)
	return fit_mesh(mesh, ref, 1.0, 2.05)

func _pill_jar(ref : AABB) -> ArrayMesh:
	var mesh := load_glb_mesh("assets/pill_jar.glb")
	if mesh == null: return null
	var glass := mat(Color(0.10, 0.42, 0.74, 0.50), 0.1, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_prim(mesh, _cyl(0.36, 0.36, 0.39), Transform3D(Basis(), Vector3(0, 0.195, 0)), glass)
	add_prim(mesh, _cyl(0.26, 0.36, 0.10), Transform3D(Basis(), Vector3(0, 0.44, 0)), glass)
	_wrap_label(mesh, "assets/pill_jar_label.png", 0.365, 0.075, 0.36)
	return fit_mesh(mesh, ref, 1.15, 1.4)

func _wrap_label(mesh : ArrayMesh, rel : String, radius : float, bottom : float, top : float) -> void:
	var image := Image.load_from_file(path(rel))
	if image == null: return
	image.generate_mipmaps()
	var label := mat(Color.WHITE, 0.0, 0.62, 0.0, ImageTexture.create_from_image(image))
	label.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 32:
		for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var angle : float = TAU * (i + corner.x) / 32.0
			var normal := Vector3(cos(angle), 0.0, sin(angle))
			surface.set_normal(normal)
			surface.set_uv(Vector2((i + corner.x) / 16.0, 1.0 - corner.y))
			surface.add_vertex(normal * radius + Vector3(0, top if corner.y else bottom, 0))
	surface.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, label)

func _glb_item(rel : String, ref : AABB, w : float, h : float, extra := Transform3D()) -> ArrayMesh:
	var src := load_glb_mesh(rel)
	if src == null: return null
	if rel.ends_with("whiskey_shot.glb"): _fix_shot_materials(src)
	if rel.ends_with("whiskey.glb"): _fix_bottle_materials(src)
	return fit_mesh(src, ref, w, h, extra)

func _fix_shot_materials(m : ArrayMesh) -> void:
	for i in m.get_surface_count():
		var mt := m.surface_get_material(i)
		var n := mt.resource_name if mt else ""
		var sm := StandardMaterial3D.new()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if n.findn("ice") != -1:
			sm.albedo_color = Color(0.85, 0.95, 1.0, 0.55); sm.roughness = 0.15
		elif n.findn("liquid") != -1:
			sm.albedo_color = Color(0.75, 0.38, 0.06, 0.85); sm.roughness = 0.1
			sm.emission_enabled = true; sm.emission = Color(0.6, 0.28, 0.02); sm.emission_energy_multiplier = 0.15
		else:
			sm.albedo_color = Color(0.9, 0.95, 1.0, 0.22); sm.roughness = 0.05; sm.metallic_specular = 0.9
		m.surface_set_material(i, sm)

func _fix_bottle_materials(m : ArrayMesh) -> void:
	for i in m.get_surface_count():
		var mt := m.surface_get_material(i)
		var n := mt.resource_name if mt else ""
		if n.findn("liquid") != -1:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.7, 0.33, 0.05)
			sm.roughness = 0.1
			sm.emission_enabled = true; sm.emission = Color(0.5, 0.2, 0.02); sm.emission_energy_multiplier = 0.1
			m.surface_set_material(i, sm)
		elif n == "Material.003" and mt is StandardMaterial3D:
			var sm2 : StandardMaterial3D = mt.duplicate()
			sm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm2.albedo_color = Color(0.35, 0.12, 0.02, 0.6)
			sm2.roughness = 0.05
			m.surface_set_material(i, sm2)

func _card(rel : String, ref : AABB) -> ArrayMesh:
	var tex := card_texture(rel)
	var am := ArrayMesh.new()
	var w := ref.size.x * 0.78
	var d := w * 1.53
	if tex: d = w * float(tex.get_height()) / float(tex.get_width())
	var floor_y := ref.position.y
	var c := Vector3(ref.get_center().x, floor_y + 0.03, ref.get_center().z)
	var front := mat(Color.WHITE, 0.0, 0.55, 0.0, tex)
	front.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	front.alpha_scissor_threshold = 0.5
	front.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad(am, c, w, d, front, false)
	var back := mat(Color(0.12, 0.1, 0.1), 0.0, 0.7, 0.0, tex)
	back.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	back.alpha_scissor_threshold = 0.5
	back.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad(am, c - Vector3(0, 0.012, 0), w, d, back, true)
	return am

func _quad(am : ArrayMesh, c : Vector3, w : float, d : float, m : Material, down : bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w * 0.5
	var hd := d * 0.5
	var p := [c + Vector3(-hw, 0, -hd), c + Vector3(hw, 0, -hd), c + Vector3(hw, 0, hd), c + Vector3(-hw, 0, hd)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var order := [0, 1, 2, 0, 2, 3] if !down else [0, 2, 1, 0, 3, 2]
	for idx in order:
		st.set_normal(Vector3.DOWN if down else Vector3.UP)
		st.set_uv(uv[idx])
		st.add_vertex(p[idx])
	st.commit(am)
	am.surface_set_material(am.get_surface_count() - 1, m)

func _floor_xf(ref : AABB, s : float, off : Vector3, basis := Basis()) -> Transform3D:
	var c := ref.get_center()
	return Transform3D(basis, Vector3(c.x + off.x * s, ref.position.y + off.y * s, c.z + off.z * s))

func _scaled(prim : PrimitiveMesh, s : float) -> PrimitiveMesh:
	if prim is BoxMesh: prim.size *= s
	elif prim is CylinderMesh:
		prim.top_radius *= s; prim.bottom_radius *= s; prim.height *= s
	elif prim is SphereMesh:
		prim.radius *= s; prim.height *= s
	elif prim is TorusMesh:
		prim.inner_radius *= s; prim.outer_radius *= s
	elif prim is PrismMesh: prim.size *= s
	return prim

func _cyl(top : float, bottom : float, h : float, seg := 20) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = top; c.bottom_radius = bottom; c.height = h; c.radial_segments = seg
	return c

func _sph(r : float, h : float) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = r; s.height = h; s.radial_segments = 16; s.rings = 8
	return s

func _box(x : float, y : float, z : float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z)
	return b

func _tor(inner : float, outer : float) -> TorusMesh:
	var t := TorusMesh.new(); t.inner_radius = inner; t.outer_radius = outer; t.rings = 24; t.ring_segments = 10
	return t

func _nuke(ref : AABB) -> ArrayMesh:
	var am := ArrayMesh.new()
	var s : float = ref.size.x / 2.0
	var fire := mat(Color(1.0, 0.45, 0.1), 0.0, 0.8, 1.2)
	var ash := mat(Color(0.45, 0.4, 0.36), 0.0, 0.9, 0.05)
	var hot := mat(Color(1.0, 0.8, 0.3), 0.0, 0.7, 2.0)
	add_prim(am, _scaled(_cyl(0.75, 0.85, 0.15), s), _floor_xf(ref, s, Vector3(0, 0.075, 0)), ash)
	add_prim(am, _scaled(_cyl(0.18, 0.32, 1.1), s), _floor_xf(ref, s, Vector3(0, 0.7, 0)), fire)
	add_prim(am, _scaled(_tor(0.18, 0.42), s), _floor_xf(ref, s, Vector3(0, 0.75, 0), Basis.from_scale(Vector3(1, 0.5, 1))), ash)
	add_prim(am, _scaled(_sph(0.62, 0.7), s), _floor_xf(ref, s, Vector3(0, 1.45, 0)), fire)
	add_prim(am, _scaled(_sph(0.5, 0.45), s), _floor_xf(ref, s, Vector3(0, 1.72, 0)), ash)
	add_prim(am, _scaled(_tor(0.4, 0.7), s), _floor_xf(ref, s, Vector3(0, 1.3, 0), Basis.from_scale(Vector3(1, 0.6, 1))), hot)
	return am

func _smoke(ref : AABB) -> ArrayMesh:
	var am := ArrayMesh.new()
	var s : float = ref.size.x / 2.0
	var body := mat(Color(0.24, 0.3, 0.2), 0.3, 0.6)
	var metal := mat(Color(0.55, 0.55, 0.55), 0.8, 0.35)
	var band := mat(Color(0.85, 0.85, 0.8), 0.0, 0.7, 0.1)
	add_prim(am, _scaled(_cyl(0.36, 0.36, 1.2), s), _floor_xf(ref, s, Vector3(0, 0.6, 0)), body)
	add_prim(am, _scaled(_cyl(0.37, 0.37, 0.2), s), _floor_xf(ref, s, Vector3(0, 0.75, 0)), band)
	add_prim(am, _scaled(_cyl(0.22, 0.3, 0.22), s), _floor_xf(ref, s, Vector3(0, 1.31, 0)), metal)
	add_prim(am, _scaled(_box(0.12, 0.5, 0.14), s), _floor_xf(ref, s, Vector3(0.28, 1.1, 0)), metal)
	add_prim(am, _scaled(_tor(0.08, 0.14), s), _floor_xf(ref, s, Vector3(-0.2, 1.48, 0), Basis(Vector3.RIGHT, PI / 2)), metal)
	return am

func _storm(ref : AABB) -> ArrayMesh:
	var am := ArrayMesh.new()
	var s : float = ref.size.x / 2.0
	var cloud := mat(Color(0.32, 0.33, 0.38), 0.0, 1.0, 0.05)
	var bolt := mat(Color(1.0, 0.9, 0.3), 0.0, 0.5, 2.5)
	var base := mat(Color(0.2, 0.2, 0.22), 0.6, 0.5)
	add_prim(am, _scaled(_cyl(0.5, 0.55, 0.12), s), _floor_xf(ref, s, Vector3(0, 0.06, 0)), base)
	add_prim(am, _scaled(_box(0.12, 0.28, 0.06), s), _floor_xf(ref, s, Vector3(0.05, 0.3, 0), Basis(Vector3.BACK, 0.4)), bolt)
	add_prim(am, _scaled(_box(0.1, 0.32, 0.06), s), _floor_xf(ref, s, Vector3(-0.02, 0.55, 0), Basis(Vector3.BACK, -0.5)), bolt)
	add_prim(am, _scaled(_box(0.08, 0.6, 0.08), s), _floor_xf(ref, s, Vector3(0.0, 0.42, -0.25)), base)
	for p in [[Vector3(0, 1.05, 0), 0.5], [Vector3(-0.42, 0.95, 0.05), 0.38], [Vector3(0.42, 0.95, -0.05), 0.4], [Vector3(0.15, 1.25, 0.1), 0.36], [Vector3(-0.2, 1.2, -0.12), 0.34]]:
		add_prim(am, _scaled(_sph(p[1], p[1] * 1.6), s), _floor_xf(ref, s, p[0]), cloud)
	return am

func _barrels(ref : AABB) -> ArrayMesh:
	var src := barrel_segment_mesh()
	var am := ArrayMesh.new()
	if src == null:
		var s : float = ref.size.x / 2.0
		var m := mat(Color(0.2, 0.2, 0.22), 0.8, 0.35)
		for x in [-0.25, 0.25]:
			add_prim(am, _scaled(_cyl(0.11, 0.11, 1.8), s), _floor_xf(ref, s, Vector3(x, 0.12, 0), Basis(Vector3.BACK, PI / 2)), m)
		return am
	# lay the two barrel pieces side by side along their longest axis
	var a := src.get_aabb()
	var long_axis := 0
	if a.size.y > a.size[long_axis]: long_axis = 1
	if a.size.z > a.size[long_axis]: long_axis = 2
	var rot := Basis()
	if long_axis == 1: rot = Basis(Vector3.BACK, PI / 2)
	elif long_axis == 2: rot = Basis(Vector3.UP, PI / 2)
	var thick : float = min(a.size[(long_axis + 1) % 3], a.size[(long_axis + 2) % 3])
	var tmp := ArrayMesh.new()
	for k in 2:
		var xf := Transform3D(rot, Vector3(0, 0, (k - 0.5) * thick * 1.15))
		for i in src.get_surface_count():
			add_arrays(tmp, src.surface_get_arrays(i), xf, src.surface_get_material(i))
	return fit_mesh(tmp, ref, ref.size.x * 1.05, 0.8)

var _barrel_src : ArrayMesh = null
func barrel_segment_mesh() -> ArrayMesh:
	if _barrel_src: return _barrel_src
	var inter = core.inter()
	if inter == null: return null
	var g = inter.globalparent_shotgun_cut_segment_mesh
	if g is MeshInstance3D and g.mesh:
		var am := ArrayMesh.new()
		var m : Mesh = g.mesh
		for i in m.get_surface_count():
			var mt : Material = g.get_surface_override_material(i)
			if mt == null: mt = m.surface_get_material(i)
			if mt == null: mt = g.material_override
			add_arrays(am, m.surface_get_arrays(i), Transform3D(), mt)
		_barrel_src = am
	return _barrel_src

func _blindfold(ref : AABB) -> ArrayMesh:
	var am := ArrayMesh.new()
	var s : float = ref.size.x / 2.0
	var cloth := mat(Color(0.08, 0.08, 0.09), 0.0, 0.95)
	add_prim(am, _scaled(_tor(0.5, 0.72), s), _floor_xf(ref, s, Vector3(0, 0.05, 0), Basis.from_scale(Vector3(1, 0.35, 0.8))), cloth)
	add_prim(am, _scaled(_box(0.16, 0.06, 0.55), s), _floor_xf(ref, s, Vector3(0.85, 0.03, 0.15), Basis(Vector3.UP, 0.4)), cloth)
	add_prim(am, _scaled(_box(0.16, 0.06, 0.5), s), _floor_xf(ref, s, Vector3(0.9, 0.03, -0.2), Basis(Vector3.UP, -0.3)), cloth)
	return am

func blindfold_band(radius : float) -> ArrayMesh:
	var am := ArrayMesh.new()
	var cloth := mat(Color(0.06, 0.06, 0.07), 0.0, 0.95)
	add_prim(am, _tor(radius * 0.97, radius * 1.12), Transform3D(Basis.from_scale(Vector3(1, 2.2, 1)), Vector3.ZERO), cloth)
	return am

func _headphones(ref : AABB) -> ArrayMesh:
	var am := ArrayMesh.new()
	var s : float = ref.size.x / 2.0
	var plastic := mat(Color(0.1, 0.1, 0.11), 0.2, 0.4)
	var pad := mat(Color(0.5, 0.12, 0.1), 0.0, 0.8)
	_arc(am, ref, s, 0.62, 0.95, plastic)
	for x in [-0.62, 0.62]:
		add_prim(am, _scaled(_cyl(0.3, 0.3, 0.2), s), _floor_xf(ref, s, Vector3(x, 0.32, 0), Basis(Vector3.BACK, PI / 2)), plastic)
		add_prim(am, _scaled(_cyl(0.24, 0.24, 0.06), s), _floor_xf(ref, s, Vector3(x * 0.82, 0.32, 0), Basis(Vector3.BACK, PI / 2)), pad)
	return am

func _arc(am : ArrayMesh, ref : AABB, s : float, r : float, cy : float, m : Material) -> void:
	for i in 9:
		var a := PI * (0.0 + float(i) / 8.0)
		var p := Vector3(cos(a) * r, cy - 0.32 + sin(a) * r * 0.9, 0)
		add_prim(am, _scaled(_box(0.16, 0.12, 0.14), s), _floor_xf(ref, s, p, Basis(Vector3.BACK, a + PI / 2)), m)

func headphones_head(radius : float) -> ArrayMesh:
	var am := ArrayMesh.new()
	var plastic := mat(Color(0.1, 0.1, 0.11), 0.2, 0.4)
	var pad := mat(Color(0.5, 0.12, 0.1), 0.0, 0.8)
	for i in 11:
		var a := PI * float(i) / 10.0
		add_prim(am, _box(radius * 0.16, radius * 0.1, radius * 0.22), Transform3D(Basis(Vector3.BACK, a + PI / 2), Vector3(cos(a) * radius * 1.08, sin(a) * radius * 1.1, 0)), plastic)
	for x in [-1.0, 1.0]:
		add_prim(am, _cyl(radius * 0.38, radius * 0.38, radius * 0.25), Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(x * radius * 1.08, 0, 0)), plastic)
		add_prim(am, _cyl(radius * 0.3, radius * 0.3, radius * 0.08), Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(x * radius * 0.95, 0, 0)), pad)
	return am

func _tape(ref : AABB) -> ArrayMesh:
	var am := ArrayMesh.new()
	var s : float = ref.size.x / 2.0
	var blue := mat(Color(0.12, 0.3, 0.85), 0.1, 0.35, 0.08)
	var card := mat(Color(0.55, 0.42, 0.28), 0.0, 0.9)
	var dark := mat(Color(0.05, 0.05, 0.05), 0.0, 1.0)
	add_prim(am, _scaled(_cyl(0.62, 0.62, 0.42), s), _floor_xf(ref, s, Vector3(0, 0.21, 0)), blue)
	add_prim(am, _scaled(_cyl(0.36, 0.36, 0.44), s), _floor_xf(ref, s, Vector3(0, 0.215, 0)), card)
	add_prim(am, _scaled(_cyl(0.3, 0.3, 0.46), s), _floor_xf(ref, s, Vector3(0, 0.22, 0)), dark)
	add_prim(am, _scaled(_box(0.6, 0.01, 0.42), s), _floor_xf(ref, s, Vector3(0.75, 0.005, 0.3)), blue)
	return am

# ------------------------------------------------------------------ tail (easter egg)

func tail_node() -> MeshInstance3D:
	var src := load_glb_mesh("assets/tail.glb")
	if src == null: return null
	var mi := MeshInstance3D.new()
	mi.name = "brmod_tail"
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float amp = 0.16;
uniform float speed = 3.2;
uniform float tail_len = 1.2;
void vertex() {
	float t = clamp((-VERTEX.z - 0.04) / tail_len, 0.0, 1.0);
	float w = sin(TIME * speed - t * 2.6);
	VERTEX.x += w * amp * t * t;
	VERTEX.y += sin(TIME * speed * 0.5 + t) * 0.04 * t;
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * 0.9;
	ROUGHNESS = 0.7;
}
"""
	var am := ArrayMesh.new()
	for i in src.get_surface_count():
		var sm := ShaderMaterial.new()
		sm.shader = shader
		var orig := src.surface_get_material(i)
		if orig is StandardMaterial3D and orig.albedo_texture:
			sm.set_shader_parameter("tex", orig.albedo_texture)
		add_arrays(am, src.surface_get_arrays(i), Transform3D(), sm)
	mi.mesh = am
	return mi

# ------------------------------------------------------------------ sounds

func sound(key : String) -> AudioStream:
	if _sounds.has(key): return _sounds[key]
	var s : AudioStream = null
	# a user-supplied file wins: BRMod/sounds/custom_<key>.wav
	for f in ["sounds/custom_%s.wav" % key, "sounds/%s.wav" % key]:
		if FileAccess.file_exists(path(f)):
			s = load_wav(path(f))
			if s: break
	if s == null:
		var game := {
			"uno_use": "res://audio/health counter confirmation.ogg",
			"pills": "res://audio/player use medicine.ogg",
			"pills_bad": "res://audio/player death medicine.ogg",
			"drink": "res://audio/player use beer.ogg",
			"live": "res://audio/temp gunshot_live.wav",
		}
		if game.has(key) and ResourceLoader.exists(game[key]): s = load(game[key])
	_sounds[key] = s
	return s

func load_wav(p : String) -> AudioStreamWAV:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return null
	var b := f.get_buffer(f.get_length())
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF": return null
	var pos := 12
	var channels := 1
	var rate := 22050
	var bits := 16
	var data := PackedByteArray()
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		if id == "fmt ":
			channels = b.decode_u16(pos + 10)
			rate = b.decode_u32(pos + 12)
			bits = b.decode_u16(pos + 22)
		elif id == "data":
			data = b.slice(pos + 8, pos + 8 + size)
		pos += 8 + size + (size % 2)
	if bits != 16 and bits != 8: return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = rate
	w.stereo = channels == 2
	w.data = data
	return w
