extends RayCast3D

@export var crosshair_panel: Panel

func _physics_process(_delta: float) -> void:
	if not crosshair_panel: return
	
	var style_box = crosshair_panel.get_theme_stylebox("panel") as StyleBoxFlat
	
	if is_colliding():
		var hit = get_collider()
		
		# Verificamos si es interactuable
		if hit.is_in_group("interactuables"):

			crosshair_panel.scale = Vector2(0.75, 0.75)
			
			if Input.is_action_just_pressed("interactuar"):
				var target = hit
				while target != null:
					if target.has_method("interactuar"):
						target.interactuar(hit.name)
						break
					target = target.get_parent()
		else:
			style_box.bg_color = Color.LIGHT_GRAY
			crosshair_panel.scale = Vector2(0.75, 0.75)
	else:
		style_box.bg_color = Color.LIGHT_GRAY
		crosshair_panel.scale = Vector2(0.75, 0.75)
