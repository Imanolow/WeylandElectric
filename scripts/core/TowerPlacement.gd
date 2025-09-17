extends Node3D
class_name TowerPlacer_New

# ============================================================================
# TOWER PLACEMENT SYSTEM - CLEAN ARCHITECTURE
# ============================================================================
# Maneja colocación de HighVoltageTower + SmallPost con validaciones estrictas
# Torre -> Poste_a -> Poste_b (2-5 postes 'a' por torre, 1 'b' por cada 'a')
# ============================================================================

# EXPORTED VARIABLES - Configuración desde inspector
@export_group("Scene References")
@export var tower_scene: PackedScene
@export var pole_scene: PackedScene

@export_group("Placement Settings") 
@export var placement_range: float = 10.0
@export var min_tower_distance: float = 5.0
@export var pole_count_min: int = 2
@export var pole_count_max: int = 5
@export var pole_radius_min: float = 1.5
@export var pole_radius_max: float = 3.0
@export var secondary_pole_distance_min: float = 2.0
@export var secondary_pole_distance_max: float = 3.5
@export var enable_secondary_poles: bool = true

@export_group("Physics Settings")
@export var ground_layer: int = 1
@export var obstacle_layer: int = 2

# CORE SYSTEMS
var camera: Camera3D
var placed_towers: Array[Node3D] = []
var placed_poles_a: Array[Node3D] = []
var placed_poles_b: Array[Node3D] = []

# PREVIEW SYSTEM
var tower_preview: Node3D
var poles_a_preview: Array[Node3D] = []
var poles_b_preview: Array[Node3D] = []
var preview_material_valid: StandardMaterial3D
var preview_material_invalid: StandardMaterial3D

# LAYOUT DATA - Mantener posiciones relativas fijas
var current_pole_layout: Array[Vector3] = []  # Posiciones relativas a torre
var current_pole_b_layout: Array[Vector3] = [] # Posiciones relativas a postes_a
var last_layout_position: Vector3 = Vector3.INF  # Cache para evitar regenerar layout
var preview_layout_generated: bool = false  # Si ya se generó layout para este preview

# SPECIAL TOWERS & BOUNDS
var start_tower: Node3D = null
var end_tower: Node3D = null
var level_bounds: Area3D = null
var level_completed: bool = false

# CONNECTION SYSTEM
var tower_connections: Array = []
var pole_connections: Array = []
var connection_lines: Array[Node3D] = []
var placed_cables: Array[Node3D] = []

# PLACEMENT MODE CONTROL
var placement_mode_active: bool = false

# RANGE INDICATOR SYSTEM
var range_indicator: Node3D
var range_indicator_points: Array[MeshInstance3D] = []

# CABLE PREVIEW SYSTEM
var cable_preview_lines: Array[MeshInstance3D] = []

# ============================================================================
# INITIALIZATION - Setup completo del sistema
# ============================================================================
func _ready():
	setup_camera()
	setup_preview_materials()
	find_special_towers()
	find_level_bounds()
	create_persistent_preview_instances()
	create_range_indicator()
	setup_input_handlers()


func setup_camera():
	"""Encuentra la cámara principal del jugador"""
	camera = get_viewport().get_camera_3d()
	if not camera:
		push_error("[TowerPlacer] No se encontró Camera3D en la escena")

func setup_preview_materials():
	"""Crea materiales para preview válido/inválido"""
	# Material válido - Verde translúcido
	preview_material_valid = StandardMaterial3D.new()
	preview_material_valid.albedo_color = Color(0.0, 1.0, 0.0, 0.5)
	preview_material_valid.flags_transparent = true
	preview_material_valid.no_depth_test = true
	
	# Material inválido - Rojo translúcido  
	preview_material_invalid = StandardMaterial3D.new()
	preview_material_invalid.albedo_color = Color(1.0, 0.0, 0.0, 0.5)
	preview_material_invalid.flags_transparent = true
	preview_material_invalid.no_depth_test = true

func find_special_towers():
	"""Busca torres especiales TowerBegin y TowerEnd"""
	var scene_root = get_tree().current_scene
	
	# Buscar nodos con nombres específicos
	start_tower = scene_root.find_child("TowerBegin", true, false)
	end_tower = scene_root.find_child("TowerEnd", true, false)
	
	# Torres encontradas (sin logging)

func find_level_bounds():
	"""Busca el sistema de límites del nivel"""
	var scene_root = get_tree().current_scene
	level_bounds = scene_root.find_child("LevelBounds", true, false) as Area3D
	
	# Level bounds encontrado (sin logging)

func create_persistent_preview_instances():
	"""Crea instancias persistentes para el preview que se reutilizan"""
	if not tower_scene or not pole_scene:
		push_error("[TowerPlacer] Escenas no configuradas - no se puede crear preview")
		return
	
	# Crear torre de preview una sola vez
	tower_preview = tower_scene.instantiate()
	add_child(tower_preview)
	tower_preview.visible = false
	
	# Deshabilitar colisiones para el preview de torre
	var tower_static_body = tower_preview.find_child("StaticBody3D", true, false)
	if tower_static_body and tower_static_body is CollisionObject3D:
		tower_static_body.set_collision_layer(0)
		tower_static_body.set_collision_mask(0)
	


func setup_input_handlers():
	"""Configura manejo de entrada del usuario"""
	# El sistema se activa automáticamente
	enable_placement_mode()

func create_range_indicator():
	"""Crea el contenedor para los puntos del indicador de rango"""
	range_indicator = Node3D.new()
	add_child(range_indicator)
	range_indicator.visible = false

func clear_range_indicator():
	"""Limpia todos los puntos del indicador de rango"""
	for point in range_indicator_points:
		if point and is_instance_valid(point):
			point.queue_free()
	range_indicator_points.clear()

func show_range_indicator():
	"""Muestra el indicador de rango según la situación"""
	if not range_indicator or not range_indicator.is_inside_tree():
		return
	
	clear_range_indicator()
	
	var center_pos: Vector3
	
	# Si no hay torres colocadas, mostrar rango desde TowerBegin
	if placed_towers.is_empty() and start_tower:
		center_pos = start_tower.global_position
		create_circle_points(center_pos, placement_range)
	
	# Si hay torres colocadas, mostrar rango desde la última torre
	elif not placed_towers.is_empty():
		var last_tower = placed_towers[-1]
		center_pos = last_tower.global_position
		create_circle_points(center_pos, placement_range)
	
	range_indicator.visible = true

func create_circle_points(center: Vector3, radius: float):
	"""Crea puntos alrededor del círculo que se adapten al terreno"""
	var num_points = 64  # Muchos puntos para que parezca continuo
	var angle_step = TAU / num_points
	
	for i in range(num_points):
		var angle = i * angle_step
		var circle_pos = Vector3(
			center.x + cos(angle) * radius,
			center.y,
			center.z + sin(angle) * radius
		)
		
		# Ajustar al terreno
		var ground_height = get_ground_height_at_position(circle_pos)
		if ground_height != Vector3.INF.y:
			circle_pos.y = ground_height + 0.05  # Muy cerca del terreno
			
			# Crear punto pequeño (esfera)
			var point_mesh = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.1  # Punto pequeño pero visible
			sphere.height = 0.2
			point_mesh.mesh = sphere
			
			# Material azul
			var material = StandardMaterial3D.new()
			material.flags_transparent = true
			material.flags_unshaded = true
			material.albedo_color = Color(0, 0, 1, 0.8)  # Azul visible
			material.no_depth_test = true
			point_mesh.material_override = material
			
			# Posicionar
			point_mesh.position = circle_pos
			
			# Agregar al range_indicator
			range_indicator.add_child(point_mesh)
			range_indicator_points.append(point_mesh)

