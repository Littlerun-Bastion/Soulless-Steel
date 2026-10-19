extends TestSuite

# SaveFileTest: the profile on disk, through FileManager for real: saving and
# loading everything back, the "no profile loaded" guard, creating a new
# profile, recovering from the backup file after an interrupted save, and
# resolving an expedition the game closed in the middle of.
#
# Every file here is a test file (TestSuite points FileManager at
# user://test/); the real profile is never read or written.


const REAL_PROFILE := "user://profile.save"


func run_tests() -> void:
	var real_modified := FileAccess.get_modified_time(REAL_PROFILE)
	await case("save and load round trip", _test_round_trip)
	await case("nothing is saved before a profile is loaded", _test_save_guard)
	await case("a new profile is created when there is none", _test_new_profile)
	await case("a newer backup is recovered", _test_newer_backup)
	await case("an older backup is archived", _test_older_backup)
	await case("a backup without its profile becomes the profile", _test_backup_only)
	await case("an expedition left running is lost on the next boot", _test_abandoned_on_boot)
	await case("the real profile was never touched", func():
		check_eq(FileAccess.get_modified_time(REAL_PROFILE), real_modified, "user://profile.save unchanged"))


func before_each() -> void:
	remove_test_files()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	PlayerProgress.reset()
	FileManager.profile_loaded = false


# ---- Helpers ----

func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_line(JSON.stringify(data))
	file.close()


func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_line()) if file != null else null
	return data if data is Dictionary else {}


# A full profile (as the game saves it) with this much money and save time.
func _profile_with(money: float, year: int) -> Dictionary:
	PlayerProgress.reset()
	PlayerProgress.add_money(money, false)
	var data: Dictionary = JSON.parse_string(JSON.stringify(Profile.get_save_data()))
	data["time"]["year"] = year
	PlayerProgress.reset()
	return data


func _archived_files() -> Array:
	return Array(DirAccess.get_files_at(FileManager.archive_dir)) if DirAccess.dir_exists_absolute(FileManager.archive_dir) else []


# ---- Cases ----

func _test_round_trip() -> void:
	PlayerProgress.add_money(4321, false)
	PlayerProgress.add_part("arm_weapon", "Clarent-01", false)
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 8)
	cargo.add_stack_anywhere(item_stack.from_generic(load("res://database/items/salvage/control_module.tres")))
	PlayerProgress.set_mech_inventory(cargo)
	PlayerProgress.add_materials({"steel": 12, "avidendrites": 1}, false)
	var design := PlayerProgress.DEFAULT_MECHA.duplicate()
	design["arm_weapon_right"] = "OM1804"
	PlayerProgress.set_current_mecha(design, false)
	StoryDirector.set_flag("save_test", 7, false)

	FileManager.profile_loaded = true
	FileManager.save_profile()
	check(FileAccess.file_exists(FileManager.profile_path), "the profile file was written")
	check(not FileAccess.file_exists(FileManager.backup_path), "the backup is removed after a good save")

	PlayerProgress.reset()
	StoryDirector.reset(false)
	FileManager.load_profile()
	check_eq(PlayerProgress.get_money(), 4321.0, "money")
	check_eq(PlayerProgress.count_part("arm_weapon", "Clarent-01"), 1, "stash part")
	check(PlayerProgress.get_mech_inventory().get_stacks().any(func(s): return s.item != null and s.item.id == "control_module"), "cargo item")
	check_eq(PlayerProgress.get_materials(), {"steel": 12, "avidendrites": 1}, "materials")
	check_eq(PlayerProgress.get_current_mecha()["arm_weapon_right"], "OM1804", "mecha design")
	check_eq(StoryDirector.get_flag("save_test"), 7, "story flag")
	check(FileManager.profile_loaded, "the profile counts as loaded")


func _test_save_guard() -> void:
	FileManager.profile_loaded = false
	FileManager.save_profile()
	check(not FileAccess.file_exists(FileManager.profile_path), "save refused before a profile is loaded")


func _test_new_profile() -> void:
	FileManager.load_profile()
	check(FileAccess.file_exists(FileManager.profile_path), "a fresh profile was created")
	check(FileManager.profile_loaded, "and counts as loaded")
	check_eq(PlayerProgress.get_current_mecha(), PlayerProgress.DEFAULT_MECHA, "starting with the default mecha")


# The backup is written first on every save; finding one means the last
# save was interrupted. The newer of the two wins, the other is archived.
func _test_newer_backup() -> void:
	_write(FileManager.profile_path, _profile_with(100, 2020))
	_write(FileManager.backup_path, _profile_with(200, 2030))
	FileManager.load_profile()
	check_eq(PlayerProgress.get_money(), 200.0, "the newer backup's progress was loaded")
	check(not FileAccess.file_exists(FileManager.backup_path), "the backup became the profile")
	check(_archived_files().size() == 1, "the old profile was archived, not deleted")


func _test_older_backup() -> void:
	_write(FileManager.profile_path, _profile_with(300, 2030))
	_write(FileManager.backup_path, _profile_with(400, 2020))
	FileManager.load_profile()
	check_eq(PlayerProgress.get_money(), 300.0, "the newer profile was kept")
	check(not FileAccess.file_exists(FileManager.backup_path), "the stale backup was cleared")
	check(_archived_files().size() == 1, "and archived")


func _test_backup_only() -> void:
	_write(FileManager.backup_path, _profile_with(500, 2030))
	FileManager.load_profile()
	check_eq(PlayerProgress.get_money(), 500.0, "the backup's progress was loaded")
	check(FileAccess.file_exists(FileManager.profile_path) and not FileAccess.file_exists(FileManager.backup_path),
			"the backup was renamed to the profile")


func _test_abandoned_on_boot() -> void:
	var cargo := Inventory.new()
	cargo.initialize_grid(6, 8)
	cargo.add_stack_anywhere(item_stack.from_generic(load("res://database/items/salvage/control_module.tres")))
	PlayerProgress.set_mech_inventory(cargo)
	PlayerProgress.begin_expedition()
	FileManager.profile_loaded = true
	FileManager.save_profile()  # as if the game closed mid-run
	check(_read(FileManager.profile_path)["progress"]["in_expedition"], "the save says a run was in progress")

	PlayerProgress.reset()
	FileManager.load_game()
	check(not PlayerProgress.is_in_expedition(), "the run is over after loading")
	check(PlayerProgress.get_mech_inventory().is_empty(), "its cargo is lost")
	check(PlayerProgress.has_loss_report(), "the main menu will say what was lost")
	check_eq(PlayerProgress.take_loss_report().get("reason"), PlayerProgress.LOSS_ABANDONED, "as abandoned")
