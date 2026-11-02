import Foundation
import SwiftUI

/// The signed-in member's cocktail data, the same rows the website uses (lib/cocktails_member.tcl,
/// through /cocktails/api/me), so the app and the site stay one: Liked and Made (drink ids from
/// every book; Made with when it was last made), notes ({id: comment}), Your Bar and the "hide if you
/// cannot make" preference. A copy is kept on the device so the lists show offline; each change is
/// its own request (one drink, one note), so the app and the site can't undo each other's changes.
@MainActor
final class Member: ObservableObject {
	static let shared = Member()

	@Published private(set) var wish: [Int] = []
	@Published private(set) var made: [Int] = []
	@Published private(set) var madeOn: [String: Int] = [:]
	@Published private(set) var notes: [String: String] = [:]
	@Published private(set) var bar = Bar.normalized(nil)
	@Published private(set) var hideUnmakeable = false
	@Published private(set) var loaded = false
	/// the server's bar couldn't be read: never overwrite it
	private var barUnreadable = false

	private let cacheKey = "member.cache"
	private var account: Account { Account.shared }

	init() { restore() }

	// MARK: load / clear

	func load() async {
		guard account.signedIn, let me = await account.me() else { return }
		let liked = me["liked"] as? [[String: Any]] ?? [], mades = me["made"] as? [[String: Any]] ?? []
		wish = liked.compactMap { Self.int($0["id"]) }
		made = mades.compactMap { Self.int($0["id"]) }
		madeOn = Dictionary(uniqueKeysWithValues: mades.compactMap { m in Self.int(m["id"]).flatMap { id in Self.int(m["last_made_at"]).map { (String(id), $0) } } })
		notes = (me["notes"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
		if let b = me["bar"] as? [String: Any] {
			if let d = try? JSONSerialization.data(withJSONObject: b), case .some(let parsed) = Bar.decode(String(decoding: d, as: UTF8.self)) { bar = Bar.normalized(parsed); barUnreadable = false } else { barUnreadable = true }
		} else { bar = Bar.normalized(nil); barUnreadable = false }
		hideUnmakeable = (me["prefs"] as? [String: Any])?["hide_unmakeable"] as? Bool ?? false
		loaded = true
		save()
	}
	func clear() {
		wish = []; made = []; madeOn = [:]; notes = [:]; bar = Bar.normalized(nil); hideUnmakeable = false; loaded = false
		UserDefaults.standard.removeObject(forKey: cacheKey)
	}

	// MARK: marks (pdt_marks_js)

	func isWish(_ id: Int) -> Bool { wish.contains(id) }
	func isMade(_ id: Int) -> Bool { made.contains(id) }

	func toggleWish(_ id: Int) {
		let adding = !wish.contains(id)
		if adding { wish.append(id) } else { wish.removeAll { $0 == id } }
		send(adding ? "PUT" : "DELETE", "liked/\(id)")
	}
	/// marking Made dates it today; un-marking takes it off
	func toggleMade(_ id: Int) {
		let adding = !made.contains(id)
		if adding { made.append(id); madeOn[String(id)] = Self.now } else { made.removeAll { $0 == id }; madeOn.removeValue(forKey: String(id)) }
		send(adding ? "PUT" : "DELETE", "made/\(id)", query: adding ? ["source": "app"] : [:])
	}
	/// the scale maker reaching the glass: made, and made again today if it was already
	func addMade(_ id: Int) {
		if !made.contains(id) { made.append(id) }
		madeOn[String(id)] = Self.now
		send("PUT", "made/\(id)", query: ["source": "scale"])
	}
	func note(_ id: Int) -> String { notes[String(id)] ?? "" }
	func setNote(_ id: Int, _ text: String) {
		let v = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
		guard v != note(id) else { return }
		if v.isEmpty { notes.removeValue(forKey: String(id)) } else { notes[String(id)] = v }
		// one note per request, so a note written on the site since isn't wiped
		send(v.isEmpty ? "DELETE" : "PUT", "notes/\(id)", fields: v.isEmpty ? [:] : ["note": v])
	}

	// MARK: Your Bar (bar.js)

	var items: [Bar.Item] { bar.current.items }
	func has(_ it: Bar.Item) -> Bool { items.contains { $0.key == it.key } }
	func add(_ it: Bar.Item) { editBar { b in let i = b.curIndex; if !b.locs[i].items.contains(where: { $0.key == it.key }) { b.locs[i].items.append(it) } } }
	func add(_ its: [Bar.Item]) { editBar { b in let i = b.curIndex; for it in its where !b.locs[i].items.contains(where: { $0.key == it.key }) { b.locs[i].items.append(it) } } }
	func remove(_ it: Bar.Item) { editBar { b in let i = b.curIndex; b.locs[i].items.removeAll { $0.key == it.key } } }
	func setLocation(_ id: String) { editBar { $0.cur = id } }
	func renameLocation(_ name: String) {
		let n = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
		guard !n.isEmpty else { return }
		editBar { b in b.locs[b.curIndex].name = n }
	}
	func newLocation(_ name: String) {
		let n = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
		guard !n.isEmpty else { return }
		editBar { b in let l = Bar.Loc(id: Bar.newId(), name: n, items: []); b.locs.append(l); b.cur = l.id }
	}
	func deleteLocation() {
		guard bar.locs.count > 1 else { return }
		editBar { b in let c = b.cur; b.locs.removeAll { $0.id == c }; b.cur = b.locs[0].id }
	}
	var canEditBar: Bool { account.signedIn && !barUnreadable }
	private func editBar(_ f: (inout Bar) -> Void) {
		guard canEditBar else { return }
		var b = bar
		f(&b)
		bar = Bar.normalized(b)
		send("PUT", "bar", fields: ["bar": bar.json()])
	}
	func setHideUnmakeable(_ v: Bool) {
		hideUnmakeable = v
		send("PUT", "prefs", fields: ["hide_unmakeable": v ? "1" : "0"])
	}

	// MARK: can make (pdt_canmake_names), per book

	/// the names of a book's cocktails the bar can make, and what each other one is missing
	func canMake(_ book: Book) -> (names: Set<String>, missing: [String: [String]]) {
		let ix = BarIndex.of(book), o = ix.owned(items)
		var ok = Set<String>(), miss: [String: [String]] = [:]
		for r in ix.recipes {
			let m = ix.missingNames(r, o)
			if m.isEmpty { ok.insert(r.name) } else { miss[r.name] = m }
		}
		return (ok, miss)
	}

	// MARK: plumbing

	private func send(_ method: String, _ path: String, query: [String: String] = [:], fields: [String: String] = [:]) {
		save()
		Task { await account.api(method, path, query: query, fields: fields) }
	}
	private static var now: Int { Int(Date().timeIntervalSince1970) }
	private static func int(_ v: Any?) -> Int? { (v as? Int) ?? (v as? Double).map { Int($0) } ?? (v as? String).flatMap { Int($0) } }
	private struct Cache: Codable { var wish, made: [Int]; var madeOn: [String: Int]; var notes: [String: String]; var bar: Bar; var hide: Bool }
	private func save() {
		let c = Cache(wish: wish, made: made, madeOn: madeOn, notes: notes, bar: bar, hide: hideUnmakeable)
		if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: cacheKey) }
	}
	private func restore() {
		guard Account.shared.signedIn, let d = UserDefaults.standard.data(forKey: cacheKey), let c = try? JSONDecoder().decode(Cache.self, from: d) else { return }
		wish = c.wish; made = c.made; madeOn = c.madeOn; notes = c.notes; bar = c.bar; hideUnmakeable = c.hide
	}
}
