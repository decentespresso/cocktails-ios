import Foundation

/// The member's bar, as the website stores it in the permacookie pdt_bar (cocktails/js/bar.js):
/// {cur, locs: [{id, name, items}], v}. One bar for every book (ingredient ids are shared).
struct Bar: Codable, Equatable {
	struct Item: Codable, Hashable {
		var t: String           // "i" an ingredient, "b" any bottle of a kind, "c" one added by hand
		var id: Int? = nil      // t=i
		var b: String? = nil    // t=b, t=c: the kind
		var d: String? = nil    // t=c: the description
		/// itemKey in bar.js
		var key: String { t == "i" ? "i\(id ?? 0)" : t == "b" ? "b\(b ?? "")" : "c\(b ?? "")|\(d ?? "")" }
		static func ing(_ id: Int) -> Item { Item(t: "i", id: id) }
		static func kind(_ b: String) -> Item { Item(t: "b", b: b) }
	}
	struct Loc: Codable, Equatable, Identifiable {
		var id: String
		var name: String
		var items: [Item]
	}
	var cur: String
	var locs: [Loc]
	var v: Int = 1

	/// bar.js normalize(): at least one location ("Home"), a current one that exists
	static func normalized(_ b: Bar?) -> Bar {
		var b = b ?? Bar(cur: "", locs: [])
		if b.locs.isEmpty { b.locs = [Loc(id: newId(), name: T("Home"), items: [])] }
		for i in b.locs.indices {
			if b.locs[i].id.isEmpty { b.locs[i].id = newId() }
			if b.locs[i].name.isEmpty { b.locs[i].name = "Bar" }
		}
		if !b.locs.contains(where: { $0.id == b.cur }) { b.cur = b.locs[0].id }
		b.v = 1
		return b
	}
	static func newId() -> String { "l" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(6)) }

	var current: Loc { locs.first { $0.id == cur } ?? locs[0] }
	var curIndex: Int { locs.firstIndex { $0.id == cur } ?? 0 }
}

