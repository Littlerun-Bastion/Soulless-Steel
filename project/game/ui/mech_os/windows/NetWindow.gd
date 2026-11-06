extends MechWindow
class_name NetWindow

## NET: the in-fiction web browser (the sidebar's NET; Hangar only for now,
## see HangarScreen). From the top:
##   toolbar     BACK, FWD, RELOAD (STOP while a page loads), HOME, and the
##               address field (Enter loads what's typed)
##   favorites   the sites on NetSites.FAVORITES and a Manufacturers menu;
##               the open site shows bright
##   page area   the page (NetPage) in a sunken well that scrolls
##   status bar  what's happening (a link's address while the mouse is over
##               it), the load bar, the modem speed and the balance
##
## Every load takes a while, like a 1999 modem (NetLoad): LOAD_MIN-LOAD_MAX
## seconds for a page not yet seen this session, CACHED_MIN-CACHED_MAX for
## one that has been. The page is built when the load starts, kept hidden,
## and swapped in for the old one when the load ends, so a load never fails
## for being slow to build. load_time_scale stretches every load; 0 (tests)
## or LOAD_ENABLED off makes them instant. The window's rng draws every
## random number, so a test can seed it.
##
## History: going somewhere new puts the open page on the back list and
## clears the forward list; BACK and FWD move between them; RELOAD loads the
## open address again. A load that's stopped or replaced leaves the history
## as it was.

const HOME_URL := "amazing.com"
const LOAD_ENABLED := true
const LOAD_MIN := 1.0
const LOAD_MAX := 3.0
const CACHED_MIN := 0.3
const CACHED_MAX := 0.8
const TITLE_PREFIX := "NET // "
const SPEED_TEXT := "14.4 KBPS"
const DONE_TEXT := "Document: Done."
const STOPPED_TEXT := "Transfer interrupted!"

## Seconds of game time per second of a load's plan; 0 = instant.
static var load_time_scale := 1.0
## Addresses loaded this session: they load faster (CACHED_MIN-CACHED_MAX).
static var visited: Dictionary = {}

var rng := RandomNumberGenerator.new()
var current_url := ""
var page: NetPage = null
var back_history: Array = []
var forward_history: Array = []
var loading := false

var back_button: Button
var forward_button: Button
var reload_button: Button
var home_button: Button
var address_field: LineEdit
var status_label: Label
var load_bar: NetLoadBar
var balance_label: Label

var _pending_page: NetPage = null
var _pending_url := ""
var _pending_back: Array = []
var _pending_forward: Array = []
var _plan: NetLoad = null
var _clock := 0.0
var _load_status := DONE_TEXT
var _hover_url := ""
var _favorites: Dictionary = {}  # domain -> LinkButton
var _makers_link: LinkButton
var _page_holder: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	rng.randomize()


func _ready() -> void:
	super()
	_build()
	PlayerProgress.money_changed.connect(_on_money_changed)
	_on_money_changed(PlayerProgress.get_money())
	_update_buttons()
	_open_home_if_blank.call_deferred()


func _process(delta: float) -> void:
	if not loading:
		return
	_clock += delta / load_time_scale if load_time_scale > 0.0 else _plan.duration
	if _clock >= _plan.duration:
		_finish_load()
	else:
		_update_load_ui()


# ---- going places ---------------------------------------------------------

## Loads an address as a new page (Enter in the address field, a link).
func navigate(address: String) -> void:
	var parsed := NetSites.parse(address)
	if parsed.domain == "":
		return
	if parsed.url == current_url:
		reload()
		return
	var back := back_history.duplicate()
	if current_url != "":
		back.append(current_url)
	_start_load(parsed, back, [])


func go_back() -> void:
	if back_history.is_empty():
		return
	var back := back_history.duplicate()
	var url: String = back.pop_back()
	var forward := forward_history.duplicate()
	forward.append(current_url)
	_start_load(NetSites.parse(url), back, forward)


func go_forward() -> void:
	if forward_history.is_empty():
		return
	var forward := forward_history.duplicate()
	var url: String = forward.pop_back()
	var back := back_history.duplicate()
	back.append(current_url)
	_start_load(NetSites.parse(url), back, forward)


func reload() -> void:
	if current_url == "":
		go_home()
		return
	_start_load(NetSites.parse(current_url), back_history.duplicate(), forward_history.duplicate())


