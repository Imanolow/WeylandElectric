extends Node3D
class_name TowerPlacer

@export var tower_scene: PackedScene
@export var pole_scene: PackedScene
@export var placement_range: float = 10.0
@export var min_tower_distance: float = 5.0  # Aumentado de 3.0 a 5.0 para mayor separación entre torres
@export var pole_count: int = 3
@export var pole_radius_min: float = 1.5
@export var pole_radius_max: float = 3.0
@export var auto_connection_distance: float = 8.0  # Distancia máxima para conexiones automáticas entre torres
@export var pole_connection_distance: float = 3.0  # Distancia máxima para conexiones entre postes (más pequeña)
@export var secondary_pole_distance: float = 2.5  # Distancia del poste secundario desde el primario
@export var enable_secondary_poles: bool = true  # Si crear postes secundarios en cadena
@export var ground_layer: int = 1

# Variables de límites del nivel
var level_bounds: Area3D = null

var camera: Camera3D
var placed_towers: Array[Node3D] = []

# Variables de conexiones
var tower_connections: Array[Array] = [] # Array de [torre1, torre2] para cada conexión
var pole_connections: Array[Array] = [] # Array de [torre_pos, poste_pos] para cada conexión de poste
var secondary_pole_connections: Array[Array] = [] # Array de [poste1_pos, poste2_pos] para postes secundarios
var auto_connections: Array[Array] = [] # Para evitar conexiones automáticas duplicadas
var placed_poles: Array[Node3D] = []  # Todos los postes colocados (primarios y secundarios)
var tower_preview: Node3D
var pole_previews: Array[Node3D] = []
var current_pole_positions: Array[Vector3] = []  # Posiciones exactas de los postes del preview actual
var preview_material_valid: StandardMaterial3D
var preview_material_invalid: StandardMaterial3D
var range_indicator: Node3D
var range_indicator_points: Array[MeshInstance3D] = []  # Array de puntos del círculo
var connection_lines: Array[Node3D] = [] # Para dibujar las conexiones

# Referencias a torres especiales
var start_tower: Node3D = null
var end_tower: Node3D = null
var level_completed: bool = false

# Variables para control de preview de postes
var last_preview_position: Vector3 = Vector3.INF
var preview_poles_seed: int = 0
var current_secondary_pole_positions: Array[Vector3] = []  # Posiciones de postes secundarios del preview

func _ready():
	camera = get_viewport().get_camera_3d()
	setup_preview_materials()
	create_preview_tower()
	create_range_indicator()
	find_special_towers()
	find_level_bounds()

func _find_obstacles_recursive(node: Node, obstacles: Array):
	if node.name.begins_with("Obstacle"):
		obstacles.append(node)
	for child in node.get_children():
		_find_obstacles_recursive(child, obstacles)

# Funciones para detectar obstáculos usando grupos de Godot
func is_obstacle_high(node: Node) -> bool:
	return node.is_in_group("ObstacleHigh")

func is_obstacle_low(node: Node) -> bool:
	return node.is_in_group("ObstacleLow")

func is_obstacle(node: Node) -> bool:
	return is_obstacle_high(node) or is_obstacle_low(node)

# Obtener todos los obstáculos altos en la escena
func get_all_high_obstacles() -> Array[Node]:
	return get_tree().get_nodes_in_group("ObstacleHigh")

# Obtener todos los obstáculos bajos en la escena
func get_all_low_obstacles() -> Array[Node]:
	return get_tree().get_nodes_in_group("ObstacleLow")

# Obtener todos los obstáculos (altos y bajos)
func get_all_obstacles() -> Array[Node]:
	var all_obs: Array[Node] = []
	all_obs.append_array(get_all_high_obstacles())
	all_obs.append_array(get_all_low_obstacles())
	return all_obs

func setup_preview_materials():
	preview_material_valid = StandardMaterial3D.new()
	preview_material_valid.albedo_color = Color.GREEN
	preview_material_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material_valid.albedo_color.a = 0.5
	
	preview_material_invalid = StandardMaterial3D.new()
	preview_material_invalid.albedo_color = Color.RED
	preview_material_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material_invalid.albedo_color.a = 0.5

func create_preview_tower():
	# Usar solo la escena configurada en el inspector
	if not tower_scene:
		print("Error: No hay escena de torre configurada en Tower Scene")
		return
	
	# Instanciar la escena directamente
	tower_preview = tower_scene.instantiate()
	if not tower_preview:
		print("Error: No se pudo instanciar la escena")
		return
	
	add_child(tower_preview)
	tower_preview.visible = false
	
	# Aplicar material a toda la torre
	apply_material_to_node(tower_preview, preview_material_valid)

# Función centralizada para generar posiciones de postes de forma consistente
func generate_pole_positions(tower_pos: Vector3) -> Array[Vector3]:
	# Usar semilla basada en posición para que sea consistente
	var grid_x = int(tower_pos.x / 2.0)  # Cuadrícula de 2x2 metros
	var grid_z = int(tower_pos.z / 2.0)
	var poles_seed = hash(Vector2i(grid_x, grid_z))
	seed(poles_seed)
	
	# Generar número aleatorio de postes (2-5) pero consistente por zona
	var random_pole_count = randi_range(2, 5)
	var pole_positions: Array[Vector3] = []
	
	# Generar EXACTAMENTE el número aleatorio de postes - sin ajustes ni compromisos
	for i in range(random_pole_count):
		var attempts = 0
		var pole_pos: Vector3
		var valid_position = false
		
		# Intentar encontrar una posición válida para este poste
		while attempts < 50 and not valid_position:
			var angle = randf() * TAU
			var distance = randf_range(pole_radius_min, pole_radius_max)
			
			pole_pos = tower_pos + Vector3(
				cos(angle) * distance,
				0,
				sin(angle) * distance
			)
			
			# FORZAR que esté en el suelo
			pole_pos.y = get_ground_height(pole_pos)
			
			# Verificar que no esté sobre obstáculos
			if is_pole_position_blocked(pole_pos):
				attempts += 1
				continue
			
			# NUEVA VALIDACIÓN: Verificar que esté dentro de los límites del nivel
			if not is_position_inside_level_bounds(pole_pos):
				attempts += 1
				continue
			
			# NUEVA VALIDACIÓN: Verificar que el cable Torre→Poste no cruce cables existentes
			if would_pole_connection_cross_existing_cables(tower_pos, pole_pos):
				attempts += 1
				continue
			
			# Si llegamos aquí, la posición es válida
			valid_position = true
		
		# OBLIGATORIO: Si no se encontró posición válida, FALLAR TODA LA GENERACIÓN
		if not valid_position:
			# Limpiar arrays y devolver vacío = colocación imposible
			current_secondary_pole_positions.clear()
			randomize()
			return []
		
		pole_positions.append(pole_pos)
	
	# Generar posiciones de postes secundarios si está habilitado
	current_secondary_pole_positions.clear()
	if enable_secondary_poles:
		for primary_pole_pos in pole_positions:
			var secondary_pos = generate_secondary_pole_position(tower_pos, primary_pole_pos)
			# OBLIGATORIO: Si cualquier secundario falla, FALLAR TODA LA GENERACIÓN
			if secondary_pos == Vector3.INF:
				current_secondary_pole_positions.clear()  # Limpiar array secundario antes de fallar
				randomize()
				return []
			current_secondary_pole_positions.append(secondary_pos)
	
	# Restaurar semilla aleatoria global
	randomize()
	return pole_positions