/// Lenient decoding: the site writes ids as numbers, but a hand-edited value may not match exactly
extension Bar {
	static func decode(_ s: String) -> Bar?? {
		let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
		if t.isEmpty { return .some(nil) }                       // no bar yet
		guard let d = t.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }   // unreadable
		var locs: [Loc] = []
		for l in any["locs"] as? [[String: Any]] ?? [] {
			var items: [Item] = []
			for it in l["items"] as? [[String: Any]] ?? [] {
				guard let t = it["t"] as? String else { continue }
				let id = (it["id"] as? Int) ?? (it["id"] as? String).flatMap(Int.init)
				items.append(Item(t: t, id: id, b: it["b"] as? String, d: it["d"] as? String))
			}
			locs.append(Loc(id: l["id"] as? String ?? "", name: l["name"] as? String ?? "", items: items))
		}
		return .some(Bar(cur: any["cur"] as? String ?? "", locs: locs))
	}
	func json() -> String {
		let enc = JSONEncoder()
		enc.outputFormatting = [.withoutEscapingSlashes]
		return String(decoding: (try? enc.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
	}
}

/// What Your Bar needs to know about one book (pdt_bar_page in lib/direct.tcl): every ingredient
/// with its "any" kind and category, the kinds, the kitchen basics, the browse-by-type groups, and
/// each cocktail's required ingredients (garnishes left out).
final class BarIndex {
	struct Ing { let id: Int; let name: String; let kind: String; let cat: String; let book: String }
	struct Kind { let k: String; let label: String; let produce: Bool; let gives: String }
	struct TypeGroup { let k: String; let label: String; let cats: [String] }
	struct Req { let id: Int; let kind: String; let name: String }
	struct Rec { let id: Int; let name: String; let pop: Int; let req: [Req] }

	let book: Book
	private(set) var ings: [Ing] = []
	private(set) var ingById: [Int: Ing] = [:]
	private(set) var kinds: [Kind] = []
	private(set) var kindByKey: [String: Kind] = [:]
	private(set) var basics: [Int] = []
	private(set) var recipes: [Rec] = []
	private(set) var recByName: [String: Rec] = [:]
	private var useCount: [Int: Int] = [:]

	private static var cache: [String: BarIndex] = [:]
	private static let lock = NSLock()
	static func clearCache() { lock.lock(); cache = [:]; lock.unlock() }
	static func of(_ book: Book) -> BarIndex {
		lock.lock(); defer { lock.unlock() }
		if let x = cache[book.key] { return x }
		let x = BarIndex(book)
		cache[book.key] = x
		return x
	}

	/// pdt_bar_kind_list: the "any brand" kinds besides the base spirits
	static let kindList: [(String, String)] = [
		("pisco", "Pisco"), ("aquavit", "Aquavit"), ("absinthe", "Absinthe"), ("genever", "Genever"), ("arrack", "Arrack"),
		("vermouth_sweet", "Sweet vermouth"), ("vermouth_dry", "Dry vermouth"), ("vermouth_blanc", "Blanc vermouth"), ("port", "Port"),
		("orange_liqueur", "Orange liqueur"), ("maraschino", "Maraschino"), ("green_chartreuse", "Green Chartreuse"),
		("bitters_orange", "Orange bitters"), ("sparkling", "Sparkling wine"),
		("orgeat", "Orgeat"), ("maple_syrup", "Maple syrup"), ("grenadine", "Grenadine"), ("ginger_beer", "Ginger beer"), ("ginger_ale", "Ginger ale"),
		("tonic", "Tonic water"), ("cola", "Cola"), ("root_beer", "Root beer"), ("cranberry_juice", "Cranberry juice"), ("grapefruit_juice", "Grapefruit juice"),
		("apple_cider", "Apple cider"), ("agave", "Agave syrup"), ("pomegranate_molasses", "Pomegranate molasses"), ("coconut_water", "Coconut water"),
		("raspberry_preserves", "Raspberry preserves"), ("apricot_preserves", "Apricot preserves"), ("strawberry_preserves", "Strawberry preserves"),
		("orange_marmalade", "Orange marmalade"), ("sugar_syrup", "Sugar or simple syrup"), ("demerara", "Demerara sugar or syrup"),
		("honey", "Honey or honey syrup"),
	]
	/// pdt_homemade_kinds: home-made syrups share a kind with their base
	static func homemadeKind(_ name: String) -> String {
		let n = name.trimmingCharacters(in: .whitespaces).lowercased()
		if ["simple syrup", "rich simple syrup", "cane sugar syrup", "caramelized simple syrup", "sugar", "superfine sugar", "sugar cube"].contains(n) { return "sugar_syrup" }
		if ["demerara syrup", "demerara sugar", "demerara sugar cube"].contains(n) { return "demerara" }
		if ["honey syrup", "acacia honey syrup"].contains(n) { return "honey" }
		return ""
	}
	static let basicNames = ["Lemon Juice", "Lime Juice", "Orange Juice", "Simple Syrup", "Demerara Syrup", "Honey Syrup", "Sugar", "Sugar Cube",
		"Demerara Sugar", "Egg White", "Egg Yolk", "Whole Egg", "Heavy Cream", "Whole Milk", "Club Soda", "Hot Water",
		"Ice-Cold Filtered Water", "Salt", "Kosher Salt", "Pinch Kosher Salt", "Pinch Sea Salt", "Ground Black Pepper", "Angostura Bitters"]
	static let types: [TypeGroup] = [
		TypeGroup(k: "spirits", label: "Spirits", cats: ["gin", "whiskey", "rum", "tequila", "vodka", "mezcal", "brandy", "misc_alcohol"]),
		TypeGroup(k: "liqueur", label: "Liqueurs & amari", cats: ["liqueur", "absinthe"]),
		TypeGroup(k: "vermouth", label: "Vermouth, sherry & port", cats: ["vermouth", "fortified_wine"]),
		TypeGroup(k: "wine", label: "Wine, sparkling & beer", cats: ["wine", "champagne", "beer"]),
		TypeGroup(k: "bitters", label: "Bitters", cats: ["bitters"]),
		TypeGroup(k: "juice", label: "Juices", cats: ["juice"]),
		TypeGroup(k: "fruit", label: "Fruit", cats: ["fruit", "fruit_puree"]),
		TypeGroup(k: "syrup", label: "Syrups & sweeteners", cats: ["syrup", "sugar_sweetener", "shrubb", "horchata"]),
		TypeGroup(k: "mixer", label: "Mixers & water", cats: ["mixer_soda", "water"]),
		TypeGroup(k: "dairy", label: "Eggs & dairy", cats: ["egg", "dairy_cream", "ice_cream"]),
		TypeGroup(k: "veg", label: "Vegetables & savory", cats: ["vegetables", "savory"]),
		TypeGroup(k: "herb", label: "Herbs, spices & more", cats: ["spice_herb_garnish", "tea_coffee", "absolutes", "fat_oil", "garnish_tool"]),
	]

	private init(_ book: Book) {
		self.book = book
		let db = book.store.db
		var kind: [Int: String] = [:]
		for r in db.rows("SELECT ingredient_id, generic FROM ingredient WHERE generic IS NOT NULL AND generic<>''") { kind[r.i(0)] = r.s(1) }
		for r in db.rows("SELECT ingredient_id, name FROM ingredient") { let hk = Self.homemadeKind(r.s(1)); if !hk.isEmpty && kind[r.i(0)] == nil { kind[r.i(0)] = hk } }
		var produce: [Kind] = []
		if !db.one("SELECT 1 FROM sqlite_master WHERE name='produce_gives'").isNull {
			for r in db.rows("SELECT g.ingredient_id, p.k FROM produce_gives g JOIN produce p USING(produce_id)") where kind[r.i(0)] == nil { kind[r.i(0)] = "p_" + r.s(1) }
			for r in db.rows("SELECT p.k, p.name, group_concat(i.name, '|') FROM produce p JOIN produce_gives g USING(produce_id) JOIN ingredient i USING(ingredient_id) GROUP BY p.produce_id ORDER BY p.sortorder") {
				produce.append(Kind(k: "p_" + r.s(0), label: T(r.s(1)), produce: true, gives: r.s(2).split(separator: "|").map { T(String($0)) }.joined(separator: ", ")))
			}
		}
		var seen = Set<Int>()
		// every ingredient, including bottles no recipe uses (ones added for Your Bar alone, as on the site)
		for r in db.rows("SELECT i.ingredient_id, i.name, (SELECT t.name FROM ingtag t WHERE t.ingredient_id=i.ingredient_id LIMIT 1) FROM ingredient i WHERE i.name IS NOT NULL ORDER BY i.name") {
			ings.append(Ing(id: r.i(0), name: r.s(1), kind: kind[r.i(0)] ?? "", cat: r.s(2), book: book.key))
			seen.insert(r.i(0))
		}
		// the other books' ingredients too: one bar for every book
		for ob in Book.all where ob != book {
			for r in ob.store.db.rows("SELECT i.ingredient_id, i.name, i.generic, (SELECT t.name FROM ingtag t WHERE t.ingredient_id=i.ingredient_id LIMIT 1) FROM ingredient i WHERE i.name IS NOT NULL ORDER BY i.name") where !seen.contains(r.i(0)) {
				seen.insert(r.i(0))
				let g = r.s(2)
				ings.append(Ing(id: r.i(0), name: r.s(1), kind: kind[r.i(0)] ?? (g.isEmpty ? Self.homemadeKind(r.s(1)) : g), cat: r.s(3), book: ob.key))
			}
		}
		for i in ings { ingById[i.id] = i }
		kinds = Store.baseSpirits.map { Kind(k: $0, label: Store.spiritLabel($0), produce: false, gives: "") }
			+ Self.kindList.map { Kind(k: $0.0, label: T($0.1), produce: false, gives: "") } + produce
		for k in kinds { kindByKey[k.k] = k }
		basics = Self.basicNames.compactMap { n in db.one("SELECT ingredient_id FROM ingredient WHERE name=?1", n).isNull ? nil : db.one("SELECT ingredient_id FROM ingredient WHERE name=?1", n).int }
		// required ingredients: not Garnish(2) Rim(6) Spritz(8) Flame(9) Twist(10), and not a citrus
		// twist/peel/zest/wheel/wedge/disc unless muddled (3) into the drink
		let pop = book.store.popularity()
		var steps: [Int: [Req]] = [:]
		for r in db.rows("SELECT s.drink_id, s.ingredient_id, s.mixtype_id, i.name FROM step s JOIN ingredient i ON i.ingredient_id=s.ingredient_id") {
			let mt = r.i(2), nm = r.s(3)
			if [2, 6, 8, 9, 10].contains(mt) { continue }
			if mt != 3 && nm.range(of: "(twist|peel|zest|wheel|wedge|disc)$", options: [.regularExpression, .caseInsensitive]) != nil { continue }
			steps[r.i(0), default: []].append(Req(id: r.i(1), kind: kind[r.i(1)] ?? "", name: nm))
		}
		for r in db.rows("SELECT drink_id, name FROM drink ORDER BY name") {
			guard let req = steps[r.i(0)], !req.isEmpty else { continue }
			let rec = Rec(id: r.i(0), name: r.s(1), pop: pop[r.i(0)] ?? 0, req: req)
			recipes.append(rec)
			recByName[rec.name] = rec
		}
		for r in recipes { for q in r.req { useCount[q.id, default: 0] += 1 } }
	}

	// MARK: matching (bar.js)

	struct Owned { var ex: Set<Int>; var gen: Set<String> }
	/// a bottle you own also counts for its kind (your Don Julio covers any tequila), but not for
	/// produce (bottled lemon juice is not a whole lemon)
	func owned(_ items: [Bar.Item]) -> Owned {
		var o = Owned(ex: [], gen: [])
		for it in items {
			if it.t == "i", let id = it.id {
				o.ex.insert(id)
				if let g = ingById[id], !g.kind.isEmpty, !g.kind.hasPrefix("p_") { o.gen.insert(g.kind) }
				else if let p = PendingBottles.get(id), !p.kind.isEmpty { o.gen.insert(p.kind) }
			} else if let b = it.b { o.gen.insert(b) }
		}
		return o
	}
	func canMake(_ r: Rec, _ o: Owned) -> Bool { r.req.allSatisfy { o.ex.contains($0.id) || (!$0.kind.isEmpty && o.gen.contains($0.kind)) } }
	func makeable(_ o: Owned) -> [Rec] { recipes.filter { canMake($0, o) } }
	/// the distinct things still missing ("b:<kind>" counts once however many of its bottles it lists)
	func missingKeys(_ r: Rec, _ o: Owned) -> [String] {
		var ks: [String] = []
		for q in r.req where !(o.ex.contains(q.id) || (!q.kind.isEmpty && o.gen.contains(q.kind))) {
			let k = q.kind.isEmpty ? "i:\(q.id)" : "b:\(q.kind)"
			if !ks.contains(k) { ks.append(k) }
		}
		return ks
	}
	/// the card's "Missing:" names (pdt_canmake_names): each missing ingredient's own name, once
	func missingNames(_ r: Rec, _ o: Owned) -> [String] {
		var m: [String] = []
		for q in r.req where !(o.ex.contains(q.id) || (!q.kind.isEmpty && o.gen.contains(q.kind))) { if !m.contains(q.name) { m.append(q.name) } }
		return m
	}
	func keyLabel(_ k: String) -> String {
		let v = String(k.dropFirst(2))
		if k.hasPrefix("b") { return kindByKey[v]?.label ?? v }
		return Int(v).flatMap { ingById[$0] }.map { T($0.name) } ?? Int(v).flatMap { PendingBottles.get($0) }?.name ?? "#\(v)"
	}
	func keyItem(_ k: String) -> Bar.Item { let v = String(k.dropFirst(2)); return k.hasPrefix("b") ? .kind(v) : .ing(Int(v) ?? 0) }
	/// a picture for an item: the ingredient's own, or for a kind the most-used bottle of it that has one
	func keyImage(_ k: String) -> URL? {
		let v = String(k.dropFirst(2))
		if k.hasPrefix("i") { return Int(v).flatMap { ingById[$0] }.flatMap { Img.ingredient($0.name) } ?? Int(v).flatMap { PendingBottles.get($0) }?.file }
		return kindImage(v)
	}
	private var kindImg: [String: URL?] = [:]
	func kindImage(_ kind: String) -> URL? {
		if let x = kindImg[kind] { return x }
		let best = ings.filter { $0.kind == kind && Img.ingredient($0.name) != nil }.max { (useCount[$0.id] ?? 0) < (useCount[$1.id] ?? 0) }
		let u = best.flatMap { Img.ingredient($0.name) }
		kindImg[kind] = u
		return u
	}
	func isProduce(_ kind: String) -> Bool { kindByKey[kind]?.produce ?? false }

	/// the browse-by-type group of an item: its category, or for a kind any of its ingredients'
	func typeOf(_ k: String) -> String {
		let v = String(k.dropFirst(2))
		let ing = k.hasPrefix("i") ? Int(v).flatMap { ingById[$0] } : ings.first { $0.kind == v }
		let cat = ing?.cat ?? (k.hasPrefix("i") ? Int(v).flatMap { PendingBottles.get($0) }?.cat : nil)
		if let cat { for t in Self.types where t.cats.contains(cat) { return t.k } }
		return "_other"
	}
	func isBottle(_ k: String) -> Bool { ["spirits", "liqueur", "vermouth", "wine", "bitters"].contains(typeOf(k)) }

	struct PlanStep { let key: String; let recipes: [Rec] }
	/// the best N purchases as a set, greedily: each pick completes the most cocktails given the bar
	/// plus the earlier picks (ties: the one bringing most others closest)
	func bestPlan(_ items: [Bar.Item], _ n: Int, assume: [Int], only: ((String) -> Bool)?) -> [PlanStep] {
		var o = owned(items)
		for id in assume { o.ex.insert(id) }
		var plan: [PlanStep] = []
		for step in 0..<n {
			var gain: [String: [Rec]] = [:], near: [String: Double] = [:], order: [String] = []
			for r in recipes {
				let ks = missingKeys(r, o)
				if ks.isEmpty || ks.count > n - step { continue }
				for k in ks {
					if ks.count == 1 { gain[k, default: []].append(r) }
					if near[k] == nil { order.append(k) }
					near[k, default: 0] += 1 / pow(2, Double(ks.count))
				}
			}
			var best: (k: String, g: Int, n: Double)? = nil
			// in the order the keys first appear, as bar.js's Object.keys: the first of equals wins
			for k in order {
				if let only, !only(k) { continue }
				let g = gain[k]?.count ?? 0
				if best == nil || g > best!.g || (g == best!.g && near[k]! > best!.n) { best = (k, g, near[k]!) }
			}
			guard let b = best else { break }
			let v = String(b.k.dropFirst(2))
			if b.k.hasPrefix("b") { o.gen.insert(v) } else if let id = Int(v) { o.ex.insert(id) }
			plan.append(PlanStep(key: b.k, recipes: (gain[b.k] ?? []).sorted(by: Self.byPop)))
		}
		return plan
	}
	static func byPop(_ a: Rec, _ b: Rec) -> Bool { a.pop != b.pop ? a.pop > b.pop : a.name.localizedCompare(b.name) == .orderedAscending }

	struct Buy { let key: String; var score: Double; var now: [Rec]; var next: [Rec]; var pairs: [String: [Rec]] }
	/// "What is still missing": per missing item, what it completes now and with one more item
	func computeBuy(_ items: [Bar.Item]) -> [Buy] {
		let o = owned(items), w: [Double] = [0, 1, 0.5, 0.25]
		var cand: [String: Buy] = [:]
		for r in recipes {
			let ks = missingKeys(r, o), m = ks.count
			if m < 1 || m > 3 { continue }
			for k in ks {
				var c = cand[k] ?? Buy(key: k, score: 0, now: [], next: [], pairs: [:])
				c.score += w[m]
				if m == 1 { c.now.append(r) }
				else if m == 2 { c.next.append(r); let other = ks[0] == k ? ks[1] : ks[0]; c.pairs[other, default: []].append(r) }
				cand[k] = c
			}
		}
		return cand.values.map { c in var c = c; c.now.sort(by: Self.byPop); c.next.sort(by: Self.byPop); return c }
			.sorted { a, b in
				if a.now.count != b.now.count { return a.now.count > b.now.count }
				if a.score != b.score { return a.score > b.score }
				return keyLabel(a.key).localizedCompare(keyLabel(b.key)) == .orderedAscending
			}
	}
	/// "Your top recipe blockers": what's missing from the most cocktails you can't make yet
	func blockers(_ items: [Bar.Item]) -> [(key: String, count: Int)] {
		let o = owned(items)
		var cnt: [String: Int] = [:]
		for r in recipes { for k in missingKeys(r, o) { cnt[k, default: 0] += 1 } }
		return cnt.map { ($0.key, $0.value) }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : keyLabel($0.0).localizedCompare(keyLabel($1.0)) == .orderedAscending }
	}

	// MARK: search (bar.js matchBase / nameHas)

	static let baseAlias = ["whisky": "whiskey", "bourbon": "whiskey", "rye": "whiskey", "scotch": "whiskey", "rhum": "rum", "cachaca": "rum", "cachaça": "rum",
		"cognac": "brandy", "armagnac": "brandy", "calvados": "brandy", "applejack": "brandy", "mescal": "mezcal", "old tom": "gin", "genepi": "absinthe"]
	func search(_ raw: String) -> [Bar.Item] {
		// accents don't matter ("creme" finds Crème de Myrtille), as bar.js
		let q = Self.fold(raw.trimmingCharacters(in: .whitespaces))
		guard !q.isEmpty else { return [] }
		var alias = Set<String>()
		for (a, k) in Self.baseAlias where a.hasPrefix(q) || q.hasPrefix(a) { alias.insert(k) }
		var out: [Bar.Item] = kinds.filter { $0.k.contains(q) || $0.label.lowercased().contains(q) || alias.contains($0.k) }.map { .kind($0.k) }
		func has(_ n: String) -> Bool {
			let n = Self.fold(n)
			return n.contains(q) || n.contains(q.replacingOccurrences(of: "whisky", with: "whiskey")) || n.contains(q.replacingOccurrences(of: "whiskey", with: "whisky"))
		}
		for g in ings where out.count < 40 && (has(g.name) || has(T(g.name))) { out.append(.ing(g.id)) }
		for p in PendingBottles.all() where out.count < 40 && has(p.name) && ingById[p.id] == nil { out.append(.ing(p.id)) }
		return out
	}
	static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

	// MARK: stand-ins (admin/ingredient_substitutes.json)

	/// "With a stand-in": cocktails you can't make as written where a bottle you own stands in for
	/// each thing missing; each with its swaps (have, want), fewest swaps first, then popularity
	func standins(_ o: Owned) -> [(rec: Rec, swaps: [(have: Int, want: Int)])] {
		var out: [(rec: Rec, swaps: [(have: Int, want: Int)])] = []
		for r in recipes where !canMake(r, o) {
			var swaps: [(have: Int, want: Int)] = [], ok = true, seen = Set<Int>()
			for q in r.req where !(o.ex.contains(q.id) || (!q.kind.isEmpty && o.gen.contains(q.kind))) && !seen.contains(q.id) {
				seen.insert(q.id)
				if let have = Substitutes.ids(for: q.id).first(where: { o.ex.contains($0) }) { swaps.append((have, q.id)) } else { ok = false; break }
			}
			if ok && !swaps.isEmpty { out.append((r, swaps)) }
		}
		return out.sorted { a, b in a.swaps.count != b.swaps.count ? a.swaps.count < b.swaps.count : Self.byPop(a.rec, b.rec) }
	}
	func recById(_ id: Int) -> Rec? { recipes.first { $0.id == id } }
	func name(_ id: Int) -> String { ingById[id].map { T($0.name) } ?? PendingBottles.get(id)?.name ?? "#\(id)" }
	func itemLabel(_ it: Bar.Item) -> String {
		switch it.t {
		case "i": return it.id.flatMap { ingById[$0] }.map { T($0.name) } ?? it.id.flatMap { PendingBottles.get($0) }?.name ?? "#\(it.id ?? 0)"
		case "b": return kindByKey[it.b ?? ""]?.label ?? (it.b ?? "")
		default: return it.d ?? "(custom)"
		}
	}
}

