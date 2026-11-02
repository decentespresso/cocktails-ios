import SwiftUI

/// /<book>/recipes/ with its sort pills: most popular, A–Z, by base spirit, sweet vs sour
struct RecipesView: View {
	let book: Book
	@State var sort: String
	@State private var open: Set<String> = []
	init(book: Book, sort: String) { self.book = book; _sort = State(initialValue: sort) }

	var body: some View {
		let s = book.store
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("All recipes"), nil)], title: T("All recipes"))
				.padding(.bottom, -14)
			FlowLayout(spacing: 8, lineSpacing: 8) {
				Text(nCocktails(book.nstated)).font(Theme.sans(14.4)).foregroundStyle(Theme.soft).padding(.trailing, 2).padding(.top, 6)
				ForEach([("pop", T("most popular")), ("az", T("A–Z")), ("spirit", T("by base spirit")), ("sweet", T("sweet vs sour"))], id: \.0) { k, l in
					Button { sort = k } label: { SortPill(label: l, on: sort == k) }.buttonStyle(.plain)
				}
			}
			.padding(.top, 8).padding(.bottom, 26)
			switch sort {
			case "az": CardGrid(book: book, drinks: s.allAZ())
			case "spirit":
				VStack(spacing: 0) {
					ForEach(s.groupsBySpirit(), id: \.label) { g in
						GroupSection(label: g.label, image: g.key.flatMap { s.spiritImg($0) }, count: g.drinks.count, open: open.contains(g.label), toggle: { toggle(g.label) }) {
							CardGrid(book: book, drinks: g.drinks, ranked: true)
						}
					}
				}
			case "sweet":
				VStack(spacing: 0) {
					ForEach(s.groupsBySweetness(), id: \.label) { g in
						GroupSection(label: g.label, image: nil, count: g.drinks.count, open: open.contains(g.label), toggle: { toggle(g.label) }) {
							CardGrid(book: book, drinks: g.drinks)
						}
					}
				}
			default: CardGrid(book: book, drinks: s.byPopularity(), ranked: true)
			}
		}
	}
	private func toggle(_ k: String) { if open.contains(k) { open.remove(k) } else { open.insert(k) } }
}

/// .sgroup: a collapsible group (collapsed by default), as the grouped recipe sorts
struct GroupSection<Content: View>: View {
	let label: String
	let image: URL?
	let count: Int
	let open: Bool
	let toggle: () -> Void
	@ViewBuilder var content: Content
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Button(action: toggle) {
				HStack(spacing: 12) {
					Image(systemName: "arrowtriangle.right.fill").font(.system(size: 8)).foregroundStyle(Theme.faint).rotationEffect(.degrees(open ? 90 : 0))
					if let image { Pic(url: image).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 7)) }
					Text(label).font(Theme.sans(20.8, .semibold)).kerning(-0.2).foregroundStyle(Theme.ink)
					Spacer()
					Text("\(count)").font(Theme.mono(13)).foregroundStyle(Theme.faint)
				}
				.padding(.vertical, 14).padding(.horizontal, 2).contentShape(Rectangle())
			}.buttonStyle(.plain)
			if open { content.padding(.top, 4).padding(.bottom, 24) }
			Rectangle().fill(Theme.line).frame(height: 1)
		}
	}
}

/// /<book>/spirits
struct SpiritsView: View {
	let book: Book
	var body: some View {
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Spirits"), nil)], title: T("Choose a base spirit"))
			VStack(spacing: 0) { ForEach(book.store.spiritCounts(), id: \.0) { SpiritRow(book: book, key: $0.0, count: $0.1) } }
			FlowLayout { NavigationLink(value: Route.glasses(book.key)) { Chip(label: "\(T("Browse by glass")) →") }.buttonStyle(.plain) }
				.padding(.top, 22)
		}
	}
}

