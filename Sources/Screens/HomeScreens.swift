import SwiftUI

/// /cocktails/ (direct_cocktails_home): "Choose a cocktail book" and one card per book.
struct BooksView: View {
	@State private var hidden = VideoCard.isHidden
	var body: some View {
		PageScroll {
			// .phgrid: the heading and the tour video side by side above 860px, stacked below
			VW { vw in
				let head = VStack(alignment: .leading, spacing: 0) {
					H1(T("Choose a cocktail book"))
					Text(TM("Recipes from <b><i>The PDT Cocktail Book</i></b> and <b><i>Death & Co: Modern Classic Cocktails</i></b>. Every ingredient weighed to the gram, every step described. Ready to make on our <a href=\"/scale\">Half Decent Scale</a>."))
						.font(Theme.sans(15.2)).foregroundStyle(Theme.soft).lineSpacing(3).padding(.top, 12)
				}
				if Theme.narrow(vw) || hidden {
					head.padding(.top, 18)
					if !hidden { VideoCard(hidden: $hidden).padding(.top, 22) }
				} else {
					HStack(alignment: .center, spacing: 44) {
						head.frame(maxWidth: .infinity, alignment: .leading)
						VideoCard(hidden: $hidden).frame(maxWidth: 440)
					}.padding(.top, 18)
				}
			}
			.padding(.bottom, 26)
			BookGrid()
		}
		// hidden on the website (or another device) by a signed-in member: hide it here too
		.task {
			if !hidden, Account.shared.signedIn, let me = await Account.shared.me(), (me["prefs"] as? [String: Any])?["video_hidden"] as? Bool == true {
				UserDefaults.standard.set(true, forKey: "vidHidden"); hidden = true
			}
		}
		.navigationTitle("Decent Cocktails")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
		.safeAreaInset(edge: .top, spacing: 0) { SiteNav(book: nil) }
	}
}

/// .vid: the explainer video's card (pdt_video_card): its thumbnail with "Watch the 2-minute
/// tour" and a play button, opening the YouTube video; the x hides it for good (on the device, and
/// for a signed-in member in the site's member prefs (video_hidden), which hides it on the website too)
struct VideoCard: View {
	@Binding var hidden: Bool
	@Environment(\.vw) private var vw
	@State private var playing = false
	static let youtube = URL(string: "https://www.youtube.com/watch?v=JzXRUSfnMUs")!
	static var isHidden: Bool { UserDefaults.standard.bool(forKey: "vidHidden") }
	var body: some View {
		Button { playing = true } label: {
			Pic(url: Img.local("img/video/explainer.jpg"), bg: nil).aspectRatio(16 / 9, contentMode: .fit)
				.overlay {
					HStack(spacing: 10) {
						// .vidcap: clamp(1.8rem, 4.8vw, 2.3rem), on two lines as the site's wraps
						Text(T("Watch the 2-minute tour").replacingOccurrences(of: "-", with: "\u{2011}")).font(Theme.sans(min(36.8, max(28.8, vw * 0.048)), .bold)).foregroundStyle(.white)
							.lineSpacing(-4).shadow(color: .black.opacity(0.55), radius: 2, y: 1).multilineTextAlignment(.center)
							.frame(maxWidth: min(36.8, max(28.8, vw * 0.048)) * 6.5)
						Circle().fill(Theme.acc).frame(width: 46, height: 46)
							.overlay(Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(.white).offset(x: 2))
							.shadow(color: .black.opacity(0.3), radius: 6, y: 4)
					}
					.padding(.vertical, 7).padding(.leading, 20).padding(.trailing, 7)
					.background(Color.black.opacity(0.6), in: Capsule())
					.padding(.horizontal, 12)
				}
				.clipShape(RoundedRectangle(cornerRadius: 14))
				.overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
		}
		.buttonStyle(.plain)
		.accessibilityLabel(T("Play the Decent Cocktails video"))
		.overlay(alignment: .topTrailing) {
			Button { hide() } label: {
				Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
					.frame(width: 32, height: 32).background(Color(hex: 0x55554E), in: Circle())
					.overlay(Circle().stroke(Theme.paper, lineWidth: 2))
			}
			.buttonStyle(.plain).focusEffectDisabled()
			.offset(x: 12, y: -12)
			.accessibilityLabel(T("Hide this video"))
		}
		.sheet(isPresented: $playing) { SafariView(url: Self.youtube).ignoresSafeArea() }
	}
	private func hide() {
		UserDefaults.standard.set(true, forKey: "vidHidden")
		hidden = true
		if Account.shared.signedIn { Task { await Account.shared.api("PUT", "prefs", fields: ["video_hidden": "1"]) } }
	}
}

