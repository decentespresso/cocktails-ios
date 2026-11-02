import SwiftUI

/// /<book>/recipes/<name>: the phone layout of the recipe page (pdt_mobile.css <= 699px):
/// title + description with the photo floated right, the ingredient strip, the numbered
/// steps with the serve row, the facts, and the similar cocktails.
struct RecipeView: View {
	let book: Book
	let name: String
	/// the batch size: every amount, the facts and the photo follow it (window.pdtBatch)
	/// (the debug launch argument -drinks 2 starts at that size, for screenshots)
	@State private var n: Double = UserDefaults.standard.double(forKey: "drinks") > 0 ? UserDefaults.standard.double(forKey: "drinks") : 1
	@State private var sizeOpen = false
	@State private var photoOpen = false
	@State private var makerOpen = UserDefaults.standard.bool(forKey: "maker")   // debug: -maker 1 opens it
	@ObservedObject private var member = Member.shared
	@ObservedObject private var account = Account.shared

	var body: some View {
		if let r = book.store.recipe(name) {
			content(r)
		} else {
			NotFoundView(book: book)
		}
	}

	@ViewBuilder private func content(_ r: Recipe) -> some View {
		PageScroll {
			VW { vw in
				if Theme.phone(vw) { phoneLayout(r) } else { CW { cw in wideLayout(r, vw, cw) } }
			}
			if !r.similar.isEmpty {
				Block(top: 30) {
					SectionHead(title: T("Similar cocktails"))
					ScrollView(.horizontal, showsIndicators: false) {
						LazyHStack(alignment: .top, spacing: 16) {
							ForEach(r.similar, id: \.self) { s in
								NavigationLink(value: Route.recipe(book.key, name: s.drink.name)) {
									SimilarCard(card: book.store.card(s.drink), s: s)
								}.buttonStyle(.plain).frame(width: 280)
							}
						}
					}
				}.padding(.top, 30)
			}
		}
		.sheet(isPresented: $sizeOpen) { SizePanel(stats: r.stats, n: $n).presentationDetents([.medium, .large]) }
		.fullScreenCover(isPresented: $photoOpen) { PhotoView(url: r.image, name: r.name, big: Img.cocktailBig(book.key, r.name)) }
		// a page of its own on the stack (not a full-screen cover: on the Mac a cover sits under the
		// window's toolbar and its Back never worked); Back, Done and the bar's ‹ all pop it
		.navigationDestination(isPresented: $makerOpen) { MakerView(recipe: r, n: n) }
	}