/// the same page in the other books, with how many cocktails it has there
func otherBooks(_ book: Book, _ count: (Store) -> Int, _ route: (Book) -> Route) -> [(book: Book, n: Int, route: Route)] {
	Book.all.filter { $0 != book }.compactMap { ob in
		let n = count(ob.store)
		return n > 0 ? (ob, n, route(ob)) : nil
	}
}

/// /<book>/spirit/<a>, /spirit/<a>/<b> and /mix?a=&b= (cat:, kw:, ing: combos)
struct SpiritView: View {
	let book: Book
	let key: String
	let and: String
	@State private var sort = "pop"
	/// .sortbar: sort  [MOST POPULAR] [A–Z]
	private var sortPills: some View {
		HStack(spacing: 8) {
			Text(T("sort")).font(Theme.sans(14.4)).foregroundStyle(Theme.soft)
			Button { sort = "pop" } label: { SortPill(label: T("most popular"), on: sort == "pop") }.buttonStyle(.plain)
			Button { sort = "az" } label: { SortPill(label: T("A–Z"), on: sort == "az") }.buttonStyle(.plain)
		}.fixedSize()
	}

	var body: some View {
		let s = book.store
		let flat = s.drinksForCombo(key, and)
		let n = flat.count
		let label = Store.spiritLabel(key)
		let others = otherBooks(book, { $0.drinksForCombo(key, and).count }, { .spirit($0.key, key: key, and: and) })
		PageScroll {
			if and.isEmpty {
				Crumb(items: [(T("Home"), .home(book.key)), (T("Spirits"), .spirits(book.key)), (label, nil)]).padding(.top, 10)
				HStack(spacing: 18) {
					VStack(alignment: .leading, spacing: 10) {
						H1(label)
						Text(n == 1 ? T("1 cocktail features {spirit}", ["spirit": label]) : T("{n} cocktails feature {spirit}", ["n": n, "spirit": label]))
							.font(Theme.mono(13)).foregroundStyle(Theme.soft)
					}
					Spacer()
					if let u = s.spiritImg(key) { Pic(url: u, bg: nil).frame(width: 84, height: 84) }
				}
				// + other base spirits that pair with it
				FlowLayout {
					Text("+").font(Theme.mono(16)).foregroundStyle(Theme.faint)
					ForEach(s.spiritCounts().filter { $0.0 != key }, id: \.0) { k2, _ in
						let cc = s.drinksForSpirit(key, and: k2).count
						if cc > 0 {
							NavigationLink(value: Route.spirit(book.key, key: key, and: k2)) { Chip(label: Store.spiritLabel(k2), image: s.spiritImg(k2), count: cc) }.buttonStyle(.plain)
						}
					}
				}.padding(.top, 16)
				FlowLayout {
					Text("+").font(Theme.mono(16)).foregroundStyle(Theme.faint)
					ForEach(s.spiritCompanions(key), id: \.id) { ic in
						NavigationLink(value: Route.spirit(book.key, key: key, and: "ing:\(ic.name)")) { Chip(label: T(ic.name), image: Img.ingredient(ic.name), count: ic.count) }.buttonStyle(.plain)
					}
				}.padding(.top, 16).padding(.bottom, 24)
				let types = s.spiritTypes(key)
				if !types.isEmpty {
					Block(rule: false, top: 20) {
						// the page's sort sits in this header (it sorts the cocktails below), as on the site
						SectionHead(title: T("Types of {spirit}", ["spirit": label]), count: types.count) { sortPills }
						IngGrid(items: types.map { (T($0.name), Img.ingredient($0.name), Route.ingredient(book.key, name: $0.name, with: "")) })
					}
				}
				Block {
					SectionHead(title: T("{spirit} cocktails", ["spirit": label]), count: n) { OtherBookPills(others: others) }
					if s.spiritTypes(key).isEmpty { sortPills.padding(.bottom, 20) }
					if sort == "az" { CardGrid(book: book, drinks: flat) } else { CardGrid(book: book, drinks: s.sortedByPopularity(flat), ranked: true) }
				}
			} else {
				// spirit + anything: the ingredient-pair layout
				let alabel = Store.secondLabel(and)
				Crumb(items: [(T("Home"), .home(book.key)), (T("Spirits"), .spirits(book.key)), (label, .spirit(book.key, key: key, and: "")), (alabel, nil)]).padding(.top, 10)
				// .inghero: the title and pairings on the left, the picture on the right; on phones
				// (<= 520px) the picture first, full width
				VW { vw in
					if Theme.small(vw) {
						pairPictures(s, alabel, height: 180)
						H1Pair(a: label, b: alabel).padding(.top, 14)
						spiritPairs(s, alabel)
					} else {
						HStack(alignment: .center, spacing: min(40, max(20, vw * 0.04))) {
							VStack(alignment: .leading, spacing: 0) {
								H1Pair(a: label, b: alabel)
								spiritPairs(s, alabel)
							}.frame(maxWidth: .infinity, alignment: .leading)
							pairPictures(s, alabel, height: 168).frame(maxWidth: 300)
						}
					}
				}
				.padding(.bottom, 26)
				Block {
					SectionHead(title: T("Cocktails with {ingredient} and {other}", ["ingredient": label, "other": alabel]), count: n) { OtherBookPills(others: others) }
					CardGrid(book: book, drinks: s.sortedByPopularity(flat))
				}
			}
		}
	}

