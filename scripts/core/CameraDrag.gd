extends Node

var dragging := false
var last_mouse_pos := Vector2.ZERO
var camera: Camera3D
@export var drag_speed: float = 0.15  # Velocidad ajustable desde el inspector
@export var smooth_drag: bool = true   # Suavizado opcional

func _ready():
	camera = get_parent() as Camera3D
	if not camera:
		print("❌ Error: CameraDrag debe ser hijo de un nodo Camera3D")

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
		
		if smooth_drag:
			# Movimiento suavizado
			var tween = create_tween()
			var current_pos = camera.global_position
			var target_pos = current_pos + movement
			target_pos.y = current_pos.y  # Forzar que Y se mantenga igual
			tween.tween_property(camera, "global_position", target_pos, 0.1)
		else:
			# Movimiento directo
			camera.global_position += movement