# Función para generar la posición del poste secundario en línea con el primario
func generate_secondary_pole_position(tower_pos: Vector3, primary_pole_pos: Vector3) -> Vector3:
	# Calcular la dirección desde la torre hacia el poste primario
	var direction = (primary_pole_pos - tower_pos).normalized()
	
	# Intentar varias distancias para encontrar una posición válida
	var distances_to_try = [
		secondary_pole_distance, 
		secondary_pole_distance * 0.8, 
		secondary_pole_distance * 1.2, 
		secondary_pole_distance * 0.6,
		secondary_pole_distance * 1.4
	]
	
	for distance in distances_to_try:
		# Colocar el poste secundario en la misma línea, más lejos
		var secondary_pos = primary_pole_pos + direction * distance
		
		# Ajustar altura al terreno
		secondary_pos.y = get_ground_height(secondary_pos)
		
		# Verificar que la posición sea válida (sin obstáculos)
		if is_pole_position_blocked(secondary_pos):
			continue  # Intentar siguiente distancia
		
		# Verificar que esté dentro de los límites del nivel
		if not is_position_inside_level_bounds(secondary_pos):
			continue  # Intentar siguiente distancia
		
		# Verificar que el cable entre postes no cruce obstáculos
		if would_pole_connection_cross_obstacles(primary_pole_pos, secondary_pos):
			continue  # Intentar siguiente distancia
		
		# NUEVA VALIDACIÓN: Verificar que el cable no cruce con cables existentes
		if would_pole_connection_cross_existing_cables(primary_pole_pos, secondary_pos):
			continue  # Intentar siguiente distancia
		
		# Si llegamos aquí, la posición es válida
		return secondary_pos
	
	# Si no encontramos ninguna posición válida, intentar otras direcciones
	# Pequeña variación en la dirección (±15 grados)
	for angle_offset in [deg_to_rad(15), deg_to_rad(-15), deg_to_rad(30), deg_to_rad(-30)]:
		var rotated_direction = direction.rotated(Vector3.UP, angle_offset)
		
		for distance in [secondary_pole_distance, secondary_pole_distance * 0.8]:
			var secondary_pos = primary_pole_pos + rotated_direction * distance
			secondary_pos.y = get_ground_height(secondary_pos)
			
			if not is_pole_position_blocked(secondary_pos) and is_position_inside_level_bounds(secondary_pos) and not would_pole_connection_cross_obstacles(primary_pole_pos, secondary_pos) and not would_pole_connection_cross_existing_cables(primary_pole_pos, secondary_pos):
				return secondary_pos
	
	# Si no encontramos ninguna posición válida
	return Vector3.INF

# Función para verificar si una conexión entre postes cruza obstáculos
func would_pole_connection_cross_obstacles(pole1_pos: Vector3, pole2_pos: Vector3) -> bool:
	# Obtener todos los obstáculos
	var all_obstacles = []
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleHigh"))
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleLow"))
	
	# Buscar en grupo general "obstacles" también
	var general_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obs in general_obstacles:
		all_obstacles.append(obs)
	
	# Buscar recursivamente por nombre (fallback)
	var recursive_obstacles = []
	_find_obstacles_recursive(get_tree().root, recursive_obstacles)
	all_obstacles.append_array(recursive_obstacles)
	
	# Posiciones del cable entre postes (a menor altura que los cables principales)
	var start_pos = pole1_pos + Vector3(0, 1.0, 0)  # Postes a 1m de altura
	var end_pos = pole2_pos + Vector3(0, 1.0, 0)
	
	# Proyectar la línea del cable al plano XZ
	var cable_start_2d = Vector2(start_pos.x, start_pos.z)
	var cable_end_2d = Vector2(end_pos.x, end_pos.z)
	
	for obstacle in all_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var obs_pos = obstacle.global_position
		var obs_size = Vector3(2.0, 2.0, 2.0)  # Tamaño por defecto
		
		# Buscar CollisionShape3D para obtener el tamaño real
		for child in obstacle.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				obs_size = child.shape.size
				break
		
		# Verificar si el obstáculo está a la altura correcta para intersectar el cable
		var obs_bottom = obs_pos.y - obs_size.y/2
		var obs_top = obs_pos.y + obs_size.y/2
		var cable_min_height = min(start_pos.y, end_pos.y)
		var cable_max_height = max(start_pos.y, end_pos.y)
		
		# Si el obstáculo no está en el rango de altura del cable, ignorarlo
		if obs_top < cable_min_height or obs_bottom > cable_max_height:
			continue
		
		# Verificar intersección en 2D (X,Z) con el tamaño completo del obstáculo
		var obs_pos_2d = Vector2(obs_pos.x, obs_pos.z)
		var obs_size_2d = Vector2(obs_size.x, obs_size.z)
		
		if does_line_intersect_box_2d(cable_start_2d, cable_end_2d, obs_pos_2d, obs_size_2d):
			return true
	
	return false

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	
	for child in node.get_children():
		var result = _find_mesh_instance(child)
		if result:
			return result
	
	return null

func create_range_indicator():
	# Ya no creamos un cilindro, sino un contenedor para los puntos
	range_indicator = Node3D.new()
	add_child(range_indicator)
	range_indicator.visible = false

func clear_range_indicator():
	# Limpiar todos los puntos anteriores
	for point in range_indicator_points:
		if point and is_instance_valid(point):
			point.queue_free()
	range_indicator_points.clear()

func find_special_towers():
	# Buscar torres especiales en la escena
	var scene_root = get_tree().current_scene
	_find_towers_recursive(scene_root)
	
	if start_tower:
		print("Torre inicial encontrada: ", start_tower.name)
	if end_tower:
		print("Torre final encontrada: ", end_tower.name)

func find_level_bounds():
	# Buscar el área de límites del nivel
	var bounds_nodes = get_tree().get_nodes_in_group("level_bounds")
	if bounds_nodes.size() > 0:
		level_bounds = bounds_nodes[0]
		print("Límites del nivel encontrados: ", level_bounds.name)
	else:
		print("⚠️ Advertencia: No se encontraron límites de nivel. Agregue un Area3D al grupo 'level_bounds'")

func is_position_inside_level_bounds(pos: Vector3) -> bool:
	if not level_bounds:
		return true  # Si no hay límites definidos, permitir en cualquier lugar
	
	# Obtener el CollisionShape3D hijo del Area3D
	var collision_shape = null
	for child in level_bounds.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return true  # Si no hay shape, permitir colocación
	
	var shape = collision_shape.shape
	
	# Manejar ConvexPolygonShape3D
	if shape is ConvexPolygonShape3D:
		var points = shape.points
		if points.size() < 3:
			return true
		
		# Convertir puntos 3D a 2D (usar X y Z, ignorar Y)
		var points_2d = []
		for point in points:
			points_2d.append(Vector2(point.x, point.z))
		
		# Verificar si el punto está dentro del polígono usando ray-casting
		var test_point = Vector2(pos.x, pos.z)
		return _point_in_polygon(test_point, points_2d)
	
	# Manejar BoxShape3D como fallback
	elif shape is BoxShape3D:
		var size = shape.size
		var bounds_center = level_bounds.global_position
		
		return (abs(pos.x - bounds_center.x) <= size.x / 2.0 and
				abs(pos.z - bounds_center.z) <= size.z / 2.0)
	
	return true