	/// phones (pdt_mobile.css <= 699px): the photo floated beside the title, then the steps, the
	/// scale button and the facts in one column
	@ViewBuilder private func phoneLayout(_ r: Recipe) -> some View {
		crumbRow(r).padding(.top, 10)
		// the photo floated right of the title and description, as tall as them (the page's script),
		// at most 40% of the width: the picture trimmed on all sides (tz/)
		CW { cw in
			IngHero(row: cw, pair: false, gap: 16, cap: 1000, minH: 150) {
				VStack(alignment: .leading, spacing: 0) {
					H1(r.name)
					if let d = r.description {
						Text(d).font(Theme.sans(15.2)).foregroundStyle(Theme.soft).lineSpacing(3).padding(.top, 12)
					}
				}
			} picture: { h in
				if r.image != nil {
					Button { photoOpen = true } label: {
						if n > 1 { photos(r) } else { Pic(url: Img.cocktailTrim(book.key, r.name) ?? r.image, bg: nil).frame(maxWidth: cw * 0.4, maxHeight: h) }
					}
					.buttonStyle(.plain).accessibilityLabel(T("See it larger"))
				}
			}
		}
		alsoIn(r)
		strip(r, height: 100, packed: false).padding(.top, 16).padding(.bottom, 6)
		batch.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 18)
		spec(r).padding(.top, 10)
		prebatch(r)
		Button { makerOpen = true } label: { scaleCTA }.buttonStyle(.plain).padding(.top, 14)
		facts(r).padding(.top, 22)
	}

	/// .recipe: two columns (1.55fr 1fr; 1.45fr 1fr on a portrait iPad, 700-860px): the steps on the
	/// left; the photo, the facts and the scale button on the right
	@ViewBuilder private func wideLayout(_ r: Recipe, _ vw: CGFloat, _ w: CGFloat) -> some View {
		let gap = min(54, max(28, vw * 0.05))
		let k: CGFloat = Theme.narrow(vw) ? 1.45 : 1.55
		let aside = (w - gap) / (k + 1)
		HStack(alignment: .top, spacing: gap) {
			VStack(alignment: .leading, spacing: 0) {
				crumbRow(r).padding(.top, 10)
				H1(r.name)
				if let d = r.description {
					Text(d).font(Theme.sans(15.2)).foregroundStyle(Theme.soft).lineSpacing(3).padding(.top, 12)
						.frame(maxWidth: 600, alignment: .leading)
				}
				alsoIn(r)
				strip(r, height: 140, packed: true).padding(.top, 10).padding(.bottom, 6)
				batch.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 12)
				spec(r).padding(.top, 12)
				prebatch(r)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			VStack(alignment: .leading, spacing: 18) {
				if r.image != nil {
					Button { photoOpen = true } label: { bigPhotos(r) }.buttonStyle(.plain)
						.accessibilityLabel(T("See it larger"))
				}
				facts(r)
				Button { makerOpen = true } label: { scaleCTA }.buttonStyle(.plain)
			}
			.frame(width: aside)
			.padding(.top, 14)
		}
	}

	private func crumbRow(_ r: Recipe) -> some View {
		let sp = book.store.drinkSpirits(r.id).first
		return HStack(alignment: .center, spacing: 10) {
			Crumb(items: [(T("Home"), .home(book.key)),
				sp.map { (Store.spiritLabel($0), Route.spirit(book.key, key: $0, and: "")) } ?? (T("All recipes"), .recipes(book.key, sort: "pop")),
				(r.name, nil)])
			Spacer(minLength: 0)
			if account.signedIn { marks(r) }
		}
	}
	@ViewBuilder private func alsoIn(_ r: Recipe) -> some View {
		ForEach(Array(r.alsoIn.enumerated()), id: \.offset) { _, o in
			NavigationLink(value: Route.recipe(o.book.key, name: o.name)) {
				Text(TM(o.same ? "Also in <em>{book}</em>, with the same recipe" : "Also in <em>{book}</em>, with a different recipe", ["book": o.book.title]) + AttributedString(" →"))
					.font(Theme.sans(14.4)).foregroundStyle(Theme.ink).underline(color: Theme.line2).multilineTextAlignment(.leading)
			}.buttonStyle(.plain).padding(.top, 10)
		}
	}
	/// .ingstrip: one picture per ingredient, trimmed to the bottle (ingredients/tc/), each at its
	/// own height on the site's scale (216px picture = 140px) and packed edge to edge, bottoms
	/// lined up; smaller only when they don't fit the width
	@ViewBuilder private func strip(_ r: Recipe, height: CGFloat, packed: Bool) -> some View {
		if !r.strip.isEmpty {
			StripLayout {
				ForEach(r.strip, id: \.self) { ing in
					NavigationLink(value: Route.ingredient(book.key, name: ing, with: "")) {
						Pic(url: Img.ingredientTrim(ing) ?? Img.ingredient(ing), bg: nil)
					}.buttonStyle(.plain)
					.layoutValue(key: StripSize.self, value: Img.ingredientTrim(ing).flatMap { PicCache.image($0)?.size } ?? CGSize(width: 216, height: 216))
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
	@ViewBuilder private func prebatch(_ r: Recipe) -> some View {
		if n > 1, let w = r.stats?.water, w > 0 {
			Text(T("Pre-batching {n} drinks? Add {w} g of water to stand in for the ice dilution, and chill it well.",
				["n": Recipe.num(n), "w": Int((w * n).rounded())]))
				.font(Theme.sans(13.8)).foregroundStyle(Theme.soft).lineSpacing(3)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 14).padding(.vertical, 10)
				.background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
				.overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
				.padding(.top, 14)
		}
	}
	/// .rviz in the right column: the photo at the column's width (white, padded 4 x 18); a round
	/// shows it once per drink, as the site's .rviz.multi grid does
	@ViewBuilder private func bigPhotos(_ r: Recipe) -> some View {
		let k = n > 1 ? min(8, Int((n - 1e-9).rounded(.up))) : 1
		Group {
			if k < 2 {
				Pic(url: r.image).aspectRatio(1, contentMode: .fit)
			} else {
				let cols = k <= 3 ? k : (k <= 4 ? 2 : (k <= 6 ? 3 : 4))
				LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
					ForEach(0..<k, id: \.self) { i in
						Pic(url: r.image).aspectRatio(1, contentMode: .fit)
							.opacity(i == k - 1 && n < 8 && n.truncatingRemainder(dividingBy: 1) > 1e-9 ? 0.35 : 1)
					}
				}
			}
		}
		.padding(.horizontal, 18).padding(.vertical, 4)
		.background(Theme.picBG)
	}

	/// the cocktail picture once per drink: 2.5 drinks = 2 glasses and a faded third; 8 at most, then "+N"
	@ViewBuilder private func photos(_ r: Recipe) -> some View {
		let k = n > 1 ? min(8, Int((n - 1e-9).rounded(.up))) : 1
		if k < 2 {
			Pic(url: r.image).frame(width: 130, height: 150)
		} else {
			let cols = k <= 3 ? k : (k <= 4 ? 2 : (k <= 6 ? 3 : 4))
			LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
				ForEach(0..<k, id: \.self) { i in
					Pic(url: r.image).aspectRatio(1, contentMode: .fit)
						.opacity(i == k - 1 && n < 8 && n.truncatingRemainder(dividingBy: 1) > 1e-9 ? 0.35 : 1)
				}
			}
			.frame(width: 150)
			.overlay(alignment: .bottomTrailing) {
				if n > 8 {
					Text("+\(Int((n - 8 - 1e-9).rounded(.up)))").font(Theme.mono(12.8, .semibold)).foregroundStyle(Theme.ink)
						.padding(.horizontal, 9).padding(.vertical, 3).background(Theme.line2, in: Capsule()).padding(8)
				}
			}
		}
	}

	/// .batch: − [1 DRINK] +, the middle opens the size panel
	private var batch: some View {
		HStack(spacing: 6) {
			Button { n = Recipe.step(n, -1) } label: { Text("−").font(Theme.mono(16)).frame(width: 34, height: 30) }
				.disabled(n <= 0.25).accessibilityLabel(T("Fewer drinks"))
			Button { sizeOpen = true } label: {
				HStack(alignment: .firstTextBaseline, spacing: 5) {
					Text(Recipe.num(n)).font(Theme.mono(14.4)).foregroundStyle(Theme.ink).frame(minWidth: 18)
					Text((n == 1 ? T("drink") : T("drinks")).uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
				}.padding(.horizontal, 12).frame(height: 30)
			}.accessibilityLabel(T("Adjust the size"))
			Button { n = Recipe.step(n, 1) } label: { Text("+").font(Theme.mono(16)).frame(width: 34, height: 30) }
				.disabled(n >= 99).accessibilityLabel(T("More drinks"))
		}
		.buttonStyle(BatchButton())
	}

	/// .spec: the numbered rows, the serve row at its place
	private func spec(_ r: Recipe) -> some View {
		let comments = account.signedIn && member.isMade(r.id)
		let miss = missing(r)
		return VW { vw in VStack(spacing: 0) {
			ForEach(Array(r.rows.enumerated()), id: \.offset) { i, row in
				if i == r.serveAt { serveRow(r, last: false) }
				ingRow(row, last: i == r.rows.count - 1 && !comments, missing: miss.contains(row.ingredient), wide: !Theme.small(vw))
			}
			if r.serveAt >= r.rows.count { serveRow(r, last: !comments) }
			if comments { CommentsRow(id: r.id) }
		}
		.overlay(Rectangle().stroke(Theme.line)) }
	}
	/// the ingredients the bar doesn't cover (the cards' "Missing:"), signed in with something in the bar
	private func missing(_ r: Recipe) -> Set<String> {
		guard account.signedIn, !member.items.isEmpty, let rec = BarIndex.of(book).recByName[r.name] else { return [] }
		let ix = BarIndex.of(book)
		return Set(ix.missingNames(rec, ix.owned(member.items)))
	}

	/// .rmarks: ♡ Wishlist and Made, toggles kept in the pdt_wish / pdt_made permacookies
	private func marks(_ r: Recipe) -> some View {
		HStack(spacing: 8) {
			let w = member.isWish(r.id), m = member.isMade(r.id)
			Button { member.toggleWish(r.id) } label: {
				HStack(spacing: 5) {
					Image(systemName: w ? "heart.fill" : "heart").font(.system(size: 10.5)).foregroundStyle(w ? Theme.acc : Theme.faint)
					Text(T("Wishlist").uppercased())
				}.markStyle(on: w)
			}.buttonStyle(.plain).accessibilityLabel(T("Save to your wishlist")).accessibilityAddTraits(w ? .isSelected : [])
			Button { member.toggleMade(r.id) } label: {
				HStack(spacing: 5) {
					if m { Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)) }
					Text(T("Made").uppercased())
				}.markStyle(on: m)
			}.buttonStyle(.plain).accessibilityLabel(T("Mark as made")).accessibilityAddTraits(m ? .isSelected : [])
		}
		.fixedSize()
	}

	/// .spec .r: wider than 520px the type and action sit in their own 96px column before the name
	/// (thumbnail 44px); on phones under the name (thumbnail 40px)
	private func ingRow(_ row: Recipe.Row, last: Bool, missing: Bool = false, wide: Bool = false) -> some View {
		HStack(alignment: .center, spacing: wide ? 16 : 10) {
			Text("\(row.n)").font(Theme.mono(11.5)).foregroundStyle(Theme.faint).frame(width: wide ? 10 : 20, alignment: .leading)
			NavigationLink(value: Route.ingredient(book.key, name: row.ingredient, with: "")) {
				Pic(url: Img.ingredient(row.ingredient)).frame(width: wide ? 44 : 40, height: wide ? 44 : 40)
			}.buttonStyle(.plain)
			if wide {
				VStack(alignment: .leading, spacing: 6) {
					if !row.cat.isEmpty {
						NavigationLink(value: Route.cat(book.key, row.cat)) {
							Text(Store.prettyCat(row.cat).uppercased()).font(Theme.mono(11.5, .semibold)).kerning(0.25).foregroundStyle(Theme.soft)
								.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
						}.buttonStyle(.plain)
					}
					Text(row.mixLabel.uppercased()).font(Theme.mono(10.6)).kerning(0.45).foregroundStyle(Theme.faint)
				}
				.frame(width: 96, alignment: .leading)
				VStack(alignment: .leading, spacing: 2) {
					NavigationLink(value: Route.ingredient(book.key, name: row.ingredient, with: "")) {
						Text(row.label).font(Theme.sans(16.6, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
							.fixedSize(horizontal: false, vertical: true)
					}.buttonStyle(.plain)
					if missing && !row.isGarnish { missingNote(row) }
				}
			} else { VStack(alignment: .leading, spacing: 2) {
				NavigationLink(value: Route.ingredient(book.key, name: row.ingredient, with: "")) {
					Text(row.label).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
						.fixedSize(horizontal: false, vertical: true)
				}.buttonStyle(.plain)
				// the method word moves to the next line when a long category ("SPICES, HERBS &
				// GARNISHES") leaves no room, rather than cutting the category off
				FlowLayout(spacing: 8, lineSpacing: 3) {
					if !row.cat.isEmpty {
						NavigationLink(value: Route.cat(book.key, row.cat)) {
							Text(Store.prettyCat(row.cat).uppercased()).font(Theme.mono(11.5, .semibold)).kerning(0.25).foregroundStyle(Theme.soft)
								.multilineTextAlignment(.leading)
						}.buttonStyle(.plain)
					}
					Text(row.mixLabel.uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
				}
				if missing && !row.isGarnish { missingNote(row) }
			} }
			Spacer(minLength: 4)
			RowAmount(row: row, n: n)
		}
		.padding(.vertical, 15).padding(.horizontal, 16)
		.overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1) } }
	}

	/// .rmiss: "You do not have this ingredient." and up to two substitutes, those in the bar first
	@ViewBuilder private func missingNote(_ row: Recipe.Row) -> some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(T("You do not have this ingredient.")).font(Theme.sans(12.8, .semibold)).foregroundStyle(Theme.acc)
			if let n = Substitutes.note(row.ingredientId, book: book, items: member.items) {
				ForEach(Array(n.subs.enumerated()), id: \.offset) { _, x in
					let (sub, have) = x
					let name = Text(T(sub.name)).font(Theme.sans(12.8, .semibold)).foregroundColor(Theme.ink)
					let line = Text(T("Instead:").uppercased()).font(Theme.mono(10.5)).foregroundColor(Theme.faint) + Text(" ") + name
						+ (have ? Text(" " + T("(in Your Bar)")).foregroundColor(Theme.green) : Text(""))
						+ Text(": " + T(sub.tip)).foregroundColor(Theme.soft)
					if let id = sub.id, let nm = book.store.ingredientName(id) {
						NavigationLink(value: Route.ingredient(book.key, name: nm, with: "")) { line.multilineTextAlignment(.leading) }.buttonStyle(.plain)
					} else {
						line
					}
				}
				if !n.none.isEmpty { Text(T(n.none)).foregroundStyle(Theme.soft) }
			}
		}
		.font(Theme.sans(12.8)).lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 5)
	}

	private func serveRow(_ r: Recipe, last: Bool) -> some View {
		var g = r.glass.replacingOccurrences(of: "\\s*glass$", with: "", options: [.regularExpression, .caseInsensitive])
		g = g.isEmpty ? T("Glass") : T(g.capitalized(firstOnly: true))
		return HStack(alignment: .center, spacing: 10) {
			Text("\(r.serveNumber)").font(Theme.mono(11.5)).foregroundStyle(Theme.faint).frame(width: 20, alignment: .leading)
			NavigationLink(value: Route.glass(book.key, name: r.glass)) {
				Pic(url: Img.glass(r.glass)).frame(width: 40, height: 40)
			}.buttonStyle(.plain)
			VStack(alignment: .leading, spacing: 6) {
				Text(g.uppercased()).font(Theme.mono(11.5, .semibold)).kerning(0.25).foregroundStyle(Theme.soft)
				Text(T("Glass").uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
			}
			.frame(width: 96, alignment: .leading)
			Text(r.method).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(.vertical, 15).padding(.horizontal, 16)
		.overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1) } }
	}

	/// .facts: pictures | label | values, for the batch size; then the book citation. Tapping it opens
	/// the size panel (it rescales these numbers)
	@ViewBuilder private func facts(_ r: Recipe) -> some View {
		let rows = r.facts(n)
		if !rows.isEmpty || r.cite != nil {
			// .facts: a grid of pictures | label | values, each column as wide as its widest cell
			Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
				ForEach(Array(rows.enumerated()), id: \.offset) { i, fr in
					GridRow(alignment: .center) {
						FactIcons(pics: fr.icons, more: fr.more).padding(.trailing, 8)
						Text(fr.label).font(Theme.sans(15.2)).foregroundStyle(Theme.soft).lineLimit(1).fixedSize()
							.padding(.leading, 5).padding(.trailing, 12)
						VStack(alignment: .trailing, spacing: 2) {
							ForEach(Array(fr.lines.enumerated()), id: \.offset) { j, v in
								Text(v).font(Theme.sans(15.2, j == 0 ? .semibold : .medium)).foregroundStyle(j == 0 ? Theme.ink : Theme.soft)
									.fixedSize(horizontal: false, vertical: true)
							}
						}
						.multilineTextAlignment(.trailing)
						.frame(maxWidth: .infinity, alignment: .trailing)
					}
					.padding(.vertical, 8)
					if i < rows.count - 1 || r.cite != nil {
						Rectangle().fill(Theme.line).frame(height: 1).gridCellUnsizedAxes(.horizontal)
					}
				}
				if let c = r.cite {
					GridRow(alignment: .top) {
						Image(systemName: "book").foregroundStyle(Color(hex: 0x7A5530)).padding(.top, 2)
						Text(c).font(Theme.sans(15.2)).foregroundStyle(Theme.soft).padding(.leading, 5)
							.fixedSize(horizontal: false, vertical: true)
							.gridCellColumns(2)
					}.padding(.vertical, 8)
				}
			}
			.padding(.horizontal, 16).padding(.vertical, 4)
			.overlay(Rectangle().stroke(Theme.line))
			.contentShape(Rectangle())
			.onTapGesture { if r.stats != nil { sizeOpen = true } }
		}
	}

	/// .scaleCta: the scale picture and "Make this cocktail with the Half Decent Scale →"
	/// (opens the scale maker)
	private var scaleCTA: some View {
		HStack(spacing: 10) {
			Pic(url: Img.local("img/scale-cta.avif"), bg: nil).frame(width: 50, height: 32)
			Text("\(T("Make this cocktail with the Half Decent Scale")) →").font(Theme.sans(13.8, .medium)).foregroundStyle(Theme.soft)
				.multilineTextAlignment(.leading)
		}
		// .scaleCta .btn: always the full width
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 16).padding(.vertical, 5)
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
	}
}