func hide_range_indicator():
	"""Oculta el indicador de rango"""
	if range_indicator and is_instance_valid(range_indicator):
		range_indicator.visible = false
		clear_range_indicator()

# ============================================================================
# INPUT HANDLING - Manejo de entrada del usuario
# ============================================================================
func _input(event):
	"""Manejo principal de entrada del usuario"""
	if event is InputEventMouseMotion:
		update_preview_at_cursor()
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_tower_at_cursor()

# ============================================================================
# VALIDATION SYSTEM - Verificaciones estrictas de colocación
# ============================================================================
func is_valid_tower_position(pos: Vector3) -> bool:
	"""Valida si una posición es válida para torre"""
	if not is_within_level_bounds(pos):
		return false
	
	# Torres no pueden tocar ObstacleHigh ni ObstacleLow
	if has_obstacle_collision(pos, "ObstacleHigh"):
		return false
	
	if has_obstacle_collision(pos, "ObstacleLow"):
		return false
	
	if not is_on_valid_terrain(pos):
		return false
	
	if not has_minimum_distance_to_towers(pos):
		return false
	
	if not is_within_placement_range(pos):
		return false
	
	# Verificar que el cable principal no cruce obstáculos
	if not can_create_main_cable_to_position(pos):
		return false
	
	# Verificar que todos los cables torre->poste sean válidos
	if not can_create_pole_cables_from_position(pos):
		return false
	
	# Verificar que todas las posiciones de postes sean válidas (no en obstáculos)
	if not are_all_pole_positions_valid(pos):
		return false
	
	return true

func are_all_pole_positions_valid(tower_pos: Vector3) -> bool:
	"""Verifica que todas las posiciones de postes sean válidas (no en obstáculos)"""
	# Generar layout si es necesario para validación
	if current_pole_layout.is_empty():
		generate_pole_layout(tower_pos)
	
	# Verificar postes 'a'
	var poles_a_positions = get_pole_positions_for_tower(tower_pos)
	for pole_pos in poles_a_positions:
		if has_obstacle_collision(pole_pos, "ObstacleHigh") or has_obstacle_collision(pole_pos, "ObstacleLow"):
			return false
		if not is_on_valid_terrain(pole_pos):
			return false
	
	# Verificar postes 'b'
	var poles_b_positions = get_pole_b_positions_for_poles_a(tower_pos)
	for pole_pos in poles_b_positions:
		if has_obstacle_collision(pole_pos, "ObstacleHigh") or has_obstacle_collision(pole_pos, "ObstacleLow"):
			return false
		if not is_on_valid_terrain(pole_pos):
			return false
	
	return true

func is_position_blocked_by_obstacles(pos: Vector3) -> bool:
	"""COPIADO EXACTAMENTE DE TowerPlace.gd - is_position_valid (invertir lógica)"""
	# 0. Verificar que esté dentro de los límites del nivel
	if not is_position_inside_level_bounds(pos):
		return true  # Bloqueado si está fuera de límites
	
	# 1. Si el nivel ya se completó, bloquear más torres
	if level_completed:
		return true  # Bloqueado si nivel completado
	
	# 2. Si no hay torres colocadas, verificar rango desde torre inicial
	if placed_towers.is_empty():
		if start_tower:
			var distance_to_start = start_tower.global_position.distance_to(pos)
			var start_range = 10.0  # Mismo rango que las torres normales
			if distance_to_start > start_range:
				return true  # Bloqueado si está fuera de rango
		# Si no hay torre inicial, permitir colocar en cualquier lugar
	
	# 3. Verificar distancia mínima
	if is_too_close_to_existing_tower(pos):
		return true  # Bloqueado si muy cerca
	
	# 4. Verificar obstáculos en el cable (solo si hay torres previas)
	if has_obstacle_at_tower_position(pos):
		return true  # Bloqueado si cable cruza obstáculos
	
	# 5. Verificar si hay ObstacleLow directamente donde se colocaría la torre
	if has_low_obstacle_at_position(pos):
		return true  # Bloqueado si hay obstáculo bajo
	
	# 6. Verificar rango (solo si hay torres previas)
	if not placed_towers.is_empty():
		var last_tower = placed_towers[-1]
		var distance_to_last = last_tower.position.distance_to(pos)
		
		if distance_to_last > placement_range:
			return true  # Bloqueado si fuera de rango
		
		# 7. Verificar cruce con cables existentes
		if would_connection_cross_existing_cables(last_tower.position, pos):
			return true  # Bloqueado si cruza cables existentes
	
	# 8. NUEVA VALIDACIÓN: Verificar que TODOS los postes del preview se puedan colocar
	# NO regenerar - usar las posiciones ya calculadas en el preview
	if current_pole_layout.is_empty():
		return true  # Bloqueado si no hay postes primarios en el preview
	
	# 9. VALIDAR QUE TODOS LOS POSTES_A NO ESTÉN EN OBSTÁCULOS
	var poles_a_positions = get_pole_positions_for_tower(pos)
	for pole_a_pos in poles_a_positions:
		if is_pole_blocked_by_obstacles(pole_a_pos):
			return true  # Bloqueado si algún poste_a está en obstáculo
		
		# 9.1. VALIDAR QUE EL CABLE TORRE→POSTE_A NO CRUCE ObstacleHigh
		if would_cable_cross_high_obstacles(pos, pole_a_pos):
			return true  # Bloqueado si cable torre→poste_a cruza obstáculo alto
	
	# 10. Si los postes secundarios están habilitados, TODOS deben poder colocarse
	if enable_secondary_poles and not current_pole_b_layout.is_empty():
		var poles_b_positions = get_pole_b_positions_for_poles_a(pos)
		for pole_b_pos in poles_b_positions:
			if pole_b_pos == Vector3.INF or is_pole_blocked_by_obstacles(pole_b_pos):
				return true  # Bloqueado si algún poste_b no se puede colocar o está en obstáculo
	
	return false  # NO bloqueado = posición válida

func can_create_main_cable_to_position(pos: Vector3) -> bool:
	"""Verifica si se puede crear el cable principal hacia esta posición"""
	var source_pos: Vector3
	
	# Si hay torres colocadas, conectar desde la última
	if not placed_towers.is_empty():
		source_pos = placed_towers[-1].global_position
	# Si no hay torres pero hay TowerBegin, conectar desde ella
	elif start_tower:
		source_pos = start_tower.global_position
	else:
		return true  # Sin fuente, no hay cable que validar
	
	# Verificar si el cable cruza obstáculos
	return not would_cable_cross_obstacles(source_pos, pos)

func can_create_pole_cables_from_position(pos: Vector3) -> bool:
	"""Verifica si se pueden crear todos los cables torre->postes desde esta posición"""
	# Generar layout si es necesario para validación
	if current_pole_layout.is_empty():
		generate_pole_layout(pos)
	
	# Obtener posiciones de postes con altura de terreno
	var poles_a_positions = get_pole_positions_for_tower(pos)
	var poles_b_positions = get_pole_b_positions_for_poles_a(pos)
	
	# Verificar cables Torre->Poste_a
	for pole_a_pos in poles_a_positions:
		if would_cable_cross_obstacles(pos, pole_a_pos):
			return false
	
	# Verificar cables Poste_a->Poste_b
	for i in range(poles_a_positions.size()):
		if i < poles_b_positions.size():
			var pole_a_pos = poles_a_positions[i]
			var pole_b_pos = poles_b_positions[i]
			if would_pole_cable_cross_obstacles(pole_a_pos, pole_b_pos):
				return false
	
	return true