func _point_in_polygon(point: Vector2, polygon: Array) -> bool:
	var x = point.x
	var y = point.y
	var inside = false
	
	var j = polygon.size() - 1
	for i in range(polygon.size()):
		var xi = polygon[i].x
		var yi = polygon[i].y
		var xj = polygon[j].x
		var yj = polygon[j].y
		
		if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
			inside = !inside
		j = i
	
	return inside

func _find_towers_recursive(node: Node):
	# Verificar si este nodo tiene el script de torre inicial o final
	var script = node.get_script()
	if script:
		var script_path = script.resource_path
		if "towers/TowerBegin.gd" in script_path:
			start_tower = node
		elif "towers/TowerEnd.gd" in script_path:
			end_tower = node
	
	# Buscar en los hijos
	for child in node.get_children():
		_find_towers_recursive(child)

func apply_material_to_node(node: Node, material: Material):
	if not node:
		return
	
	# Buscar MeshInstance3D en la jerarquía completa
	if node is MeshInstance3D:
		node.material_override = material
		return
	
	# Buscar recursivamente en todos los hijos
	for child in node.get_children():
		apply_material_to_node(child, material)

func _input(event):
	if event is InputEventMouseMotion:
		update_tower_preview(event.position)
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			try_place_tower()

func update_tower_preview(mouse_pos: Vector2):
	if not camera:
		return
	
	if not tower_preview or not is_instance_valid(tower_preview):
		create_preview_tower()
		return
	
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000, 1)
	var result = space_state.intersect_ray(query)
	
	if result:
		var target_pos = result.position
		tower_preview.position = target_pos
		
		# Aplicar la misma orientación del preview que al colocar la torre
		if placed_towers.size() > 0:
			var last_tower = placed_towers[-1]
			var direction = (target_pos - last_tower.position).normalized()
			var angle = atan2(direction.x, direction.z)
			tower_preview.rotation.y = angle
		elif start_tower:
			var direction = (target_pos - start_tower.global_position).normalized()
			var angle = atan2(direction.x, direction.z)
			tower_preview.rotation.y = angle
		
		tower_preview.visible = true
		
		# PRIMERO: Crear el preview de postes (esto genera y guarda las posiciones)
		create_pole_previews(target_pos, true)  # Usar material válido temporalmente
		
		# SEGUNDO: Validar usando las posiciones ya generadas en el preview
		var is_valid = is_position_valid(target_pos)
		
		# TERCERO: Aplicar el material correcto según la validación
		if is_valid:
			apply_material_to_node(tower_preview, preview_material_valid)
			show_range_indicator(target_pos)
			# Actualizar materiales de postes a válido
			var pole_material = preview_material_valid
			for pole_preview in pole_previews:
				if pole_preview and is_instance_valid(pole_preview):
					apply_material_to_node(pole_preview, pole_material)
		else:
			apply_material_to_node(tower_preview, preview_material_invalid)
			hide_range_indicator()
			# Actualizar materiales de postes a inválido
			var pole_material = preview_material_invalid
			for pole_preview in pole_previews:
				if pole_preview and is_instance_valid(pole_preview):
					apply_material_to_node(pole_preview, pole_material)
	else:
		tower_preview.visible = false
		hide_range_indicator()
		hide_pole_previews()

func create_pole_previews(tower_pos: Vector3, is_valid_position: bool = true):
	# Usar solo la escena configurada en el inspector
	if not pole_scene:
		print("Error: No hay escena de poste configurada en Pole Scene")
		return
	
	# Solo regenerar postes si nos hemos movido lo suficiente (variación más lenta)
	var distance_moved = tower_pos.distance_to(last_preview_position)
	if distance_moved < 2.0 and last_preview_position != Vector3.INF:
		# Si no nos hemos movido mucho, solo cambiar materiales si es necesario
		var target_material = preview_material_valid if is_valid_position else preview_material_invalid
		for pole_preview in pole_previews:
			if pole_preview and is_instance_valid(pole_preview):
				apply_material_to_node(pole_preview, target_material)
		return
	
	hide_pole_previews()
	last_preview_position = tower_pos
	
	# Usar la función centralizada para obtener posiciones consistentes
	var pole_positions = generate_pole_positions(tower_pos)
	
	# GUARDAR las posiciones exactas para usar al hacer click
	current_pole_positions = pole_positions.duplicate()
	
	# Elegir material según validez
	var pole_material = preview_material_valid if is_valid_position else preview_material_invalid
	
	for pole_pos in pole_positions:
		# Instanciar la escena directamente
		var pole_preview = pole_scene.instantiate()
		if not pole_preview:
			continue
		
		add_child(pole_preview)
		pole_preview.position = pole_pos
		
		# Aplicar material a toda la estructura del poste
		apply_material_to_node(pole_preview, pole_material)
		pole_previews.append(pole_preview)
	
	# Crear previews de postes secundarios si están habilitados
	if enable_secondary_poles:
		for secondary_pos in current_secondary_pole_positions:
			# Solo crear preview si la posición es válida
			if secondary_pos != Vector3.INF:
				var secondary_preview = pole_scene.instantiate()
				if not secondary_preview:
					continue
				
				add_child(secondary_preview)
				secondary_preview.position = secondary_pos
				
				# Aplicar material a toda la estructura del poste secundario
				apply_material_to_node(secondary_preview, pole_material)
				pole_previews.append(secondary_preview)

func get_ground_height(pos: Vector3) -> float:
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 10,
		pos + Vector3.DOWN * 10
	)
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position.y
	return pos.y

func hide_pole_previews():
	for pole in pole_previews:
		if pole and is_instance_valid(pole):
			pole.queue_free()
	pole_previews.clear()
	current_pole_positions.clear()  # Limpiar también las posiciones guardadas
	current_secondary_pole_positions.clear()  # Limpiar posiciones secundarias

func show_range_indicator(pos: Vector3):
	if not range_indicator:
		return
	
	clear_range_indicator()  # Limpiar puntos anteriores
	
	if placed_towers.size() > 0:
		# Mostrar el rango desde la última torre colocada
		var last_tower = placed_towers[-1]
		create_circle_points(last_tower.position, placement_range)
	elif start_tower:
		# Si no hay torres colocadas, mostrar rango desde la torre inicial
		create_circle_points(start_tower.global_position, placement_range)
	else:
		# Si no hay torre inicial, mostrar en la posición del mouse
		create_circle_points(pos, placement_range)
	
	range_indicator.visible = true

