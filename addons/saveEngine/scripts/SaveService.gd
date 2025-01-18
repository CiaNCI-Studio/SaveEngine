extends Node

signal loadCompleted
signal loadStarted
signal saveCompleted
signal saveStarted

const  PERSISTENCE_GROUP : String = "persist"
const  SETTINGS_FOLDER_PATH : String = "res://Data/Settings/"
const  SETTINGS_FILE_NAME : String = "saveSettings.cfg"
const  IGNORE_GLOBAL_PROPERTIES : Array[String] = ["Auto Translate",
													"Editor Description",
													"GameState.gd",
													"Node",
													"Physics Interpolation",
													"Process",
													"Thread Group",
													"_import_path",
													"auto_translate_mode",
													"editor_description",
													"multiplayer",
													"name",
													"owner",
													"physics_interpolation_mode",
													"process_mode",
													"process_physics_priority",
													"process_priority",
													"process_thread_group",
													"process_thread_group_order",
													"process_thread_messages",
													"scene_file_path",
													"script",
													"unique_name_in_owner"]

@export var CurrentLoadedSlot : SaveFile
@export var Settings : SaveSettigns

func _ready() -> void:
	__EnsureSettingsFolder()
	__LoadSettings()
	__EnsureSaveFolder()

func NewSlot(slotId : String = "", name : String = "", currentScene : String = "", metaData : Dictionary = {}) -> bool:			
	var currentSlots = GetSlots()
	if currentSlots.any(func(slot:SaveFile): return slot.SlotId == slotId):
		return false
	CurrentLoadedSlot = SaveFile.new()
	if not slotId.is_empty():		
		CurrentLoadedSlot.SlotId = slotId
	else: 
		CurrentLoadedSlot.SlotId = __GetDateTime()
	if not name.is_empty():		
		CurrentLoadedSlot.Name = name
	else: 
		CurrentLoadedSlot.Name = "SaveSlot"
		
	if not currentScene.is_empty():		
		CurrentLoadedSlot.CurrentSceneId = currentScene
	else: 
		CurrentLoadedSlot.CurrentSceneId = get_tree().current_scene.scene_file_path
	
	CurrentLoadedSlot.MetaData = metaData		
	CurrentLoadedSlot.LastTime = Time.get_unix_time_from_system()
	CurrentLoadedSlot.GameTime = 0
	
	return SaveGame(false)
	
func DeleteSlot(slotId : String) -> bool:
	var filePath = Settings.SaveFilesPrefix + Settings.SaveFolderPath + slotId + ".sav"
	var fileMetaPath = Settings.SaveFilesPrefix + Settings.SaveFolderPath + slotId + ".meta.sav"
	if FileAccess.file_exists(filePath) and FileAccess.file_exists(fileMetaPath):		
		DirAccess.remove_absolute(filePath)
		DirAccess.remove_absolute(fileMetaPath)	
	else:
		return false
	return true
	
func SaveGame(autoSetCurrentScene = true) -> bool:
	if not CurrentLoadedSlot:		
		return false
	emit_signal("saveStarted")	
	CurrentLoadedSlot.GlobalData = __GetGlobalData()
	CurrentLoadedSlot.DateTime = Time.get_datetime_dict_from_system()	
	CurrentLoadedSlot.GameTime = CurrentLoadedSlot.GameTime + (Time.get_unix_time_from_system() - CurrentLoadedSlot.LastTime)
	CurrentLoadedSlot.LastTime = Time.get_unix_time_from_system()	
	if autoSetCurrentScene:
		CurrentLoadedSlot.CurrentSceneId = get_tree().current_scene.scene_file_path
	CurrentLoadedSlot.Hash = ""	
	var serialized = __SerializeSaveFile(CurrentLoadedSlot)
	var filePath = Settings.SaveFilesPrefix + Settings.SaveFolderPath + CurrentLoadedSlot.SlotId + ".sav"
	var file = FileAccess.open(filePath, FileAccess.WRITE)
	file.store_string(serialized)
	file.close()
	__SaveMetaFile(CurrentLoadedSlot, filePath)	
	emit_signal("saveCompleted")
	return true
	