func is_within_placement_range(pos: Vector3) -> bool:
	"""Verifica si la posición está dentro del rango de colocación"""
	# Pequeño margen de tolerancia para evitar problemas de precisión flotante
	var tolerance = 0.01
	
	# Si no hay torres colocadas, verificar rango desde TowerBegin
	if placed_towers.is_empty():
		if start_tower:
			var distance_to_start = pos.distance_to(start_tower.global_position)
			return distance_to_start <= (placement_range + tolerance)
		else:
			return true  # Sin torre inicial, permitir colocación en cualquier lugar
	
	# Si hay torres colocadas, verificar rango desde la última torre
	var last_tower = placed_towers[-1]
	var distance_to_last = pos.distance_to(last_tower.global_position)
	return distance_to_last <= (placement_range + tolerance)

# ============================================================================
# CABLE VALIDATION SYSTEM - Validación de cruces de cables con obstáculos
# ============================================================================
func would_cable_cross_obstacles(start_pos: Vector3, end_pos: Vector3) -> bool:
	"""Verifica si un cable entre dos puntos cruza con ObstacleHigh"""
	var obstacles = get_tree().get_nodes_in_group("ObstacleHigh")
	
	# Posiciones del cable con altura de conexión
	var cable_start = Vector3(start_pos.x, start_pos.y + 2.2, start_pos.z)  # Torre a 2.2m
	var cable_end = Vector3(end_pos.x, end_pos.y + 2.2, end_pos.z)
	
	# Proyectar al plano XZ para verificar intersección
	var cable_start_2d = Vector2(cable_start.x, cable_start.z)
	var cable_end_2d = Vector2(cable_end.x, cable_end.z)
	
	for obstacle in obstacles:
		if _does_line_intersect_obstacle_2d(cable_start_2d, cable_end_2d, obstacle):
			return true
	
	return false

func would_pole_cable_cross_obstacles(start_pos: Vector3, end_pos: Vector3) -> bool:
	"""Verifica si un cable entre postes cruza con ObstacleHigh"""
	var obstacles = get_tree().get_nodes_in_group("ObstacleHigh")
	
	# Posiciones del cable con altura de postes
	var cable_start = Vector3(start_pos.x, start_pos.y + 1.3, start_pos.z)  # Poste a 1.3m
	var cable_end = Vector3(end_pos.x, end_pos.y + 1.3, end_pos.z)
	
	# Proyectar al plano XZ para verificar intersección
	var cable_start_2d = Vector2(cable_start.x, cable_start.z)
	var cable_end_2d = Vector2(cable_end.x, cable_end.z)
	
	for obstacle in obstacles:
		if _does_line_intersect_obstacle_2d(cable_start_2d, cable_end_2d, obstacle):
			return true
	
	return false

func _does_line_intersect_obstacle_2d(line_start: Vector2, line_end: Vector2, obstacle: Node) -> bool:
	"""Verifica si una línea 2D intersecta con la proyección de un obstáculo"""
	if not obstacle is StaticBody3D:
		return false
	
	# Buscar CollisionShape3D y MeshInstance3D
	var collision_shape = null
	for child in obstacle.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return false
	
	# Obtener transform del obstáculo
	var obstacle_transform = obstacle.global_transform * collision_shape.transform
	var obstacle_pos = obstacle_transform.origin
	
	# Manejar BoxShape3D
	if collision_shape.shape is BoxShape3D:
		var box_size = collision_shape.shape.size
		var box_center_2d = Vector2(obstacle_pos.x, obstacle_pos.z)
		var box_size_2d = Vector2(box_size.x, box_size.z)
		
		return _line_intersects_box_2d(line_start, line_end, box_center_2d, box_size_2d)
	
	return false

func _line_intersects_box_2d(line_start: Vector2, line_end: Vector2, box_center: Vector2, box_size: Vector2) -> bool:
	"""Verifica si una línea intersecta con un rectángulo 2D"""
	var half_size = box_size * 0.5
	var box_min = box_center - half_size
	var box_max = box_center + half_size
	
	# Verificar si los extremos están dentro del rectángulo
	if _point_in_rect_2d(line_start, box_min, box_max) or _point_in_rect_2d(line_end, box_min, box_max):
		return true
	
	# Verificar intersección con cada lado del rectángulo
	var rect_lines = [
		[Vector2(box_min.x, box_min.y), Vector2(box_max.x, box_min.y)],  # Inferior
		[Vector2(box_max.x, box_min.y), Vector2(box_max.x, box_max.y)],  # Derecha
		[Vector2(box_max.x, box_max.y), Vector2(box_min.x, box_max.y)],  # Superior
		[Vector2(box_min.x, box_max.y), Vector2(box_min.x, box_min.y)]   # Izquierda
	]
	
	for rect_line in rect_lines:
		if _lines_intersect_2d(line_start, line_end, rect_line[0], rect_line[1]):
			return true
	
	return false

func _point_in_rect_2d(point: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	"""Verifica si un punto está dentro de un rectángulo 2D"""
	return (point.x >= rect_min.x and point.x <= rect_max.x and 
			point.y >= rect_min.y and point.y <= rect_max.y)

func _lines_intersect_2d(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	"""Verifica si dos líneas 2D se intersectan"""
	var denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
	if abs(denom) < 0.0001:
		return false  # Líneas paralelas
	
	var t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom
	var u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denom
	
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0

func is_valid_pole_position(pos: Vector3, _pole_type: String = "a") -> bool:
	"""Valida si una posición es válida para poste"""
	if not is_within_level_bounds(pos):
		return false
	
	# Postes no pueden tocar ObstacleHigh (pero sí pueden estar cerca de ObstacleLow)
	if has_obstacle_collision(pos, "ObstacleHigh"):
		return false
	
	if not is_on_valid_terrain(pos):
		return false
	
	return true

func is_within_level_bounds(pos: Vector3) -> bool:
	"""Verifica si la posición está dentro de los límites del nivel"""
	if not level_bounds:
		return true  # Sin límites definidos, permitir todo
	
	# Obtener el CollisionShape3D hijo del Area3D
	var collision_shape = null
	for child in level_bounds.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return true  # Sin forma definida, permitir todo
	
	var shape = collision_shape.shape
	var bounds_transform = level_bounds.global_transform * collision_shape.transform
	
	# Convertir posición a espacio local del bounds
	var local_pos = bounds_transform.affine_inverse() * pos
	
	# Manejar BoxShape3D
	if shape is BoxShape3D:
		var box_size = shape.size
		return (abs(local_pos.x) <= box_size.x * 0.5 and 
				abs(local_pos.y) <= box_size.y * 0.5 and 
				abs(local_pos.z) <= box_size.z * 0.5)
	
	# Manejar ConvexPolygonShape3D (proyectar al plano XZ)
	elif shape is ConvexPolygonShape3D:
		var points = shape.points
		if points.size() < 3:
			return true
		
		# Proyectar puntos y posición al plano XZ
		var polygon_2d = []
		for point in points:
			var world_point = bounds_transform * point
			polygon_2d.append(Vector2(world_point.x, world_point.z))
		
		var pos_2d = Vector2(pos.x, pos.z)
		return _point_in_polygon(pos_2d, polygon_2d)
	
	return true

func _point_in_polygon(point: Vector2, polygon: Array) -> bool:
	"""Algoritmo de ray casting para determinar si un punto está dentro de un polígono"""
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

func has_obstacle_collision(pos: Vector3, obstacle_group: String) -> bool:
	"""Verifica colisión con obstáculos específicos"""
	var obstacles = []
	
	# Obtener obstáculos según el tipo
	if obstacle_group == "ObstacleHigh":
		obstacles = get_tree().get_nodes_in_group("ObstacleHigh")
	elif obstacle_group == "ObstacleLow":
		obstacles = get_tree().get_nodes_in_group("ObstacleLow")
	else:
		# Buscar todos los obstáculos
		obstacles.append_array(get_tree().get_nodes_in_group("ObstacleHigh"))
		obstacles.append_array(get_tree().get_nodes_in_group("ObstacleLow"))
	
	# Verificar colisión con cada obstáculo
	for obstacle in obstacles:
		if _is_position_inside_obstacle(pos, obstacle):
			return true
	
	return false

func _is_position_inside_obstacle(pos: Vector3, obstacle: Node) -> bool:
	"""Verifica si una posición está dentro de un obstáculo específico"""
	if not obstacle is StaticBody3D:
		return false
	
	# Buscar CollisionShape3D
	var collision_shape = null
	for child in obstacle.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return false
	
	var shape = collision_shape.shape
	var obstacle_transform = obstacle.global_transform * collision_shape.transform
	var local_pos = obstacle_transform.affine_inverse() * pos
	
	# Manejar BoxShape3D SIN margen - detección exacta
	if shape is BoxShape3D:
		var box_size = shape.size
		var is_inside = (abs(local_pos.x) <= box_size.x * 0.5 and 
						abs(local_pos.y) <= box_size.y * 0.5 and 
						abs(local_pos.z) <= box_size.z * 0.5)
		
		return is_inside
	
	# Expandir para otros tipos de formas según necesidad
	return false

func is_on_valid_terrain(pos: Vector3) -> bool:
	"""Verifica que hay terreno sólido debajo"""
	var ground_height = get_ground_height_at_position(pos)
	return ground_height != Vector3.INF.y

func get_ground_height_at_position(pos: Vector3) -> float:
	"""COPIADO DIRECTAMENTE DE TowerPlace.gd"""
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, pos.y + 50, pos.z),
		Vector3(pos.x, pos.y - 50, pos.z),
		1
	)
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position.y
	return pos.y