	/// "Pairs most with": the other base spirits (with this pair's second half selected)
	@ViewBuilder private func spiritPairs(_ s: Store, _ alabel: String) -> some View {
				Eye(T("Pairs most with")).padding(.top, 16).padding(.bottom, 7)
				FlowLayout(spacing: 7, lineSpacing: 7) {
					if !Store.baseSpirits.contains(and) {
						NavigationLink(value: Route.spirit(book.key, key: key, and: "")) { PairChip(label: alabel, selected: true) }.buttonStyle(.plain)
					}
					ForEach(s.spiritCounts().filter { $0.0 != key }, id: \.0) { k2, _ in
						if and == k2 {
							NavigationLink(value: Route.spirit(book.key, key: key, and: "")) { PairChip(label: Store.spiritLabel(k2), selected: true) }.buttonStyle(.plain)
						} else {
							let cc = s.drinksForSpirit(key, and: k2).count
							if cc > 0 { NavigationLink(value: Route.spirit(book.key, key: key, and: k2)) { PairChip(label: Store.spiritLabel(k2), count: cc) }.buttonStyle(.plain) }
						}
					}
				}
	}

	@ViewBuilder private func pairPictures(_ s: Store, _ alabel: String, height: CGFloat) -> some View {
		if Store.baseSpirits.contains(and), let pair = Img.spiritPair(key, and) {
			// the two spirits' bottles side by side; tap for the larger picture (the site's #bpair)
			ZoomPic(url: pair, name: "\(Store.spiritLabel(key)) + \(Store.spiritLabel(and))", big: Img.spiritPairBig(key, and)) {
				Pic(url: pair, bg: nil).frame(maxWidth: .infinity).frame(height: height)
			}
		} else {
			let aimg: URL? = and.hasPrefix("cat:") ? s.catImg(String(and.dropFirst(4)))
				: and.hasPrefix("ing:") ? Img.ingredient(String(and.dropFirst(4)))
				: and.hasPrefix("kw:") ? Img.ingredient(s.keywordIngredient(String(and.dropFirst(3))))
				: nil
			HStack(spacing: -56) {
				if let u = s.spiritImg(key) { Pic(url: u).frame(width: 168, height: 168).blendMode(.multiply) }
				if let aimg { Pic(url: aimg).frame(width: 168, height: 168).blendMode(.multiply) }
			}
			.background(Theme.picBG)
		}
	}
}