/// the amount at the batch size (pdtAmt): grams, else a counted amount, else "to taste"; the book's
/// amount under it (the recipe's steps and the scale maker's list)
struct RowAmount: View {
	let row: Recipe.Row
	let n: Double
	var body: some View {
		VStack(alignment: .trailing, spacing: 1) {
			if let g = row.grams {
				if g.hasPrefix("~") { gramsText("~" + Recipe.num((Double(row.mg) / 1000 * n).rounded())) }
				else { gramsText(String(format: "%.1f", Double(row.mg) / 1000 * n)) }
			} else if let c = row.count {
				Text(Recipe.scaleQ(c, n)).font(Theme.mono(17, .semibold)).foregroundStyle(Theme.acc)
			} else if row.toTaste {
				Text(T("to taste")).font(Theme.mono(15, .semibold)).foregroundStyle(Theme.faint)
			}
			if let oz = row.oz { Text(Recipe.scaleQ(oz, n)).font(Theme.mono(11.8)).foregroundStyle(Theme.faint) }
		}
	}
	/// "28.4g" with the decimals and the g at half size, the number in the accent colour
	private func gramsText(_ g: String) -> Text {
		let parts = g.split(separator: ".", maxSplits: 1).map(String.init)
		var t = Text(parts[0]).font(Theme.mono(17, .semibold)).foregroundColor(Theme.acc)
		if parts.count > 1 { t = t + Text(".\(parts[1])").font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.acc) }
		return t + Text("g").font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.ink)
	}
}

