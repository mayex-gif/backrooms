extends Area3D

# Guardamos una referencia al Marker3D que está en esta misma puerta
@export var marker_asociado: Marker3D

# Referencia al generador maestro (la buscamos al iniciar)
var generador_maestro: Node3D

func _ready():
	# Buscamos el generador en la escena principal. 
	# Asegurate de que tu GeneradorNivel esté en el árbol principal (Main)
	generador_maestro = get_tree().get_first_node_in_group("generadores")
	
	# Conectamos la señal de colisión por código
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	# Verificamos que el que cruzó la puerta sea el jugador
	if body.name == "Jugador":
		if generador_maestro and marker_asociado:
			# Le pasamos el Marker a la función que ya comprobaste que funciona
			generador_maestro.conectar_nueva_habitacion(marker_asociado)
			
			# Destruimos este gatillo para que no genere infinitas habitaciones 
			# si el jugador se queda parado en el marco de la puerta
			queue_free()