func go_home() -> void:
	navigate(HOME_URL)


## Stops the load in progress; the open page stays.
func stop() -> void:
	if not loading:
		return
	_cancel_load()
	_load_status = STOPPED_TEXT
	address_field.text = NetSites.display(current_url)
	_refresh_status()
	_update_buttons()


func is_loading() -> bool:
	return loading


## 0-100 while a page loads, 0 otherwise.
func load_progress() -> int:
	return load_bar.progress


## Seconds into the load in progress (the plan's clock).
func load_elapsed() -> float:
	return _clock


## How long the load in progress takes in all, 0 when none.
func load_duration() -> float:
	return _plan.duration if _plan != null else 0.0


func get_status_text() -> String:
	return status_label.text


func get_title_text() -> String:
	return title_label.text


# ---- loading --------------------------------------------------------------

func _start_load(parsed: Dictionary, back: Array, forward: Array) -> void:
	_cancel_load()
	_pending_url = parsed.url
	_pending_back = back
	_pending_forward = forward
	var new_page := NetSites.build(parsed.domain)
	new_page.navigate_requested.connect(navigate)
	new_page.link_hovered.connect(_on_link_hovered)
	new_page.visible = false
	_page_holder.add_child(new_page)
	new_page.open(parsed.path, parsed.query)
	_pending_page = new_page
	address_field.text = NetSites.display(parsed.url)
	if not LOAD_ENABLED or load_time_scale <= 0.0:
		_plan = null
		_finish_load()
		return
	var cached := visited.has(parsed.url)
	var duration := rng.randf_range(CACHED_MIN, CACHED_MAX) if cached else rng.randf_range(LOAD_MIN, LOAD_MAX)
	_plan = NetLoad.plan_failed(duration) if NetSites.kind_of(parsed.domain) == NetSites.UNKNOWN \
			else NetLoad.plan(rng, duration)
	_clock = 0.0
	loading = true
	_update_load_ui()
	_update_buttons()


func _finish_load() -> void:
	loading = false
	var failed := NetSites.kind_of(NetSites.parse(_pending_url).domain) == NetSites.UNKNOWN
	current_url = _pending_url
	back_history = _pending_back
	forward_history = _pending_forward
	if is_instance_valid(page):
		_page_holder.remove_child(page)
		page.queue_free()
	page = _pending_page
	_pending_page = null
	page.visible = true
	_scroll.scroll_vertical = 0
	if not failed:
		visited[current_url] = true
	_load_status = "Unable to locate the server: %s" % page.domain if failed else DONE_TEXT
	window_title = TITLE_PREFIX + page.page_title
	title_label.text = window_title
	load_bar.progress = 0
	_plan = null
	_clock = 0.0
	_hover_url = ""
	_refresh_status()
	_update_favorites()
	_update_buttons()


func _cancel_load() -> void:
	if is_instance_valid(_pending_page):
		_page_holder.remove_child(_pending_page)
		_pending_page.queue_free()
	_pending_page = null
	loading = false
	_plan = null
	_clock = 0.0
	if load_bar != null:
		load_bar.progress = 0


func _update_load_ui() -> void:
	var host: String = NetSites.parse(_pending_url).domain
	var percent := _plan.progress_at(_clock)
	var phase := _plan.phase_at(_clock)
	if phase == NetLoad.Phase.LOOKUP:
		_load_status = "Looking up host: %s..." % host
	elif phase == NetLoad.Phase.CONTACT:
		_load_status = "Contacting host: %s..." % host
	elif phase == NetLoad.Phase.WAIT:
		_load_status = "Host contacted. Waiting for reply..."
	else:
		_load_status = "Transferring data from %s... (%d%%)" % [host, percent]
	load_bar.progress = percent
	_refresh_status()


func _open_home_if_blank() -> void:
	if current_url == "" and not loading:
		go_home()


# ---- building -------------------------------------------------------------