/// admin/ingredient_substitutes.json (bundled): what to use instead of a missing ingredient,
/// keyed by ingredient id (shared by the books): {name, subs: [{name, id|null, tip}], none}
enum Substitutes {
	struct Sub { let name: String; let id: Int?; let tip: String }
	private static let all: [String: (subs: [Sub], none: String)] = {
		guard let d = try? Data(contentsOf: Img.dataDir.appendingPathComponent("ingredient_substitutes.json")),
			  let o = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] else { return [:] }
		return o.mapValues { v in
			let subs = (v["subs"] as? [[String: Any]] ?? []).map { Sub(name: $0["name"] as? String ?? "", id: $0["id"] as? Int, tip: $0["tip"] as? String ?? "") }
			return (subs, v["none"] as? String ?? "")
		}
	}()
	/// the ids that can stand in for an ingredient
	static func ids(for iid: Int) -> [Int] { all[String(iid)]?.subs.compactMap(\.id) ?? [] }
	/// the other way round: what an ingredient can stand in for, {target id, its name, the tip}
	private static let reverse: [Int: [(id: Int, name: String, tip: String)]] = {
		var r: [Int: [(id: Int, name: String, tip: String)]] = [:]
		for (k, v) in all { guard let tid = Int(k), let o = rawNames[k] else { continue }; for s in v.subs { if let sid = s.id { r[sid, default: []].append((tid, o, s.tip)) } } }
		return r
	}()
	private static let rawNames: [String: String] = {
		guard let d = try? Data(contentsOf: Img.dataDir.appendingPathComponent("ingredient_substitutes.json")),
			  let o = try? JSONSerialization.jsonObject(with: d) as? [String: [String: Any]] else { return [:] }
		return o.compactMapValues { $0["name"] as? String }
	}()
	static func standsIn(for iid: Int) -> [(id: Int, name: String, tip: String)] { reverse[iid] ?? [] }
	/// pdt_missing_note: up to two, the ones already in the bar first (marked have = true)
	static func note(_ iid: Int, book: Book, items: [Bar.Item]) -> (subs: [(Sub, have: Bool)], none: String)? {
		guard let e = all[String(iid)] else { return nil }
		let ix = BarIndex.of(book), o = ix.owned(items)
		let marked = e.subs.map { s -> (Sub, have: Bool) in
			guard let id = s.id else { return (s, false) }
			let k = ix.ingById[id]?.kind ?? ""
			return (s, o.ex.contains(id) || (!k.isEmpty && o.gen.contains(k)))
		}
		return (Array((marked.filter(\.have) + marked.filter { !$0.have }).prefix(2)), e.subs.isEmpty ? e.none : "")
	}
}

/// bottles the member photographed that wait for an admin (GET /cocktails/api/me "bottles"), with
/// their photo saved on the device; Member fills this, the bar index reads it for names and pictures
enum PendingBottles {
	struct P { let id: Int; let name: String; let cat: String; let kind: String; let file: URL? }
	private static var byId: [Int: P] = [:]
	private static let lock = NSLock()
	static func set(_ ps: [P]) { lock.lock(); byId = Dictionary(ps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }); lock.unlock() }
	static func get(_ id: Int) -> P? { lock.lock(); defer { lock.unlock() }; return byId[id] }
	static func all() -> [P] { lock.lock(); defer { lock.unlock() }; return Array(byId.values).sorted { $0.name < $1.name } }
}
