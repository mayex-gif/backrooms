extends Node3D

@export var radio_carga: float = 100.0 # Reducido a 30m para optimizar más (ajustar a gusto)
const INTERVALO_ESCANEO: float = 0.5 

var jugador: CharacterBody3D = null
var tiempo_acumulado: float = 0.0

# Almacenamos las referencias acá en lugar de buscar en el árbol de nodos
var lista_habitaciones: Array[Node3D] = []

func _ready():
	jugador = get_tree().get_first_node_in_group("jugador") as CharacterBody3D

func _process(delta: float) -> void:
	if not jugador:
		# Intento de re-vinculación por si el jugador tarda en spawnear
		jugador = get_tree().get_first_node_in_group("jugador") as CharacterBody3D
		return
		
	tiempo_acumulado += delta
	if tiempo_acumulado >= INTERVALO_ESCANEO:
		tiempo_acumulado = 0.0
		_gestionar_habitaciones()

# Función pública que llamará el generador para registrar habitaciones nuevas
func registrar_habitacion(hab: Node3D):
	if not lista_habitaciones.has(hab):
		lista_habitaciones.append(hab)
		# La apagamos por defecto al spawnear si está lejos del origen
		_evaluar_habitacion(hab)

func _gestionar_habitaciones():
	for i in range(lista_habitaciones.size() - 1, -1, -1):
		var hab = lista_habitaciones[i]
		
		# Seguro por si borrás alguna habitación en tiempo de ejecución
		if not is_instance_valid(hab):
			lista_habitaciones.remove_at(i)
			continue
			
		_evaluar_habitacion(hab)

func _evaluar_habitacion(hab: Node3D):
	var distancia = jugador.global_position.distance_to(hab.global_position)
	
	if distancia <= radio_carga:
		if not hab.visible:
			hab.visible = true
			hab.process_mode = Node.PROCESS_MODE_INHERIT 
	else:
		if hab.visible:
			hab.visible = false
			hab.process_mode = Node.PROCESS_MODE_DISABLED