/// .rcomments: the member's note on a cocktail they've made (pdt_notes), saved when editing ends
struct CommentsRow: View {
	let id: Int
	@ObservedObject private var member = Member.shared
	@State private var text = ""
	@FocusState private var focused: Bool
	var body: some View {
		// top, not firstTextBaseline: an empty vertical TextField has no baseline, so the label
		// and the cursor came apart while typing the first comment (same font, so tops line up)
		HStack(alignment: .top, spacing: 7) {
			if !text.isEmpty || focused { Text("\(T("Comments")):").font(Theme.mono(13, .semibold)).foregroundStyle(Theme.soft) }
			TextField(T("Comments"), text: $text, axis: .vertical)
				.font(Theme.mono(13)).foregroundStyle(Theme.ink)
				.focused($focused)
				.submitLabel(.done)
				.onSubmit { focused = false }
				.onChange(of: text) { _, v in if v.contains("\n") { text = v.replacingOccurrences(of: "\n", with: " "); focused = false } }
		}
		.padding(.vertical, 14).padding(.horizontal, 16)
		.onAppear { text = member.note(id) }
		.onChange(of: focused) { _, f in if !f { member.setNote(id, text); text = member.note(id) } }
		.onChange(of: member.notes) { _, _ in if !focused { text = member.note(id) } }
	}
}

