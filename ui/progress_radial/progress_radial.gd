extends TextureRect

@export var rotations_per_second: float = 0.5


func _process(delta: float) -> void:
	rotation = fposmod(rotation + rotations_per_second * TAU * delta, TAU)
