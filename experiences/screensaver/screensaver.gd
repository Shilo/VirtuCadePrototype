extends Node2D

const SPEED: float = 220.0
const PLAYFIELD_SIZE := Vector2(1280.0, 720.0)

@onready var logo: ScreensaverLogo = %Logo

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	logo.replicator.authority_changed.connect(func(__): _refresh_authority_state())
	Fusion.room_joined.connect(_refresh_authority_state)
	_refresh_authority_state()


func _refresh_authority_state() -> void:
	var has_authority_in_room := logo.replicator.has_authority() and Fusion.is_in_room()
	set_process(has_authority_in_room)
	
	if not has_authority_in_room:
		return
	if velocity != Vector2.ZERO:
		return

	var dir := Vector2(
		1.0 if randf() < 0.5 else -1.0,
		1.0 if randf() < 0.5 else -1.0,
	)
	velocity = dir * SPEED
	_recolor()


func _process(delta: float) -> void:
	var half := logo.texture.get_size() * logo.scale.abs() * 0.5
	var min_pos := half
	var max_pos := PLAYFIELD_SIZE - half

	var new_pos := logo.position + velocity * delta
	var bounced_x := false
	var bounced_y := false

	if new_pos.x <= min_pos.x:
		new_pos.x = min_pos.x
		velocity.x = absf(velocity.x)
		bounced_x = true
	elif new_pos.x >= max_pos.x:
		new_pos.x = max_pos.x
		velocity.x = -absf(velocity.x)
		bounced_x = true

	if new_pos.y <= min_pos.y:
		new_pos.y = min_pos.y
		velocity.y = absf(velocity.y)
		bounced_y = true
	elif new_pos.y >= max_pos.y:
		new_pos.y = max_pos.y
		velocity.y = -absf(velocity.y)
		bounced_y = true

	logo.position = new_pos

	if bounced_x or bounced_y:
		_recolor()
	if bounced_x and bounced_y:
		logo.play_corner_hit()


func _recolor() -> void:
	logo.modulate = Color.from_hsv(randf(), 0.7, 1.0)