/// /<book>/glasses
struct GlassesView: View {
	let book: Book
	var body: some View {
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Glasses"), nil)], title: T("Browse by glass"))
			VStack(spacing: 0) {
				ForEach(book.store.glasses(), id: \.0) { g, c in
					LinkRow(label: T(g), image: Img.glass(g), imageSize: 51, count: c, route: .glass(book.key, name: g), topRule: false)
				}
			}
		}
	}
}

/// /<book>/glass/<name>
struct GlassView: View {
	let book: Book
	let name: String
	var body: some View {
		let flat = book.store.drinksInGlass(name)
		PageScroll {
			Crumb(items: [(T("Home"), .home(book.key)), (T("Glasses"), .glasses(book.key)), (T(name), nil)]).padding(.top, 10)
			// .ghead: the title lined up with the breadcrumb, the glass at the right
			HStack(spacing: 18) {
				VStack(alignment: .leading, spacing: 10) {
					H1(T("{glass} cocktails", ["glass": T(name)]))
					Text(nCocktails(flat.count)).font(Theme.mono(13)).foregroundStyle(Theme.soft)
				}
				Spacer(minLength: 0)
				if let u = Img.glass(name) { Pic(url: u, bg: nil).frame(width: 84, height: 84) }
			}
			.padding(.bottom, 28)
			CardGrid(book: book, drinks: flat)
		}
	}
}

/// /<book>/category/<cat>
struct CategoryView: View {
	let book: Book
	let cat: String
	var body: some View {
		let c = book.store.category(cat)
		let label = Store.prettyCat(cat)
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (label, nil)], title: label,
				sub: c.ings.count == 1 ? T("1 ingredient in this category") : T("{n} ingredients in this category", ["n": c.ings.count]))
			IngGrid(items: c.ings.map { (T($0), Img.ingredient($0), Route.ingredient(book.key, name: $0, with: "")) })
				.padding(.bottom, 30)
			Block {
				SectionHead(title: T("Cocktails using this"), count: c.drinks.count)
				CardGrid(book: book, drinks: c.drinks, ranked: true)
			}
		}
	}
}

/// /<book>/ingredients/
struct IngredientsView: View {
	let book: Book
	var body: some View {
		let s = book.store
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Ingredients"), nil)], title: T("All ingredients")).padding(.bottom, -22)
			FlowLayout {
				ForEach(s.categoryChips(), id: \.0) { nm, c in
					NavigationLink(value: Route.cat(book.key, nm)) { Chip(label: "\(Store.prettyCat(nm)) \(c)", image: s.catImg(nm)) }.buttonStyle(.plain)
				}
			}.padding(.top, 16).padding(.bottom, 30)
			Block {
				SectionHead(title: T("Every ingredient")) { PillLink(label: T("Most-used ingredients"), route: .usage(book.key)) }
				IngGrid(items: s.allIngredients().map { (T($0), Img.ingredient($0), Route.ingredient(book.key, name: $0, with: "")) })
			}
		}
	}
}