func has_minimum_distance_to_towers(pos: Vector3) -> bool:
	"""Verifica distancia mínima a otras torres"""
	for tower in placed_towers:
		if pos.distance_to(tower.global_position) < min_tower_distance:
			return false
	return true

# ============================================================================
# POLE LAYOUT GENERATION - Sistema de generación de layout de postes
# ============================================================================
func generate_pole_layout(tower_pos: Vector3):
	"""Genera layout único para cada posición de torre usando semilla consistente"""
	
	# Crear cuadrícula de 2x2 metros para posiciones consistentes
	var grid_x = int(tower_pos.x / 2.0)
	var grid_z = int(tower_pos.z / 2.0)
	var grid_pos = Vector3(grid_x * 2.0, 0, grid_z * 2.0)
	
	# Si ya tenemos layout para esta cuadrícula, no regenerar
	if grid_pos.distance_to(last_layout_position) < 1.0:
		return
	
	last_layout_position = grid_pos
	
	# Usar posición de cuadrícula como semilla para layout consistente pero único
	var layout_seed = hash(Vector2i(grid_x, grid_z))
	seed(layout_seed)
	
	current_pole_layout.clear()
	current_pole_b_layout.clear()
	
	# Cantidad aleatoria de postes (2-5) - controlada por código
	var pole_count = randi_range(2, 5)
	
	# Generar posiciones con ÁNGULO MÍNIMO entre postes (evitar que estén muy cerca)
	var min_angle_between_poles = deg_to_rad(30)  # 30 grados mínimo entre postes
	var used_angles: Array[float] = []
	
	for i in range(pole_count):
		var angle: float
		var attempts = 0
		
		# Buscar ángulo que respete distancia mínima con otros postes
		while attempts < 50:  # Máximo 50 intentos
			angle = randf() * 2.0 * PI
			
			# Verificar si está suficientemente lejos de ángulos ya usados
			var valid = true
			for used_angle in used_angles:
				var angle_diff = abs(angle - used_angle)
				# Considerar la diferencia mínima en el círculo (puede ser por el otro lado)
				angle_diff = min(angle_diff, 2.0 * PI - angle_diff)
				
				if angle_diff < min_angle_between_poles:
					valid = false
					break
			
			if valid:
				break
			attempts += 1
		
		used_angles.append(angle)
		var radius = randf_range(1.5, 3.0)  # RADIO ALEATORIO controlado por código
		
		var pole_a_pos = Vector3(
			cos(angle) * radius,
			0,
			sin(angle) * radius
		)
		
		current_pole_layout.append(pole_a_pos)
		
		# Poste 'b' en línea recta desde torre: Torre → Poste_A → Poste_B
		var secondary_distance = randf_range(2.0, 4.0)  # Distancia controlada por código
		var direction_from_tower = Vector3(cos(angle), 0, sin(angle))
		var pole_b_offset = direction_from_tower * secondary_distance
		
		current_pole_b_layout.append(pole_b_offset)
	
	# Restaurar semilla aleatoria global
	randomize()

func get_pole_positions_for_tower(tower_pos: Vector3) -> Array[Vector3]:
	"""Obtiene posiciones absolutas de postes 'a' para una torre con altura de terreno correcta"""
	var positions: Array[Vector3] = []
	for relative_pos in current_pole_layout:
		var pole_pos = tower_pos + relative_pos
		
		# Ajustar altura al terreno
		var ground_height = get_ground_height_at_position(pole_pos)
		if ground_height != Vector3.INF.y:
			pole_pos.y = ground_height
		
		positions.append(pole_pos)
	return positions

func get_pole_b_positions_for_poles_a(tower_pos: Vector3) -> Array[Vector3]:
	"""Obtiene posiciones absolutas de postes 'b' basado en postes 'a' con altura de terreno correcta"""
	var positions: Array[Vector3] = []
	var poles_a_positions = get_pole_positions_for_tower(tower_pos)
	
	for i in range(current_pole_b_layout.size()):
		if i < poles_a_positions.size():
			var pole_a_pos = poles_a_positions[i]
			var pole_b_pos = pole_a_pos + current_pole_b_layout[i]
			
			# Ajustar altura al terreno
			var ground_height = get_ground_height_at_position(pole_b_pos)
			if ground_height != Vector3.INF.y:
				pole_b_pos.y = ground_height
			
			positions.append(pole_b_pos)
	
	return positions

# ============================================================================
# PREVIEW SYSTEM - Visualización en tiempo real
# ============================================================================
func show_tower_preview(pos: Vector3):
	"""Muestra preview de torre + postes en posición usando instancias persistentes"""
	if not tower_preview:
		return
	
	# GENERAR SOLO UNA VEZ - al activar preview por primera vez
	if not preview_layout_generated:
		generate_pole_layout(pos)
		preview_layout_generated = true
	
	# USAR EXACTAMENTE EL MÉTODO DE TowerPlace.gd EN PREVIEW
	var is_tower_valid = not is_position_blocked_by_obstacles(pos) and is_valid_tower_position(pos)
	
	# Actualizar posición de la torre preview existente
	tower_preview.global_position = pos
	tower_preview.visible = true
	
	# Orientar la torre preview hacia la anterior
	orient_tower_to_previous(tower_preview)
	
	# Aplicar material según validez
	apply_preview_material(tower_preview, is_tower_valid)
	
	# Mostrar postes con el mismo color que la torre
	show_poles_preview(pos, is_tower_valid)
	
	# Mostrar cables de preview
	show_cable_preview(pos, is_tower_valid)

