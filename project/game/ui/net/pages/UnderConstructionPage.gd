class_name UnderConstructionPage
extends NetPage

## What a planned site shows until it's built (NetSites.PLANNED and every
## maker's own site): a dashed UNDER CONSTRUCTION box with the site's name
## and a link back to the home page. Every path on the site shows it.

const MESSAGE := "This site is not available yet. Please check back soon!"
const BOX_WIDTH := 520


func open(page_path: String, page_query: Dictionary) -> void:
	super(page_path, page_query)
	var site := NetSites.site_name(domain)
	page_title = "%s - Under Construction" % site
	var margin := NetUI.panel(&"NetContent")
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var column := NetUI.vbox(&"NetStack")
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)
	var box := NetUI.construction(["UNDER CONSTRUCTION", site, MESSAGE])
	box.custom_minimum_size.x = BOX_WIDTH
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(box)
	var back := NetUI.link(self, "Back to the home page", NetWindow.HOME_URL)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)
