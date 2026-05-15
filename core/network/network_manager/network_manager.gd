extends CanvasLayer

const lobby_room_name: String = "lobby"


func _ready() -> void:
	connect_to_lobby.call_deferred()


func connect_to_lobby() -> void:
	Fusion.connected_to_photon.connect(func():
		Fusion.join_or_create_room(lobby_room_name)
	)
	Fusion.connect_to_photon()