/// .bkgrid: columns of min(100%, 420px), 26 apart: one on a phone or a portrait iPad, two wider
struct BookGrid: View {
	@Environment(\.cw) private var w
	var body: some View {
		let n = max(1, Int((w + 26) / (420 + 26)))
		LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 26, alignment: .top), count: n), spacing: 26) {
			ForEach(Book.all) { BookCard(book: $0) }
		}
	}
}

struct BookCard: View {
	let book: Book
	/// the book's three pictures: Death & Co's picks (dark drinks), else the 3 most popular
	private var shown: [DrinkRef] {
		let s = book.store
		if book.key == "deathco" {
			let picks = ["Negroni", "Get Lucky", "Black Market Brandy"].compactMap { nm -> DrinkRef? in
				let v = s.db.one("SELECT drink_id FROM drink WHERE name=?1", nm)
				return v.isNull ? nil : DrinkRef(id: v.int, name: nm)
			}
			if !picks.isEmpty { return picks }
		}
		return s.byPopularity(limit: 3)
	}
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .bottom, spacing: 8) {
				ForEach(shown) { d in
					NavigationLink(value: Route.recipe(book.key, name: d.name)) {
						Pic(url: book.store.cocktailImg(d.name)).frame(height: 150)
					}.buttonStyle(.plain)
				}
			}
			.padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
			.frame(maxWidth: .infinity, minHeight: 190)
			.background(Theme.picBG)
			Rectangle().fill(Theme.line).frame(height: 1)
			NavigationLink(value: Route.home(book.key)) {
				VStack(alignment: .leading, spacing: 6) {
					Eye("\(book.authors) · \(book.year)")
					Text(book.title).font(Theme.sans(21, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
					Text(nCocktails(book.nstated)).font(Theme.mono(13.4)).foregroundStyle(Theme.ink)
					Text("\(T("Browse the recipes")) →").font(Theme.mono(12.5)).foregroundStyle(Theme.acc).padding(.top, 8)
				}
				.padding(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
				.frame(maxWidth: .infinity, alignment: .leading)
				// the text half in light grey, so each book reads as its own card
				.background(Theme.bookCard)
				.contentShape(Rectangle())
			}.buttonStyle(.plain)
		}
		.overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line2))
		.clipShape(RoundedRectangle(cornerRadius: 14))
	}
}

/// /<book>/ (direct_pdt HOME)
struct HomeView: View {
	let book: Book
	@State private var q = ""
	@State private var mixA = ""
	@State private var mixB = ""
	@State private var openCats: Set<String> = []
	@State private var openIngs: Set<String> = []
	@Environment(\.navPush) private var push

