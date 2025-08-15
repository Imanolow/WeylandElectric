extends Node3D
class_name TowerEnd

# Torre final del nivel - punto de llegada para completar el nivel
@export var connection_range: float = 10.0

func _ready():
	# Registrar esta torre como torre final en el GameManager
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_end_tower"):
		game_manager.register_end_tower(self)

func get_connection_range() -> float:
	return connection_range

func get_connection_position() -> Vector3:
	return global_position

func level_completed():
	# Se llama cuando se conecta una torre a esta torre final
	print("¡Nivel completado!")
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("level_completed"):
		game_manager.level_completed()
