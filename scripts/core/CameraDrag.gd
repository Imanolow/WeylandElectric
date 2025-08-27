extends Node

var dragging := false
var last_mouse_pos := Vector2.ZERO
var camera: Camera3D
@export var drag_speed: float = 0.15  # Velocidad ajustable desde el inspector
@export var smooth_drag: bool = true   # Suavizado opcional

# Variables de límites del nivel
var level_bounds: Area3D = null

func _ready():
	camera = get_parent() as Camera3D
	if not camera:
		print("❌ Error: CameraDrag debe ser hijo de un nodo Camera3D")
	
	# Buscar los límites del nivel
	find_level_bounds()

func find_level_bounds():
	# Buscar el área de límites del nivel
	var bounds_nodes = get_tree().get_nodes_in_group("level_bounds")
	if bounds_nodes.size() > 0:
		level_bounds = bounds_nodes[0]
		print("Límites de cámara encontrados: ", level_bounds.name)
	else:
		print("⚠️ Advertencia: No se encontraron límites para la cámara")

func is_position_inside_bounds(pos: Vector3) -> bool:
	if not level_bounds:
		return true  # Si no hay límites definidos, permitir movimiento libre
	
	# Obtener el CollisionShape3D hijo del Area3D
	var collision_shape = null
	for child in level_bounds.get_children():
		if child is CollisionShape3D:
			collision_shape = child
			break
	
	if not collision_shape or not collision_shape.shape:
		return true  # Si no hay shape, permitir movimiento
	
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

func _unhandled_input(event):
	if not camera:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			last_mouse_pos = event.position
				
	elif event is InputEventMouseMotion and dragging:
		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position
		
		# Movimiento relativo a la orientación de la cámara (invertido para drag natural)
		var right = camera.global_transform.basis.x
		var forward = camera.global_transform.basis.z
		
		# Movimiento invertido y relativo a la vista de la cámara
		var movement = (-right * delta.x * drag_speed) + (-forward * delta.y * drag_speed)
		movement.y = 0  # Mantener la altura fija
		
		# Calcular nueva posición y verificar límites
		var current_pos = camera.global_position
		var target_pos = current_pos + movement
		target_pos.y = current_pos.y  # Forzar que Y se mantenga igual
		
		# Solo mover si la nueva posición está dentro de los límites
		if is_position_inside_bounds(target_pos):
			if smooth_drag:
				# Movimiento suavizado
				var tween = create_tween()
				tween.tween_property(camera, "global_position", target_pos, 0.1)
			else:
				# Movimiento directo
				camera.global_position = target_pos
