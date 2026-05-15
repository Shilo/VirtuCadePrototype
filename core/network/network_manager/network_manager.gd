extends CanvasLayer


func _ready() -> void:
	connect_to_photon.call_deferred()


func connect_to_photon() -> void:
	var user_id = "user_%d" % randi()
	Fusion.connect_to_photon(user_id)
	Fusion.connected_to_photon.connect(func():
		print("trying to join/create room as user: ", user_id)
		Fusion.join_or_create_room()
	)