func show_poles_preview(tower_pos: Vector3, tower_is_valid: bool = true):
	"""Muestra preview de todos los postes para una torre usando instancias persistentes"""
	if not pole_scene:
		return
	
	# Solo mostrar postes si ya existe layout
	if current_pole_layout.is_empty():
		return  # Sin layout, no mostrar postes
	
	# Ocultar todos los postes previamente mostrados
	hide_poles_preview()
	
	# Preview postes 'a' - mismo color que la torre
	var poles_a_positions = get_pole_positions_for_tower(tower_pos)
	for i in range(poles_a_positions.size()):
		var pole_pos = poles_a_positions[i]
		var pole_preview = get_or_create_pole_preview_a(i)
		
		pole_preview.global_position = pole_pos
		pole_preview.visible = true
		
		# Los postes tienen el mismo color que la torre
		apply_preview_material(pole_preview, tower_is_valid)
	
	# Preview postes 'b' - mismo color que la torre
	var poles_b_positions = get_pole_b_positions_for_poles_a(tower_pos)
	for i in range(poles_b_positions.size()):
		var pole_pos = poles_b_positions[i]
		var pole_preview = get_or_create_pole_preview_b(i)
		
		pole_preview.global_position = pole_pos
		pole_preview.visible = true
		
		# Los postes tienen el mismo color que la torre
		apply_preview_material(pole_preview, tower_is_valid)

func apply_preview_material(node: Node3D, is_valid: bool):
	"""Aplica material de preview a un nodo y sus hijos"""
	var material = preview_material_valid if is_valid else preview_material_invalid
	
	# Buscar MeshInstance3D recursivamente
	apply_material_recursive(node, material)

func apply_material_recursive(node: Node, material: Material):
	"""Aplica material recursivamente a todos los MeshInstance3D"""
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		mesh_instance.material_override = material
	
	for child in node.get_children():
		apply_material_recursive(child, material)

func get_or_create_pole_preview_a(index: int) -> Node3D:
	"""Obtiene o crea instancia de preview para poste 'a' en el índice dado"""
	# Expandir array si es necesario
	while poles_a_preview.size() <= index:
		var new_pole = pole_scene.instantiate()
		add_child(new_pole)
		new_pole.visible = false
		
		# Deshabilitar colisiones para el preview de poste
		var pole_static_body = new_pole.find_child("StaticBody3D", true, false)
		if pole_static_body and pole_static_body is CollisionObject3D:
			pole_static_body.set_collision_layer(0)
			pole_static_body.set_collision_mask(0)
		
		poles_a_preview.append(new_pole)
	
	return poles_a_preview[index]

func get_or_create_pole_preview_b(index: int) -> Node3D:
	"""Obtiene o crea instancia de preview para poste 'b' en el índice dado"""
	# Expandir array si es necesario
	while poles_b_preview.size() <= index:
		var new_pole = pole_scene.instantiate()
		add_child(new_pole)
		new_pole.visible = false
		
		# Deshabilitar colisiones para el preview de poste
		var pole_static_body = new_pole.find_child("StaticBody3D", true, false)
		if pole_static_body and pole_static_body is CollisionObject3D:
			pole_static_body.set_collision_layer(0)
			pole_static_body.set_collision_mask(0)
		
		poles_b_preview.append(new_pole)
	
	return poles_b_preview[index]

func hide_poles_preview():
	"""Oculta todos los postes preview sin eliminarlos"""
	for pole in poles_a_preview:
		if pole:
			pole.visible = false
	
	for pole in poles_b_preview:
		if pole:
			pole.visible = false

func hide_preview():
	"""Oculta todos los elementos de preview sin eliminar las instancias"""
	if tower_preview:
		tower_preview.visible = false
	
	hide_poles_preview()
	hide_cable_preview()

func show_cable_preview(tower_pos: Vector3, is_valid: bool = true):
	"""Muestra cables de preview desde la torre hacia la torre anterior y postes"""
	hide_cable_preview()  # Limpiar cables previos
	
	# Cable hacia torre anterior
	if placed_towers.size() > 0:
		var last_tower = placed_towers[-1]
		create_cable_line(last_tower.global_position, tower_pos, is_valid)
	elif start_tower:
		# Cable hacia torre inicial
		create_cable_line(start_tower.global_position, tower_pos, is_valid)
	
	# Cables torre → postes A
	var poles_a_positions = get_pole_positions_for_tower(tower_pos)
	for pole_pos in poles_a_positions:
		# Validar que este cable específico no cruce obstáculos
		var cable_valid = is_valid and not would_cable_cross_obstacles(tower_pos, pole_pos)
		create_cable_line(tower_pos, pole_pos, cable_valid, true)
	
	# Cables poste A → poste B
	var poles_b_positions = get_pole_b_positions_for_poles_a(tower_pos)
	for i in range(poles_a_positions.size()):
		if i < poles_b_positions.size():
			var pole_a_pos = poles_a_positions[i]
			var pole_b_pos = poles_b_positions[i]
			# Validar que este cable específico no cruce obstáculos
			var cable_valid = is_valid and not would_pole_cable_cross_obstacles(pole_a_pos, pole_b_pos)
			create_cable_line(pole_a_pos, pole_b_pos, cable_valid, true)

func create_cable_line(start_pos: Vector3, end_pos: Vector3, is_valid: bool, is_tower_to_pole: bool = false):
	"""Crea una línea de cable entre dos puntos"""
	var line_mesh = MeshInstance3D.new()
	
	# Crear geometría de línea
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	
	vertices.append(start_pos)
	vertices.append(end_pos)
	indices.append(0)
	indices.append(1)
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	line_mesh.mesh = mesh
	
	# Material del cable
	var material = StandardMaterial3D.new()
	material.flags_unshaded = true
	material.flags_transparent = true
	material.vertex_color_use_as_albedo = true
	
	if is_valid:
		material.albedo_color = Color.YELLOW if not is_tower_to_pole else Color.ORANGE
		material.albedo_color.a = 0.8
	else:
		material.albedo_color = Color.RED
		material.albedo_color.a = 0.6
	
	line_mesh.material_override = material
	
	# Agregar al mundo
	add_child(line_mesh)
	cable_preview_lines.append(line_mesh)

func hide_cable_preview():
	"""Oculta y limpia todas las líneas de cable de preview"""
	for line in cable_preview_lines:
		if line and is_instance_valid(line):
			line.queue_free()
	cable_preview_lines.clear()

# ============================================================================
# REAL CABLE SYSTEM - Cables reales con curvatura gravitacional
# ============================================================================

func create_real_cables_for_tower(tower: Node3D, tower_pos: Vector3):
	"""Crea todos los cables reales para una torre recién colocada"""
	# Cable principal hacia torre anterior o torre inicial
	if placed_towers.size() > 1:  # Hay torre anterior
		var previous_tower = placed_towers[-2]  # La anterior a la que acabamos de agregar
		create_main_cable(previous_tower, tower)
	elif start_tower:
		# Cable hacia torre inicial
		create_main_cable(start_tower, tower)
	
	# Cables torre → postes A (usar posición del suelo para la torre, como TowerPlace.gd)
	var poles_a_positions = get_pole_positions_for_tower(tower_pos)
	for pole_pos in poles_a_positions:
		var pole_connection_point = pole_pos + Vector3(0, 1.2, 0)  # Altura ajustada
		create_thin_cable(tower_pos, pole_connection_point)  # Torre al suelo, como TowerPlace.gd
	
	# Cables poste A → poste B
	var poles_b_positions = get_pole_b_positions_for_poles_a(tower_pos)
	for i in range(poles_a_positions.size()):
		if i < poles_b_positions.size():
			var pole_a_pos = poles_a_positions[i] + Vector3(0, 1.2, 0)  # Altura ajustada
			var pole_b_pos = poles_b_positions[i] + Vector3(0, 1.2, 0)  # Altura ajustada
			create_pole_to_pole_cable(pole_a_pos, pole_b_pos)