extension View {
	/// .rmark: small outlined mono label; the pressed one dims
	func markStyle(on: Bool) -> some View {
		self.font(Theme.mono(10.9)).kerning(0.33).foregroundStyle(on ? Theme.soft : Theme.faint)
			.padding(.horizontal, 10).padding(.vertical, 5)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.faint : Theme.line2))
	}
}

/// pdt_404: "Page not found"
struct NotFoundView: View {
	let book: Book
	var body: some View {
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Not found"), nil)], title: T("Page not found"),
				sub: T("There is no cocktail page at this address."))
		}
	}
}

/// a similar cocktail: its card, its description, then the taste note and how it differs
/// (inside the card, as .cndiff / the shared-ingredients lines)
struct SimilarCard: View {
	let card: Store.Card
	let s: Recipe.Similar
	var body: some View {
		DrinkCard(card: card, description: s.description, extra: AnyView(extra))
	}
	private var extra: some View {
		VStack(alignment: .leading, spacing: 8) {
			Rectangle().fill(Theme.line).frame(height: 1).padding(.bottom, 2)
			if let t = s.taste { Text(t).font(Theme.sans(13.6)).foregroundStyle(Theme.ink).lineSpacing(3) }
			if s.same != nil || s.different != nil {
				VStack(alignment: .leading, spacing: 4) {
					if let x = s.same { bullet(T("Same"), x) }
					if let x = s.different { bullet(T("Different"), x) }
				}.padding(.leading, 4)
			}
			if let x = s.shared { (Text("\(T("Shared ingredients")): ").foregroundColor(Theme.faint) + Text(x).foregroundColor(Theme.soft)).font(Theme.sans(12.2)) }
			if !s.differs.isEmpty { (Text("\(T("Differs")): ").foregroundColor(Theme.faint) + Text(s.differs.joined(separator: ", ")).foregroundColor(Theme.soft)).font(Theme.sans(12.2)) }
		}
		.lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
	}
	private func bullet(_ k: String, _ v: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 7) {
			Text("•").foregroundStyle(Theme.faint)
			(Text("\(k): ").foregroundColor(Theme.faint) + Text(v).foregroundColor(Theme.soft))
		}.font(Theme.sans(12.2))
	}
}