	var body: some View {
		let s = book.store
		PageScroll {
			// .hero: the headline (clamp(2.5rem, 6.2vw, 4.8rem)), the lede and the search; above
			// 860px the picture beside them, below it under them
			VW { vw in
				Crumb(items: [(T("Home"), .home(book.key))]).padding(.top, 10)
				let h1 = min(76.8, max(40, vw * 0.062))
				let text = VStack(alignment: .leading, spacing: 0) {
					// h1: the <em> words in the accent colour, the scale in green (not italic)
					Text(TM("{n} <em>cocktails</em> using a <em class=\"g\">scale</em>", ["n": book.nstated], style: [
						"em": { $0.inlinePresentationIntent = nil; $0.foregroundColor = Theme.acc },
						"em.g": { $0.inlinePresentationIntent = nil; $0.foregroundColor = Theme.green },
					]))
						.font(Theme.sans(h1, .semibold)).kerning(-h1 * 0.03).lineSpacing(-h1 * 0.15).foregroundStyle(Theme.ink)
						.frame(maxWidth: h1 * 8, alignment: .leading)
					lede.font(Theme.sans(min(17.9, max(16, vw * 0.016)))).foregroundStyle(Theme.soft).lineSpacing(4).padding(.top, 26)
						.frame(maxWidth: 560, alignment: .leading)
					SearchBox(q: $q) { push(.search(book.key, q: q)) }.frame(maxWidth: 480).padding(.top, 28)
				}
				let pic = Pic(url: book.heroURL, bg: nil).aspectRatio(1, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
				if Theme.narrow(vw) {
					text.padding(.top, min(70, max(40, vw * 0.07)) - 16)
					pic.padding(.top, 24).padding(.bottom, 30)
				} else {
					HStack(alignment: .center, spacing: min(48, max(24, vw * 0.04))) {
						text.frame(maxWidth: .infinity, alignment: .leading)
						pic.frame(maxWidth: .infinity)
					}
					.padding(.top, min(70, max(40, vw * 0.07)) - 16).padding(.bottom, 38)
				}
			}
			// 01 By base spirit
			Block {
				SectionHead(title: T("By base spirit")) { PillLink(label: T("All"), route: .spirits(book.key)) }
				VStack(spacing: 0) { ForEach(s.spiritCounts(), id: \.0) { SpiritRow(book: book, key: $0.0, count: $0.1) } }
			}
			// 02 Base spirit + ...?
			Block {
				SectionHead(title: "\(T("Base spirit +")) …?")
				MixBox(book: book, a: $mixA, b: $mixB)
			}
			// spirit pairs + ingredient types
			Block {
				Eye(T("By spirit pairs")).padding(.bottom, 10)
				VStack(spacing: 0) {
					ForEach(s.spiritPairs(), id: \.key) { g in
						LinkRow(label: Store.spiritLabel(g.key), image: s.spiritImg(g.key), count: g.count, route: .spirit(book.key, key: g.key, and: ""))
						ForEach(g.pairs, id: \.0) { p in
							LinkRow(label: Store.spiritLabel(p.0), image: s.spiritImg(p.0), count: p.1, route: .spirit(book.key, key: g.key, and: p.0), indent: 14, sub: true)
						}
					}
				}
				Eye(T("By ingredient type")).padding(.top, 34).padding(.bottom, 10)
				Drill(book: book, open: $openCats, openIngs: $openIngs)
			}
			// 03 Most popular
			Block {
				SectionHead(title: T("Most popular cocktails")) { PillLink(label: T("Browse all {n}", ["n": book.nstated]), route: .recipes(book.key, sort: "pop")) }
				CardGrid(book: book, drinks: s.byPopularity(limit: 12))
			}
		}
		.onAppear { if mixA.isEmpty { mixA = s.spiritCounts().first?.0 ?? "gin" } }
	}

	private var lede: Text {
		if book.key == "pdt" {
			return Text(TM("Recipes from the <b><i>Please Don't Tell</i></b> (New York) bar book. Every ingredient weighed, every step described."))
		}
		return Text(TM("Recipes from <b><i>{book}</i></b>. Every ingredient weighed, every step described.", ["book": book.title]))
	}
}

/// .heroSearch: the search field with its mono SEARCH → button
struct SearchBox: View {
	@Binding var q: String
	var autofocus = false
	let go: () -> Void
	@FocusState private var focused: Bool
	var body: some View {
		HStack(spacing: 0) {
			TextField(T("Negroni, mezcal, lime..."), text: $q)
				.font(Theme.sans(17)).foregroundStyle(Theme.ink).padding(.vertical, 11)
				.textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
				.focused($focused).onSubmit(go)
			Button(action: go) {
				Text("\(T("Search").uppercased()) →").font(Theme.mono(13)).kerning(0.5).foregroundStyle(Theme.acc)
					.padding(.horizontal, 15).padding(.vertical, 9)
					.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
			}.buttonStyle(.plain).padding(.leading, 8)
		}
		.padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 5))
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
		.frame(maxWidth: 480)
		.onAppear { if autofocus { focused = true } }
	}
}