func create_main_cable(tower1: Node3D, tower2: Node3D):
	"""Crea cable principal entre dos torres con curvatura gravitacional"""
	var cable_container = Node3D.new()
	
	# Calcular posiciones de inicio y fin (a 2.2m de altura como TowerPlace.gd)
	var start_pos = tower1.global_position + Vector3(0, 2.2, 0)
	var end_pos = tower2.global_position + Vector3(0, 2.2, 0)
	var distance = start_pos.distance_to(end_pos)
	
	# Calcular la curvatura del cable (12% como TowerPlace.gd)
	var cable_sag = distance * 0.12
	
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
	
	# Agregar el contenedor al árbol ANTES de crear los segmentos
	add_child(cable_container)
	placed_cables.append(cable_container)
	
	# Crear segmentos del cable entre cada par de puntos
	for i in range(cable_points.size() - 1):
		var segment_start = cable_points[i]
		var segment_end = cable_points[i + 1]
		var segment_length = segment_start.distance_to(segment_end)
		var segment_center = (segment_start + segment_end) / 2.0
		
		# Crear cilindro para este segmento
		var segment_mesh = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = 0.03  # Cable principal grosor
		cylinder.bottom_radius = 0.03
		cylinder.height = segment_length
		
		segment_mesh.mesh = cylinder
		segment_mesh.position = segment_center
		
		# Material para el cable principal
		var cable_material = StandardMaterial3D.new()
		cable_material.albedo_color = Color(0.15, 0.15, 0.15)  # Gris muy oscuro
		cable_material.metallic = 0.8
		cable_material.roughness = 0.4
		segment_mesh.material_override = cable_material
		
		# Agregar al contenedor ANTES de orientar
		cable_container.add_child(segment_mesh)
		
		# Orientar usando el método EXACTO de TowerPlace.gd
		var direction = (segment_end - segment_start).normalized()
		if direction.length() > 0:
			var target_pos = segment_center + direction
			segment_mesh.look_at_from_position(segment_center, target_pos, Vector3.UP)
			segment_mesh.rotate_object_local(Vector3.RIGHT, PI/2)

func create_thin_cable(start_point: Vector3, end_point: Vector3):
	"""Crea cable fino entre torre y poste - EXACTO como TowerPlace.gd"""
	var cable_container = Node3D.new()
	add_child(cable_container)
	placed_cables.append(cable_container)
	
	# Usar directamente los puntos de conexión que se pasan como parámetros
	var start_pos = start_point
	var end_pos = end_point
	
	# Si es un cable desde torre, usar altura de torre (EXACTO como TowerPlace.gd)
	if start_point.y < 1.5:  # Probablemente es posición de torre (al nivel del suelo)
		start_pos = start_point + Vector3(0, 2.2, 0)  # Torre a su altura + 2.2m
	
	var distance = start_pos.distance_to(end_pos)
	
	# Menos combadura para cables cortos (EXACTO como TowerPlace.gd)
	var cable_sag = distance * 0.08  # 8% de combadura
	
	# Menos segmentos para cables más simples (EXACTO como TowerPlace.gd)
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
		cylinder_mesh.top_radius = 0.02  # Cable muy fino (EXACTO como TowerPlace.gd)
		cylinder_mesh.bottom_radius = 0.02
		cylinder_mesh.height = current_pos.distance_to(next_pos)
		
		segment_mesh.mesh = cylinder_mesh
		segment_mesh.position = (current_pos + next_pos) / 2.0
		
		# Material del cable fino (más oscuro/menos visible) EXACTO como TowerPlace.gd
		var cable_material = StandardMaterial3D.new()
		cable_material.albedo_color = Color(0.25, 0.25, 0.25)  # Gris medio
		cable_material.metallic = 0.6
		cable_material.roughness = 0.7
		segment_mesh.material_override = cable_material
		
		cable_container.add_child(segment_mesh)
		
		# Orientar usando el método EXACTO de TowerPlace.gd
		var direction = (next_pos - current_pos).normalized()
		if direction.length() > 0:
			var target_pos = segment_mesh.position + direction
			segment_mesh.look_at_from_position(segment_mesh.position, target_pos, Vector3.UP)
			segment_mesh.rotate_object_local(Vector3.RIGHT, PI/2)

func create_pole_to_pole_cable(start_point: Vector3, end_point: Vector3):
	"""Crea cable muy fino entre postes con curvatura mínima"""
	var cable_container = Node3D.new()
	add_child(cable_container)
	placed_cables.append(cable_container)
	
	var start_pos = start_point
	var end_pos = end_point
	var distance = start_pos.distance_to(end_pos)
	
	# Menos combadura para cables cortos entre postes (5% como TowerPlace.gd)
	var cable_sag = distance * 0.05
	
	# Menos segmentos para cables más simples
	var num_segments = 4
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
		cylinder_mesh.top_radius = 0.015  # Cable aún más fino para postes
		cylinder_mesh.bottom_radius = 0.015
		cylinder_mesh.height = current_pos.distance_to(next_pos)
		
		segment_mesh.mesh = cylinder_mesh
		segment_mesh.position = (current_pos + next_pos) / 2.0
		
		# Material del cable entre postes
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.25, 0.25)
		material.metallic = 0.4
		material.roughness = 0.6
		segment_mesh.material_override = material
		
		cable_container.add_child(segment_mesh)
		
		# Orientar usando el método EXACTO de TowerPlace.gd
		var direction = (next_pos - current_pos).normalized()
		if direction.length() > 0:
			var target_pos = segment_mesh.position + direction
			segment_mesh.look_at_from_position(segment_mesh.position, target_pos, Vector3.UP)
			segment_mesh.rotate_object_local(Vector3.RIGHT, PI/2)

func update_preview_at_cursor():
	"""Actualiza preview según posición del cursor - COPIADO EXACTAMENTE de TowerPlace.gd"""
	if not placement_mode_active or not camera:
		return
	
	if not tower_preview or not is_instance_valid(tower_preview):
		create_persistent_preview_instances()
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000, 1)
	var result = space_state.intersect_ray(query)
	
	if result:
		# COPIADO EXACTAMENTE DE TowerPlace.gd - usar result.position directamente
		var target_pos = result.position
		

		
		tower_preview.position = target_pos
		
		# Aplicar orientación EXACTA de TowerPlace.gd
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
		
		# PRIMERO: Crear el preview de postes (EXACTO de TowerPlace.gd)
		show_tower_preview(target_pos)  # Esto genera las posiciones
		
		# SEGUNDO: Validar usando las posiciones ya generadas en el preview
		var is_valid = not is_position_blocked_by_obstacles(target_pos)
		
		# TERCERO: Aplicar material correcto según validación + SIEMPRE mostrar radio
		if is_valid:
			apply_preview_material(tower_preview, true)
			show_range_indicator()  # SIEMPRE mostrar radio
			# Actualizar materiales de postes a válido
			for pole_preview in poles_a_preview:
				if pole_preview and is_instance_valid(pole_preview):
					apply_preview_material(pole_preview, true)
			for pole_preview in poles_b_preview:
				if pole_preview and is_instance_valid(pole_preview):
					apply_preview_material(pole_preview, true)
		else:
			apply_preview_material(tower_preview, false)
			show_range_indicator()  # SIEMPRE mostrar radio (como solicitado)
			# Actualizar materiales de postes a inválido
			for pole_preview in poles_a_preview:
				if pole_preview and is_instance_valid(pole_preview):
					apply_preview_material(pole_preview, false)
			for pole_preview in poles_b_preview:
				if pole_preview and is_instance_valid(pole_preview):
					apply_preview_material(pole_preview, false)
	else:
		tower_preview.visible = false
		hide_range_indicator()
		hide_preview()

