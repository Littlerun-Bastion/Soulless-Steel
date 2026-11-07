class_name NetSites
extends RefCounted

## The NET's sites and its addresses.
##
## An address is "domain/path?query". "http://", "www." and upper case in
## the domain are accepted and dropped (parse); the address field shows
## "http://www.<domain>/<path>" (display). build() makes the page for a
## domain: the built sites (SITES) have their own pages (pilot.net's in the
## look PilotNet.look() names), the planned sites (PLANNED, and every maker's
## own site) show Under Construction, and anything else is Server not found.

const STORE_DOMAIN := "amazing.com"
const PILOTNET_DOMAIN := "pilot.net"
const STEELAPEDIA_DOMAIN := "steelapedia.net"
const FOURX_DOMAIN := "fourx.net"
const MEMORIAL_DOMAIN := "memorialwall.org"
## The built sites: domain -> name (build() makes their pages).
const SITES := {
	STORE_DOMAIN: "amazing.com",
	PILOTNET_DOMAIN: "pilot.net",
	STEELAPEDIA_DOMAIN: "Steelapedia",
	FOURX_DOMAIN: "FourX.net",
	MEMORIAL_DOMAIN: "The Memorial Wall",
}
## Sites still to build: domain -> name (they show Under Construction).
const PLANNED := {}
## The favorites row: [label, domain]. The Memorial Wall is left off: pilots
## find it from pilot.net.
const FAVORITES := [
	["pilot.net", "pilot.net"],
	["amazing.com", "amazing.com"],
	["Steelapedia", "steelapedia.net"],
	["FourX.net", "fourx.net"],
]
const BUILT := "built"
const PLANNED_SITE := "planned"
const UNKNOWN := "unknown"


## {"domain", "path", "query": {key: value}, "url"}. "url" is the address in
## its one canonical form ("amazing.com/c/head"), the same however it was
## typed; "" domain for an empty address.
static func parse(address: String) -> Dictionary:
	var text := address.strip_edges()
	for scheme in ["http://", "https://"]:
		if text.to_lower().begins_with(scheme):
			text = text.substr(scheme.length())
	if text.to_lower().begins_with("www."):
		text = text.substr(4)
	var cut := text.length()
	for mark in ["/", "?"]:
		var at := text.find(mark)
		if at >= 0:
			cut = mini(cut, at)
	var domain := text.substr(0, cut).to_lower().trim_suffix(".")
	var rest := text.substr(cut)
	var query_text := ""
	var q := rest.find("?")
	if q >= 0:
		query_text = rest.substr(q + 1)
		rest = rest.substr(0, q)
	var segments := Array(rest.split("/", false)).map(func(s): return str(s).uri_decode())
	var path := "/" + "/".join(segments)
	var query := {}
	for pair in query_text.split("&", false):
		var eq := pair.find("=")
		var key := (pair if eq < 0 else pair.substr(0, eq)).uri_decode().to_lower()
		var value := ("" if eq < 0 else pair.substr(eq + 1)).replace("+", " ").uri_decode()
		if key != "":
			query[key] = value
	return {"domain": domain, "path": path, "query": query, "url": make_url(domain, path, query)}


## The canonical address: "domain/path?key=value".
static func make_url(domain: String, path := "/", query := {}) -> String:
	if domain == "":
		return ""
	var segments := Array(path.split("/", false)).map(func(s): return str(s).uri_encode())
	var url := domain + "/" + "/".join(segments)
	if url.ends_with("/") and not segments.is_empty():
		url = url.trim_suffix("/")
	if not query.is_empty():
		var pairs := []
		for key in query:
			pairs.append("%s=%s" % [str(key).uri_encode(), str(query[key]).uri_encode()])
		url += "?" + "&".join(pairs)
	return url


## "http://www.amazing.com/c/head" for the address field and the status bar.
static func display(address: String) -> String:
	var parsed := parse(address)
	if parsed.domain == "":
		return ""
	return "http://www." + str(parsed.url)


static func kind_of(domain: String) -> String:
	if SITES.has(domain):
		return BUILT
	if PLANNED.has(domain):
		return PLANNED_SITE
	var maker := Manufacturers.of_domain(domain)
	if maker != "" and not Manufacturers.is_test(maker):
		return PLANNED_SITE
	return UNKNOWN


## The site's name, "" for an unknown domain.
static func site_name(domain: String) -> String:
	if SITES.has(domain):
		return SITES[domain]
	if PLANNED.has(domain):
		return PLANNED[domain]
	var maker := Manufacturers.of_domain(domain)
	if maker != "" and not Manufacturers.is_test(maker):
		return Manufacturers.display_name(maker)
	return ""


## A new page for the domain, not yet opened.
static func build(domain: String) -> NetPage:
	var page: NetPage
	var kind := kind_of(domain)
	if domain == PILOTNET_DOMAIN:
		page = PilotNetPortalPage.new() if PilotNet.look() == PilotNet.LOOK_PORTAL else PilotNetPage.new()
	elif domain == STEELAPEDIA_DOMAIN:
		page = SteelapediaPage.new()
	elif domain == FOURX_DOMAIN:
		page = FourXPage.new()
	elif domain == MEMORIAL_DOMAIN:
		page = MemorialWallPage.new()
	elif kind == BUILT:
		page = AmazingPage.new()
	elif kind == PLANNED_SITE:
		page = UnderConstructionPage.new()
	else:
		page = ServerNotFoundPage.new()
	page.domain = domain
	return page


# ---- amazing.com addresses ------------------------------------------------

static func store_url(path := "/", query := {}) -> String:
	return make_url(STORE_DOMAIN, path, query)


static func product_url(part_type: String, part_id: String) -> String:
	return store_url("/p/%s/%s" % [part_type, part_id])


static func category_url(part_type: String) -> String:
	return store_url("/c/" + part_type)


static func maker_url(maker_id: String) -> String:
	return store_url("/maker/" + maker_id)


static func search_url(text: String) -> String:
	return store_url("/search", {"q": text})


## A Steelapedia article's address.
static func wiki_url(slug: String) -> String:
	return make_url(STEELAPEDIA_DOMAIN, "/wiki/" + slug)


# ---- FourX.net addresses --------------------------------------------------

static func fourx_url(path := "/", query := {}) -> String:
	return make_url(FOURX_DOMAIN, path, query)


## An instrument's quote page.
static func quote_url(symbol: String) -> String:
	return fourx_url("/q/" + symbol)


# ---- The Memorial Wall's addresses ----------------------------------------

static func memorial_url(path := "/", query := {}) -> String:
	return make_url(MEMORIAL_DOMAIN, path, query)


## A Memorial Wall record's page.
static func memorial_record_url(id: int) -> String:
	return memorial_url("/pilot/%d" % id)
