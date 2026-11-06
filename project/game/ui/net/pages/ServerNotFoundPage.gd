class_name ServerNotFoundPage
extends NetPage

## The classic error for an address no site answers at, with a link back to
## the home page. RELOAD tries the address again.

const TITLE := "Server not found"


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	page_title = TITLE
	var margin := NetUI.panel(&"NetContent")
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var column := NetUI.vbox(&"NetStack")
	margin.add_child(column)
	column.add_child(NetUI.heading(TITLE))
	column.add_child(NetUI.rule())
	column.add_child(NetUI.text(message(domain), &"NetBody", true))
	column.add_child(NetUI.text("If you typed the address, check it for mistakes. Otherwise try again later.", &"NetMeta", true))
	var back := NetUI.link(self, "Go to the home page", NetWindow.HOME_URL)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(back)


static func message(server: String) -> String:
	return "The server at %s could not be found. Check the address and try again." % server