func orient_tower_to_previous(tower: Node3D):
	"""Orienta la torre para mirar hacia la torre anterior"""
	var target_position: Vector3
	
	# Si hay torres colocadas, mirar hacia la última
	if not placed_towers.is_empty():
		var last_tower = placed_towers[-1]
		target_position = last_tower.global_position
	# Si no hay torres pero hay TowerBegin, mirar hacia ella
	elif start_tower:
		target_position = start_tower.global_position
	else:
		return  # Sin referencia, no orientar
	
	# Calcular dirección en el plano XZ
	var tower_pos = tower.global_position
	var direction = target_position - tower_pos
	direction.y = 0  # Mantener solo rotación horizontal
	
	if direction.length() > 0.001:  # Evitar división por cero
		direction = direction.normalized()
		
		# Calcular ángulo de rotación
		var angle = atan2(direction.x, direction.z)
		tower.rotation.y = angle

# ============================================================================
# PLACEMENT EXECUTION - Colocación definitiva de estructuras
# ============================================================================
func place_tower_at_cursor() -> bool:
	"""Coloca torre + postes en la posición del cursor"""
	if not placement_mode_active or not camera:
		return false
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	# USAR EL MISMO RAYCAST QUE TowerPlace.gd
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000, 1)
	
	var result = space_state.intersect_ray(query)
	if not result:
		return false
	
	var placement_pos = result.position
	
	return place_tower_at_position(placement_pos)

func place_tower_at_position(pos: Vector3) -> bool:
	"""Coloca torre + postes en posición específica"""
	# USAR EXACTAMENTE EL MÉTODO DE TowerPlace.gd
	if is_position_blocked_by_obstacles(pos):
		return false
	
	if not is_valid_tower_position(pos):
		return false
	
	if not tower_scene or not pole_scene:
		push_error("[TowerPlacer] Escenas no configuradas")
		return false
	
	# USAR el layout ya generado en el preview - NO generar uno nuevo
	
	# Colocar torre exactamente igual que TowerPlace.gd
	var new_tower = tower_scene.instantiate()
	new_tower.position = pos
	add_child(new_tower)
	

	
	# Orientar la torre hacia la torre anterior
	orient_tower_to_previous(new_tower)
	
	placed_towers.append(new_tower)
	
	# Colocar postes usando el layout ya generado con la posición corregida
	var poles_a_positions = get_pole_positions_for_tower(pos)
	for pole_pos in poles_a_positions:
		var new_pole_a = pole_scene.instantiate()
		get_tree().current_scene.add_child(new_pole_a)
		new_pole_a.global_position = pole_pos
		
		# DESHABILITAR COLISIONES para que no interfieran con raycast
		var pole_static_body = new_pole_a.find_child("StaticBody3D", true, false)
		if pole_static_body and pole_static_body is CollisionObject3D:
			pole_static_body.set_collision_layer(0)
			pole_static_body.set_collision_mask(0)
		
		placed_poles_a.append(new_pole_a)
	
	var poles_b_positions = get_pole_b_positions_for_poles_a(pos)
	for pole_pos in poles_b_positions:
		var new_pole_b = pole_scene.instantiate()
		get_tree().current_scene.add_child(new_pole_b)
		new_pole_b.global_position = pole_pos
		
		# DESHABILITAR COLISIONES para que no interfieran con raycast
		var pole_static_body = new_pole_b.find_child("StaticBody3D", true, false)
		if pole_static_body and pole_static_body is CollisionObject3D:
			pole_static_body.set_collision_layer(0)
			pole_static_body.set_collision_mask(0)
		
		placed_poles_b.append(new_pole_b)
	
	create_tower_connections(new_tower)
	
	# Reset para siguiente torre - permitir nuevo layout para siguiente preview
	preview_layout_generated = false
	hide_preview()
	
	# Actualizar el indicador de rango para la nueva torre
	show_range_indicator()
	
	return true

func create_tower_connections(tower: Node3D):
	"""Crea conexiones de cables para la nueva torre"""
	# Crear todos los cables reales con curvatura gravitacional
	create_real_cables_for_tower(tower, tower.global_position)
	
	var connection_data = {
		"tower": tower,
		"poles_a": [],
		"poles_b": [],
		"cables": []
	}
	
	tower_connections.append(connection_data)

# ============================================================================
# AUXILIARY VALIDATION FUNCTIONS - Copiadas de TowerPlace.gd
# ============================================================================

func is_too_close_to_existing_tower(pos: Vector3) -> bool:
	for tower in placed_towers:
		if not is_instance_valid(tower):
			continue
		var distance = tower.position.distance_to(pos)
		if distance < min_tower_distance:
			return true
	return false

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
		if obs.name.to_lower().contains("low") or obs.name.to_lower().contains("bajo"):
			all_obstacles.append(obs)
	
	# Método 3: Buscar recursivamente por nombre (fallback)
	var recursive_obstacles = []
	_find_obstacles_recursive(get_tree().root, recursive_obstacles)
	for obs in recursive_obstacles:
		if obs.name.to_lower().contains("low") or obs.name.to_lower().contains("bajo"):
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
		
		# Usar margen moderado para torres: tamaño del obstáculo + margen pequeño
		var margin_x = (obs_size.x * 0.5) + 0.3  # Medio obstáculo + 0.3 metros de margen
		var margin_z = (obs_size.z * 0.5) + 0.3  # Medio obstáculo + 0.3 metros de margen
		
		# Si la torre está dentro del área expandida del obstáculo bajo, bloquear colocación
		if distance_x < margin_x and distance_z < margin_z:
			return true
	
	return false

func has_obstacle_at_tower_position(pos: Vector3) -> bool:
	if placed_towers.is_empty():
		return false
	
	var last_tower = placed_towers[-1]
	
	# Usar EXACTAMENTE la misma lógica que create_connection()
	# Pero primero obtener las alturas reales del terreno
	var last_tower_ground = get_ground_height_at_position(last_tower.position)
	var new_tower_ground = get_ground_height_at_position(pos)
	
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
		var obs_height = 3.0  # Altura por defecto
		
		# Buscar CollisionShape3D para obtener la altura real
		for child in obstacle.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				obs_height = child.shape.size.y
				break
		
		# Solo considerar obstáculos que pueden interferir con el cable
		# El cable está a 2.2m, así que solo obstáculos de 2.2m+ son relevantes
		if obs_height < 2.2:
			continue
		
		# Verificar si el cable (línea 3D) cruza el obstáculo (caja 3D)
		if would_cable_cross_obstacle_3d(start_pos, end_pos, obs_pos, Vector3(2.0, obs_height, 2.0)):
			return true
	
	return false

func would_connection_cross_existing_cables(_tower1_pos: Vector3, _tower2_pos: Vector3) -> bool:
	# Verificar cruces con cables principales de torres existentes
	for connection in tower_connections:
		if connection.has("tower") and is_instance_valid(connection.tower):
			# Por ahora simplificar - implementación completa pendiente
			pass
	
	return false

func would_cable_cross_obstacle_3d(cable_start: Vector3, cable_end: Vector3, obstacle_center: Vector3, obstacle_size: Vector3) -> bool:
	# Proyectar al plano XZ para simplificar
	var cable_start_2d = Vector2(cable_start.x, cable_start.z)
	var cable_end_2d = Vector2(cable_end.x, cable_end.z)
	var obstacle_center_2d = Vector2(obstacle_center.x, obstacle_center.z)
	var obstacle_size_2d = Vector2(obstacle_size.x, obstacle_size.z)
	
	# Usar función auxiliar para verificar intersección línea-rectángulo en 2D
	return does_line_intersect_box_2d(cable_start_2d, cable_end_2d, obstacle_center_2d, obstacle_size_2d)

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

