extends Node3D

const DINO_HOME_POS := Vector3(18.0, 0.0, -18.0)
const DINO_HOME_CLEAR_RADIUS := 7.5
const POND_CLEAR_RADIUS := 4.8

@export var grass_blade_count := 9200
@export var grass_accent_count := 3600
@export var grass_radius := 36.0
@export var rock_count := 42
@export var rock_radius := 34.0
@export var tree_count := 26
@export var tree_radius := 32.0
@export var flower_cluster_count := 32
@export var flower_radius := 30.0
@export var bench_count := 4
@export var bench_radius := 16.0
@export var lamppost_count := 7
@export var lamppost_radius := 22.0
@export var land_mound_count := 12
@export var land_mound_radius := 35.0
@export var city_block_count := 14
@export var particle_amount := 80

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_build_city_core()
	_build_grass()
	_build_path()
	_build_dino_home_path()
	_build_pond()
	_build_land_mounds()
	_build_rocks()
	_build_trees()
	_build_flowers()
	_build_benches()
	_build_lampposts()
	_build_dino_home()
	_build_fireflies()
	_build_digital_particles()


# ---------------------------------------------------------------------------
# Grass — two MultiMesh layers for depth and colour variation
# ---------------------------------------------------------------------------

func _build_grass() -> void:
	var main_mat := StandardMaterial3D.new()
	main_mat.albedo_color = Color(0.24, 0.56, 0.20, 1.0)
	main_mat.roughness = 0.78
	main_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	main_mat.rim_enabled = true
	main_mat.rim = 0.36
	main_mat.rim_tint = 0.58
	main_mat.emission_enabled = true
	main_mat.emission = Color(0.18, 0.42, 0.20, 1.0)
	main_mat.emission_energy_multiplier = 0.04

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.14, 0.40, 0.12, 1.0)
	accent_mat.roughness = 0.82
	accent_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	accent_mat.rim_enabled = true
	accent_mat.rim = 0.28
	accent_mat.rim_tint = 0.55

	_spawn_grass_layer(grass_blade_count, main_mat, Vector3(0.08, 0.36, 0.015))
	_spawn_grass_layer(grass_accent_count, accent_mat, Vector3(0.06, 0.26, 0.012))


func _spawn_grass_layer(count: int, material: StandardMaterial3D, blade_size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = blade_size

	var xforms: Array[Transform3D] = []
	for _i in range(count):
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * grass_radius
		var x := cos(angle) * dist
		var z := sin(angle) * dist
		if _is_reserved_space(Vector3(x, 0.0, z), 0.4):
			continue

		var height_scale := rng.randf_range(0.55, 1.5)
		var yaw := rng.randf() * TAU
		var lean := rng.randf_range(-0.18, 0.18)

		var basis := Basis(Vector3.UP, yaw)
		basis = basis.rotated(basis.x, lean)
		basis = basis.scaled(Vector3(1.0, height_scale, 1.0))

		var y_pos := blade_size.y * 0.5 * height_scale
		xforms.append(Transform3D(basis, Vector3(x, y_pos, z)))

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = xforms.size()
	for i in range(xforms.size()):
		multimesh.set_instance_transform(i, xforms[i])

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _make_path_material(base_color: Color) -> StandardMaterial3D:
	var path_mat := StandardMaterial3D.new()
	path_mat.albedo_color = base_color
	path_mat.roughness = 0.87
	path_mat.metallic_specular = 0.22
	path_mat.uv1_scale = Vector3(4.0, 24.0, 1.0)

	var path_noise := FastNoiseLite.new()
	path_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	path_noise.frequency = 0.38
	var path_noise_tex := NoiseTexture2D.new()
	path_noise_tex.width = 256
	path_noise_tex.height = 256
	path_noise_tex.seamless = true
	path_noise_tex.noise = path_noise
	path_mat.roughness_texture = path_noise_tex
	path_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return path_mat


# ---------------------------------------------------------------------------
# City core - obvious urban shapes around spawn
# ---------------------------------------------------------------------------

func _build_city_core() -> void:
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.15, 0.16, 0.18, 1.0)
	road_mat.roughness = 0.9
	road_mat.metallic_specular = 0.15

	var road_long := MeshInstance3D.new()
	var road_long_mesh := PlaneMesh.new()
	road_long_mesh.size = Vector2(10.0, 80.0)
	road_long_mesh.material = road_mat
	road_long.mesh = road_long_mesh
	road_long.position = Vector3(0.0, 0.02, 0.0)
	road_long.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road_long)

	var road_cross := MeshInstance3D.new()
	var road_cross_mesh := PlaneMesh.new()
	road_cross_mesh.size = Vector2(80.0, 10.0)
	road_cross_mesh.material = road_mat
	road_cross.mesh = road_cross_mesh
	road_cross.position = Vector3(0.0, 0.02, 0.0)
	road_cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road_cross)

	var building_palette: Array[Color] = [
		Color(0.46, 0.47, 0.52, 1.0),
		Color(0.54, 0.52, 0.48, 1.0),
		Color(0.36, 0.40, 0.46, 1.0),
		Color(0.49, 0.43, 0.38, 1.0),
	]

	for _i in range(city_block_count):
		for _attempt in range(10):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(12.0, 30.0)
			var x := cos(angle) * dist
			var z := sin(angle) * dist

			# Keep roads relatively clear so movement still feels readable.
			if absf(x) < 6.5 or absf(z) < 6.5:
				continue
			if _is_reserved_space(Vector3(x, 0.0, z), 2.6):
				continue

			var width := rng.randf_range(3.0, 7.0)
			var depth := rng.randf_range(3.0, 7.0)
			var height := rng.randf_range(4.0, 16.0)

			var bmesh := BoxMesh.new()
			bmesh.size = Vector3(width, height, depth)

			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = building_palette[rng.randi() % building_palette.size()]
			bmat.roughness = rng.randf_range(0.72, 0.9)
			bmat.metallic_specular = rng.randf_range(0.16, 0.28)
			bmat.clearcoat_enabled = true
			bmat.clearcoat = 0.08
			bmat.clearcoat_roughness = 0.85

			var building := MeshInstance3D.new()
			building.mesh = bmesh
			building.set_surface_override_material(0, bmat)
			building.position = Vector3(x, height * 0.5, z)
			add_child(building)
			break


