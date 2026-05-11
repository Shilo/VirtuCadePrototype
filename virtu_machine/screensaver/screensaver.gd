extends Node2D

const SPEED: float = 220.0

@onready var logo: Sprite2D = %Logo

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	var dir := Vector2(
		1.0 if randf() < 0.5 else -1.0,
		1.0 if randf() < 0.5 else -1.0,
	)
	velocity = dir * SPEED
	_recolor()


func _process(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var half := logo.texture.get_size() * logo.scale.abs() * 0.5
	var min_pos := half
	var max_pos := viewport_size - half

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
		_on_corner_hit()


func _recolor() -> void:
	logo.modulate = Color.from_hsv(randf(), 0.7, 1.0)


func _on_corner_hit() -> void:
	var tween := create_tween()
	tween.tween_property(logo, "scale", logo.scale * 1.25, 0.1)
	tween.tween_property(logo, "scale", logo.scale, 0.15)
