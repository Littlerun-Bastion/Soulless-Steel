class_name BbsText
extends RefCounted

## Text-mode layout for the NET's text sites (pilot.net, FourX.net). Such a
## page is lines of BBCode in RichTextLabels set in one monospaced font
## (VT323, NetBbsText), so every character takes one column. A Seg is a run
## of BBCode and the number of columns it takes. The helpers make Segs from
## plain text (escaped, and cut to fit with CUT), join and pad them, frame
## lines in ASCII boxes, lay out tables and set blocks of lines side by side.
## Colours are the theme's: NetBbsText's default colour for plain text,
## NetBbsLink for bright text and links, NetBbsDim for dim text and
## NetBbsSelected for the inverted block.

const THEME := preload("res://game/ui/mech_os/MechTheme.tres")
## A link to "do:<action>:<target>" acts instead of loading an address.
const ACTION := "do:"
const CUT := "…"


## A run of BBCode and the columns it takes.
class Seg extends RefCounted:
	var code := ""
	var width := 0

	func _init(new_code := "", new_width := 0) -> void:
		code = new_code
		width = new_width

	## This run, then other.
	func plus(other: Seg) -> Seg:
		return Seg.new(code + other.code, width + other.width)

	## Padded with spaces to columns wide (never cut).
	func padded(columns: int) -> Seg:
		return Seg.new(code + " ".repeat(maxi(columns - width, 0)), maxi(width, columns))


# ---- runs ---------------------------------------------------------------------

static func plain(text: String) -> Seg:
	return Seg.new(esc(text), text.length())


static func bright(text: String) -> Seg:
	return Seg.new("[color=%s]%s[/color]" % [color("NetBbsLink"), esc(text)], text.length())


static func dim(text: String) -> Seg:
	return Seg.new("[color=%s]%s[/color]" % [color("NetBbsDim"), esc(text)], text.length())


## A link to an address (NetSites) or an action (ACTION).
static func link(text: String, url: String) -> Seg:
	return Seg.new("[url=%s][color=%s]%s[/color][/url]" % [url, color("NetBbsLink"), esc(text)], text.length())


## A link that acts: "do:<action_name>:<target>".
static func action(text: String, action_name: String, target: String) -> Seg:
	return link(text, "%s%s:%s" % [ACTION, action_name, target])


## The inverted block: dark text on a light ground; a link when url is given.
static func inverted(text: String, url := "") -> Seg:
	var code := "[bgcolor=%s][color=%s]%s[/color][/bgcolor]" % [selected_ground(), color("NetBbsSelected"), esc(text)]
	return Seg.new("[url=%s]%s[/url]" % [url, code] if url != "" else code, text.length())


static func space(columns: int) -> Seg:
	return Seg.new(" ".repeat(maxi(columns, 0)), maxi(columns, 0))


## A rule of ch, dim.
static func rule(width: int, ch := "-") -> Seg:
	return dim(ch.repeat(maxi(width, 0)))


## Runs one after another.
static func join(runs: Array) -> Seg:
	var out := Seg.new()
	for run in runs:
		out = out.plus(run)
	return out


## left, then right against the right edge of width columns.
static func spread(left: Seg, right: Seg, width: int) -> Seg:
	return join([left, space(width - left.width - right.width), right])


## text cut or padded to exactly width columns: plain, "bright" or "dim", or
## a link when url is given (padded outside the link, so its underline stops
## at the text). align "right" pads on the left.
static func cell(text: String, width: int, style := "", url := "", align := "") -> Seg:
	var shown := cut(text, width)
	var run: Seg
	if url != "":
		run = link(shown, url)
	elif style == "bright":
		run = bright(shown)
	elif style == "dim":
		run = dim(shown)
	else:
		run = plain(shown)
	var gap := " ".repeat(maxi(width - shown.length(), 0))
	return Seg.new(gap + run.code if align == "right" else run.code + gap, maxi(width, shown.length()))


## label, dots, then value against the right edge: "Balance ...... 1,200 CT".
## The label is cut to leave room for the value.
static func pair(label: String, value: String, width: int, value_style := "bright") -> Seg:
	var room := maxi(width - value.length() - 3, 1)
	var shown := cut(label, room)
	var dots := width - shown.length() - value.length() - 2
	return join([plain(shown + " "), dim(".".repeat(maxi(dots, 0))), plain(" "),
			bright(value) if value_style == "bright" else plain(value)])


# ---- text ---------------------------------------------------------------------

## text cut to width columns at most, ending in CUT where it was cut.
static func cut(text: String, width: int) -> String:
	if text.length() <= width:
		return text
	if width <= 0:
		return ""
	return text.substr(0, width - 1) + CUT