# ---------------------------------------------------------------------------
# Dirt path — a simple dark strip through the centre of the park
# ---------------------------------------------------------------------------

func _build_path() -> void:
	var path_mat := _make_path_material(Color(0.47, 0.39, 0.27, 1.0))

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.8, 44.0)
	mesh.material = path_mat

	var path_node := MeshInstance3D.new()
	path_node.mesh = mesh
	path_node.position = Vector3(0.0, 0.006, 0.0)
	path_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(path_node)

	var cross_mesh := PlaneMesh.new()
	cross_mesh.size = Vector2(28.0, 2.4)
	cross_mesh.material = path_mat

	var cross := MeshInstance3D.new()
	cross.mesh = cross_mesh
	cross.position = Vector3(0.0, 0.006, 0.0)
	cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cross)


func _build_dino_home_path() -> void:
	var path_mat := _make_path_material(Color(0.5, 0.42, 0.31, 1.0))

	var branch_mesh := PlaneMesh.new()
	branch_mesh.size = Vector2(2.1, 16.0)
	branch_mesh.material = path_mat

	var branch := MeshInstance3D.new()
	branch.mesh = branch_mesh
	branch.position = Vector3(9.0, 0.007, -9.0)
	branch.rotation.y = deg_to_rad(45.0)
	branch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(branch)

	var approach_mesh := PlaneMesh.new()
	approach_mesh.size = Vector2(3.2, 7.5)
	approach_mesh.material = path_mat

	var approach := MeshInstance3D.new()
	approach.mesh = approach_mesh
	approach.position = DINO_HOME_POS + Vector3(-1.2, 0.007, 4.0)
	approach.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(approach)


# ---------------------------------------------------------------------------
# Pond — a small reflective pool, fitting the Greenbelt Parklands theme
# ---------------------------------------------------------------------------

func _build_pond() -> void:
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.12, 0.32, 0.52, 0.72)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.04
	water_mat.metallic = 0.65
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.08, 0.22, 0.38, 1.0)
	water_mat.emission_energy_multiplier = 0.18

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(7.0, 5.0)
	mesh.material = water_mat

	var pond := MeshInstance3D.new()
	pond.mesh = mesh
	pond.position = Vector3(14.0, 0.012, -9.0)
	pond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pond.add_to_group("dino_poi_pond")
	add_child(pond)

	_build_pond_rocks(pond.position)


func _build_land_mounds() -> void:
	var mound_mat := StandardMaterial3D.new()
	mound_mat.albedo_color = Color(0.22, 0.47, 0.17, 1.0)
	mound_mat.roughness = 0.86
	mound_mat.metallic_specular = 0.2
	mound_mat.rim_enabled = true
	mound_mat.rim = 0.2
	mound_mat.rim_tint = 0.35

	for _i in range(land_mound_count):
		var placed := false
		for _attempt in range(10):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(15.0, land_mound_radius)
			var x := cos(angle) * dist
			var z := sin(angle) * dist
			var pos := Vector3(x, -0.28, z)

			# Keep the central park crossroads and Dino POIs readable.
			if absf(x) < 4.0 and absf(z) < 24.0:
				continue
			if absf(z) < 3.0 and absf(x) < 15.0:
				continue
			if _is_reserved_space(pos, 3.6):
				continue

			var mound := MeshInstance3D.new()
			var mound_mesh := SphereMesh.new()
			mound_mesh.radius = 1.0
			mound_mesh.height = 2.0
			mound_mesh.radial_segments = 12
			mound_mesh.rings = 7
			mound.mesh = mound_mesh
			mound.set_surface_override_material(0, mound_mat)
			mound.scale = Vector3(
				rng.randf_range(2.8, 6.8),
				rng.randf_range(0.22, 0.6),
				rng.randf_range(2.8, 6.8)
			)
			mound.position = pos
			add_child(mound)
			placed = true
			break
		if not placed:
			continue


func _build_pond_rocks(centre: Vector3) -> void:
	for _i in range(10):
		var offset_angle := rng.randf() * TAU
		var offset_dist := rng.randf_range(3.0, 4.5)
		var rock := _make_rock_mesh(rng.randf_range(0.15, 0.35))
		rock.position = centre + Vector3(cos(offset_angle) * offset_dist, 0.08, sin(offset_angle) * offset_dist)
		add_child(rock)


# ---------------------------------------------------------------------------
# Rocks
# ---------------------------------------------------------------------------

var _rock_colors: Array[Color] = [
	Color(0.48, 0.44, 0.38, 1.0),
	Color(0.38, 0.36, 0.32, 1.0),
	Color(0.55, 0.50, 0.44, 1.0),
	Color(0.33, 0.34, 0.30, 1.0),
	Color(0.30, 0.38, 0.28, 1.0),
]


func _build_rocks() -> void:
	for _i in range(rock_count):
		for _attempt in range(8):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(4.0, rock_radius)
			var scale_f := rng.randf_range(0.25, 1.1)
			var pos := Vector3(cos(angle) * dist, scale_f * 0.18, sin(angle) * dist)
			if _is_reserved_space(pos, 1.1):
				continue
			var rock := _make_rock_mesh(scale_f)
			rock.position = pos
			rock.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
			add_child(rock)
			break


func _make_rock_mesh(scale_f: float) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = rng.randf_range(0.45, 0.85)
	sphere.radial_segments = rng.randi_range(5, 9)
	sphere.rings = rng.randi_range(3, 6)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _rock_colors[rng.randi() % _rock_colors.size()]
	mat.roughness = rng.randf_range(0.82, 0.96)

	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.set_surface_override_material(0, mat)
	mesh.scale = Vector3(scale_f, scale_f * rng.randf_range(0.55, 1.0), scale_f)
	return mesh


# ---------------------------------------------------------------------------
# Trees — cylinder trunk + sphere canopy
# ---------------------------------------------------------------------------

