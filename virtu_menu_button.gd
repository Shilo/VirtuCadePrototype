class_name VirtuMenuButton extends MenuButton


func _ready():
	get_popup().about_to_popup.connect(_on_about_to_popup, ConnectFlags.CONNECT_DEFERRED)

func _on_about_to_popup():
	var popup := get_popup()
	var pos := global_position
	
	pos.x += size.x - popup.size.x
	pos.y -= popup.size.y + 4
	
	popup.position = pos
