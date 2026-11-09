class_name Manufacturers
extends RefCounted

# Every company that makes parts. A part names its maker in
# manufacturer_name (part data); of_part() turns that into an id here.
# "domain" is the maker's own site on the NET (NetSites lists it as a site
# still under construction). The "test" maker marks placeholder parts: the
# Store never sells them.

const TEST := "test"

const DATA := {
	"martel": {"name": "Martel Shipping and SAV Manufacturing", "short": "Martel", "domain": "martel-sav.com"},
	"orontes": {"name": "Orontes Constructions", "short": "Orontes", "domain": "orontes-con.com"},
	"pt_gajah_teknis": {"name": "PT Gajah Teknis", "short": "Gajah Teknis", "domain": "gajahteknis.co.id"},
	"nordomeccanica": {"name": "Nordomeccanica", "short": "Nordomeccanica", "domain": "nordomeccanica.it"},
	"nomhoyi_superheavy": {"name": "Nomhoyi Superheavy", "short": "Nomhoyi", "domain": "nomhoyi.co.za"},
	"svelbard": {"name": "Svelbard Industries", "short": "Svelbard", "domain": "svelbard.no"},
	"sparrowhawk": {"name": "Sparrowhawk Solutions", "short": "Sparrowhawk", "domain": "sparrowhawk-solutions.com"},
	"claymore": {"name": "Claymore International", "short": "Claymore", "domain": "claymore-intl.co.uk"},
	"wu_zhi": {"name": "Wu-Zhi", "short": "Wu-Zhi", "domain": "wuzhi.com.cn"},
	"western_shore": {"name": "Western Shore Customs", "short": "Western Shore", "domain": "westernshorecustoms.com"},
	"silver_star": {"name": "Silver Star Armaments", "short": "Silver Star", "domain": "silverstar-arms.com"},
	"silver_star_europe": {"name": "Silver Star Armaments Europe", "short": "Silver Star EU", "domain": "silverstar-arms.de"},
	"gladiolo": {"name": "Gladiolo Sistemas", "short": "Gladiolo", "domain": "gladiolo.com.br"},
	"huanglong": {"name": "Huanglong Enterprises", "short": "Huanglong", "domain": "huanglong.com.hk"},
	"kaguya": {"name": "Kaguya Softworks", "short": "Kaguya", "domain": "kaguya-soft.co.jp"},
	"yamaguchi": {"name": "Yamaguchi Heavy Industries", "short": "Yamaguchi", "domain": "yamaguchi-hi.co.jp"},
	"artes_estrella": {"name": "Artes Estrella", "short": "Artes Estrella", "domain": "artesestrella.com.mx"},
	"araco": {"name": "ARACo", "short": "ARACo", "domain": "araco.com"},
	"black_coast": {"name": "Black Coast Research", "short": "Black Coast", "domain": "blackcoast-research.org"},
	"espada": {"name": "Espada Electronica", "short": "Espada", "domain": "espada-electronica.es"},
	TEST: {"name": "Test", "short": "Test", "domain": "test.invalid", "test": true},
}


static func ids() -> Array:
	return DATA.keys()


## Every maker but the test one, A to Z by name.
static func real_ids() -> Array:
	var result := DATA.keys().filter(func(id): return not is_test(id))
	result.sort_custom(func(a, b): return display_name(a).naturalnocasecmp_to(display_name(b)) < 0)
	return result


static func is_valid(id: String) -> bool:
	return DATA.has(id)


## The id whose name matches the part's manufacturer_name, ignoring case and
## the spaces round it; "" when none does.
static func of_part(part) -> String:
	if part == null:
		return ""
	var maker_name = part.get("manufacturer_name")
	if maker_name == null:
		return ""
	return of_name(str(maker_name))


static func of_name(maker_name: String) -> String:
	var wanted := maker_name.strip_edges().to_lower()
	if wanted == "":
		return ""
	for id in DATA:
		if str(DATA[id].name).to_lower() == wanted:
			return id
	return ""


static func is_test(id: String) -> bool:
	return DATA.has(id) and bool(DATA[id].get("test", false))


static func display_name(id: String) -> String:
	return str(DATA[id].name) if DATA.has(id) else id


static func short_name(id: String) -> String:
	return str(DATA[id].short) if DATA.has(id) else id


static func domain_of(id: String) -> String:
	return str(DATA[id].domain) if DATA.has(id) else ""


## The maker whose site this is, or "".
static func of_domain(domain: String) -> String:
	for id in DATA:
		if DATA[id].domain == domain:
			return id
	return ""
