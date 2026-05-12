class_name VirtuMachineError extends CenterContainer

static func show_scene(virtu_machine_name: String) -> void:
	var resource_path := (VirtuMachineError as GDScript).resource_path
	var scene_path := resource_path.get_basename() + ".tscn"
	var scene: PackedScene = load(scene_path)
	print(scene_path)
	
	var node := scene.instantiate()
	node.name = virtu_machine_name
	
	Engine.get_main_loop().change_scene_to_node(node)


func _ready() -> void:
	%VirtuMachineName.text = name.capitalize()
