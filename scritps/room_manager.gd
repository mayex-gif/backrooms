extends Node3D

@export var radio_carga: float = 50.0 # Metros de radio alrededor del jugador
const INTERVALO_ESCANEO: float = 0.5 # Revisamos 2 veces por segundo (súper optimizado)

var jugador: CharacterBody3D = null
var tiempo_acumulado: float = 0.0

func _ready():
	# Buscamos al jugador
	jugador = get_tree().get_first_node_in_group("jugador") as CharacterBody3D

func _process(delta: float) -> void:
	if not jugador:
		return
		
	tiempo_acumulado += delta
	if tiempo_acumulado >= INTERVALO_ESCANEO:
		tiempo_acumulado = 0.0
		_gestionar_habitaciones()

func _gestionar_habitaciones():
	# Buscamos todos los módulos que hayas etiquetado como "habitacion"
	var habitaciones = get_tree().get_nodes_in_group("habitacion")
	
	for hab in habitaciones:
		if not hab is Node3D:
			continue
			
		# Calculamos la distancia desde el jugador al centro del módulo/habitación
		var distancia = jugador.global_position.distance_to(hab.global_position)
		
		if distancia <= radio_carga:
			# DENTRO DEL RADIO: Activamos la habitación
			if not hab.visible:
				hab.visible = true
				# Reactivamos físicas, luces y scripts internos
				hab.process_mode = Node.PROCESS_MODE_INHERIT 
		else:
			# FUERA DEL RADIO: Hibernamos la habitación
			if hab.visible:
				hab.visible = false
				# Congelamos absolutamente todo su consumo de CPU
				hab.process_mode = Node.PROCESS_MODE_DISABLED