/// /<book>/ingredients/<a>[/<b>]
struct IngredientView: View {
	let book: Book
	let name: String
	let with: String
	var body: some View {
		let s = book.store
		let flat = s.drinksWith(name, with)
		let n = flat.count
		let ingt = T(name)
		let cats = Array(Set(s.ingCats(name).map { s.displayCat($0, name) })).sorted()
		let others = otherBooks(book, { $0.ingredientExists(name) && (with.isEmpty || $0.ingredientExists(with)) ? $0.drinksWith(name, with).count : 0 },
			{ .ingredient($0.key, name: name, with: with) })
		PageScroll {
			let crumb: [(String, Route?)] = with.isEmpty
				? [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (ingt, nil)]
				: [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (ingt, .ingredient(book.key, name: name, with: "")), (T(with), nil)]
			let crumbRow = HStack(alignment: .center) {
				Crumb(items: crumb)
				Spacer(minLength: 8)
				if with.isEmpty, let iid = s.ingredientId(name) { IHaveButton(book: book, id: iid) }
			}
			let title = Group {
				if with.isEmpty { H1(ingt) } else {
					H1Pair(a: ingt, b: T(with))
				}
			}
			VW { vw in
				if Theme.small(vw) {
					// phones (<= 520px): the crumb on top; one bottle floats right of the title and its
					// category, a pair stands full width above the title; the pairings below
					crumbRow.padding(.top, 10)
					if with.isEmpty {
						HStack(alignment: .top, spacing: 14) {
							VStack(alignment: .leading, spacing: 0) {
								title
								catChips(s, cats).padding(.top, 16)
							}
							.frame(maxWidth: .infinity, alignment: .leading)
							bottles(height: 150, single: true, width: 120)
						}.padding(.top, 14)
					} else {
						bottles(height: 168, single: false).frame(maxWidth: .infinity)
						title.padding(.top, 14)
						catChips(s, cats).padding(.top, 16)
					}
					pairsBlock(s)
				} else {
					// .inghero.ingtop: the text (crumb, title, category, pairings) on the left, the
					// picture on the right, as tall as the text (at most 40% of the row; a pair 55%)
					CW { cw in IngHero(row: cw, pair: !with.isEmpty) {
						VStack(alignment: .leading, spacing: 0) {
							crumbRow
							title.padding(.top, 14)
							catChips(s, cats).padding(.top, 16)
							pairsBlock(s)
						}
					} picture: { h in
						bottles(height: h, single: with.isEmpty)
					}
					.padding(.top, 10) }
				}
			}
			Block(top: 38) {
				let title = with.isEmpty
					? (n == 1 ? T("1 cocktail with {ingredient}", ["ingredient": ingt]) : T("{n} cocktails with {ingredient}", ["n": n, "ingredient": ingt]))
					: (n == 1 ? T("1 cocktail with {ingredient} and {other}", ["ingredient": ingt, "other": T(with)]) : T("{n} cocktails with {ingredient} and {other}", ["n": n, "ingredient": ingt, "other": T(with)]))
				SectionHead(title: title) { OtherBookPills(others: others) }
				CardGrid(book: book, drinks: flat)
			}.padding(.top, 24)
		}
	}
}

extension IngredientView {
	/// the bottle, or the pair's two side by side; each opens its larger picture
	@ViewBuilder fileprivate func bottles(height: CGFloat, single: Bool, width: CGFloat? = nil) -> some View {
		if single {
			if let u = Img.ingredient(name) {
				ZoomPic(url: u, name: T(name), big: Img.ingredientBig(name), link: Img.productPhoto(name)) {
					Pic(url: u, bg: nil).frame(width: width ?? height, height: height)
				}
			}
		} else {
			// .ipair.trim: the two bottles trimmed to themselves (ingredients/tc/), clamp(170px, 24vw,
			// 280px) tall, clamp(14px, 2.5vw, 28px) apart, on white
			VW { vw in
				let h = min(280, max(170, vw * 0.24))
				HStack(alignment: .bottom, spacing: min(28, max(14, vw * 0.025))) {
					ForEach([name, with], id: \.self) { nm in
						let u = Img.ingredientTrim(nm) ?? Img.ingredient(nm)
						let sz = u.flatMap { PicCache.image($0)?.size } ?? CGSize(width: 1, height: 1)
						ZoomPic(url: Img.ingredient(nm), name: T(nm), big: Img.ingredientBig(nm), link: Img.productPhoto(nm)) {
							Pic(url: u, bg: nil).frame(width: h * sz.width / max(sz.height, 1), height: h)
						}
					}
				}
				.padding(.horizontal, 4).padding(.vertical, 6)
				.background(Theme.picBG)
			}
		}
	}
	/// "Pairs most with": the other ingredients it's used with most, each a pair page
	@ViewBuilder fileprivate func pairsBlock(_ s: Store) -> some View {
		let pairs = s.pairsWith(name)
		if !pairs.isEmpty {
			Eye(T("Pairs most with")).padding(.top, 16).padding(.bottom, 7)
			FlowLayout(spacing: 7, lineSpacing: 7) {
				if !with.isEmpty && !pairs.contains(where: { $0.0 == with }) {
					NavigationLink(value: Route.ingredient(book.key, name: name, with: "")) { PairChip(label: T(with), selected: true) }.buttonStyle(.plain)
				}
				ForEach(pairs, id: \.0) { nm, c in
					if nm == with {
						NavigationLink(value: Route.ingredient(book.key, name: name, with: "")) { PairChip(label: T(nm), selected: true) }.buttonStyle(.plain)
					} else {
						NavigationLink(value: Route.ingredient(book.key, name: name, with: nm)) { PairChip(label: T(nm), count: c) }.buttonStyle(.plain)
					}
				}
			}
		}
	}
	fileprivate func catChips(_ s: Store, _ cats: [String]) -> some View {
		FlowLayout {
			ForEach(cats, id: \.self) { ct in
				NavigationLink(value: Route.cat(book.key, ct)) { Chip(label: Store.prettyCat(ct), image: s.catImg(ct)) }.buttonStyle(.plain)
			}
		}
	}
}