func create_circle_points(center: Vector3, radius: float):
	# Crear puntos alrededor del círculo que se adapten al terreno
	var num_points = 64  # Más puntos = círculo más suave
	var angle_step = TAU / num_points  # TAU = 2 * PI
	
	for i in range(num_points):
		var angle = i * angle_step
		var point_x = center.x + cos(angle) * radius
		var point_z = center.z + sin(angle) * radius
		var point_position = Vector3(point_x, 0, point_z)
		
		# Obtener la altura real del terreno en esta posición
		var ground_height = get_ground_height(point_position)
		point_position.y = ground_height + 0.15  # Elevar ligeramente sobre el terreno
		
		# Crear un pequeño cubo para cada punto
		var point_mesh = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.4, 0.1, 0.4)  # Pequeño y plano
		point_mesh.mesh = box_mesh
		
		# Material semi-transparente azul (como el original)
		var material = StandardMaterial3D.new()
		material.flags_transparent = true
		material.albedo_color = Color(0, 0, 1, 0.4)  # Azul como el original
		material.flags_unshaded = true
		point_mesh.material_override = material
		
		point_mesh.position = point_position
		range_indicator.add_child(point_mesh)
		range_indicator_points.append(point_mesh)

func hide_range_indicator():
	if range_indicator:
		range_indicator.visible = false
		clear_range_indicator()  # Limpiar puntos cuando se oculta

func get_closest_tower_in_range(pos: Vector3) -> Node3D:
	var closest_tower = null
	var closest_distance = placement_range + 1
	
	for tower in placed_towers:
		if not is_instance_valid(tower):
			continue
		var distance = tower.position.distance_to(pos)
		if distance <= placement_range and distance < closest_distance:
			closest_distance = distance
			closest_tower = tower
	
	return closest_tower

func is_position_valid(pos: Vector3) -> bool:
	# 0. Verificar que esté dentro de los límites del nivel
	if not is_position_inside_level_bounds(pos):
		return false
	
	# 1. Si el nivel ya se completó, no permitir más torres
	if level_completed:
		return false
	
	# 1. Si no hay torres colocadas, verificar rango desde torre inicial
	if placed_towers.is_empty():
		if start_tower:
			var distance_to_start = start_tower.global_position.distance_to(pos)
			var start_range = 10.0  # Mismo rango que las torres normales
			if distance_to_start > start_range:
				return false
		# Si no hay torre inicial, permitir colocar en cualquier lugar
	
	# 2. Verificar distancia mínima
	if is_too_close_to_existing_tower(pos):
		return false
	
	# 3. Verificar obstáculos en el cable (solo si hay torres previas)
	if has_obstacle_at_tower_position(pos):
		return false
	
	# 4. Verificar si hay ObstacleLow directamente donde se colocaría la torre
	if has_low_obstacle_at_position(pos):
		return false
	
	# 5. Verificar rango (solo si hay torres previas)
	if not placed_towers.is_empty():
		var last_tower = placed_towers[-1]
		var distance_to_last = last_tower.position.distance_to(pos)
		
		if distance_to_last > placement_range:
			return false
		
		# 6. Verificar cruce con cables existentes
		if would_connection_cross_existing_cables(last_tower.position, pos):
			return false
	
	# 7. NUEVA VALIDACIÓN: Verificar que TODOS los postes del preview se puedan colocar
	# NO regenerar - usar las posiciones ya calculadas en el preview
	if current_pole_positions.is_empty():
		return false  # Si no hay postes primarios en el preview, es inválido
	
	# Si los postes secundarios están habilitados, TODOS deben poder colocarse
	if enable_secondary_poles:
		for secondary_pos in current_secondary_pole_positions:
			if secondary_pos == Vector3.INF:
				return false  # Si algún poste secundario no se puede colocar, la torre es inválida
	
	return true

func is_too_close_to_existing_tower(pos: Vector3) -> bool:
	for tower in placed_towers:
		if not is_instance_valid(tower):
			continue
		var distance = tower.position.distance_to(pos)
		if distance < min_tower_distance:
			return true
	return false

# Función para detectar colisiones con objetos del escenario
func has_collision_at_position(_pos: Vector3) -> bool:
	# Por ahora devolver false para aislar el problema
	return false

# Función para verificar si hay ObstacleLow directamente en la posición de la torre
func has_low_obstacle_at_position(pos: Vector3) -> bool:
	# ESTRATEGIA MEJORADA: Usar grupos específicos primero, luego fallback
	var all_obstacles = []
	
	# Método 1: Usar grupos específicos (más eficiente)
	var low_obstacles = get_tree().get_nodes_in_group("ObstacleLow")
	for obs in low_obstacles:
		all_obstacles.append(obs)
	
	# Método 2: Buscar en grupo general "obstacles" solo obstáculos bajos
	var general_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obs in general_obstacles:
		if obs.name.begins_with("ObstacleLow"):
			all_obstacles.append(obs)
	
	# Método 3: Buscar recursivamente por nombre (fallback)
	var recursive_obstacles = []
	_find_obstacles_recursive(get_tree().root, recursive_obstacles)
	for obs in recursive_obstacles:
		if obs.name.begins_with("ObstacleLow"):
			all_obstacles.append(obs)
	
	for obstacle in all_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var obs_pos = obstacle.global_position
		var obs_size = Vector3(2.0, 2.0, 2.0)  # Tamaño por defecto
		
		# Buscar CollisionShape3D para obtener el tamaño real
		for child in obstacle.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				obs_size = child.shape.size
				break
		
		# Verificar si la posición de la torre está dentro del área del obstáculo (en 2D)
		# INCLUIR MARGEN DE SEGURIDAD para las torres
		var distance_x = abs(pos.x - obs_pos.x)
		var distance_z = abs(pos.z - obs_pos.z)
		
		# Usar un margen más grande para torres: tamaño del obstáculo + margen adicional
		var margin_x = (obs_size.x * 0.5) + 1.0  # Medio obstáculo + 1 metro de margen
		var margin_z = (obs_size.z * 0.5) + 1.0  # Medio obstáculo + 1 metro de margen
		
		# Si la torre está dentro del área expandida del obstáculo bajo, bloquear colocación
		if distance_x < margin_x and distance_z < margin_z:
			return true
	
	return false

# Función para verificar si una posición de poste está bloqueada por obstáculos
func is_pole_position_blocked(pole_pos: Vector3) -> bool:
	# ESTRATEGIA MEJORADA: Usar grupos específicos primero, luego fallback
	var all_obstacles = []
	
	# Método 1: Usar grupos específicos (más eficiente)
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleHigh"))
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleLow"))
	
	# Método 2: Buscar en grupo general "obstacles"
	var general_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obs in general_obstacles:
		all_obstacles.append(obs)
	
	# Método 3: Buscar recursivamente por nombre (fallback)
	var recursive_obstacles = []
	_find_obstacles_recursive(get_tree().root, recursive_obstacles)
	all_obstacles.append_array(recursive_obstacles)
	
	# Método 4: Buscar por CollisionLayer específica
	var space_state = get_viewport().get_world_3d().direct_space_state
	var shape = SphereShape3D.new()
	shape.radius = 0.1
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = pole_pos
	query.collision_mask = 2  # Capa de obstáculos
	var physics_results = space_state.intersect_shape(query)
	
	for obstacle in all_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		# Verificar tanto ObstacleHigh como ObstacleLow (postes no pueden estar sobre ninguno)
		if not (obstacle.name.begins_with("Obstacle") or is_obstacle(obstacle)):
			continue
		
		var obs_pos = obstacle.global_position
		var obs_size = Vector3(2.0, 2.0, 2.0)  # Tamaño por defecto
		
		# Buscar CollisionShape3D para obtener el tamaño real
		for child in obstacle.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				obs_size = child.shape.size
				break
		
		# Verificar si la posición del poste está dentro del área del obstáculo (en 2D)
		var distance_x = abs(pole_pos.x - obs_pos.x)
		var distance_z = abs(pole_pos.z - obs_pos.z)
		
		# Usar un margen más conservador para postes
		var margin_x = obs_size.x * 0.6  # Aumentado de 0.4 a 0.6 para ser más estricto
		var margin_z = obs_size.z * 0.6  # Aumentado de 0.4 a 0.6 para ser más estricto
		
		if distance_x < margin_x and distance_z < margin_z:
			return true
	
	# Si no encontró obstáculos por nombre, usar detección de física
	for result in physics_results:
		var collider = result.collider
		if collider.name.begins_with("Obstacle"):
			return true
	
	return false

