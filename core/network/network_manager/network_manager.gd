extends CanvasLayer

const lobby_room_name: String = "lobby"
const experience_room_prefix: String = "experience_"

var _pending_room_name: String
var _register_current_scene_after_join := false


func _ready() -> void:
	Fusion.connected_to_photon.connect(_on_connected_to_photon)
	Fusion.room_left.connect(_on_room_left)
	Fusion.room_joined.connect(_on_room_joined)
	connect_to_lobby.call_deferred()


func connect_to_lobby() -> void:
	join_lobby_room()
	Fusion.connect_to_photon()


func join_lobby_room() -> void:
	_join_room(lobby_room_name, false)


func join_experience_room(experience_name: String) -> void:
	_join_room(experience_room_prefix + experience_name, true)


func _join_room(room_name: String, register_current_scene_after_join: bool) -> void:
	_pending_room_name = room_name
	_register_current_scene_after_join = register_current_scene_after_join

	if not Fusion.is_connected_to_photon():
		return
	if Fusion.is_in_room():
		Fusion.leave_room()
		return

	_join_pending_room()


func _join_pending_room() -> void:
	if _pending_room_name.is_empty():
		return

	Fusion.join_or_create_room(_pending_room_name)


func _on_connected_to_photon() -> void:
	if _pending_room_name.is_empty():
		join_lobby_room()
		return

	_join_pending_room()


func _on_room_left() -> void:
	_join_pending_room()


func _on_room_joined() -> void:
	_pending_room_name = ""
	if _register_current_scene_after_join:
		register_current_scene.call_deferred()


func register_current_scene() -> void:
	if not Fusion.is_in_room():
		return
	if get_tree().current_scene == null:
		return

	Fusion.register_current_scene()