/// the .batch buttons: hairline box, mono, dim when disabled
struct BatchButton: ButtonStyle {
	@Environment(\.isEnabled) private var enabled
	func makeBody(configuration: Configuration) -> some View {
		configuration.label.foregroundStyle(Theme.soft)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(configuration.isPressed ? Theme.ink : Theme.line2))
			.opacity(enabled ? 1 : 0.3)
			.contentShape(Rectangle())
	}
}

/// the natural size of a strip picture (pixels, on the 216px scale)
struct StripSize: LayoutValueKey { static let defaultValue = CGSize(width: 216, height: 216) }
/// .ingstrip's flow: each at size x 140/216, side by side, bottoms aligned; all scaled down
/// together when the row is wider than the space
struct StripLayout: Layout {
	private func sizes(_ subviews: Subviews, _ width: CGFloat?) -> [CGSize] {
		let k: CGFloat = 140 / 216
		let natural = subviews.map { let s = $0[StripSize.self]; return CGSize(width: s.width * k, height: s.height * k) }
		let total = natural.reduce(0) { $0 + $1.width }
		let f = min(1, (width ?? total) / max(total, 1))
		return natural.map { CGSize(width: $0.width * f, height: $0.height * f) }
	}
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let s = sizes(subviews, proposal.width)
		return CGSize(width: s.reduce(0) { $0 + $1.width }, height: s.map(\.height).max() ?? 0)
	}
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let s = sizes(subviews, bounds.width)
		var x = bounds.minX
		for (v, sz) in zip(subviews, s) {
			v.place(at: CGPoint(x: x, y: bounds.maxY), anchor: .bottomLeading, proposal: ProposedViewSize(sz))
			x += sz.width
		}
	}
}