/// .inghero.ingtop above 520px: the text on the left; the picture on the right, as tall as the
/// text (the page's fit(): at most 40% of the row for one bottle, (55% + 56px) / 2 for a pair)
struct IngHero<Text_: View, Picture: View>: View {
	let row: CGFloat
	let pair: Bool
	var gap: CGFloat? = nil
	var cap: CGFloat? = nil
	var minH: CGFloat = 120
	@ViewBuilder let text: () -> Text_
	@ViewBuilder let picture: (CGFloat) -> Picture
	@State private var textH: CGFloat = 168
	var body: some View {
		let cap = cap ?? (pair ? (row * 0.55 + 56) / 2 : row * 0.4)
		HStack(alignment: .top, spacing: gap ?? min(40, max(20, row * 0.04))) {
			text()
				.frame(maxWidth: .infinity, alignment: .leading)
				.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textH = $0 }
			picture(max(minH, min(cap, textH)))
		}
	}
}

/// /<book>/search?q=
struct SearchView: View {
	let book: Book
	@State private var q: String
	@State private var submitted: String
	init(book: Book, initial: String) { self.book = book; _q = State(initialValue: initial); _submitted = State(initialValue: initial) }
	var body: some View {
		let s = book.store
		let res = submitted.isEmpty ? ([], []) : s.search(submitted)
		PageScroll {
			Crumb(items: [(T("Home"), .home(book.key)), (T("Search"), nil)]).padding(.top, 10)
			H1(submitted.isEmpty ? T("Search") : "\(T("Search")) “\(submitted)”")
			SearchBox(q: $q, autofocus: submitted.isEmpty) { submitted = q.trimmingCharacters(in: .whitespaces) }.padding(.top, 18)
			if !submitted.isEmpty {
				let n = res.0.count, ni = res.1.count
				Text((n == 1 ? T("1 cocktail matches") : T("{n} cocktails match", ["n": n])) + (ni > 0 ? " · " + (ni == 1 ? T("1 ingredient") : T("{n} ingredients", ["n": ni])) : ""))
					.font(Theme.mono(13)).foregroundStyle(Theme.soft).padding(.top, 14)
				let gens = s.searchGenerics(submitted)
				if !gens.isEmpty {
					SectionHead(title: T("Spirits & types")).padding(.top, 28)
					IngGrid(items: gens.map { ($0.label, $0.image, $0.route) })
				}
				if ni > 0 {
					SectionHead(title: ni == 1 ? T("1 ingredient") : T("{n} ingredients", ["n": ni])).padding(.top, 28)
					IngGrid(items: res.1.map { (T($0), Img.ingredient($0), Route.ingredient(book.key, name: $0, with: "")) })
				}
				if n > 0 {
					if ni > 0 { SectionHead(title: nCocktails(n)).padding(.top, 28) } else { Spacer().frame(height: 28) }
					CardGrid(book: book, drinks: res.0)
				} else if ni == 0 {
					Text(T("Nothing matched. Try a spirit or ingredient name.")).font(Theme.mono(13.5)).foregroundStyle(Theme.faint).padding(.vertical, 26)
				}
			}
		}
	}
}

