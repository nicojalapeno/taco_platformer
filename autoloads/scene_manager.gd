extends Node

signal load_start(loading_screen)
signal scene_added(loaded_scene:Node, loading_screen)
signal load_complete(loaded_scene:Node)

signal _content_finished_loading(content)
signal _content_invalid(content_path:String)
signal _content_failed_to_load(content_path:String)

var _loading_screen_scene: PackedScene = preload("res://gui/menus/loading_screen.tscn")
var _loading_screen:LoadingScreen

var _transition:String
var _content_path:String # internal - stores the path to the asset SceneManager is trying to load
var _load_progress_timer:Timer # internal - Timer used to check in on load progress

# internal - Node into which we're loading the new scene, defaults to [code]get_tree().root[/code] if left [code]null[/null]
var _load_scene_into:Node 

# internal - Node we're unloading. Passing in [code]null[/code] for scene to unload will skip unloading process and add the new scene.
var _scene_to_unload:Node

# Used to block SceneManager from attempting to load two things at the same time
var _loading_in_progress:bool = false

func _ready() -> void:
	_content_invalid.connect(_on_content_invalid)
	_content_failed_to_load.connect(_on_content_failed_to_load)
	_content_finished_loading.connect(_on_content_finished_loading)


func _add_loading_screen(transition_type:String="fade_to_black"):
	_transition = "no_to_transition" if transition_type == "no_transition" else transition_type
	_loading_screen = _loading_screen_scene.instantiate() as LoadingScreen
	get_tree().root.add_child(_loading_screen)
	_loading_screen.start_transition(_transition)


func swap_scenes(scene_to_load:String, load_into:Node=null, scene_to_unload:Node=null, transition_type:String="fade_to_black") -> void:
	
	if _loading_in_progress:
		push_warning("SceneManager is already loading something")
		return
	
	_loading_in_progress = true
	if load_into == null: load_into = get_tree().root
	_load_scene_into = load_into
	_scene_to_unload = scene_to_unload
	
	_add_loading_screen(transition_type)
	_load_content(scene_to_load)	


func _load_content(content_path:String) -> void:
	
	load_start.emit(_loading_screen)
	
	_content_path = content_path
	var loader = ResourceLoader.load_threaded_request(content_path)
	if not ResourceLoader.exists(content_path) or loader == null:
		_content_invalid.emit(content_path)
		return 		
	
	_load_progress_timer = Timer.new()
	_load_progress_timer.wait_time = 0.1
	_load_progress_timer.timeout.connect(_monitor_load_status)
	
	get_tree().root.add_child(_load_progress_timer)
	_load_progress_timer.start()


func _monitor_load_status() -> void:
	var load_progress = []
	var load_status = ResourceLoader.load_threaded_get_status(_content_path, load_progress)

	match load_status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_content_invalid.emit(_content_path)
			_load_progress_timer.stop()
			return
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if _loading_screen != null:
				_loading_screen.update_bar(load_progress[0] * 100) # 0.1
		ResourceLoader.THREAD_LOAD_FAILED:
			_content_failed_to_load.emit(_content_path)
			_load_progress_timer.stop()
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			_load_progress_timer.stop()
			_load_progress_timer.queue_free()
			_content_finished_loading.emit(ResourceLoader.load_threaded_get(_content_path).instantiate())
			

func _on_content_failed_to_load(path:String) -> void:
	printerr("error: Failed to load resource: '%s'" % [path])	

func _on_content_invalid(path:String) -> void:
	printerr("error: Cannot load resource: '%s'" % [path])
	
func _on_content_finished_loading(incoming_scene) -> void:
	var outgoing_scene = _scene_to_unload
	
	# if our outgoing_scene has data to pass, give it to our incoming_scene
	if outgoing_scene != null:
		if outgoing_scene.has_method("get_data") and incoming_scene.has_method("receive_data"):
			incoming_scene.receive_data(outgoing_scene.get_data())
			
	# load the incoming into the designated node
	_load_scene_into.add_child(incoming_scene)
		# listen for this if you want to perform tasks on the scene immeidately after adding it to the tree
		# ex: moving the HUD back up to the top of the stack
	scene_added.emit(incoming_scene, _loading_screen)

	if _scene_to_unload != null:
		if _scene_to_unload != get_tree().root: 
			_scene_to_unload.queue_free()


	# called right after scene is added to tree (presuming _ready has fired)
	# ex: do some setup before player gains control (I'm using it to position the player) 
	if incoming_scene.has_method("init_scene"): 
		incoming_scene.init_scene()
	
	# probably not necessary since we split our _content_finished_loading but it won't hurt to have an extra check
	if _loading_screen != null:
		_loading_screen.finish_transition()
		
		# Wait or loading animation to finish
		await _loading_screen.anim_player.animation_finished

	# if your incoming scene implements init_scene() > call it here
	# ex: I'm using it to enable control of the player (they're locked while in transition)
	if incoming_scene.has_method("start_scene"): 
		incoming_scene.start_scene()
	
	# load is complete, free up SceneManager to load something else and report load_complete signal
	_loading_in_progress = false
	load_complete.emit(incoming_scene)
