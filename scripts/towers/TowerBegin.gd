extends Node3D
class_name TowerBegin

# Torre inicial del nivel - punto de partida para las conexiones
@export var connection_range: float = 50.0

func _ready():
	# Registrar esta torre como torre inicial en el GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_start_tower"):
		game_manager.register_start_tower(self)

func get_connection_range() -> float:
	return connection_range

func get_connection_position() -> Vector3:
	return global_position
