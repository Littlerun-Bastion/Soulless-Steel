extends Node


func _notification(what):
	if what == MainLoop.NOTIFICATION_CRASH:
		save_profile()


func save_and_quit():
	save_game()
	get_tree().quit()


func save_game():
	save_profile()


func load_game():
	load_profile()


func load_profile():
	var profile_file
	if FileAccess.file_exists("user://profile.backup"):
		push_warning("Something went wrong with profile in a previous sessions, trying to fix it")
		if not FileAccess.file_exists("user://profile.save"):
			push_warning("No original profile found")
			#If there isn't an official profile, just rename the backup
			DirAccess.rename_absolute("user://profile.backup", "user://profile.save")
		else:
			var backup_data
			profile_file = FileAccess.open("user://profile.backup", FileAccess.READ)
			if not profile_file:
				push_error("Error trying to open debug profile whilst fixing errors:" + str(FileAccess.get_open_error()))
			while profile_file.get_position() < profile_file.get_length():
				# Get the saved dictionary from the next line in the save file
				var test_json_conv = JSON.new()
				test_json_conv.parse(profile_file.get_line())
				backup_data = test_json_conv.get_data()
			profile_file.close()
			if backup_data.has("time"):
				var profile_data
				profile_file = FileAccess.open("user://profile.save", FileAccess.READ)
				if not profile_file:
					push_error("Error trying to open original profile whilst fixing errors:" + str(FileAccess.get_open_error()))
				while profile_file.get_position() < profile_file.get_length():
					# Get the saved dictionary from the next line in the save file
					var test_json_conv = JSON.new()
					test_json_conv.parse(profile_file.get_line())
					profile_data = test_json_conv.get_data()
				profile_file.close()
				if profile_data.has("time"):
					if Debug.compare_datetimes(backup_data.time, profile_data.time):
						push_warning("Backup data is more recent... using backup")
						arquive_file("user://profile.save")
						DirAccess.rename_absolute("user://profile.backup", "user://profile.save")
					else:
						push_warning("Original profile data is more recent... arquiving backup")
						arquive_file("user://profile.backup")
						DirAccess.remove_absolute("user://profile.backup")
				else:
					push_warning("Profile data has no time information... using backup")
					arquive_file("user://profile.save")
					DirAccess.rename_absolute("user://profile.backup", "user://profile.save")
			else:
				push_warning("Backup data has no time information... this shouldn't happen aaaah")
				arquive_file("user://profile.backup")
				
		push_warning("Fixed it!")


	if not FileAccess.file_exists("user://profile.save"):
		push_warning("Profile file not found. Starting a new profile file.")
		save_profile()
		
	profile_file = FileAccess.open("user://profile.save", FileAccess.READ)
	if not profile_file:
		push_error("Error trying to open profile whilst loading:" + str(FileAccess.get_open_error()))
		
	while profile_file.get_position() < profile_file.get_length():
		# Get the saved dictionary from the next line in the save file
		var test_json_conv = JSON.new()
		test_json_conv.parse(profile_file.get_line())
		var data = test_json_conv.get_data()
		Profile.set_save_data(data)
		break
		
	profile_file.close()


func save_profile():
	var profile_data = Profile.get_save_data()
	
	#First save on a separate file as to avoid corruption
	var backup_file
	backup_file = FileAccess.open("user://profile.backup", FileAccess.WRITE)
	if not backup_file:
		push_error("Error trying to open backup profile whilst saving:" + str(FileAccess.get_open_error()))
	backup_file.store_line(JSON.stringify(profile_data))
	backup_file.close()
	
	#Now save directly on official profile.save
	var profile_file
	profile_file = FileAccess.open("user://profile.save", FileAccess.WRITE)
	if not profile_file:
		push_error("Error trying to open profile whilst saving:" + str(FileAccess.get_open_error()))
	profile_file.store_line(JSON.stringify(profile_data))
	profile_file.close()
	
	#If reached here, everything should be okay, lets delete the backup
	var err = DirAccess.remove_absolute("user://profile.backup")
	if err != OK:
		push_error("Error trying to delete backup profile whilst saving:" + str(err))


func has_mecha_design(design_name):
	if not DirAccess.dir_exists_absolute("user://mecha_designs"):
		push_warning("Making mecha designs directory")
		var err = DirAccess.make_dir_absolute("user://mecha_designs")
		if err != OK:
			push_error("Error trying to create design directory: " + str(err))
			return false
	return FileAccess.file_exists("user://mecha_designs/"+str(design_name)+".design")


func save_mecha_design(mecha, design_name):
	if has_mecha_design(design_name):
		push_warning("Overwritting previous mecha design named: " + str(design_name))
	
	var design_file
	design_file = FileAccess.open("user://mecha_designs/"+design_name+".design", FileAccess.WRITE)
	if not design_file:
		push_error("Error trying to create design file whilst saving: " + str(FileAccess.get_open_error()))
	
	var data = mecha.get_design_data()
	design_file.store_line(JSON.stringify(data))
	design_file.close()


func load_mecha_design(design_name):
	if not has_mecha_design(design_name):
		push_error("Not an existing mecha design name: " + str(design_name))
		return false
		
	var design_file
	design_file = FileAccess.open("user://mecha_designs/"+design_name+".design", FileAccess.READ)
	if not design_file:
		push_error("Error trying to load mecha design file: " + str(FileAccess.get_open_error()))
	
	var data = false
	while design_file.get_position() < design_file.get_length():
		var test_json_conv = JSON.new()
		test_json_conv.parse(design_file.get_line())
		data = test_json_conv.get_data()
		break
	
	design_file.close()
	return data


func get_all_mecha_design_names():
	if not DirAccess.dir_exists_absolute("user://mecha_designs"):
		push_warning("Making mecha designs directory")
		var err = DirAccess.make_dir_absolute("user://mecha_designs")
		if err != OK:
			push_error("Error trying to create design directory: " + str(err))
			return false
	
	var designs = []
	var dir = DirAccess.open("user://mecha_designs")
	if dir:
		dir.list_dir_begin() # TODOGODOT4 fill missing arguments https://github.com/godotengine/godot/pull/40547
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				var design_name = file_name.replace(".design", "")
				designs.append(design_name)
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access mecha designs dir path: " + str(DirAccess.get_open_error()))
	
	return designs


func arquive_file(path, use_warning := true):
	if not DirAccess.dir_exists_absolute("user://archived_files"):
		push_warning("Making archived files directory")
		DirAccess.make_dir_absolute("user://archived_files")
	var date = Time.get_datetime_dict_from_system()
	var archive_filename = str(date.year) + "y_" + str(date.month) + "mo_" + str(date.day) + "d_" +\
							str(date.hour) + "h_" + str(date.minute) + "mi_" + str(date.second) + "s_" +\
							str(randi()%1000) + "_" + path.lstrip("user://")
	var err =  DirAccess.copy_absolute(path, "user://archived_files/" + archive_filename)
	if err != OK:
		push_error("Error trying to duplicate file whilst archiving:" + str(err))
	
	if use_warning:
		push_warning("Archived file: " + str(archive_filename))
	else:
		print("Archived file: " + str(archive_filename))
