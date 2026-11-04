import Foundation

/// Picture locations. Each book db names its pictures in the `image` column of drink,
/// ingredient and glass (admin/cocktail_lib.py fill_image_columns): the path below
/// cocktails/img/ without the extension, NULL where there's none. The AVIFs are bundled
/// under Data/img by scripts/sync_data.sh. A missing file = no picture (as on the site).
enum Img {
	static let dataDir: URL = Bundle.main.resourceURL!.appendingPathComponent("Data")

	/// name -> image, per table; ingredients and glasses are shared between the books, so
	/// theirs are merged across every db; a drink's is per book (names collide across books)
	private static func names(_ table: String, _ db: SQLiteDB) -> [String: String] {
		var m: [String: String] = [:]
		for r in db.rows("SELECT name, image FROM \(table) WHERE image IS NOT NULL AND name IS NOT NULL") { m[r.s(0)] = r.s(1) }
		return m
	}
	private static let drinks: [String: [String: String]] = Dictionary(uniqueKeysWithValues: Book.all.map { ($0.key, names("drink", $0.store.db)) })
	private static let ingredients: [String: String] = Book.all.reduce(into: [:]) { m, b in m.merge(names("ingredient", b.store.db)) { a, _ in a } }
	private static let glasses: [String: String] = Book.all.reduce(into: [:]) { m, b in m.merge(names("glass", b.store.db)) { a, _ in a } }

	static func local(_ rel: String) -> URL? {
		let u = dataDir.appendingPathComponent(rel)
		return FileManager.default.fileExists(atPath: u.path) ? u : nil
	}
	private static func avif(_ image: String?) -> URL? { image.flatMap { local("img/\($0).avif") } }
	static func cocktail(_ book: String, _ name: String) -> URL? { avif(drinks[book]?[name]) }
	static func ingredient(_ name: String) -> URL? { avif(ingredients[name]) }
	/// the cocktail photo trimmed on all sides (<book>/tz/), for the phone layout's photo
	static func cocktailTrim(_ book: String, _ name: String) -> URL? {
		drinks[book]?[name].flatMap { rel in local("img/" + (rel as NSString).deletingLastPathComponent + "/tz/" + (rel as NSString).lastPathComponent + ".jpg") }
	}
	/// the ingredient trimmed to the bottle and its shadow (ingredients/tc/, admin/pdt_img_jpg.py);
	/// every one on the same scale, the full picture being 216px tall
	static func ingredientTrim(_ name: String) -> URL? {
		ingredients[name].flatMap { rel in local("img/" + (rel as NSString).deletingLastPathComponent + "/tc/" + (rel as NSString).lastPathComponent + ".jpg") }
	}
	static func glass(_ name: String) -> URL? { avif(glasses[name]) }
	/// dark mode (the site's cocktails/js/dark_img.js): a drink, ingredient or spirit picture's cut-out,
	/// <dir>/dark/[t/]<name>.avif, white background and shadow removed; nil where there's none.
	/// t/ and tc/ (small, trimmed) use dark/t/, the rest dark/
	static func dark(_ u: URL?) -> URL? {
		guard let u, u.isFileURL else { return nil }
		let p = u.path, root = dataDir.appendingPathComponent("img").path + "/"
		guard p.hasPrefix(root) else { return nil }
		var parts = String(p.dropFirst(root.count)).split(separator: "/").map(String.init)
		guard parts.count >= 2, ["pdt", "deathco", "ingredients", "spirits"].contains(parts[0]), !parts.contains("dark") else { return nil }
		let file = parts.removeLast(), name = (file as NSString).deletingPathExtension
		let sub = parts.count > 1 ? parts[1] : ""
		guard parts.count <= 2, sub.isEmpty || ["t", "tc", "tz", "tr", "vc"].contains(sub) else { return nil }
		return local("img/\(parts[0])/dark/" + (sub == "t" || sub == "tc" ? "t/" : "") + name + ".avif")
	}
	static func spiritPair(_ a: String, _ b: String) -> URL? { local("img/spirits/pair/\(a)-\(b).avif") }

	// the full-size pictures (1024px PNG) aren't bundled: "See it larger" fetches them from the
	// website, as its overlays do, showing the bundled one until it arrives
	static let site = URL(string: "https://decentespresso.com/cocktails/img/")!
	private static func remote(_ rel: String) -> URL? {
		rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: $0, relativeTo: site)?.absoluteURL }
	}
	static func cocktailBig(_ book: String, _ name: String) -> URL? { drinks[book]?[name].flatMap { remote("\($0).png") } }
	static func ingredientBig(_ name: String) -> URL? { ingredients[name].flatMap { remote("\($0).png") } }
	static func spiritPairBig(_ a: String, _ b: String) -> URL? { spiritPair(a, b) == nil ? nil : remote("spirits/pair/\(a)-\(b).png") }
	/// the real product photo an ingredient's picture was modelled on (ingredient.bottle_img; the
	/// overlay's "product photo" link)
	static func productPhoto(_ name: String) -> URL? { productPhotos[name].flatMap { remote($0) } }
	private static let productPhotos: [String: String] = Book.all.reduce(into: [:]) { m, b in
		for r in b.store.db.rows("SELECT name, bottle_img FROM ingredient WHERE bottle_img IS NOT NULL AND bottle_img <> ''") where m[r.s(0)] == nil { m[r.s(0)] = r.s(1) }
	}
}
