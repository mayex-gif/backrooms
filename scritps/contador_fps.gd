extends Label

func _process(_delta):
	# Obtenemos los cuadros por segundo del motor gráfico
	var fps = Engine.get_frames_per_second()
	text = "FPS: " + str(fps)