func is_point_in_rect(point: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	return point.x >= rect_min.x and point.x <= rect_max.x and point.y >= rect_min.y and point.y <= rect_max.y

func lines_intersect_2d_simple(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var denominator = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
	if abs(denominator) < 0.0001:
		return false  # Líneas paralelas
	
	var t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denominator
	var u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denominator
	
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0

func _find_obstacles_recursive(node: Node, obstacles: Array):
	if node.name.begins_with("Obstacle"):
		obstacles.append(node)
	for child in node.get_children():
		_find_obstacles_recursive(child, obstacles)

func apply_material_to_node(node: Node, material: Material):
	if not node:
		return
	
	# Buscar MeshInstance3D en la jerarquía completa
	if node is MeshInstance3D:
		node.set_surface_override_material(0, material)
		return
	
	# Buscar recursivamente en todos los hijos
	for child in node.get_children():
		apply_material_to_node(child, material)

func is_pole_blocked_by_obstacles(pole_pos: Vector3) -> bool:
	"""Verifica si una posición de poste está bloqueada por obstáculos - MUY ESTRICTA"""
	
	# Buscar todos los obstáculos (altos y bajos)
	var all_obstacles = []
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleHigh"))
	all_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleLow"))
	
	# Buscar en grupo general "obstacles"
	var general_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obs in general_obstacles:
		all_obstacles.append(obs)
	
	# Buscar recursivamente por nombre (fallback)
	_find_obstacles_recursive(get_tree().root, all_obstacles)
	
	for obstacle in all_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		# Verificar tanto ObstacleHigh como ObstacleLow (postes no pueden estar sobre ninguno)
		if not (obstacle.name.begins_with("Obstacle") or obstacle.is_in_group("ObstacleHigh") or obstacle.is_in_group("ObstacleLow")):
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
		
		# Usar margen moderado para evitar postes en obstáculos
		var margin_x = (obs_size.x * 0.5) + 0.5  # Medio obstáculo + 0.5 metros de margen
		var margin_z = (obs_size.z * 0.5) + 0.5  # Medio obstáculo + 0.5 metros de margen
		
		if distance_x < margin_x and distance_z < margin_z:
			return true  # Poste bloqueado por obstáculo
	
	# También usar detección de física como respaldo
	var space_state = get_viewport().get_world_3d().direct_space_state
	var shape = SphereShape3D.new()
	shape.radius = 0.2  # Radio pequeño para detección precisa
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = pole_pos
	query.collision_mask = 2  # Capa de obstáculos
	var physics_results = space_state.intersect_shape(query)
	
	for result in physics_results:
		var collider = result.get("collider")
		if collider and (collider.name.begins_with("Obstacle")):
			return true  # Poste bloqueado por colisión física
	
	return false  # Poste NO bloqueado

func get_ground_height_towerplace_method(pos: Vector3) -> float:
	"""COPIADO EXACTAMENTE DE TowerPlace.gd - get_ground_height()"""
	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 10,
		pos + Vector3.DOWN * 10
	)
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position.y
	return pos.y

func would_cable_cross_high_obstacles(tower_pos: Vector3, pole_pos: Vector3) -> bool:
	"""Verifica si un cable torre→poste cruzaría obstáculos altos"""
	
	# Buscar solo obstáculos altos (que pueden interferir con cables)
	var high_obstacles = []
	high_obstacles.append_array(get_tree().get_nodes_in_group("ObstacleHigh"))
	
	# Buscar en grupo general "obstacles" solo los altos
	var general_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obs in general_obstacles:
		if obs.name.to_lower().contains("high") or obs.name.to_lower().contains("alto"):
			high_obstacles.append(obs)
	
	# Buscar recursivamente por nombre (fallback)
	var recursive_obstacles = []
	_find_obstacles_recursive(get_tree().root, recursive_obstacles)
	for obs in recursive_obstacles:
		if obs.name.to_lower().contains("high") or obs.name.to_lower().contains("alto"):
			high_obstacles.append(obs)
	
	# Posiciones del cable (Torre: 2.2m, Poste: 1.3m)
	var start_pos = tower_pos + Vector3(0, 2.2, 0)
	var end_pos = pole_pos + Vector3(0, 1.3, 0)
	
	# Proyectar la línea del cable al plano XZ
	var cable_start_2d = Vector2(start_pos.x, start_pos.z)
	var cable_end_2d = Vector2(end_pos.x, end_pos.z)
	
	for obstacle in high_obstacles:
		if not is_instance_valid(obstacle):
			continue
		
		var obs_pos = obstacle.global_position
		var obs_size = Vector3(2.0, 3.0, 2.0)  # Tamaño por defecto para obstáculos altos
		var obs_height = 3.0
		
		# Buscar CollisionShape3D para obtener el tamaño real
		for child in obstacle.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				obs_size = child.shape.size
				obs_height = obs_size.y
				break
		
		# Solo considerar obstáculos que pueden interferir con el cable
		# El cable está entre 1.3m y 2.2m, así que obstáculos de 1.3m+ son relevantes
		if obs_height < 1.3:
			continue
		
		# Verificar si el cable (línea 2D) cruza el obstáculo (rectángulo 2D)
		var obs_center_2d = Vector2(obs_pos.x, obs_pos.z)
		var obs_size_2d = Vector2(obs_size.x, obs_size.z)
		
		if does_line_intersect_box_2d(cable_start_2d, cable_end_2d, obs_center_2d, obs_size_2d):
			return true  # Cable cruzaría obstáculo alto
	
	return false  # Cable NO cruza obstáculos altos

func is_position_inside_level_bounds(pos: Vector3) -> bool:
	if not level_bounds:
		return true  # Sin límites definidos, permitir cualquier posición
	
	# Obtener el CollisionShape3D hijo del Area3D
	var collision_shape = null
	for child in level_bounds.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return true  # Sin forma definida, permitir cualquier posición
	
	var shape = collision_shape.shape
	
	# Manejar ConvexPolygonShape3D
	if shape is ConvexPolygonShape3D:
		var points = shape.points
		if points.size() > 2:
			# Proyectar al plano XZ para verificar si está dentro del polígono
			var polygon_2d = []
			for point in points:
				polygon_2d.append(Vector2(point.x, point.z))
			
			var pos_2d = Vector2(pos.x, pos.z)
			return _point_in_polygon(pos_2d, polygon_2d)
		else:
			return true  # Polígono inválido, permitir
	
	# Manejar BoxShape3D como fallback
	elif shape is BoxShape3D:
		var box_size = shape.size
		var bounds_center = level_bounds.global_position
		
		var min_x = bounds_center.x - box_size.x * 0.5
		var max_x = bounds_center.x + box_size.x * 0.5
		var min_z = bounds_center.z - box_size.z * 0.5
		var max_z = bounds_center.z + box_size.z * 0.5
		
		return pos.x >= min_x and pos.x <= max_x and pos.z >= min_z and pos.z <= max_z
	
	return true

# ============================================================================
# PUBLIC API - Funciones principales para uso externo
# ============================================================================
func enable_placement_mode():
	"""Activa modo de colocación con preview"""
	placement_mode_active = true

func disable_placement_mode():
	"""Desactiva modo de colocación"""
	placement_mode_active = false
	hide_preview()
	hide_range_indicator()
	hide_cable_preview()

func get_placed_structures_count() -> Dictionary:
	"""Retorna conteo de estructuras colocadas"""
	return {
		"towers": placed_towers.size(),
		"poles_a": placed_poles_a.size(), 
		"poles_b": placed_poles_b.size()
	}

func clear_all_placed_structures():
	"""Limpia todas las estructuras colocadas"""
	for tower in placed_towers:
		if tower:
			tower.queue_free()
	
	for pole in placed_poles_a:
		if pole:
			pole.queue_free()
	
	for pole in placed_poles_b:
		if pole:
			pole.queue_free()
	
	placed_towers.clear()
	placed_poles_a.clear()
	placed_poles_b.clear()
	tower_connections.clear()
	
	hide_preview()
