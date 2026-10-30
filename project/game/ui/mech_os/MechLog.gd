class_name MechLog
extends RefCounted

## The MechOS system log: what the LOG app shows.
## A static class, so there is nothing to register: any script can write
##   MechLog.write("HGR", "Equipped KR-7 Bastion (core)")
##   MechLog.write("CBT", "Target destroyed", MechLog.Kind.COMBAT)
##   MechLog.write("HGR", "Can't leave: no head equipped", MechLog.Kind.SYSTEM, true)
## Lines last for the session (not saved). The source is a short code, cut
## to three letters: MSG, HGR, SYS, CBT, LOT...

enum Kind { SYSTEM, COMBAT, LOOT }

const MAX_LINES := 300

## Statics can't have signals, so the log keeps one object that does.
class Feed extends RefCounted:
	signal line_added(line: Dictionary)
	signal cleared

static var feed := Feed.new()
static var lines: Array = []  # {"time", "source", "text", "kind", "critical"}


static func write(source: String, text: String, kind: Kind = Kind.SYSTEM, critical := false) -> void:
	var line := {
		"time": Time.get_time_string_from_system(),
		"source": source.to_upper().left(3),
		"text": text,
		"kind": kind,
		"critical": critical,
	}
	lines.append(line)
	if lines.size() > MAX_LINES:
		lines.pop_front()
	feed.line_added.emit(line)


## "[04:15:41] HGR ! Can't leave: no head equipped"
static func format(line: Dictionary) -> String:
	return "[%s] %s %s%s" % [line.time, line.source, "! " if line.critical else "", line.text]


static func clear() -> void:
	lines.clear()
	feed.cleared.emit()
