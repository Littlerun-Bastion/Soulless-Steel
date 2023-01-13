extends Node


func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		save_profile()


func save_and_quit():
	save_game()
	get_tree().quit()


func save_game():
	save_profile()


func load_game():
	load_profile()


func load_profile():
	var profile_file = File.new()
	var dir = Directory.new()
	
	if profile_file.file_exists("user://profile.backup"):
		push_warning("Something went wrong with profile in a previous sessions, trying to fix it")
		if not profile_file.file_exists("user://profile.save"):
			push_warning("No original profile found")
			#If there isn't an official profile, just rename the backup
			dir.rename("user://profile.backup", "user://profile.save")
		else:
			var backup_data
			var err = profile_file.open("user://profile.backup", File.READ)
			if err != OK:
				push_error("Error trying to open debug profile whilst fixing errors:" + str(err))
			while profile_file.get_position() < profile_file.get_len():
				# Get the saved dictionary from the next line in the save file
				backup_data = parse_json(profile_file.get_line())
			profile_file.close()
			if backup_data.has("time"):
				var profile_data
				err = profile_file.open("user://profile.save", File.READ)
				if err != OK:
					push_error("Error trying to open original profile whilst fixing errors:" + str(err))
				while profile_file.get_position() < profile_file.get_len():
					# Get the saved dictionary from the next line in the save file
					profile_data = parse_json(profile_file.get_line())
				profile_file.close()
				if profile_data.has("time"):
					if Debug.compare_datetimes(backup_data.time, profile_data.time):
						push_warning("Backup data is more recent... using backup")
						arquive_file("user://profile.save")
						dir.rename("user://profile.backup", "user://profile.save")
					else:
						push_warning("Original profile data is more recent... arquiving backup")
						arquive_file("user://profile.backup")
						dir.remove("user://profile.backup")
				else:
					push_warning("Profile data has no time information... using backup")
					arquive_file("user://profile.save")
					dir.rename("user://profile.backup", "user://profile.save")
			else:
				push_warning("Backup data has no time information... this shouldn't happen aaaah")
				arquive_file("user://profile.backup")
				
		push_warning("Fixed it!")


	if not profile_file.file_exists("user://profile.save"):
		push_warning("Profile file not found. Starting a new profile file.")
		save_profile()
		
	var err = profile_file.open("user://profile.save", File.READ)
	if err != OK:
		push_error("Error trying to open profile whilst loading:" + str(err))
		
	while profile_file.get_position() < profile_file.get_len():
		# Get the saved dictionary from the next line in the save file
		var data = parse_json(profile_file.get_line())
		Profile.set_save_data(data)
		break
		
	profile_file.close()


func save_profile():
	var profile_data = Profile.get_save_data()
	
	#First save on a separate file as to avoid corruption
	var backup_file = File.new()
	var err = backup_file.open("user://profile.backup", File.WRITE)
	if err != OK:
		push_error("Error trying to open backup profile whilst saving:" + str(err))
	backup_file.store_line(to_json(profile_data))
	backup_file.close()
	
	#Now save directly on official profile.save
	var profile_file = File.new()
	err = profile_file.open("user://profile.save", File.WRITE)
	if err != OK:
		push_error("Error trying to open profile whilst saving:" + str(err))
	profile_file.store_line(to_json(profile_data))
	profile_file.close()
	
	#If reached here, everything should be okay, lets delete the backup
	var dir = Directory.new()
	err = dir.remove("user://profile.backup")
	if err != OK:
		push_error("Error trying to delete backup profile whilst saving:" + str(err))


func has_mecha_design(name):
	var dir = Directory.new()
	if not dir.dir_exists("user://mecha_designs"):
		push_warning("Making mecha designs directory")
		var err = dir.make_dir("user://mecha_design")
		if err != OK:
			push_error("Error trying to create design directory: " + str(err))
			return false
	return dir.file_exists("user://mecha_designs/"+str(name)+".design")


func save_mecha_design(mecha, design_name):
	if has_mecha_design(design_name):
		push_warning("Overwritting previous mecha design named: " + str(design_name))
	
	var design_file = File.new()
	var err = design_file.open("user://mecha_designs/"+design_name+".design", File.WRITE)
	if err != OK:
		push_error("Error trying to create design file whilst saving: " + str(err))
	
	var data = mecha.get_design_data()
	design_file.store_line(to_json(data))
	design_file.close()


func load_mecha_design(design_name):
	if not has_mecha_design(design_name):
		push_error("Not an existing mecha design name: " + str(design_name))
		return false
		
	var design_file = File.new()
	var err = design_file.open("user://mecha_designs/"+design_name+".design", File.READ)
	if err != OK:
		push_error("Error trying to load mecha design file: " + str(err))
	
	var data = false
	while design_file.get_position() < design_file.get_len():
		data = parse_json(design_file.get_line())
		break
	
	design_file.close()
	return data


func get_all_mecha_design_names():
	var dir = Directory.new()
	if not dir.dir_exists("user://mecha_designs"):
		push_warning("Making mecha designs directory")
		dir.make_dir("user://mecha_design")
	
	var designs = []
	var err = dir.open("user://mecha_designs")
	if err == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name != "." and file_name != "..":
				var design_name = file_name.replace(".design", "")
				designs.append(design_name)
			file_name = dir.get_next()
	else:
		push_error("An error occurred when trying to access mecha designs dir path: " + str(err))
	
	return designs


func arquive_file(path, use_warning := true):
	var dir = Directory.new()
	if not dir.dir_exists("user://archived_files"):
		push_warning("Making archived files directory")
		dir.make_dir("user://archived_files")
	var date = OS.get_datetime()
	var archive_filename = str(date.year) + "y_" + str(date.month) + "mo_" + str(date.day) + "d_" +\
						   str(date.hour) + "h_" + str(date.minute) + "mi_" + str(date.second) + "s_" +\
						   str(randi()%1000) + "_" + path.lstrip("user://")
	var err =  dir.copy(path, "user://archived_files/" + archive_filename)
	if err != OK:
		push_error("Error trying to duplicate file whilst archiving:" + str(err))
	
	if use_warning:
		push_warning("Archived file: " + str(archive_filename))
	else:
		print("Archived file: " + str(archive_filename))