/// /<book>/usage: every ingredient ranked by how many cocktails use it
struct UsageView: View {
	let book: Book
	@Environment(\.navPush) private var push
	var body: some View {
		// the site's usage report: every ingredient, its cocktails, its categories, and the cocktails
		let rows: [UsageData] = book.store.memo("usage") {
			book.store.db.rows("""
				SELECT T1.name, COUNT(DISTINCT T3.drink_id) AS num, GROUP_CONCAT(DISTINCT T2.name), GROUP_CONCAT(DISTINCT T3.name)
				FROM ingredient AS T1 LEFT JOIN ingtag AS T2 ON T1.ingredient_id=T2.ingredient_id
				LEFT JOIN step AS T4 ON T1.ingredient_id=T4.ingredient_id AND T4.sortorder IS NOT NULL
				LEFT JOIN drink AS T3 ON T4.drink_id=T3.drink_id
				GROUP BY T1.ingredient_id, T1.name ORDER BY num DESC, T1.name ASC
				""").map { r in
				UsageData(name: r.s(0), count: r.i(1),
					tags: r.s(2).isEmpty ? "-" : r.s(2).split(separator: ",").map { Store.prettyCat(String($0)) }.joined(separator: ", "),
					cocktails: r.s(3).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
			}
		}
		let head = PageHead(crumb: [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (T("Most-used ingredients"), nil)],
			title: T("Most-used ingredients"), sub: T("Every ingredient ranked by how many cocktails use it"))
		GeometryReader { geo in
			let vw = geo.size.width
			let w = min(vw, 1180) - 2 * Theme.gutter(vw)
			// .utable: the full width; where it can't fit (a phone), one stacked row per ingredient
			// instead, so nothing runs off the screen (the site scrolls its table sideways there,
			// which cut off the title, the subtitle and the Used in column)
			let stacked = w < 760
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					head
					if stacked {
						Rectangle().fill(Theme.ink).frame(height: 2).padding(.top, 8)
						ForEach(rows) { UsageStackedRow(data: $0, book: book) }
					} else {
						UsageRow(data: nil, width: w, book: book).padding(.top, 24)
						ForEach(rows) { UsageRow(data: $0, width: w, book: book) }
					}
				}
				.frame(width: w, alignment: .leading)
				.padding(.horizontal, Theme.gutter(vw))
				.padding(.bottom, 40)
				.frame(maxWidth: .infinity)
			}
			.environment(\.vw, vw)
			.background(Theme.paper)
		}
		// the cocktail names in the table are links: open them in the app
		.environment(\.openURL, OpenURLAction { url in
			if let r = Route.fromPath(url.path).last { push(r); return .handled }
			return .discarded
		})
	}
}

struct UsageData: Identifiable {
	let name: String
	let count: Int
	let tags: String
	let cocktails: [String]
	var id: String { name }
}

