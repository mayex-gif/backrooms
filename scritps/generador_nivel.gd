extends Node3D

@export var habitacion_inicial_prefab: PackedScene
@export var pool_habitaciones: Array[ConfigHabitacion]

var registro_generadas: Dictionary = {}
var esta_generando: bool = false

func _ready():
	randomize()
	if habitacion_inicial_prefab:
		var habitacion_inicial = habitacion_inicial_prefab.instantiate()
		add_child(habitacion_inicial)
		habitacion_inicial.global_position = Vector3.ZERO
	else:
		push_error("Asigná una escena en 'Habitacion Inicial Prefab' en el Inspector")

func elegir_siguiente_habitacion() -> ConfigHabitacion:
	var opciones_validas: Array[ConfigHabitacion] = []
	var suma_pesos: float = 0.0
	
	for config in pool_habitaciones:
		var veces = registro_generadas.get(config.nombre_debug, 0)
		if config.limite_maximo == 0 or veces < config.limite_maximo:
			opciones_validas.append(config)
			suma_pesos += config.peso_probabilidad
			
	if opciones_validas.is_empty(): return null
		
	var tirada = randf_range(0.0, suma_pesos)
	var peso_acumulado: float = 0.0
	var seleccionada: ConfigHabitacion = null
	
	for config in opciones_validas:
		peso_acumulado += config.peso_probabilidad
		if tirada <= peso_acumulado:
			seleccionada = config
			break
			
	if seleccionada:
		registro_generadas[seleccionada.nombre_debug] = registro_generadas.get(seleccionada.nombre_debug, 0) + 1
		
	return seleccionada

# Nueva versión RECURSIVA. Por defecto, genera 3 habitaciones hacia adelante.
func conectar_nueva_habitacion(marker_salida_anterior: Marker3D, profundidad: int = 3):
	# Si llegamos al final de la cadena de recursión, cortamos.
	if profundidad <= 0:
		return
		
	if esta_generando and profundidad == 3:
		return # Solo bloqueamos el trigger inicial, no las llamadas recursivas
	esta_generando = true
	
	var config = elegir_siguiente_habitacion()
	if not config:
		esta_generando = false
		return
		
	var habitacion_nueva = config.escena.instantiate()
	add_child(habitacion_nueva)
	
	var nodo_conexiones = habitacion_nueva.get_node("Conexiones")
	if not nodo_conexiones or nodo_conexiones.get_child_count() == 0:
		esta_generando = false
		return
		
	# Elegimos qué marker de la nueva habitación usar como entrada
	var marker_entrada = nodo_conexiones.get_children().pick_random() as Marker3D
	
	# ALINEACIÓN MATEMÁTICA (Esto ya lo tenías)
	var rotacion_objetivo_y = marker_salida_anterior.global_rotation.y + PI
	habitacion_nueva.global_rotation.y += (rotacion_objetivo_y - marker_entrada.global_rotation.y)
	habitacion_nueva.global_position += (marker_salida_anterior.global_position - marker_entrada.global_position)
	
	# --- SISTEMA ANTI-COLISIONES ---
	var detector = habitacion_nueva.get_node("DetectorEspacio")
	
	# Esperamos un "tick" de físicas para que Godot actualice las cajas de colisión
	await get_tree().physics_frame
	
	# Revisamos si el detector está tocando la caja de otra habitación vieja
	if detector.has_overlapping_areas():
		print("Choque detectado. Destruyendo habitación superpuesta...")
		habitacion_nueva.queue_free()
		esta_generando = false
		
		# ACÁ VA EL PLAN B: 
		# Como no pudimos poner una habitación, te quedan dos opciones:
		# Opción A: No hacer nada (queda un agujero al vacío, ideal si vas a poner una puerta cerrada que no se abre).
		# Opción B (Recomendada): Instanciar una escena "Tapon.tscn" (una pared lisa) en el marker_salida_anterior.
		
		return # Cortamos la ejecución de esta rama para que no siga construyendo
	# --------------------------------
	
	# LIMPIEZA DE GATILLOS
	# 1. Borramos el gatillo de la entrada nueva (para que no genere hacia atrás)
	var gatillos_nuevos = habitacion_nueva.find_children("*", "Area3D")
	for gatillo in gatillos_nuevos:
		if "marker_asociado" in gatillo and gatillo.marker_asociado == marker_entrada:
			gatillo.queue_free()
			
	# RECURSIÓN: Generar el siguiente eslabón de la cadena
	var siguientes_conexiones = nodo_conexiones.get_children()
	for conector in siguientes_conexiones:
		# Ignoramos la puerta por la que acabamos de entrar
		if conector != marker_entrada:
			
			# Verificamos si todavía nos queda "energía" recursiva para seguir construyendo
			if profundidad > 1:
				# Como vamos a enchufar algo por código, sí borramos el gatillo
				for gatillo in gatillos_nuevos:
					if "marker_asociado" in gatillo and gatillo.marker_asociado == conector:
						gatillo.queue_free()
				
				# Llamada recursiva
				conectar_nueva_habitacion(conector, profundidad - 1)
			else:
				# Llegamos al borde (la última habitación de esta tanda).
				# NO BORRAMOS EL GATILLO. Se queda esperando a que el jugador lo pise
				# para detonar otra ráfaga de 3 habitaciones.
				pass
	
	await get_tree().create_timer(0.5).timeout
	esta_generando = false