## Plain text broken into lines of at most width columns, at spaces where it
## can be (a longer word is split). Each line break in text starts a new
## line, so a blank line between paragraphs stays.
static func wrap(text: String, width: int) -> Array:
	var lines := []
	for paragraph in text.replace("\r\n", "\n").split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var rest := str(word)
			while rest.length() > width:
				if line != "":
					lines.append(line)
					line = ""
				lines.append(rest.substr(0, width))
				rest = rest.substr(width)
			if line == "":
				line = rest
			elif line.length() + 1 + rest.length() <= width:
				line += " " + rest
			else:
				lines.append(line)
				line = rest
		lines.append(line)
	return lines


## "12,345"
static func thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## "[######....]": done of total in width cells.
static func bar(done: int, total: int, width := 10) -> String:
	var filled := 0 if total <= 0 else clampi(int(roundf(float(done) / total * width)), 0, width)
	return "[" + "#".repeat(filled) + ".".repeat(width - filled) + "]"


# ---- blocks -------------------------------------------------------------------

## lines in an ASCII box width columns wide, the title in its top edge:
## "+- TITLE ---+", "| line |", "+-----+". title_run (a Seg) replaces the
## bright title; with neither, the top edge is plain. A line must be no wider
## than width - 4.
static func box(title: String, width: int, lines: Array, title_run: Seg = null) -> Array:
	var out := []
	var head: Seg = title_run if title_run != null else (bright(title) if title != "" else null)
	if head == null:
		out.append(dim("+" + "-".repeat(width - 2) + "+"))
	else:
		out.append(join([dim("+- "), head, dim(" " + "-".repeat(maxi(width - head.width - 5, 0)) + "+")]))
	for line in lines:
		out.append(join([dim("| "), (line as Seg).padded(width - 4), dim(" |")]))
	out.append(dim("+" + "-".repeat(width - 2) + "+"))
	return out


## Blocks of lines side by side: block i widths[i] columns wide, gap columns
## between them. A shorter block is padded with blank lines.
static func beside(blocks: Array, widths: Array, gap := 2) -> Array:
	var height := 0
	for block in blocks:
		height = maxi(height, (block as Array).size())
	var out := []
	for row in height:
		var line := Seg.new()
		for i in blocks.size():
			if i > 0:
				line = line.plus(space(gap))
			var block: Array = blocks[i]
			var part: Seg = block[row] if row < block.size() else Seg.new()
			line = line.plus(part.padded(int(widths[i])) if i < blocks.size() - 1 else part)
		out.append(line)
	return out


## An ASCII table. columns: [{"title", "width", "align" ("right")}]. rows:
## Arrays of cells; a cell is a Seg, plain text, or an Array of those (one a
## line). Plain text is cut to fit; a Seg must fit already (see cell()).
## rules puts a rule under every row.
static func table(columns: Array, rows: Array, rules := false) -> Array:
	var edge := "+"
	for column in columns:
		edge += "-".repeat(int(column.width) + 2) + "+"
	var out := [dim(edge)]
	var head := []
	for column in columns:
		head.append(cell(str(column.get("title", "")), int(column.width), "bright", "", str(column.get("align", ""))))
	out.append(_table_line(head, columns))
	out.append(dim(edge))
	for r in rows.size():
		var row: Array = rows[r]
		var cells := []
		var height := 1
		for i in columns.size():
			var value = row[i] if i < row.size() else ""
			var lines: Array = value if value is Array else [value]
			cells.append(lines)
			height = maxi(height, lines.size())
		for at in height:
			var parts := []
			for i in columns.size():
				var lines: Array = cells[i]
				var value = lines[at] if at < lines.size() else ""
				parts.append(value if value is Seg else cell(str(value), int(columns[i].width), "", "",
						str(columns[i].get("align", ""))))
			out.append(_table_line(parts, columns))
		if rules and r < rows.size() - 1:
			out.append(dim(edge))
	out.append(dim(edge))
	return out


static func _table_line(cells: Array, columns: Array) -> Seg:
	var line := dim("|")
	for i in columns.size():
		line = join([line, space(1), (cells[i] as Seg).padded(int(columns[i].width)), space(1), dim("|")])
	return line


# ---- output -------------------------------------------------------------------

static func render(lines: Array) -> String:
	return "\n".join(lines.map(func(l): return (l as Seg).code))


## A RichTextLabel for lines: NetBbsText, no wrapping (the lines are laid out
## to the column already), as tall as its text.
static func screen(lines: Array) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.theme_type_variation = &"NetBbsText"
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.selection_enabled = false
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	node.focus_mode = Control.FOCUS_NONE
	node.text = render(lines)
	return node


## A theme colour as BBCode hex.
static func color(type: String, item := "font_color") -> String:
	return "#" + THEME.get_color(item, type).to_html(false)


## The inverted block's ground: NetBbsSelected's normal stylebox.
static func selected_ground() -> String:
	var ground: StyleBox = THEME.get_stylebox("normal", "NetBbsSelected")
	return "#" + (ground as StyleBoxFlat).bg_color.to_html(false)


static func esc(text: String) -> String:
	return text.replace("[", "\u0003").replace("]", "[rb]").replace("\u0003", "[lb]")