func _build_trees() -> void:
	for _i in range(tree_count):
		for _attempt in range(10):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(8.0, tree_radius)
			var x := cos(angle) * dist
			var z := sin(angle) * dist
			var pos := Vector3(x, 0.0, z)
			if _is_reserved_space(pos, 2.8):
				continue

			var tree := Node3D.new()
			tree.position = pos

			var trunk_height := rng.randf_range(2.0, 3.8)
			var canopy_r := rng.randf_range(1.2, 2.6)

			var trunk_mesh := CylinderMesh.new()
			trunk_mesh.top_radius = rng.randf_range(0.08, 0.14)
			trunk_mesh.bottom_radius = rng.randf_range(0.16, 0.26)
			trunk_mesh.height = trunk_height
			trunk_mesh.radial_segments = 8

			var trunk_mat := StandardMaterial3D.new()
			trunk_mat.albedo_color = Color(
				rng.randf_range(0.3, 0.4),
				rng.randf_range(0.22, 0.3),
				rng.randf_range(0.12, 0.2),
				1.0
			)
			trunk_mat.roughness = 0.88
			trunk_mat.rim_enabled = true
			trunk_mat.rim = 0.35
			trunk_mat.rim_tint = 0.6

			var trunk := MeshInstance3D.new()
			trunk.mesh = trunk_mesh
			trunk.set_surface_override_material(0, trunk_mat)
			trunk.position = Vector3(0.0, trunk_height * 0.5, 0.0)
			tree.add_child(trunk)

			var canopy_mat := StandardMaterial3D.new()
			canopy_mat.albedo_color = Color(
				rng.randf_range(0.12, 0.22),
				rng.randf_range(0.42, 0.58),
				rng.randf_range(0.1, 0.2),
				1.0
			)
			canopy_mat.roughness = 0.65
			canopy_mat.rim_enabled = true
			canopy_mat.rim = 0.55
			canopy_mat.rim_tint = 0.8
			canopy_mat.clearcoat_enabled = true
			canopy_mat.clearcoat = 0.15
			canopy_mat.clearcoat_roughness = 0.6

			# Cluster canopy — multiple overlapping spheres for a fuller silhouette.
			var cluster_count := rng.randi_range(4, 6)
			var main_y := trunk_height + canopy_r * 0.4
			_add_canopy_blob(tree, canopy_mat, Vector3(0.0, main_y, 0.0), canopy_r)
			for _c in range(cluster_count):
				var local_off := Vector3(
					rng.randf_range(-canopy_r * 0.75, canopy_r * 0.75),
					rng.randf_range(-canopy_r * 0.35, canopy_r * 0.55),
					rng.randf_range(-canopy_r * 0.75, canopy_r * 0.75)
				)
				var sub_r := canopy_r * rng.randf_range(0.55, 0.85)
				_add_canopy_blob(tree, canopy_mat, Vector3(0.0, main_y, 0.0) + local_off, sub_r)

			tree.add_to_group("dino_poi_tree")
			add_child(tree)
			break


func _add_canopy_blob(parent: Node3D, mat: StandardMaterial3D, pos: Vector3, r: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * rng.randf_range(1.3, 1.8)
	mesh.radial_segments = 14
	mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	parent.add_child(mi)


# ---------------------------------------------------------------------------
# Flower clusters — small colourful spheres
# ---------------------------------------------------------------------------

var _flower_palette: Array[Color] = [
	Color(0.95, 0.30, 0.35, 1.0),
	Color(0.95, 0.85, 0.22, 1.0),
	Color(0.60, 0.30, 0.92, 1.0),
	Color(0.95, 0.50, 0.75, 1.0),
	Color(0.30, 0.60, 0.95, 1.0),
	Color(1.0, 0.65, 0.20, 1.0),
]


func _build_flowers() -> void:
	for _i in range(flower_cluster_count):
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(3.0, flower_radius)
		var cx := cos(angle) * dist
		var cz := sin(angle) * dist
		if _is_reserved_space(Vector3(cx, 0.0, cz), 1.9):
			continue
		var cluster_color := _flower_palette[rng.randi() % _flower_palette.size()]

		for _j in range(rng.randi_range(3, 8)):
			var fx := cx + rng.randf_range(-1.2, 1.2)
			var fz := cz + rng.randf_range(-1.2, 1.2)
			var r := rng.randf_range(0.05, 0.11)

			var sphere := SphereMesh.new()
			sphere.radius = r
			sphere.height = r * 2.0
			sphere.radial_segments = 6
			sphere.rings = 4

			var mat := StandardMaterial3D.new()
			mat.albedo_color = cluster_color
			mat.emission_enabled = true
			mat.emission = cluster_color * 0.35
			mat.emission_energy_multiplier = 0.45

			var flower := MeshInstance3D.new()
			flower.mesh = sphere
			flower.set_surface_override_material(0, mat)
			flower.position = Vector3(fx, r + 0.02, fz)
			flower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(flower)


# ---------------------------------------------------------------------------
# Park benches — simple box assemblies
# ---------------------------------------------------------------------------

func _build_benches() -> void:
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.48, 0.34, 0.20, 1.0)
	wood_mat.roughness = 0.85

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.28, 0.28, 0.30, 1.0)
	metal_mat.roughness = 0.35
	metal_mat.metallic = 0.65

	for _i in range(bench_count):
		var placed := false
		for _attempt in range(8):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(5.0, bench_radius)
			var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			if _is_reserved_space(pos, 2.1):
				continue

			var bench := Node3D.new()
			bench.position = pos
			bench.rotation.y = rng.randf() * TAU

			var seat := MeshInstance3D.new()
			var seat_mesh := BoxMesh.new()
			seat_mesh.size = Vector3(1.4, 0.08, 0.45)
			seat.mesh = seat_mesh
			seat.set_surface_override_material(0, wood_mat)
			seat.position = Vector3(0.0, 0.48, 0.0)
			bench.add_child(seat)

			var back := MeshInstance3D.new()
			var back_mesh := BoxMesh.new()
			back_mesh.size = Vector3(1.4, 0.55, 0.06)
			back.mesh = back_mesh
			back.set_surface_override_material(0, wood_mat)
			back.position = Vector3(0.0, 0.72, -0.2)
			bench.add_child(back)

			for side in [-0.58, 0.58]:
				var leg := MeshInstance3D.new()
				var leg_mesh := BoxMesh.new()
				leg_mesh.size = Vector3(0.06, 0.48, 0.4)
				leg.mesh = leg_mesh
				leg.set_surface_override_material(0, metal_mat)
				leg.position = Vector3(side, 0.24, 0.0)
				bench.add_child(leg)

			add_child(bench)
			placed = true
			break
		if not placed:
			continue