/// one row of the usage table (th when data is nil): ingredient | cocktails | category | used in
struct UsageRow: View {
	let data: UsageData?
	let width: CGFloat
	let book: Book
	var body: some View {
		let c0 = max(130, width * 0.2), c1: CGFloat = 92, c2 = max(96, width * 0.14)
		HStack(alignment: .top, spacing: 0) {
			if let d = data {
				NavigationLink(value: Route.ingredient(book.key, name: d.name, with: "")) {
					Text(T(d.name)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
				}.buttonStyle(.plain).cell().frame(width: c0, alignment: .leading)
				Text("\(d.count)").font(Theme.mono(14.7)).foregroundStyle(Theme.ink).cell().frame(width: c1)
				Text(d.tags).foregroundStyle(Theme.ink).cell().frame(width: c2, alignment: .leading)
				Text(links(d)).foregroundStyle(Theme.ink).tint(Theme.ink).cell().frame(maxWidth: .infinity, alignment: .leading)
			} else {
				ForEach(Array([T("Ingredient"), T("Cocktails"), T("Category"), T("Used in")].enumerated()), id: \.offset) { i, h in
					Text(h.uppercased()).font(Theme.mono(10.6)).kerning(0.6).foregroundStyle(Theme.faint).lineLimit(1)
						.padding(.horizontal, 12).padding(.vertical, 10)
						.frame(width: [c0, c1, c2][safe: i], alignment: i == 1 ? .center : .leading)
						.frame(maxWidth: i == 3 ? .infinity : nil, alignment: .leading)
				}
			}
		}
		.overlay(alignment: .bottom) { Rectangle().fill(data == nil ? Theme.ink : Theme.line).frame(height: data == nil ? 2 : 1) }
	}
	private func links(_ d: UsageData) -> AttributedString { UsageData.links(d, book: book) }
}

/// one ingredient of the usage table on a phone: the name and its count, the category, then the
/// cocktails it's used in
struct UsageStackedRow: View {
	let data: UsageData
	let book: Book
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline, spacing: 12) {
				NavigationLink(value: Route.ingredient(book.key, name: data.name, with: "")) {
					Text(T(data.name)).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
				}.buttonStyle(.plain)
				Spacer(minLength: 0)
				Text(nCocktails(data.count)).font(Theme.mono(12)).foregroundStyle(Theme.soft).lineLimit(1).fixedSize()
			}
			if data.tags != "-" {
				Text(data.tags.uppercased()).font(Theme.mono(10.6)).kerning(0.6).foregroundStyle(Theme.faint)
			}
			if !data.cocktails.isEmpty {
				Text(UsageData.links(data, book: book)).font(Theme.sans(14.7)).lineSpacing(3).foregroundStyle(Theme.ink).tint(Theme.ink)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.padding(.vertical, 14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
	}
}

extension UsageData {
	/// "Aviation, Bee's Knees, …", each a link to its recipe
	static func links(_ d: UsageData, book: Book) -> AttributedString {
		var out = AttributedString()
		for (k, c) in d.cocktails.enumerated() {
			if k > 0 { out += AttributedString(", ") }
			var a = AttributedString(c)
			var comps = URLComponents()
			comps.scheme = "decentcocktails"; comps.host = ""; comps.path = "/cocktails/\(book.key)/recipes/\(c)"
			a.link = comps.url
			out += a
		}
		return out
	}
}
extension View {
	/// a .utable td
	fileprivate func cell() -> some View {
		self.font(Theme.sans(14.7)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
			.padding(.horizontal, 12).padding(.vertical, 11)
	}
}
extension Array {
	subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// .ihave: "I have this ingredient" (signed in, when the current bar location lacks it): adds it
/// to Your Bar, then says so with a link there
struct IHaveButton: View {
	let book: Book
	let id: Int
	@ObservedObject private var member = Member.shared
	@ObservedObject private var account = Account.shared
	@State private var added = false
	var body: some View {
		if account.signedIn && member.canEditBar {
			if added {
				NavigationLink(value: Route.bar(book.key, tab: "ing")) { (Text(Image(systemName: "checkmark")) + Text(" " + T("Added to Your Bar"))).ihaveStyle(Theme.soft) }.buttonStyle(.plain)
			} else if !member.has(.ing(id)) {
				Button { member.add(.ing(id)); added = true } label: { Text(T("I have this ingredient")).ihaveStyle(Theme.ink) }.buttonStyle(.plain)
			}
		}
	}
}
extension View {
	func ihaveStyle(_ c: Color) -> some View {
		self.font(Theme.mono(10.9)).kerning(0.33).textCase(.uppercase).foregroundStyle(c).lineLimit(1)
			.padding(.horizontal, 11).padding(.vertical, 6).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
	}
}