/// .mix: Spirit [select] + With [select] -> the spirit / mix page
struct MixBox: View {
	let book: Book
	@Binding var a: String
	@Binding var b: String
	@Environment(\.navPush) private var push
	var body: some View {
		let data = book.store.mixData()
		let rows = data[a] ?? []
		HStack(alignment: .center, spacing: 16) {
			VStack(alignment: .leading, spacing: 3) {
				Text(T("Spirit").uppercased()).font(Theme.mono(11.2)).kerning(0.6).foregroundStyle(Theme.faint)
				Menu {
					ForEach(book.store.spiritCounts(), id: \.0) { k, _ in
						Button(Store.spiritLabel(k)) { a = k; b = "" }
					}
				} label: { menuLabel(Store.spiritLabel(a)) }
			}
			Text("+").font(Theme.mono(16.8)).foregroundStyle(Theme.faint)
			VStack(alignment: .leading, spacing: 3) {
				Text(T("With").uppercased()).font(Theme.mono(11.2)).kerning(0.6).foregroundStyle(Theme.faint)
				Menu {
					Button(T("anything")) { b = ""; push(.spirit(book.key, key: a, and: "")) }
					ForEach([("sp", T("Base spirit")), ("st", T("Style")), ("fl", T("Flavour"))], id: \.0) { g, glabel in
						let opts = rows.filter { $0.group == g }
						if !opts.isEmpty {
							Section(glabel) {
								ForEach(opts, id: \.value) { o in
									Button("\(o.label) (\(o.count))") { b = o.value; push(.spirit(book.key, key: a, and: o.value)) }
								}
							}
						}
					}
				} label: { menuLabel(b.isEmpty ? T("anything") : Store.secondLabel(b)) }
			}
		}
		.padding(.horizontal, 18).padding(.vertical, 10)
		.frame(maxWidth: 560, alignment: .leading)
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
	}
	private func menuLabel(_ s: String) -> some View {
		HStack {
			Text(s).font(Theme.sans(15.7)).foregroundStyle(Theme.ink)
			Spacer()
			Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
		}
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity)
	}
}

/// "By ingredient type": category -> ingredient -> base spirits, each a tap-to-open row
struct Drill: View {
	let book: Book
	@Binding var open: Set<String>
	@Binding var openIngs: Set<String>
	var body: some View {
		let s = book.store
		VStack(alignment: .leading, spacing: 0) {
			ForEach(s.drill(), id: \.cat) { c in
				head(c.name, c.n, s.catImg(c.cat), open.contains(c.cat), level: 0) { toggle(&open, c.cat) }
				if open.contains(c.cat) {
					ForEach(c.ings, id: \.name) { ing in
						let k = "\(c.cat)\u{1}\(ing.name)"
						head(T(ing.name), ing.count, Img.ingredient(ing.name), openIngs.contains(k), level: 1) { toggle(&openIngs, k) }
						if openIngs.contains(k) {
							ForEach(ing.spirits, id: \.key) { sp in
								LinkRow(label: Store.spiritLabel(sp.key), image: s.spiritImg(sp.key), count: sp.count,
									route: .spirit(book.key, key: sp.key, and: "ing:\(ing.name)"), indent: 40, sub: true)
							}
						}
					}
				}
			}
		}
	}
	private func toggle(_ set: inout Set<String>, _ k: String) { if set.contains(k) { set.remove(k) } else { set.insert(k) } }
	private func head(_ label: String, _ count: Int, _ img: URL?, _ isOpen: Bool, level: Int, _ tap: @escaping () -> Void) -> some View {
		Button(action: tap) {
			VStack(spacing: 0) {
				if level == 0 { Rectangle().fill(Theme.line).frame(height: 1) }
				HStack(spacing: 8) {
					Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.faint)
						.rotationEffect(.degrees(isOpen ? 90 : 0))
					if let img { Pic(url: img).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5)) }
					Text(label).font(level == 0 ? Theme.sans(16, .medium) : Theme.sans(14.7, .medium)).foregroundStyle(level == 0 ? Theme.ink : Theme.soft)
					Spacer()
					Text("\(count)").font(Theme.mono(12.5)).foregroundStyle(Theme.faint)
				}
				.padding(.vertical, level == 0 ? 11 : 6).padding(.leading, 4 + CGFloat(level) * 18).padding(.trailing, 4)
			}
			.contentShape(Rectangle())
		}.buttonStyle(.plain)
	}
}

// MARK: programmatic navigation

private struct NavPushKey: EnvironmentKey { static let defaultValue: (Route) -> Void = { _ in } }
private struct NavRootKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
	/// back to the book chooser (the stack's root): the crumbs' "Home"
	var navRoot: () -> Void {
		get { self[NavRootKey.self] }
		set { self[NavRootKey.self] = newValue }
	}
	/// push a page from code (a search submit, a menu choice)
	var navPush: (Route) -> Void {
		get { self[NavPushKey.self] }
		set { self[NavPushKey.self] = newValue }
	}
}