# ---------------------------------------------------------------------------
# Lampposts — warm pools of light (energy driven by park_night_lights.gd)
# ---------------------------------------------------------------------------

func _build_lampposts() -> void:
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.22, 0.22, 0.24, 1.0)
	pole_mat.metallic = 0.55
	pole_mat.roughness = 0.45

	var hood_mat := StandardMaterial3D.new()
	hood_mat.albedo_color = Color(0.18, 0.18, 0.2, 1.0)
	hood_mat.metallic = 0.35
	hood_mat.roughness = 0.5

	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.92, 0.65, 1.0)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.82, 0.45, 1.0)
	bulb_mat.emission_energy_multiplier = 1.4

	for _i in range(lamppost_count):
		var post_placed := false
		for _attempt in range(8):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(6.0, lamppost_radius)
			var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			if _is_reserved_space(pos, 2.0):
				continue

			var post := Node3D.new()
			post.position = pos
			post.rotation.y = rng.randf() * TAU

			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = 0.06
			pole_mesh.bottom_radius = 0.08
			pole_mesh.height = 2.85
			pole_mesh.radial_segments = 8

			var pole := MeshInstance3D.new()
			pole.mesh = pole_mesh
			pole.set_surface_override_material(0, pole_mat)
			pole.position = Vector3(0.0, 1.42, 0.0)
			post.add_child(pole)

			var hood := MeshInstance3D.new()
			var hood_m := CylinderMesh.new()
			hood_m.top_radius = 0.22
			hood_m.bottom_radius = 0.14
			hood_m.height = 0.18
			hood_m.radial_segments = 10
			hood.mesh = hood_m
			hood.set_surface_override_material(0, hood_mat)
			hood.position = Vector3(0.0, 2.78, 0.0)
			post.add_child(hood)

			var bulb := MeshInstance3D.new()
			var bulb_s := SphereMesh.new()
			bulb_s.radius = 0.11
			bulb_s.height = 0.22
			bulb_s.radial_segments = 10
			bulb.mesh = bulb_s
			bulb.set_surface_override_material(0, bulb_mat)
			bulb.position = Vector3(0.0, 2.62, 0.0)
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			post.add_child(bulb)

			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.88, 0.62, 1.0)
			lamp.light_energy = 0.08
			lamp.omni_range = 12.0
			lamp.omni_attenuation = 0.55
			lamp.shadow_enabled = false
			lamp.position = Vector3(0.0, 2.58, 0.0)
			lamp.add_to_group("park_lamppost")
			post.add_child(lamp)

			add_child(post)
			post_placed = true
			break
		if not post_placed:
			continue