# Función para verificar si hay obstáculos en la posición donde se colocará la torre
func has_obstacle_at_tower_position(pos: Vector3) -> bool:
	if placed_towers.is_empty():
		return false
	
	var last_tower = placed_towers[-1]
	
	# Usar EXACTAMENTE la misma lógica que create_connection()
	# Pero primero obtener las alturas reales del terreno
	var last_tower_ground = get_ground_height(last_tower.position)
	var new_tower_ground = get_ground_height(pos)
	
	# Calcular posiciones del cable a 2.2m sobre cada torre (igual que create_connection)
	var start_pos = Vector3(last_tower.position.x, last_tower_ground + 2.2, last_tower.position.z)
	var end_pos = Vector3(pos.x, new_tower_ground + 2.2, pos.z)
	
	# Buscar todos los obstáculos usando grupos mejorados
	var all_obstacles = []
	
	# Método 1: Usar grupos específicos
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleHigh"))
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleLow"))
	
	# Método 2: Buscar en grupo general "obstacles"
	var general_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obs in general_obstacles:
		all_obstacles.append(obs)
	
	# Método 3: Buscar recursivamente por nombre (fallback)
	_find_obstacles_recursive(get_tree().root, all_obstacles)
	
	for obstacle in all_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var obs_pos = obstacle.global_position
		var obs_size = Vector3(2.0, 2.0, 2.0)  # Tamaño por defecto
		
		# Buscar CollisionShape3D para obtener el tamaño real
		for child in obstacle.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				obs_size = child.shape.size
				break
		
		# Verificar si el obstáculo está a la altura correcta para intersectar el cable
		var obs_bottom = obs_pos.y - obs_size.y/2
		var obs_top = obs_pos.y + obs_size.y/2
		var cable_min_height = min(start_pos.y, end_pos.y)
		var cable_max_height = max(start_pos.y, end_pos.y)
		
		# Si el obstáculo no está en el rango de altura del cable, ignorarlo
		if obs_top < cable_min_height or obs_bottom > cable_max_height:
			continue
		
		# Verificar intersección en 2D (X,Z) con el tamaño completo del obstáculo
		var cable_start_2d = Vector2(start_pos.x, start_pos.z)
		var cable_end_2d = Vector2(end_pos.x, end_pos.z)
		var obs_pos_2d = Vector2(obs_pos.x, obs_pos.z)
		var obs_size_2d = Vector2(obs_size.x, obs_size.z)
		
		if does_line_intersect_box_2d(cable_start_2d, cable_end_2d, obs_pos_2d, obs_size_2d):
			return true
	
	return false

# Función para verificar si una línea intersecta con un rectángulo en 2D
func does_line_intersect_box_2d(line_start: Vector2, line_end: Vector2, box_center: Vector2, box_size: Vector2) -> bool:
	# Convertir a coordenadas del rectángulo usando el tamaño completo
	var half_size_x = box_size.x * 0.5
	var half_size_z = box_size.y * 0.5
	var box_min = Vector2(box_center.x - half_size_x, box_center.y - half_size_z)
	var box_max = Vector2(box_center.x + half_size_x, box_center.y + half_size_z)
	
	# Verificar si algún extremo de la línea está dentro del rectángulo
	if is_point_in_rect(line_start, box_min, box_max) or is_point_in_rect(line_end, box_min, box_max):
		return true
	
	# Verificar intersección con cada lado del rectángulo
	var rect_lines = [
		[Vector2(box_min.x, box_min.y), Vector2(box_max.x, box_min.y)],  # Lado inferior
		[Vector2(box_max.x, box_min.y), Vector2(box_max.x, box_max.y)],  # Lado derecho
		[Vector2(box_max.x, box_max.y), Vector2(box_min.x, box_max.y)],  # Lado superior
		[Vector2(box_min.x, box_max.y), Vector2(box_min.x, box_min.y)]   # Lado izquierdo
	]
	
	for rect_line in rect_lines:
		if lines_intersect_2d_simple(line_start, line_end, rect_line[0], rect_line[1]):
			return true
	
	return false

