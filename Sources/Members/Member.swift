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
	/// sharing (Your Bar > Settings): the member's id (their shareable pages' address), the name
	/// they're listed under, what they share (nil until they've opened Settings once), and the
	/// people whose bars they've added to the location menu
	@Published private(set) var userid = 0
	@Published private(set) var shareName = ""
	@Published private(set) var share: Share?
	@Published private(set) var following: [Person] = []
	/// bumped when the pending bottles (PendingBottles) change, so views redraw
	@Published private(set) var pendingVersion = 0
	struct Share: Codable, Equatable { var made: Bool; var liked: Bool }
	struct Person: Codable, Hashable, Identifiable { let u: Int; let name: String; var id: Int { u } }
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
		let prefs = me["prefs"] as? [String: Any] ?? [:]
		hideUnmakeable = prefs["hide_unmakeable"] as? Bool ?? false
		userid = Self.int(me["userid"]) ?? 0
		shareName = me["name"] as? String ?? ""
		share = (prefs["share"] as? [String: Any]).map { Share(made: $0["made"] as? Bool ?? false, liked: $0["liked"] as? Bool ?? false) }
		following = (me["following"] as? [[String: Any]] ?? []).compactMap { f in Self.int(f["u"]).map { Person(u: $0, name: f["name"] as? String ?? "") } }
		loaded = true
		save()
		await loadPending(me["bottles"] as? [[String: Any]] ?? [])
	}
	/// the pending bottles, each photo fetched once (with the token) into the caches folder
	private func loadPending(_ rows: [[String: Any]]) async {
		let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("pending-bottles")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		var ps: [PendingBottles.P] = []
		for r in rows {
			guard let id = Self.int(r["id"]) else { continue }
			let photo = r["photo"] as? String ?? ""
			let f = dir.appendingPathComponent("\(id).jpg")
			if !FileManager.default.fileExists(atPath: f.path), !photo.isEmpty,
			   let (d, code) = await account.fetch(String(photo.dropFirst())), code == 200 { try? d.write(to: f) }
			ps.append(.init(id: id, name: r["name"] as? String ?? "", cat: r["category"] as? String ?? "", kind: r["kind"] as? String ?? "",
				file: FileManager.default.fileExists(atPath: f.path) ? f : nil))
		}
		PendingBottles.set(ps)
		pendingVersion += 1
	}
	func clear() {
		wish = []; made = []; madeOn = [:]; notes = [:]; bar = Bar.normalized(nil); hideUnmakeable = false; loaded = false
		userid = 0; shareName = ""; share = nil; following = []; PendingBottles.set([]); pendingVersion += 1
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

	// MARK: sharing (Your Bar > Settings, other people's bars)

	/// the first visit to Settings saves the prechecked choice (bar.js renderSettings)
	func openedSettings() { if share == nil && loaded { setShare(Share(made: true, liked: true)) } }
	func setShare(_ s: Share) {
		share = s
		send("PUT", "prefs", fields: ["share_made": s.made ? "1" : "0", "share_liked": s.liked ? "1" : "0"])
	}
	/// the name others see; "" goes back to the account's name. Returns the site's error, if any
	func setShareName(_ name: String) async -> String? {
		let (code, j) = await account.apiReply("PUT", "prefs", fields: ["share_name": name.trimmingCharacters(in: .whitespaces)])
		if code != 200 { return j["error"] as? String ?? T("Something went wrong. Please try again.") }
		await load()
		return nil
	}
	/// the shareable Made / Liked page: /cocktails/<book>/made|liked/<userid>
	func shareURL(_ kind: String, _ book: Book) -> URL? {
		userid > 0 ? account.server.appendingPathComponent("cocktails/\(book.key)/\(kind)/\(userid)") : nil
	}
	struct Sharer: Identifiable { let u: Int; let name: String; let made: Int; let wish: Int; var id: Int { u } }
	/// members who share something (but you): /cocktails/<book>/bar/sharers.json
	func sharers(_ book: Book) async -> [Sharer]? {
		guard let j = await account.getJSON("cocktails/\(book.key)/bar/sharers.json") as? [String: Any] else { return nil }
		return (j["people"] as? [[String: Any]] ?? []).compactMap { p in
			Self.int(p["u"]).map { Sharer(u: $0, name: p["name"] as? String ?? "", made: Self.int(p["made"]) ?? 0, wish: Self.int(p["wish"]) ?? 0) }
		}
	}
	struct Shared { let name: String; let made: [Int]?; let wish: [Int]?; let madeOn: [String: Int]; let gone: Bool }
	/// what one of them shares (shared.json): nil fields aren't shared; gone = they stopped sharing
	func shared(_ u: Int, _ book: Book) async -> Shared? {
		guard let (d, code) = await account.fetch("cocktails/\(book.key)/bar/shared.json", query: ["u": String(u)]) else { return nil }
		if code == 404 { return Shared(name: following.first { $0.u == u }?.name ?? "", made: nil, wish: nil, madeOn: [:], gone: true) }
		guard code == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
		return Shared(name: j["name"] as? String ?? "", made: (j["made"] as? [Any])?.compactMap { Self.int($0) }, wish: (j["wish"] as? [Any])?.compactMap { Self.int($0) },
			madeOn: (j["made_on"] as? [String: Any] ?? [:]).compactMapValues { Self.int($0) }, gone: false)
	}
	func follow(_ p: Person) {
		if !following.contains(where: { $0.u == p.u }) { following.append(p) }
		send("PUT", "following/\(p.u)")
	}
	func unfollow(_ u: Int) {
		following.removeAll { $0.u == u }
		send("DELETE", "following/\(u)")
	}

	// MARK: a photographed bottle

	/// upload it; the site identifies it and adds it to the current bar. Returns what to tell the
	/// member: (added, message)
	func addBottle(photo jpeg: Data) async -> (ok: Bool, message: String) {
		let (code, j) = await account.uploadBottle(jpeg)
		if code == 200, j["ok"] as? Bool == true {
			let name = j["name"] as? String ?? ""
			await load()
			var m = T("Added {name} to Your Bar.", ["name": name])
			if j["how"] as? String == "new" { m += "\n" + T("It's new to us: it shows with your photo until we've made its picture.") }
			return (true, m)
		}
		return (false, j["error"] as? String ?? T("Something went wrong. Please try again."))
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
	private struct Cache: Codable { var wish, made: [Int]; var madeOn: [String: Int]; var notes: [String: String]; var bar: Bar; var hide: Bool
		var userid: Int?; var shareName: String?; var share: Share?; var following: [Person]? }
	private func save() {
		let c = Cache(wish: wish, made: made, madeOn: madeOn, notes: notes, bar: bar, hide: hideUnmakeable, userid: userid, shareName: shareName, share: share, following: following)
		if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: cacheKey) }
	}
	private func restore() {
		guard Account.shared.signedIn, let d = UserDefaults.standard.data(forKey: cacheKey), let c = try? JSONDecoder().decode(Cache.self, from: d) else { return }
		wish = c.wish; made = c.made; madeOn = c.madeOn; notes = c.notes; bar = c.bar; hideUnmakeable = c.hide
		userid = c.userid ?? 0; shareName = c.shareName ?? ""; share = c.share; following = c.following ?? []
	}
}