func _build_dino_home() -> void:
	var home := Node3D.new()
	home.name = "DinoHome"
	home.position = DINO_HOME_POS
	home.add_to_group("dino_poi_home")
	add_child(home)

	var ground_patch_mat := StandardMaterial3D.new()
	ground_patch_mat.albedo_color = Color(0.3, 0.42, 0.2, 1.0)
	ground_patch_mat.roughness = 0.88
	ground_patch_mat.rim_enabled = true
	ground_patch_mat.rim = 0.3
	ground_patch_mat.rim_tint = 0.6
	var ground_patch_mesh := CylinderMesh.new()
	ground_patch_mesh.top_radius = 7.2
	ground_patch_mesh.bottom_radius = 7.4
	ground_patch_mesh.height = 0.05
	ground_patch_mesh.radial_segments = 48
	var ground_patch := MeshInstance3D.new()
	ground_patch.mesh = ground_patch_mesh
	ground_patch.position = Vector3(0.0, 0.02, 0.0)
	ground_patch.set_surface_override_material(0, ground_patch_mat)
	home.add_child(ground_patch)

	var porch_path_mat := StandardMaterial3D.new()
	porch_path_mat.albedo_color = Color(0.58, 0.5, 0.36, 1.0)
	porch_path_mat.roughness = 0.9
	porch_path_mat.rim_enabled = true
	porch_path_mat.rim = 0.3
	var porch_path_mesh := PlaneMesh.new()
	porch_path_mesh.size = Vector2(2.0, 4.2)
	porch_path_mesh.material = porch_path_mat
	var porch_path := MeshInstance3D.new()
	porch_path.mesh = porch_path_mesh
	porch_path.position = Vector3(0.0, 0.026, 3.4)
	porch_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	home.add_child(porch_path)

	# Stepping stones leading to the porch
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.55, 0.52, 0.48, 1.0)
	stone_mat.roughness = 0.82
	stone_mat.rim_enabled = true
	stone_mat.rim = 0.35
	stone_mat.rim_tint = 0.55
	for step in [2.2, 3.4, 4.6, 5.8]:
		var step_mesh := CylinderMesh.new()
		step_mesh.top_radius = 0.38
		step_mesh.bottom_radius = 0.42
		step_mesh.height = 0.08
		step_mesh.radial_segments = 14
		var step_side := -0.4 if int(step * 10) % 20 < 10 else 0.4
		var stone := MeshInstance3D.new()
		stone.mesh = step_mesh
		stone.position = Vector3(step_side, 0.045, step)
		stone.set_surface_override_material(0, stone_mat)
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		home.add_child(stone)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.86, 0.8, 0.7, 1.0)
	wall_mat.roughness = 0.92
	wall_mat.rim_enabled = true
	wall_mat.rim = 0.35
	wall_mat.rim_tint = 0.7
	wall_mat.clearcoat_enabled = true
	wall_mat.clearcoat = 0.1
	wall_mat.clearcoat_roughness = 0.5

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.38, 0.26, 0.16, 1.0)
	trim_mat.roughness = 0.78
	trim_mat.rim_enabled = true
	trim_mat.rim = 0.4
	trim_mat.rim_tint = 0.6

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.22, 0.3, 0.24, 1.0)
	roof_mat.roughness = 0.85
	roof_mat.rim_enabled = true
	roof_mat.rim = 0.45
	roof_mat.rim_tint = 0.75
	roof_mat.clearcoat_enabled = true
	roof_mat.clearcoat = 0.2
	roof_mat.clearcoat_roughness = 0.55

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(1.0, 0.92, 0.68, 0.78)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(1.0, 0.82, 0.52, 1.0)
	glass_mat.emission_energy_multiplier = 1.8
	glass_mat.metallic = 0.1
	glass_mat.roughness = 0.1

	var rug_mat := StandardMaterial3D.new()
	rug_mat.albedo_color = Color(0.29, 0.62, 0.40, 1.0)
	rug_mat.roughness = 0.98

	var bed_frame_mat := StandardMaterial3D.new()
	bed_frame_mat.albedo_color = Color(0.52, 0.37, 0.24, 1.0)
	bed_frame_mat.roughness = 0.88

	var blanket_mat := StandardMaterial3D.new()
	blanket_mat.albedo_color = Color(0.38, 0.86, 0.56, 1.0)
	blanket_mat.roughness = 0.94

	var pillow_mat := StandardMaterial3D.new()
	pillow_mat.albedo_color = Color(0.90, 0.98, 0.92, 1.0)
	pillow_mat.roughness = 0.95

	var base := _box_mesh_node(Vector3(5.8, 0.35, 5.2), Vector3(0.0, 0.18, 0.0), trim_mat)
	home.add_child(base)
	var floor := _box_mesh_node(Vector3(5.2, 0.10, 4.6), Vector3(0.0, 0.36, 0.0), porch_path_mat)
	home.add_child(floor)

	var back_wall := _box_mesh_node(Vector3(5.2, 2.8, 0.22), Vector3(0.0, 1.75, -2.2), wall_mat)
	home.add_child(back_wall)
	var left_wall := _box_mesh_node(Vector3(0.22, 2.8, 4.6), Vector3(-2.49, 1.75, 0.0), wall_mat)
	home.add_child(left_wall)
	var right_wall := _box_mesh_node(Vector3(0.22, 2.8, 4.6), Vector3(2.49, 1.75, 0.0), wall_mat)
	home.add_child(right_wall)
	var front_left := _box_mesh_node(Vector3(1.7, 2.8, 0.22), Vector3(-1.75, 1.75, 2.2), wall_mat)
	home.add_child(front_left)
	var front_right := _box_mesh_node(Vector3(1.7, 2.8, 0.22), Vector3(1.75, 1.75, 2.2), wall_mat)
	home.add_child(front_right)
	var over_door := _box_mesh_node(Vector3(1.8, 0.8, 0.22), Vector3(0.0, 2.75, 2.2), wall_mat)
	home.add_child(over_door)

	var porch := _box_mesh_node(Vector3(2.6, 0.18, 1.6), Vector3(0.0, 0.26, 3.1), porch_path_mat)
	home.add_child(porch)
	for side in [-0.9, 0.9]:
		home.add_child(_box_mesh_node(Vector3(0.16, 2.2, 0.16), Vector3(side, 1.28, 3.05), trim_mat))

	var roof_left := _box_mesh_node(Vector3(2.85, 0.26, 5.8), Vector3(-1.18, 3.62, 0.0), roof_mat)
	roof_left.rotation.z = deg_to_rad(28.0)
	home.add_child(roof_left)
	var roof_right := _box_mesh_node(Vector3(2.85, 0.26, 5.8), Vector3(1.18, 3.62, 0.0), roof_mat)
	roof_right.rotation.z = deg_to_rad(-28.0)
	home.add_child(roof_right)
	var roof_cap := _box_mesh_node(Vector3(0.30, 0.20, 5.85), Vector3(0.0, 4.24, 0.0), trim_mat)
	home.add_child(roof_cap)

	var chimney := _box_mesh_node(Vector3(0.58, 1.6, 0.58), Vector3(1.55, 4.2, -1.15), trim_mat)
	home.add_child(chimney)

	home.add_child(_box_mesh_node(Vector3(1.0, 1.0, 0.08), Vector3(-1.5, 1.95, 2.12), glass_mat))
	home.add_child(_box_mesh_node(Vector3(1.0, 1.0, 0.08), Vector3(1.5, 1.95, 2.12), glass_mat))
	home.add_child(_box_mesh_node(Vector3(0.08, 1.0, 1.1), Vector3(-2.42, 1.95, -0.8), glass_mat))
	home.add_child(_box_mesh_node(Vector3(0.08, 1.0, 1.1), Vector3(2.42, 1.95, -0.8), glass_mat))

	var sign := Label3D.new()
	sign.text = "Dino Home"
	sign.position = Vector3(0.0, 3.05, 2.55)
	sign.pixel_size = 0.008
	sign.modulate = Color(0.98, 1.0, 0.92, 0.95)
	sign.outline_size = 3
	sign.outline_modulate = Color(0.18, 0.16, 0.12, 1.0)
	home.add_child(sign)

	var warm_light := OmniLight3D.new()
	warm_light.position = Vector3(0.0, 1.8, 0.9)
	warm_light.light_color = Color(1.0, 0.88, 0.66, 1.0)
	warm_light.light_energy = 0.7
	warm_light.omni_range = 8.0
	warm_light.shadow_enabled = false
	home.add_child(warm_light)

	var bed := Node3D.new()
	bed.position = Vector3(0.0, 0.42, -1.2)
	home.add_child(bed)
	bed.add_child(_box_mesh_node(Vector3(2.05, 0.25, 1.45), Vector3(0.0, 0.14, 0.0), bed_frame_mat))
	bed.add_child(_box_mesh_node(Vector3(1.82, 0.22, 1.24), Vector3(0.0, 0.29, 0.0), blanket_mat))
	bed.add_child(_box_mesh_node(Vector3(0.82, 0.14, 0.38), Vector3(0.0, 0.44, -0.34), pillow_mat))
	bed.add_child(_box_mesh_node(Vector3(2.05, 0.72, 0.12), Vector3(0.0, 0.42, -0.68), bed_frame_mat))

	var rug := _box_mesh_node(Vector3(2.5, 0.03, 1.8), Vector3(0.0, 0.39, 0.65), rug_mat)
	home.add_child(rug)

	var bowl_mat := StandardMaterial3D.new()
	bowl_mat.albedo_color = Color(0.36, 0.56, 0.78, 1.0)
	bowl_mat.roughness = 0.28
	bowl_mat.metallic = 0.25
	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.20
	bowl_mesh.bottom_radius = 0.14
	bowl_mesh.height = 0.10
	bowl.mesh = bowl_mesh
	bowl.position = Vector3(1.1, 0.44, 0.95)
	bowl.set_surface_override_material(0, bowl_mat)
	home.add_child(bowl)

	var plant_pot_mat := StandardMaterial3D.new()
	plant_pot_mat.albedo_color = Color(0.62, 0.36, 0.23, 1.0)
	plant_pot_mat.roughness = 0.92
	var plant_leaf_mat := StandardMaterial3D.new()
	plant_leaf_mat.albedo_color = Color(0.28, 0.62, 0.30, 1.0)
	plant_leaf_mat.roughness = 0.82
	for side in [-1.9, 1.9]:
		var pot := MeshInstance3D.new()
		var pot_mesh := CylinderMesh.new()
		pot_mesh.top_radius = 0.24
		pot_mesh.bottom_radius = 0.18
		pot_mesh.height = 0.26
		pot.mesh = pot_mesh
		pot.position = Vector3(side, 0.14, 2.85)
		pot.set_surface_override_material(0, plant_pot_mat)
		home.add_child(pot)

		var leaf := MeshInstance3D.new()
		var leaf_mesh := SphereMesh.new()
		leaf_mesh.radius = 0.34
		leaf_mesh.height = 0.62
		leaf.mesh = leaf_mesh
		leaf.position = Vector3(side, 0.56, 2.85)
		leaf.set_surface_override_material(0, plant_leaf_mat)
		home.add_child(leaf)

	_build_dino_mailbox(home, trim_mat)
	_build_dino_home_fence(home, trim_mat)
	_build_dino_home_sign(home, trim_mat)
	_build_dino_home_lantern(home, trim_mat)
	_build_dino_home_garden(home)
	_build_dino_home_hammock(home, trim_mat)
	_build_dino_home_bush_line(home)
	_build_dino_home_porch_swing(home, trim_mat)
	_build_dino_home_weathervane(home, trim_mat)


