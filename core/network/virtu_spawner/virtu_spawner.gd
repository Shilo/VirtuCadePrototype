class_name VirtuSpawner extends Marker2D

@export var spawnable_scenes: Array[PackedScene]
@export var random_offset: Vector2 = Vector2.ZERO

var fusion_spawner: FusionSpawner


func _enter_tree() -> void:
	if fusion_spawner != null:
		return
	fusion_spawner = FusionSpawner.new()
	fusion_spawner.spawnable_scenes = spawnable_scenes
	add_child(fusion_spawner)


func spawn() -> Node2D:
	return fusion_spawner.spawn(null, func(node: Node2D) -> void:
		node.global_position = global_position + Vector2(
			randf_range(-random_offset.x, random_offset.x),
			randf_range(-random_offset.y, random_offset.y),
		)
	)
