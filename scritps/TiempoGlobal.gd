extends Node

signal hora_actualizada(hora_actual: float)

var hora: float = 14.0 

# MATEMÁTICA: 24 horas de juego / 3600 segundos reales = 0.00666...
# Como cambiaste a 360 para pruebas, recordá poner 24.0 / 360.0 si querés que vuele
var velocidad_tiempo: float = 24.0 / 36.0 

func _process(delta: float):
	hora += delta * velocidad_tiempo
	
	if hora >= 24.0:
		hora = 0.0 
		
	hora_actualizada.emit(hora)

func dormir_hasta(nueva_hora: float):
	hora = nueva_hora
	hora_actualizada.emit(hora)