func _build_dino_mailbox(parent: Node3D, material: StandardMaterial3D) -> void:
	var post := _box_mesh_node(Vector3(0.08, 0.8, 0.08), Vector3(-1.95, 0.42, 4.15), material)
	parent.add_child(post)
	var box := _box_mesh_node(Vector3(0.34, 0.24, 0.34), Vector3(-1.95, 0.82, 4.15), material)
	parent.add_child(box)


func _build_dino_home_fence(parent: Node3D, material: StandardMaterial3D) -> void:
	for x in [-3.1, -2.2, -1.3, 1.3, 2.2, 3.1]:
		parent.add_child(_box_mesh_node(Vector3(0.08, 0.55, 0.08), Vector3(x, 0.30, 4.45), material))
	parent.add_child(_box_mesh_node(Vector3(1.7, 0.08, 0.08), Vector3(-2.25, 0.45, 4.45), material))
	parent.add_child(_box_mesh_node(Vector3(1.7, 0.08, 0.08), Vector3(2.25, 0.45, 4.45), material))


func _build_dino_home_sign(parent: Node3D, post_mat: StandardMaterial3D) -> void:
	# A hanging "Dino's Home" sign by the porch.
	var post := _box_mesh_node(Vector3(0.1, 1.8, 0.1), Vector3(-1.55, 0.92, 3.6), post_mat)
	parent.add_child(post)
	var arm := _box_mesh_node(Vector3(0.8, 0.08, 0.08), Vector3(-1.15, 1.72, 3.6), post_mat)
	parent.add_child(arm)

	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_color = Color(0.72, 0.55, 0.34, 1.0)
	plank_mat.roughness = 0.78
	plank_mat.rim_enabled = true
	plank_mat.rim = 0.4
	plank_mat.rim_tint = 0.7
	plank_mat.clearcoat_enabled = true
	plank_mat.clearcoat = 0.2
	var plank := _box_mesh_node(Vector3(0.82, 0.44, 0.05), Vector3(-0.85, 1.42, 3.6), plank_mat)
	parent.add_child(plank)

	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.36, 0.28, 0.18, 1.0)
	rope_mat.roughness = 0.95
	parent.add_child(_box_mesh_node(Vector3(0.02, 0.28, 0.02), Vector3(-1.16, 1.56, 3.6), rope_mat))
	parent.add_child(_box_mesh_node(Vector3(0.02, 0.28, 0.02), Vector3(-0.54, 1.56, 3.6), rope_mat))

	var sign_label := Label3D.new()
	sign_label.text = "Dino's Home"
	sign_label.position = Vector3(-0.85, 1.48, 3.63)
	sign_label.pixel_size = 0.005
	sign_label.modulate = Color(0.12, 0.09, 0.06, 1.0)
	sign_label.outline_size = 0
	sign_label.no_depth_test = false
	sign_label.double_sided = true
	parent.add_child(sign_label)

	var heart_label := Label3D.new()
	heart_label.text = "~"
	heart_label.position = Vector3(-0.85, 1.26, 3.63)
	heart_label.pixel_size = 0.006
	heart_label.modulate = Color(0.82, 0.28, 0.46, 1.0)
	heart_label.double_sided = true
	parent.add_child(heart_label)


