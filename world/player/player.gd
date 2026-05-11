class_name Player extends CharacterBody2D


const SPEED = 100.0
const JUMP_VELOCITY = -400.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use"):
		interact("use")
		return
	
	if event.is_action_pressed("ui_up"):
		interact("use_up")
		return
	
	if event.is_action_pressed("ui_down"):
		interact("use_down")
		return


func interact(method: StringName) -> void:
	for area in %InteractionArea.get_overlapping_areas():
		if not area.has_method(method):
			continue
		
		area.call(method, self)


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
