extends PanelContainer

@export var connecting_scene: PackedScene
@export var disconnected_texture: Texture2D
@export var error_texture: Texture2D

var _current_status := -1


func _ready() -> void:
	Fusion.connection_status_changed.connect(_connection_status_changed)


func _connection_status_changed(status: FusionClient.ConnectionStatus) -> void:
	status = _normalize_status(status)
	if status == _current_status:
		return
	_current_status = status

	for child in get_children():
		child.queue_free()

	match _current_status:
		FusionClient.ConnectionStatus.STATUS_IN_ROOM:
			visible = false
			return
		FusionClient.ConnectionStatus.STATUS_JOINING_ROOM:
			_show_scene(connecting_scene)
		FusionClient.ConnectionStatus.STATUS_DISCONNECTED:
			_show_texture(disconnected_texture)
		FusionClient.ConnectionStatus.STATUS_ERROR:
			_show_texture(error_texture)

	visible = true


func _show_texture(texture: Texture2D) -> void:
	if not texture:
		return

	var texture_rect := TextureRect.new()
	texture_rect.texture = texture
	add_child(texture_rect)


func _show_scene(scene: PackedScene) -> void:
	if not scene:
		return

	add_child(scene.instantiate())


func _normalize_status(status: FusionClient.ConnectionStatus) -> FusionClient.ConnectionStatus:
	match status:
		FusionClient.ConnectionStatus.STATUS_CONNECTED_TO_PHOTON,\
		FusionClient.ConnectionStatus.STATUS_CONNECTING_TO_PHOTON:
			return FusionClient.ConnectionStatus.STATUS_JOINING_ROOM
	return status