func _build_dino_home_lantern(parent: Node3D, post_mat: StandardMaterial3D) -> void:
	var post := _box_mesh_node(Vector3(0.08, 1.6, 0.08), Vector3(1.55, 0.82, 3.55), post_mat)
	parent.add_child(post)
	var bracket := _box_mesh_node(Vector3(0.44, 0.06, 0.06), Vector3(1.78, 1.62, 3.55), post_mat)
	parent.add_child(bracket)

	var cage_mat := StandardMaterial3D.new()
	cage_mat.albedo_color = Color(0.18, 0.14, 0.1, 1.0)
	cage_mat.metallic = 0.7
	cage_mat.roughness = 0.35
	cage_mat.rim_enabled = true
	cage_mat.rim = 0.5
	parent.add_child(_box_mesh_node(Vector3(0.3, 0.42, 0.3), Vector3(1.95, 1.4, 3.55), cage_mat))

	var lamp_glass := StandardMaterial3D.new()
	lamp_glass.albedo_color = Color(1.0, 0.85, 0.5, 0.85)
	lamp_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color(1.0, 0.78, 0.4, 1.0)
	lamp_glass.emission_energy_multiplier = 3.8
	lamp_glass.metallic = 0.2
	lamp_glass.roughness = 0.15
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.12
	bulb_mesh.height = 0.24
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(1.95, 1.4, 3.55)
	bulb.set_surface_override_material(0, lamp_glass)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bulb)

	var lamp_light := OmniLight3D.new()
	lamp_light.light_color = Color(1.0, 0.8, 0.5, 1.0)
	lamp_light.light_energy = 1.8
	lamp_light.omni_range = 6.5
	lamp_light.omni_attenuation = 1.2
	lamp_light.position = Vector3(1.95, 1.4, 3.55)
	lamp_light.shadow_enabled = false
	parent.add_child(lamp_light)


func _build_dino_home_garden(parent: Node3D) -> void:
	# Two flower beds flanking the front path, plus scattered wildflowers.
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color(0.32, 0.22, 0.14, 1.0)
	bed_mat.roughness = 0.95

	for side in [-2.7, 2.7]:
		parent.add_child(_box_mesh_node(Vector3(2.2, 0.12, 0.8), Vector3(side, 0.07, 3.8), bed_mat))

	var flower_palette: Array[Color] = [
		Color(0.95, 0.32, 0.42, 1.0),
		Color(0.98, 0.82, 0.28, 1.0),
		Color(0.72, 0.45, 0.95, 1.0),
		Color(1.0, 0.68, 0.32, 1.0),
		Color(0.42, 0.78, 0.95, 1.0),
	]
	for side in [-2.7, 2.7]:
		for i in range(11):
			var fc := flower_palette[rng.randi() % flower_palette.size()]
			var stem_mat := StandardMaterial3D.new()
			stem_mat.albedo_color = Color(0.22, 0.5, 0.24, 1.0)
			stem_mat.roughness = 0.82
			var stem_h := rng.randf_range(0.18, 0.36)
			var stem := _box_mesh_node(
				Vector3(0.03, stem_h, 0.03),
				Vector3(side + rng.randf_range(-0.9, 0.9), 0.12 + stem_h * 0.5, 3.8 + rng.randf_range(-0.3, 0.3)),
				stem_mat
			)
			parent.add_child(stem)

			var bloom_mat := StandardMaterial3D.new()
			bloom_mat.albedo_color = fc
			bloom_mat.emission_enabled = true
			bloom_mat.emission = fc
			bloom_mat.emission_energy_multiplier = 0.8
			bloom_mat.roughness = 0.4
			bloom_mat.rim_enabled = true
			bloom_mat.rim = 0.6
			var bloom := MeshInstance3D.new()
			var bloom_mesh := SphereMesh.new()
			bloom_mesh.radius = rng.randf_range(0.07, 0.11)
			bloom_mesh.height = bloom_mesh.radius * 2.0
			bloom_mesh.radial_segments = 10
			bloom_mesh.rings = 6
			bloom.mesh = bloom_mesh
			bloom.position = stem.position + Vector3(0.0, stem_h * 0.55, 0.0)
			bloom.set_surface_override_material(0, bloom_mat)
			parent.add_child(bloom)


func _build_dino_home_bush_line(parent: Node3D) -> void:
	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.18, 0.46, 0.2, 1.0)
	bush_mat.roughness = 0.7
	bush_mat.rim_enabled = true
	bush_mat.rim = 0.55
	bush_mat.rim_tint = 0.8
	bush_mat.clearcoat_enabled = true
	bush_mat.clearcoat = 0.15

	# Left side bushes along the house back
	for i in range(4):
		var x := -3.4 + i * 0.9
		var bush := MeshInstance3D.new()
		var bush_mesh := SphereMesh.new()
		bush_mesh.radius = rng.randf_range(0.35, 0.5)
		bush_mesh.height = bush_mesh.radius * 1.6
		bush_mesh.radial_segments = 14
		bush_mesh.rings = 8
		bush.mesh = bush_mesh
		bush.position = Vector3(x, bush_mesh.radius * 0.55, -2.8)
		bush.set_surface_override_material(0, bush_mat)
		parent.add_child(bush)

	# Right side bushes
	for i in range(4):
		var x := 0.8 + i * 0.9
		var bush := MeshInstance3D.new()
		var bush_mesh := SphereMesh.new()
		bush_mesh.radius = rng.randf_range(0.32, 0.48)
		bush_mesh.height = bush_mesh.radius * 1.6
		bush_mesh.radial_segments = 14
		bush_mesh.rings = 8
		bush.mesh = bush_mesh
		bush.position = Vector3(x, bush_mesh.radius * 0.55, -2.8)
		bush.set_surface_override_material(0, bush_mat)
		parent.add_child(bush)


func _build_dino_home_hammock(parent: Node3D, post_mat: StandardMaterial3D) -> void:
	# Two posts with a curved fabric hammock strung between them.
	var post_l := _box_mesh_node(Vector3(0.12, 2.2, 0.12), Vector3(-5.2, 1.12, 0.0), post_mat)
	parent.add_child(post_l)
	var post_r := _box_mesh_node(Vector3(0.12, 2.2, 0.12), Vector3(-5.2, 1.12, 2.2), post_mat)
	parent.add_child(post_r)

	var fabric_mat := StandardMaterial3D.new()
	fabric_mat.albedo_color = Color(0.82, 0.38, 0.32, 1.0)
	fabric_mat.roughness = 0.92
	fabric_mat.rim_enabled = true
	fabric_mat.rim = 0.5
	fabric_mat.rim_tint = 0.8
	fabric_mat.clearcoat_enabled = true
	fabric_mat.clearcoat = 0.1

	# Fake the sag with a slightly-rotated flat plane.
	var hammock := MeshInstance3D.new()
	var hammock_mesh := BoxMesh.new()
	hammock_mesh.size = Vector3(0.95, 0.08, 2.15)
	hammock.mesh = hammock_mesh
	hammock.position = Vector3(-5.2, 1.35, 1.1)
	hammock.rotation = Vector3(0.0, 0.0, 0.05)
	hammock.set_surface_override_material(0, fabric_mat)
	parent.add_child(hammock)