func _build() -> void:
	content.theme_type_variation = &"WindowContentFlush"
	var column := MechUI.vbox(&"PaneStack")
	content.add_child(column)

	var toolbar := MechUI.hbox(&"NetToolbar")
	back_button = _tool_button("BACK", go_back)
	forward_button = _tool_button("FWD", go_forward)
	reload_button = _tool_button("RELOAD", _on_reload_pressed)
	home_button = _tool_button("HOME", go_home)
	for button in [back_button, forward_button, reload_button, home_button]:
		toolbar.add_child(button)
	var addr := MechUI.label(&"LabelMeta", "ADDR")
	addr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toolbar.add_child(addr)
	address_field = LineEdit.new()
	address_field.theme_type_variation = &"NetAddress"
	address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_field.size_flags_vertical = Control.SIZE_FILL
	address_field.context_menu_enabled = false
	address_field.select_all_on_focus = true
	address_field.text_submitted.connect(_on_address_submitted)
	address_field.gui_input.connect(_on_address_input)
	toolbar.add_child(address_field)
	column.add_child(MechUI.pane(&"NetFrameRow", toolbar))

	var favorites := MechUI.hbox(&"NetFavorites")
	favorites.add_child(MechUI.label(&"LabelMeta", "FAVORITES:"))
	for entry in NetSites.FAVORITES:
		var link := _frame_link(str(entry[0]), str(entry[1]))
		link.pressed.connect(navigate.bind(entry[1]))
		favorites.add_child(link)
		_favorites[entry[1]] = link
	_makers_link = _frame_link("Manufacturers v", "")
	_makers_link.pressed.connect(_on_makers_pressed)
	favorites.add_child(_makers_link)
	column.add_child(MechUI.pane(&"NetFrameRowTight", favorites))

	var well_margin := MechUI.pane(&"NetWellMargin")
	well_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(well_margin)
	var well := MechUI.pane(&"NetPageWell")
	well_margin.add_child(well)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.add_child(_scroll)
	_page_holder = MechUI.vbox(&"NetZeroStack")
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_page_holder)

	var status := MechUI.hbox(&"NetFavorites")
	status_label = MechUI.label(&"LabelMeta", DONE_TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_child(status_label)
	load_bar = NetLoadBar.new()
	status.add_child(load_bar)
	status.add_child(MechUI.label(&"LabelMeta", SPEED_TEXT))
	var balance := MechUI.hbox(&"TabRow")
	balance.add_child(MechUI.label(&"LabelMeta", "BAL"))
	balance_label = MechUI.label(&"LabelBodyBright")
	balance.add_child(balance_label)
	status.add_child(balance)
	column.add_child(MechUI.pane(&"NetStatusBar", status))


func _tool_button(text: String, action: Callable) -> Button:
	var button := MechUI.button(text)
	button.pressed.connect(action)
	return button


# A link in the browser's own frame (favorites): MechOS greys, its address
# in the status bar while the mouse is over it.
func _frame_link(text: String, url: String) -> LinkButton:
	var link := LinkButton.new()
	link.theme_type_variation = &"NetFavorite"
	link.text = text
	link.focus_mode = Control.FOCUS_NONE
	if url != "":
		link.mouse_entered.connect(_on_link_hovered.bind(url))
		link.mouse_exited.connect(_on_link_hovered.bind(""))
	return link


func _update_buttons() -> void:
	if back_button == null:
		return
	back_button.disabled = back_history.is_empty()
	forward_button.disabled = forward_history.is_empty()
	reload_button.text = "STOP" if loading else "RELOAD"


func _update_favorites() -> void:
	var domain: String = NetSites.parse(current_url).domain
	for site in _favorites:
		_favorites[site].theme_type_variation = &"NetFavoriteActive" if site == domain else &"NetFavorite"
	var maker_site := Manufacturers.of_domain(domain) != ""
	_makers_link.theme_type_variation = &"NetFavoriteActive" if maker_site else &"NetFavorite"


func _refresh_status() -> void:
	status_label.text = NetSites.display(_hover_url) if _hover_url != "" else _load_status


func _on_link_hovered(url: String) -> void:
	_hover_url = url
	_refresh_status()


func _on_reload_pressed() -> void:
	if loading:
		stop()
	else:
		reload()


func _on_address_submitted(text: String) -> void:
	address_field.release_focus()
	navigate(text)


func _on_address_input(event: InputEvent) -> void:
	if event.is_action_pressed("escape"):
		address_field.text = NetSites.display(current_url)
		address_field.release_focus()
		address_field.accept_event()


# Every maker's site, as a MechOS menu at the mouse (MechOS registers the
# "net_makers" actions).
func _on_makers_pressed() -> void:
	MechOS.open_context_menu({"type": "net_makers", "source": _makers_link, "window": self})


func _on_money_changed(amount) -> void:
	balance_label.text = "%d CT" % int(amount)