func LoadGame(slotId : String) -> bool:
	emit_signal("loadStarted")
	if not __ValidateMetaFile(slotId):
		emit_signal("loadCompleted")	
		return false
		
	var filePath = Settings.SaveFilesPrefix + Settings.SaveFolderPath + slotId + ".sav"	
	var file = FileAccess.open(filePath, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	CurrentLoadedSlot = __DeserializeSaveFile(content)
	CurrentLoadedSlot.LastTime = Time.get_unix_time_from_system()
	__ApplyGlobalData()	
	emit_signal("loadCompleted")
	return true
	
func GetSlots() -> Array[SaveFile]:
	var result : Array[SaveFile] = []	
	var files : Array[String] = []
	files.append_array(DirAccess.get_files_at(Settings.SaveFolderPath))
	files = files.filter(func(item : String) : return item.ends_with(".meta.sav"))	
	for filePath in files:
		var file = FileAccess.open(Settings.SaveFolderPath + filePath, FileAccess.READ)
		var fileContent = file.get_as_text()
		file.close()
		result.append(__DeserializeSaveFile(fileContent))	
	return result

func __ApplyGlobalData():
	if not CurrentLoadedSlot:		
		return
	for autoload in get_tree().root.get_children():		
		if CurrentLoadedSlot.GlobalData.any(func(item : SaveFileGlobal) : return item.GlobalClassName == autoload.name):	
			var stored : SaveFileGlobal = CurrentLoadedSlot.GlobalData.filter(func(item : SaveFileGlobal) : return item.GlobalClassName == autoload.name)[0]
			for property in stored.GlobalData:
				autoload.set(property, SaveSerializationHelper.DeserializeVariable(stored.GlobalData[property]))
			

func __GetGlobalData() -> Array[SaveFileGlobal]:
	var result : Array[SaveFileGlobal] = []
	
	for autoload in get_tree().root.get_children():
		if __ValidateAutoload(autoload):
			result.append(__SerializeGlobal(autoload))			
	
	return result

func __ValidateAutoload(autoload) -> bool:
	var result = autoload != get_tree().get_current_scene() and autoload != self	
	if len(Settings.StaticScriptsToSave) > 0:
		result = result and Settings.StaticScriptsToSave.any(func(item : String): return autoload.script and autoload.script.resource_path.ends_with(item)) 

	return result	

func __SerializeGlobal(autoload : Node) -> SaveFileGlobal:
	var result = SaveFileGlobal.new()
	result.GlobalClassName = autoload.name
	result.GlobalId = autoload.get_script().resource_path
	result.GlobalData = {}
	for property in autoload.get_property_list():
		if __ValidateGlobalProperty(property["name"]):
			result.GlobalData.get_or_add(property["name"], SaveSerializationHelper.SerializeVariable(autoload.get(property["name"])))
	return result
	
func __ValidateGlobalProperty(propertyName) -> bool:
	return not IGNORE_GLOBAL_PROPERTIES.any(func(item): return propertyName == item)
	
func __SerializeSaveFile(saveFile : SaveFile) -> String:
	var result : Dictionary = {
		"Version" : saveFile.Version,
		"SlotId" : saveFile.SlotId,
		"Name" : saveFile.Name,
		"DateTime" : saveFile.DateTime,
		"LastTime" : saveFile.LastTime,
		"GameTime" : saveFile.GameTime,
		"Hash" : saveFile.Hash,
		"CurrentSceneId" : saveFile.CurrentSceneId,
		"MetaData" : saveFile.MetaData,
		"GlobalData" : saveFile.GlobalData.map(func(item: SaveFileGlobal): return {"GlobalId": item.GlobalId, "GlobalClassName": item.GlobalClassName, "GlobalData" : item.GlobalData }),
		"ScenesData" : saveFile.ScenesData.map(__GetSceneDictionary)
	}
	return JSON.stringify(result)
	
func __DeserializeSaveFile(saveContent : String) -> SaveFile:
	var result = SaveFile.new()
	var json = JSON.parse_string(saveContent)
	result.Version = json["Version"]
	result.SlotId = json["SlotId"]
	result.Name = json["Name"]
	result.DateTime = json["DateTime"]
	result.LastTime = json["LastTime"]
	result.GameTime = json["GameTime"]
	result.Hash = json["Hash"]
	result.CurrentSceneId = json["CurrentSceneId"]
	result.MetaData = json["MetaData"]
	result.GlobalData.append_array(json["GlobalData"].map(
		func(item): 
			var globalResult = SaveFileGlobal.new()
			globalResult.GlobalId = item["GlobalId"]
			globalResult.GlobalClassName = item["GlobalClassName"]
			globalResult.GlobalData = item["GlobalData"]
			return globalResult))		
	result.ScenesData.append_array(__GetScenesData(json["ScenesData"]))
	return result
	
func __ValidateMetaFile(slotId : String) -> bool:
	var metaFilePath = Settings.SaveFilesPrefix + Settings.SaveFolderPath + slotId + ".meta.sav"
	var file = FileAccess.open(metaFilePath, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var metaFile = __DeserializeSaveFile(content)
	var filePath = Settings.SaveFilesPrefix + Settings.SaveFolderPath + slotId + ".sav"
	var hash = __GetFileHash(filePath)
	return hash == metaFile.Hash	

func __SaveMetaFile(saveFile : SaveFile, filePath : String):
	var metaFile = SaveFile.new()
	metaFile.SlotId = saveFile.SlotId
	metaFile.Name = saveFile.Name
	metaFile.DateTime = Time.get_datetime_dict_from_system()
	metaFile.LastTime = saveFile.LastTime
	metaFile.GameTime = saveFile.GameTime	
	metaFile.Version = saveFile.Version
	metaFile.MetaData = saveFile.MetaData
	metaFile.CurrentSceneId = saveFile.CurrentSceneId
	var hash = __GetFileHash(filePath)
	if hash.is_empty():
		return ""
	metaFile.Hash = hash
	var metaFilePath = filePath.replace(".sav", ".meta.sav")
	var file = FileAccess.open(metaFilePath, FileAccess.WRITE)
	file.store_string(__SerializeSaveFile(metaFile))
	file.close()
	
func __GetFileHash(filePath : String) -> String:
	var file = FileAccess.open(filePath, FileAccess.READ)
	if file == null or not file.is_open():
		return ""
	var content = file.get_as_text()
	file.close()
	content = content + Settings.HashSalt
	return content.md5_text()
	
func __GetDateTime() -> String:
	var dateTime = Time.get_datetime_dict_from_system()
	return "%d%02d%02d_%02d%02d%02d" % [dateTime["year"], dateTime["month"], dateTime["day"], dateTime["hour"], dateTime["minute"], dateTime["second"]]
	
func __EnsureSaveFolder():
	if not DirAccess.dir_exists_absolute(Settings.SaveFolderPath):
		DirAccess.make_dir_recursive_absolute(Settings.SaveFolderPath)

func __EnsureSettingsFolder():
	if not DirAccess.dir_exists_absolute(SETTINGS_FOLDER_PATH):
		DirAccess.make_dir_recursive_absolute(SETTINGS_FOLDER_PATH)
	
func __LoadSettings():
	Settings = SaveSettigns.new()	
	if FileAccess.file_exists(SETTINGS_FOLDER_PATH + SETTINGS_FILE_NAME):
		var file = FileAccess.open(SETTINGS_FOLDER_PATH + SETTINGS_FILE_NAME, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		var json = JSON.parse_string(content)
		Settings.SaveFilesPrefix = json["SaveFilesPrefix"]
		Settings.StaticScriptsToSave.append_array(json["StaticScriptsToSave"])
	else:
		__CreateSettingsFile()
		
func __CreateSettingsFile():		
	if not FileAccess.file_exists(SETTINGS_FOLDER_PATH + SETTINGS_FILE_NAME):
		var file = FileAccess.open(SETTINGS_FOLDER_PATH + SETTINGS_FILE_NAME, FileAccess.WRITE)		
		var settings = SaveSettigns.new()
		var settingsDict = {
				"SaveFilesPrefix": settings.SaveFilesPrefix, 
				"StaticScriptsToSave": settings.StaticScriptsToSave, 
				"SaveFolderPath": settings.SaveFolderPath, 
				"HashSalt": settings.HashSalt
			}
		file.store_string(JSON.stringify(settingsDict))
		file.close()
		
func __GetSceneDictionary(sceneData : SaveFileScene) -> Dictionary:
	return {			
			"ScenePath": sceneData.ScenePath, 
			"SceneNodes" : sceneData.SceneNodes.map(__GetNodeDictionary) 
		}	
	
func __GetNodeDictionary(sceneNode : SaveFileNode) -> Dictionary:
	return {
			"NodeTreePath": sceneNode.NodeTreePath, 
			"ParentTreePath": sceneNode.ParentTreePath, 
			"NodeFilePath" : sceneNode.NodeFilePath,
			"NodeScriptPath" : sceneNode.NodeScriptPath,
			"NodeProperties" : sceneNode.NodeProperties
		}

func __GetScenesData(data) -> Array[SaveFileScene]:
	var result : Array[SaveFileScene]
	result.append_array(data.map(
		func(item): 
			var sceneResult = SaveFileScene.new()
			sceneResult.ScenePath = item["ScenePath"]
			sceneResult.SceneNodes.append_array(__GetSceneNodes(item["SceneNodes"]))
			return sceneResult
	))
	return result
	
func __GetSceneNodes(data) -> Array[SaveFileNode]:
	var result : Array[SaveFileNode]
	result.append_array(data.map(
		func(item): 
			var nodeResult = SaveFileNode.new()
			nodeResult.NodeTreePath = item["NodeTreePath"]
			nodeResult.ParentTreePath = item["ParentTreePath"]
			nodeResult.NodeFilePath = item["NodeFilePath"]			
			nodeResult.NodeScriptPath = item["NodeScriptPath"]
			nodeResult.NodeProperties = item["NodeProperties"]
			return nodeResult
	))
	return result