func _build_dino_home_porch_swing(parent: Node3D, frame_mat: StandardMaterial3D) -> void:
	# A swing bench on the left side of the porch.
	var swing_base_y := 1.1
	var seat := _box_mesh_node(Vector3(1.0, 0.06, 0.42), Vector3(-1.7, swing_base_y, 2.85), frame_mat)
	parent.add_child(seat)
	var back := _box_mesh_node(Vector3(1.0, 0.58, 0.06), Vector3(-1.7, swing_base_y + 0.32, 2.65), frame_mat)
	parent.add_child(back)

	var chain_mat := StandardMaterial3D.new()
	chain_mat.albedo_color = Color(0.22, 0.22, 0.24, 1.0)
	chain_mat.metallic = 0.75
	chain_mat.roughness = 0.3
	for z in [2.72, 2.98]:
		for x_off in [-2.1, -1.3]:
			parent.add_child(_box_mesh_node(Vector3(0.03, 1.2, 0.03), Vector3(x_off, swing_base_y + 0.6, z), chain_mat))


func _build_dino_home_weathervane(parent: Node3D, metal_mat: StandardMaterial3D) -> void:
	var vane_pole := _box_mesh_node(Vector3(0.06, 1.0, 0.06), Vector3(0.0, 4.74, 0.0), metal_mat)
	parent.add_child(vane_pole)

	var ball := MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.12
	ball_mesh.height = 0.24
	ball.mesh = ball_mesh
	ball.position = Vector3(0.0, 5.2, 0.0)
	ball.set_surface_override_material(0, metal_mat)
	parent.add_child(ball)

	var vane_mat := StandardMaterial3D.new()
	vane_mat.albedo_color = Color(0.3, 0.3, 0.32, 1.0)
	vane_mat.metallic = 0.6
	vane_mat.roughness = 0.4
	vane_mat.rim_enabled = true
	vane_mat.rim = 0.55

	var arrow_h := _box_mesh_node(Vector3(0.8, 0.08, 0.02), Vector3(0.0, 5.35, 0.0), vane_mat)
	parent.add_child(arrow_h)

	var arrow_head := MeshInstance3D.new()
	var head_mesh := PrismMesh.new()
	head_mesh.size = Vector3(0.2, 0.2, 0.04)
	arrow_head.mesh = head_mesh
	arrow_head.position = Vector3(0.4, 5.35, 0.0)
	arrow_head.rotation.z = deg_to_rad(-90.0)
	arrow_head.set_surface_override_material(0, vane_mat)
	parent.add_child(arrow_head)

	# Decorative N-E-S-W markers
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.36, 0.28, 0.18, 1.0)
	marker_mat.roughness = 0.78
	parent.add_child(_box_mesh_node(Vector3(0.08, 0.08, 0.8), Vector3(0.0, 5.1, 0.0), marker_mat))


func _box_mesh_node(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.set_surface_override_material(0, material)
	return node


func _is_reserved_space(pos: Vector3, extra_radius := 0.0) -> bool:
	var flat := Vector2(pos.x, pos.z)
	if flat.distance_to(Vector2(DINO_HOME_POS.x, DINO_HOME_POS.z)) < DINO_HOME_CLEAR_RADIUS + extra_radius:
		return true
	if flat.distance_to(Vector2(14.0, -9.0)) < POND_CLEAR_RADIUS + extra_radius:
		return true
	return false


# ---------------------------------------------------------------------------
# Fireflies — night-only particles (emitting toggled by park_night_lights.gd)
# ---------------------------------------------------------------------------

func _build_fireflies() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38.0, 2.0, 38.0)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3(0.0, 0.0, 0.0)
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	pm.color = Color(0.75, 1.0, 0.45, 0.75)

	var sphere := SphereMesh.new()
	sphere.radius = 0.022
	sphere.height = 0.044
	sphere.radial_segments = 6
	sphere.rings = 4

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 1.0, 0.4, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 1.0, 0.35, 1.0)
	mat.emission_energy_multiplier = 2.8
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sphere.material = mat

	var fireflies := GPUParticles3D.new()
	fireflies.name = "Fireflies"
	fireflies.amount = 110
	fireflies.lifetime = 5.5
	fireflies.process_material = pm
	fireflies.draw_pass_1 = sphere
	fireflies.material_override = mat
	fireflies.position = Vector3(0.0, 1.1, 0.0)
	fireflies.visibility_aabb = AABB(Vector3(-45.0, -2.0, -45.0), Vector3(90.0, 12.0, 90.0))
	fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fireflies.emitting = false
	fireflies.add_to_group("night_fireflies")
	add_child(fireflies)


# ---------------------------------------------------------------------------
# Floating digital particles — ambient glitch specks to fit the sci-fi world
# ---------------------------------------------------------------------------

func _build_digital_particles() -> void:
	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(34.0, 0.5, 34.0)
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 25.0
	process_mat.initial_velocity_min = 0.2
	process_mat.initial_velocity_max = 0.7
	process_mat.gravity = Vector3(0.0, -0.04, 0.0)
	process_mat.scale_min = 0.5
	process_mat.scale_max = 1.4
	process_mat.color = Color(0.35, 0.92, 0.58, 0.55)

	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	sphere.radial_segments = 6
	sphere.rings = 4

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.35, 0.95, 0.6, 0.65)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.25, 0.9, 0.5, 1.0)
	glow_mat.emission_energy_multiplier = 2.2
	glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sphere.material = glow_mat

	var particles := GPUParticles3D.new()
	particles.amount = particle_amount
	particles.lifetime = 7.0
	particles.process_material = process_mat
	particles.draw_pass_1 = sphere
	particles.material_override = glow_mat
	particles.position = Vector3(0.0, 1.5, 0.0)
	particles.visibility_aabb = AABB(Vector3(-40.0, -2.0, -40.0), Vector3(80.0, 16.0, 80.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