# Verificar si un punto está dentro de un rectángulo
func is_point_in_rect(point: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	return point.x >= rect_min.x and point.x <= rect_max.x and point.y >= rect_min.y and point.y <= rect_max.y

# Función simple para verificar intersección de dos líneas 2D
func lines_intersect_2d_simple(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var denominator = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
	if abs(denominator) < 0.0001:
		return false  # Líneas paralelas
	
	var t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denominator
	var u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denominator
	
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0

# Función para verificar si una nueva conexión cruza con cables existentes
func would_connection_cross_existing_cables(tower1_pos: Vector3, tower2_pos: Vector3) -> bool:
	# Verificar cruces con cables principales de torres
	var new_start = tower1_pos + Vector3(0, 2.2, 0)
	var new_end = tower2_pos + Vector3(0, 2.2, 0)
	
	for connection in tower_connections:
		var existing_tower1 = connection[0]
		var existing_tower2 = connection[1]
		
		if not is_instance_valid(existing_tower1) or not is_instance_valid(existing_tower2):
			continue
		
		var existing_start = existing_tower1.global_position + Vector3(0, 2.2, 0)
		var existing_end = existing_tower2.global_position + Vector3(0, 2.2, 0)
		
		if lines_intersect_3d(new_start, new_end, existing_start, existing_end):
			return true
	
	# Verificar cruces con conexiones automáticas existentes
	for auto_conn in auto_connections:
		var auto_tower1 = auto_conn[0]
		var auto_tower2 = auto_conn[1]
		
		if not is_instance_valid(auto_tower1) or not is_instance_valid(auto_tower2):
			continue
		
		var auto_start = auto_tower1.global_position + Vector3(0, 2.2, 0)
		var auto_end = auto_tower2.global_position + Vector3(0, 2.2, 0)
		
		if lines_intersect_3d(new_start, new_end, auto_start, auto_end):
			return true
	
	# NUEVA VALIDACIÓN: Verificar cruces con cables Torre→Poste existentes
	for pole_conn in pole_connections:
		var tower_pos = pole_conn[0]
		var pole_pos = pole_conn[1]
		
		var existing_start = tower_pos + Vector3(0, 2.2, 0)  # Torres a 2.2m
		var existing_end = pole_pos + Vector3(0, 1.3, 0)   # Postes a 1.3m
		
		if lines_intersect_3d(new_start, new_end, existing_start, existing_end):
			return true
	
	# NUEVA VALIDACIÓN: Verificar cruces con cables Poste→Poste existentes
	for secondary_conn in secondary_pole_connections:
		var primary_pos = secondary_conn[0]
		var secondary_pos = secondary_conn[1]
		
		var existing_start = primary_pos + Vector3(0, 1.3, 0)
		var existing_end = secondary_pos + Vector3(0, 1.3, 0)
		
		if lines_intersect_3d(new_start, new_end, existing_start, existing_end):
			return true
	
	return false

# Función para verificar si una conexión de poste cruza con cables existentes
func would_pole_connection_cross_existing_cables(pole1_pos: Vector3, pole2_pos: Vector3) -> bool:
	# Altura de conexión de postes (1.3m)
	var new_start = pole1_pos + Vector3(0, 1.3, 0)
	var new_end = pole2_pos + Vector3(0, 1.3, 0)
	
	# Verificar cruces con cables principales de torres
	for connection in tower_connections:
		var existing_tower1 = connection[0]
		var existing_tower2 = connection[1]
		
		if not is_instance_valid(existing_tower1) or not is_instance_valid(existing_tower2):
			continue
		
		var existing_start = existing_tower1.global_position + Vector3(0, 2.2, 0)
		var existing_end = existing_tower2.global_position + Vector3(0, 2.2, 0)
		
		if lines_intersect_3d(new_start, new_end, existing_start, existing_end):
			return true
	
	# Verificar cruces con conexiones automáticas existentes
	for auto_conn in auto_connections:
		var auto_tower1 = auto_conn[0]
		var auto_tower2 = auto_conn[1]
		
		if not is_instance_valid(auto_tower1) or not is_instance_valid(auto_tower2):
			continue
		
		var auto_start = auto_tower1.global_position + Vector3(0, 2.2, 0)
		var auto_end = auto_tower2.global_position + Vector3(0, 2.2, 0)
		
		if lines_intersect_3d(new_start, new_end, auto_start, auto_end):
			return true
	
	# Verificar cruces con cables Torre→Poste existentes
	for pole_conn in pole_connections:
		var tower_pos = pole_conn[0]
		var pole_pos = pole_conn[1]
		
		var existing_start = tower_pos + Vector3(0, 2.2, 0)  # Torres a 2.2m
		var existing_end = pole_pos + Vector3(0, 1.3, 0)   # Postes a 1.3m
		
		if lines_intersect_3d(new_start, new_end, existing_start, existing_end):
			return true
	
	# Verificar cruces con cables Poste→Poste existentes
	for secondary_conn in secondary_pole_connections:
		var primary_pos = secondary_conn[0]
		var secondary_pos = secondary_conn[1]
		
		var existing_start = primary_pos + Vector3(0, 1.3, 0)
		var existing_end = secondary_pos + Vector3(0, 1.3, 0)
		
		if lines_intersect_3d(new_start, new_end, existing_start, existing_end):
			return true
	
	return false

# Función para verificar si dos líneas se cruzan en 3D (proyectadas en el plano XZ)
func lines_intersect_3d(line1_start: Vector3, line1_end: Vector3, line2_start: Vector3, line2_end: Vector3) -> bool:
	# Proyectar las líneas al plano XZ para simplificar el cálculo
	var p1 = Vector2(line1_start.x, line1_start.z)
	var p2 = Vector2(line1_end.x, line1_end.z)
	var p3 = Vector2(line2_start.x, line2_start.z)
	var p4 = Vector2(line2_end.x, line2_end.z)
	
	return lines_intersect_2d(p1, p2, p3, p4)

# Función para verificar si una conexión cruza con obstáculos
func would_connection_cross_obstacles(tower1_pos: Vector3, tower2_pos: Vector3) -> bool:
	# Obtener todos los obstáculos
	var all_obstacles = []
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleHigh"))
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleLow"))
	
	# Buscar en grupo general "obstacles" también
	var general_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obs in general_obstacles:
		all_obstacles.append(obs)
	
	# Buscar recursivamente por nombre (fallback)
	var recursive_obstacles = []
	_find_obstacles_recursive(get_tree().root, recursive_obstacles)
	all_obstacles.append_array(recursive_obstacles)
	
	# Posiciones del cable (a 2.2m de altura sobre cada torre)
	var start_pos = tower1_pos + Vector3(0, 2.2, 0)
	var end_pos = tower2_pos + Vector3(0, 2.2, 0)
	
	# Proyectar la línea del cable al plano XZ
	var cable_start_2d = Vector2(start_pos.x, start_pos.z)
	var cable_end_2d = Vector2(end_pos.x, end_pos.z)
	
	for obstacle in all_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		# Obtener la posición del obstáculo
		var obstacle_pos = obstacle.global_position
		var obstacle_pos_2d = Vector2(obstacle_pos.x, obstacle_pos.z)
		
		# Verificar si el cable pasa cerca del obstáculo (usar radio mayor)
		var distance_to_line = distance_point_to_line_2d(obstacle_pos_2d, cable_start_2d, cable_end_2d)
		
		if distance_to_line < 3.0:  # Radio mayor de obstrucción
			return true
	
	return false

# Función auxiliar para calcular distancia de un punto a una línea en 2D
func distance_point_to_line_2d(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	
	if line_vec.length_squared() == 0:
		return point_vec.length()  # La línea es un punto
	
	var t = point_vec.dot(line_vec) / line_vec.length_squared()
	t = clamp(t, 0.0, 1.0)  # Limitar al segmento de línea
	
	var closest_point = line_start + t * line_vec
	return point.distance_to(closest_point)

# Función auxiliar para verificar intersección de líneas en 2D
func lines_intersect_2d(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
	if abs(denom) < 0.0001:
		return false # Las líneas son paralelas
	
	var t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom
	var u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denom
	
	# Margen más razonable para detección de cruces
	var margin = 0.02  # Ni muy estricto ni muy permisivo
	return t > margin and t < (1.0 - margin) and u > margin and u < (1.0 - margin)

func try_place_tower():
	if not tower_preview or not is_instance_valid(tower_preview) or not tower_preview.visible:
		return
	
	var target_pos = tower_preview.position
	
	if is_position_valid(target_pos):
		place_tower_at_position(target_pos)

func place_tower_at_position(pos: Vector3):
	# Usar solo la escena configurada en el inspector
	if not tower_scene:
		print("Error: No hay escena de torre configurada en Tower Scene")
		return
	
	# Instanciar la escena directamente
	var new_tower = tower_scene.instantiate()
	if not new_tower:
		print("Error: No se pudo instanciar la escena")
		return
	
	new_tower.position = pos
	
	# Agregar al árbol ANTES de orientar
	add_child(new_tower)
	
	# Orientar la torre perpendicular a la línea de creación en el eje X
	if placed_towers.size() > 0:
		var last_tower = placed_towers[-1]
		var direction = (pos - last_tower.position).normalized()
		# Calcular rotación para que el eje X sea perpendicular a la línea
		var angle = atan2(direction.x, direction.z)
		new_tower.rotation.y = angle
	elif start_tower:
		var direction = (pos - start_tower.global_position).normalized()
		var angle = atan2(direction.x, direction.z)
		new_tower.rotation.y = angle
	
	placed_towers.append(new_tower)
	
	# Crear conexión en cadena: conectar siempre a la torre anterior
	var connection_target = null
	if placed_towers.size() > 1:
		connection_target = placed_towers[-2]  # La torre anterior
	elif start_tower:
		connection_target = start_tower  # Conectar la primera torre a la torre inicial
	
	if connection_target:
		create_connection(connection_target, new_tower)
	
	# Verificar si se puede conectar a la torre final
	check_connection_to_end_tower(new_tower)
	
	place_poles_around_tower(pos)
	
	# Crear conexiones automáticas por proximidad
	create_auto_connections(new_tower)

func check_connection_to_end_tower(new_tower: Node3D):
	# Verificar si la nueva torre puede conectarse a la torre final
	if not end_tower:
		return
	
	var distance_to_end = new_tower.position.distance_to(end_tower.global_position)
	if distance_to_end <= placement_range:
		# Conectar a la torre final y completar el nivel
		create_connection(new_tower, end_tower)
		complete_level()

func complete_level():
	# Completar el nivel
	level_completed = true
	print("¡Nivel completado! Torres conectadas desde el inicio hasta el final.")
	
	# Llamar al método de la torre final si existe
	if end_tower and end_tower.has_method("level_completed"):
		end_tower.level_completed()
	
	# Ocultar preview y rango ya que no se pueden colocar más torres
	if tower_preview:
		tower_preview.visible = false
	hide_range_indicator()

# Función para crear una conexión visual entre dos torres
func create_connection(tower1: Node3D, tower2: Node3D):
	# Agregar la conexión al array
	tower_connections.append([tower1, tower2])
	
	# Crear cable curvado usando múltiples segmentos
	var cable_container = Node3D.new()
	
	# Calcular posiciones de inicio y fin (a 2.2m de altura)
	var start_pos = tower1.global_position + Vector3(0, 2.2, 0)
	var end_pos = tower2.global_position + Vector3(0, 2.2, 0)
	var distance = start_pos.distance_to(end_pos)
	
	# Calcular la curvatura del cable (catenaria simulada)
	var cable_sag = distance * 0.12  # 12% de combadura por la gravedad
	
	# Crear múltiples segmentos para simular el cable curvado
	var num_segments = 12
	var cable_points = []
	
	# Generar puntos de la catenaria
	for i in range(num_segments + 1):
		var t = float(i) / float(num_segments)
		
		# Interpolación lineal entre start y end
		var point = start_pos.lerp(end_pos, t)
		
		# Aplicar curvatura parabólica (simula la gravedad)
		var curve_factor = 4.0 * t * (1.0 - t)  # Máximo en t=0.5
		point.y -= cable_sag * curve_factor
		
		cable_points.append(point)
	
	# IMPORTANTE: Agregar el contenedor al árbol ANTES de crear los segmentos
	add_child(cable_container)
	
	# Crear segmentos del cable entre cada par de puntos
	for i in range(cable_points.size() - 1):
		var segment_start = cable_points[i]
		var segment_end = cable_points[i + 1]
		var segment_length = segment_start.distance_to(segment_end)
		var segment_center = (segment_start + segment_end) / 2.0
		
		# Crear cilindro para este segmento
		var segment_mesh = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.03  # Cable más delgado y realista
		cylinder.bottom_radius = 0.03
		cylinder.height = segment_length
		
		segment_mesh.mesh = cylinder
		segment_mesh.position = segment_center
		
		# Material para el cable - realista
		var cable_material = StandardMaterial3D.new()
		cable_material.albedo_color = Color(0.15, 0.15, 0.15)  # Gris muy oscuro
		cable_material.metallic = 0.8
		cable_material.roughness = 0.4
		cable_material.rim_enabled = true
		cable_material.rim = 0.2
		segment_mesh.material_override = cable_material
		
		# Agregar al contenedor ANTES de orientar
		cable_container.add_child(segment_mesh)
		
		# Orientar el segmento usando look_at_from_position (más seguro)
		var direction = (segment_end - segment_start).normalized()
		if direction.length() > 0:
			var target_pos = segment_center + direction
			segment_mesh.look_at_from_position(segment_center, target_pos, Vector3.UP)
			segment_mesh.rotate_object_local(Vector3.RIGHT, PI/2)
	
	connection_lines.append(cable_container)
	
func place_poles_around_tower(tower_pos: Vector3):
	# Usar solo la escena configurada en el inspector
	if not pole_scene:
		print("Error: No hay escena de poste configurada en Pole Scene")
		return
	
	# USAR las posiciones exactas del preview que ya están validadas
	if current_pole_positions.is_empty():
		print("Error: No hay posiciones de postes guardadas del preview")
		return
	
	# PASO 1: Colocar TODOS los postes primarios y crear cables Torre → Poste1
	var primary_poles = []  # Guardar referencias a los postes primarios
	for i in range(current_pole_positions.size()):
		var pole_pos = current_pole_positions[i]
		
		# Crear poste primario
		var pole = pole_scene.instantiate()
		if not pole:
			print("Error: No se pudo crear poste primario ", i)
			continue
		
		add_child(pole)
		pole.position = pole_pos
		pole.rotation.y = randf() * TAU
		
		# Cable: Torre → Poste Primario (al punto de conexión del poste)
		var pole_connection_point = pole_pos + Vector3(0, 1.3, 0)  # Punto de conexión del poste a 1.3m
		create_thin_cable(tower_pos, pole_connection_point)
		
		pole_connections.append([tower_pos, pole_pos])
		placed_poles.append(pole)
		primary_poles.append(pole)  # Guardar referencia
	
	# PASO 2: Si están habilitados, colocar TODOS los postes secundarios
	if enable_secondary_poles and not current_secondary_pole_positions.is_empty():
		# Asegurar que no intentamos acceder más allá del tamaño de cualquiera de los arrays
		var max_secondary = min(current_secondary_pole_positions.size(), current_pole_positions.size())
		
		# Colocar todos los postes secundarios
		for i in range(max_secondary):
			var secondary_pos = current_secondary_pole_positions[i]
			var primary_pos = current_pole_positions[i]
			
			# Crear poste secundario
			var secondary_pole = pole_scene.instantiate()
			if not secondary_pole:
				print("Error: No se pudo crear poste secundario ", i)
				continue
			
			add_child(secondary_pole)
			secondary_pole.position = secondary_pos
			secondary_pole.rotation.y = randf() * TAU
			
			# Cable: Poste Primario → Poste Secundario (conexión entre postes a menor altura)
			var primary_connection_point = primary_pos + Vector3(0, 1.3, 0)  # Punto de conexión del poste primario a 1.3m
			var secondary_connection_point = secondary_pos + Vector3(0, 1.3, 0)  # Punto de conexión del poste secundario a 1.3m
			create_pole_to_pole_cable(primary_connection_point, secondary_connection_point)
			
			secondary_pole_connections.append([primary_pos, secondary_pos])
			placed_poles.append(secondary_pole)

func create_auto_connections(new_tower: Node3D):
	var new_pos = new_tower.global_position
	
	# Conectar con otras torres cercanas
	for existing_tower in placed_towers:
		if existing_tower == new_tower:
			continue
			
		var distance = new_pos.distance_to(existing_tower.global_position)
		
		if distance <= auto_connection_distance:
			# Verificar que no existe ya esta conexión
			var connection_exists = false
			for conn in auto_connections:
				if (conn[0] == new_tower and conn[1] == existing_tower) or \
				   (conn[0] == existing_tower and conn[1] == new_tower):
					connection_exists = true
					break
			
			if not connection_exists:
				# Verificar que no cruza con cables existentes
				if not would_connection_cross_existing_cables(new_pos, existing_tower.global_position):
					# NUEVO: Verificar que no cruza con obstáculos
					if not would_connection_cross_obstacles(new_pos, existing_tower.global_position):
						create_connection(new_tower, existing_tower)
						auto_connections.append([new_tower, existing_tower])

func create_thin_cable(start_point: Vector3, end_point: Vector3):
	# Crear cable fino entre dos puntos de conexión exactos
	var cable_container = Node3D.new()
	add_child(cable_container)
	
	# Usar directamente los puntos de conexión que se pasan como parámetros
	var start_pos = start_point
	var end_pos = end_point
	
	# Si es un cable desde torre, usar altura de torre
	if start_point.y < 1.5:  # Probablemente es posición de torre (al nivel del suelo)
		start_pos = start_point + Vector3(0, 2.2, 0)  # Torre a su altura + 2.2m
	
	var distance = start_pos.distance_to(end_pos)
	
	# Menos combadura para cables cortos
	var cable_sag = distance * 0.08  # 8% de combadura (menos que los cables principales)
	
	# Menos segmentos para cables más simples
	var num_segments = 6
	for i in range(num_segments):
		var t = float(i) / float(num_segments - 1)
		var linear_pos = start_pos.lerp(end_pos, t)
		
		# Aplicar combadura parabólica
		var sag_offset = 4.0 * cable_sag * t * (1.0 - t)
		var current_pos = linear_pos - Vector3(0, sag_offset, 0)
		
		var next_t = float(i + 1) / float(num_segments - 1)
		if next_t > 1.0:
			next_t = 1.0
		var next_linear = start_pos.lerp(end_pos, next_t)
		var next_sag = 4.0 * cable_sag * next_t * (1.0 - next_t)
		var next_pos = next_linear - Vector3(0, next_sag, 0)
		
		var segment_mesh = MeshInstance3D.new()
		var cylinder_mesh = CylinderMesh.new()
		cylinder_mesh.top_radius = 0.02  # Cable muy fino (0.02 vs 0.05 de cables principales)
		cylinder_mesh.bottom_radius = 0.02
		cylinder_mesh.height = current_pos.distance_to(next_pos)
		
		segment_mesh.mesh = cylinder_mesh
		
		# Material del cable fino (más oscuro/menos visible)
		var cable_material = StandardMaterial3D.new()
		cable_material.albedo_color = Color(0.3, 0.3, 0.3)  # Gris oscuro
		cable_material.metallic = 0.8
		cable_material.roughness = 0.3
		segment_mesh.material_override = cable_material
		
		cable_container.add_child(segment_mesh)
		
		var segment_center = (current_pos + next_pos) * 0.5
		segment_mesh.position = segment_center
		
		if current_pos.distance_to(next_pos) > 0.001:
			var direction = (next_pos - current_pos).normalized()
			var target_pos = segment_center + direction
			segment_mesh.look_at_from_position(segment_center, target_pos, Vector3.UP)
			segment_mesh.rotate_object_local(Vector3.RIGHT, PI/2)
	
	# Añadir a la lista de conexiones para poder limpiarlas después
	connection_lines.append(cable_container)

# Función específica para cables entre postes (sin altura automática de torre)
func create_pole_to_pole_cable(start_point: Vector3, end_point: Vector3):
	# Crear cable fino entre dos postes
	var cable_container = Node3D.new()
	add_child(cable_container)
	
	# Usar directamente los puntos de conexión entre postes
	var start_pos = start_point
	var end_pos = end_point
	var distance = start_pos.distance_to(end_pos)
	
	# Menos combadura para cables cortos entre postes
	var cable_sag = distance * 0.05  # 5% de combadura (muy poco para cables entre postes)
	
	# Menos segmentos para cables más simples
	var num_segments = 4  # Cables entre postes más simples
	for i in range(num_segments):
		var t = float(i) / float(num_segments - 1)
		var linear_pos = start_pos.lerp(end_pos, t)
		
		# Aplicar combadura parabólica mínima
		var sag_offset = 4.0 * cable_sag * t * (1.0 - t)
		var current_pos = linear_pos - Vector3(0, sag_offset, 0)
		
		var next_t = float(i + 1) / float(num_segments - 1)
		if next_t > 1.0:
			next_t = 1.0
		var next_linear = start_pos.lerp(end_pos, next_t)
		var next_sag = 4.0 * cable_sag * next_t * (1.0 - next_t)
		var next_pos = next_linear - Vector3(0, next_sag, 0)
		
		var segment_mesh = MeshInstance3D.new()
		var cylinder_mesh = CylinderMesh.new()
		cylinder_mesh.top_radius = 0.015  # Cable aún más fino para conexiones entre postes
		cylinder_mesh.bottom_radius = 0.015
		cylinder_mesh.height = current_pos.distance_to(next_pos)
		
		segment_mesh.mesh = cylinder_mesh
		
		# Material del cable entre postes (más fino y discreto)
		var cable_material = StandardMaterial3D.new()
		cable_material.albedo_color = Color(0.4, 0.4, 0.4)  # Gris más claro
		cable_material.metallic = 0.6
		cable_material.roughness = 0.4
		segment_mesh.material_override = cable_material
		
		cable_container.add_child(segment_mesh)
		
		var segment_center = (current_pos + next_pos) * 0.5
		segment_mesh.position = segment_center
		
		if current_pos.distance_to(next_pos) > 0.001:
			var direction = (next_pos - current_pos).normalized()
			var target_pos = segment_center + direction
			segment_mesh.look_at_from_position(segment_center, target_pos, Vector3.UP)
			segment_mesh.rotate_object_local(Vector3.RIGHT, PI/2)
	
	# Añadir a la lista de conexiones para poder limpiarlas después
	connection_lines.append(cable_container)

# Función para limpiar todas las conexiones (útil para reset del juego)
func clear_all_connections():
	for line_node in connection_lines:
		if is_instance_valid(line_node):
			line_node.queue_free()
	
	connection_lines.clear()
	tower_connections.clear()
	pole_connections.clear()  # ¡NUEVO! Limpiar también conexiones de postes
	secondary_pole_connections.clear()  # ¡NUEVO! Limpiar conexiones de postes secundarios
	auto_connections.clear()  # ¡NUEVO! Limpiar también conexiones automáticas
	placed_poles.clear()  # ¡NUEVO! Limpiar lista de postes colocados
