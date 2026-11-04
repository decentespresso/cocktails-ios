import SwiftUI
import UIKit

// MARK: pictures

/// A bundled picture (AVIF), decoded once and cached.
final class PicCache {
	static let shared = NSCache<NSURL, UIImage>()
	static func image(_ url: URL) -> UIImage? {
		if let i = shared.object(forKey: url as NSURL) { return i }
		// decoded here, once, rather than lazily on SwiftUI's image threads: many AVIFs decoding at
		// once there deadlocked ImageIO (Your Bar's Ingredients tab hung on a blank screen)
		guard let raw = UIImage(contentsOfFile: url.path) else { return nil }
		let i = raw.preparingForDisplay() ?? raw
		shared.setObject(i, forKey: url as NSURL)
		return i
	}
}

/// A picture fitted into its frame (object-fit:contain), on white like the site's .viz boxes.
struct Pic: View {
	let url: URL?
	var bg: Color? = Theme.picBG
	@Environment(\.colorScheme) private var scheme
	var body: some View {
		// in dark mode, the cut-out where there is one, with no white behind it (as the site)
		let dk = scheme == .dark ? Img.dark(url) : nil
		ZStack {
			if let bg, dk == nil { bg }
			if let url = dk ?? url, let img = PicCache.image(url) {
				Image(uiImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
			}
		}
	}
}

// MARK: page structure

/// .wrap: the page column with the site's side gutters
struct PageScroll<Content: View>: View {
	@ViewBuilder var content: Content
	var body: some View {
		GeometryReader { geo in
			ScrollView {
				VStack(alignment: .leading, spacing: 0) { content }
					// the layout follows the whole window's width (what the site's media queries see:
					// Safari counts a landscape iPhone's notch margins), sizes the space really there
					.environment(\.vw, geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing)
					.environment(\.cw, min(geo.size.width, 1180) - 2 * Theme.gutter(geo.size.width))
					.padding(.horizontal, Theme.gutter(geo.size.width))
					.frame(maxWidth: 1180, alignment: .leading)
					.frame(maxWidth: .infinity)
					.padding(.bottom, 40)
			}
			.background(Theme.paper)
		}
	}
}

/// the window's width, as the site's CSS media queries see the viewport: pages pick the site's
/// layout for it (Theme.phone < 700 = pdt_mobile.css, Theme.narrow <= 860 = one column)
private struct VWKey: EnvironmentKey { static let defaultValue: CGFloat = 402 }
/// the page column's width (the window inside the safe area, at most 1180, less the gutters)
private struct CWKey: EnvironmentKey { static let defaultValue: CGFloat = 370 }
extension EnvironmentValues {
	var cw: CGFloat {
		get { self[CWKey.self] }
		set { self[CWKey.self] = newValue }
	}
	var vw: CGFloat {
		get { self[VWKey.self] }
		set { self[VWKey.self] = newValue }
	}
}

/// a view built for the window's width (the site's media queries): VW { vw in ... }
struct VW<Content: View>: View {
	@Environment(\.vw) private var vw
	@ViewBuilder let content: (CGFloat) -> Content
	var body: some View { content(vw) }
}
/// a view built for the page column's width: CW { cw in ... }
struct CW<Content: View>: View {
	@Environment(\.cw) private var cw
	@ViewBuilder let content: (CGFloat) -> Content
	var body: some View { content(cw) }
}

/// .crumb: Home / Spirits / Gin (mono, faint); the last item is the current page
struct Crumb: View {
	let items: [(String, Route?)]
	@Environment(\.navRoot) private var toRoot
	/// "Home" (a book's home page) becomes Home (the book chooser) / PDT (the book's home), so
	/// every page has a way back to choosing a book
	private var shown: [(String, Route?, root: Bool)] {
		var out: [(String, Route?, root: Bool)] = []
		for (i, it) in items.enumerated() {
			if i == 0, case .home(let b)? = it.1 {
				out.append((it.0, nil, true))
				// on the book's own home page the book is the current page, not a link
				out.append((Book.get(b).short, items.count == 1 ? nil : it.1, false))
			} else {
				out.append((it.0, it.1, false))
			}
		}
		return out
	}
	var body: some View {
		FlowLayout(spacing: 9, lineSpacing: 4) {
			ForEach(Array(shown.enumerated()), id: \.offset) { i, it in
				HStack(spacing: 9) {
					if i > 0 { Text("/").foregroundStyle(Theme.faint) }
					if it.root {
						Button { toRoot() } label: { Text(it.0).foregroundStyle(Theme.faint) }.buttonStyle(.plain)
					} else if let r = it.1 {
						NavigationLink(value: r) { Text(it.0).foregroundStyle(Theme.faint) }.buttonStyle(.plain)
					} else {
						Text(it.0).foregroundStyle(Theme.faint)
					}
				}
			}
		}
		.font(Theme.mono(12))
		.padding(.bottom, 14)
	}
}

/// .phead: breadcrumb, big title, optional mono sub line
struct PageHead: View {
	var crumb: [(String, Route?)] = []
	let title: String
	var sub: String? = nil
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			if !crumb.isEmpty { Crumb(items: crumb) }
			H1(title)
			if let sub { Text(sub).font(Theme.mono(13)).foregroundStyle(Theme.soft).padding(.top, 10) }
		}
		.padding(.top, 10)
		.padding(.bottom, 22)
	}
}

/// .phead h1: clamp(2rem,5vw,3.2rem), tight leading
struct H1: View {
	let text: String
	init(_ t: String) { text = t }
	@Environment(\.vw) private var vw
	var body: some View {
		// .phead h1: clamp(2rem, 5vw, 3.2rem), letter-spacing -.025em
		let size = min(51.2, max(32, vw * 0.05))
		Text(text).font(Theme.sans(size, .semibold)).kerning(-size * 0.025).lineSpacing(-size * 0.1).foregroundStyle(Theme.ink)
			.fixedSize(horizontal: false, vertical: true)
	}
}

/// a pair page's h1: "Gin + Rum", the second half faint, at the page title's size
struct H1Pair: View {
	let a: String
	let b: String
	@Environment(\.vw) private var vw
	var body: some View {
		let size = min(51.2, max(32, vw * 0.05))
		(Text(a) + Text(" + \(b)").foregroundColor(Theme.faint))
			.font(Theme.sans(size, .semibold)).kerning(-size * 0.025).lineSpacing(-size * 0.1).foregroundStyle(Theme.ink)
			.fixedSize(horizontal: false, vertical: true)
	}
}

/// section.blk: a block with a top rule
struct Block<Content: View>: View {
	var rule = true
	var top: CGFloat = 38
	@ViewBuilder var content: Content
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			if rule { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, -40) }
			content.padding(.top, top)
		}
		.padding(.bottom, 4)
	}
}

/// .sh: section head: title, a hairline to the right, then a count and/or a pill link
struct SectionHead<Trailing: View>: View {
	let title: String
	var count: Int? = nil
	@ViewBuilder var trailing: Trailing
	var body: some View {
		// one line when the title fits beside the link; on a narrow screen the link goes under it
		ViewThatFits(in: .horizontal) {
			HStack(alignment: .firstTextBaseline, spacing: 14) {
				titleText.fixedSize()
				rule
				trailing
			}
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .firstTextBaseline, spacing: 14) {
					titleText.fixedSize(horizontal: false, vertical: true)
					rule
				}
				trailing
			}
		}
		.padding(.bottom, 22)
	}
	private var titleText: some View {
		Text(title).font(Theme.sans(22, .semibold)).kerning(-0.3).foregroundStyle(Theme.ink)
	}
	@ViewBuilder private var rule: some View {
		Rectangle().fill(Theme.line).frame(height: 1).frame(minWidth: 10).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 6 }
		if let count { Text("\(count)").font(Theme.mono(12)).foregroundStyle(Theme.faint) }
	}
}
extension SectionHead where Trailing == EmptyView {
	init(title: String, count: Int? = nil) { self.title = title; self.count = count; trailing = EmptyView() }
}

/// .sh a: the accent pill link at the end of a section head ("All →")
struct PillLink: View {
	let label: String
	let route: Route
	var body: some View {
		NavigationLink(value: route) {
			Text("\(label) →").font(Theme.mono(12)).foregroundStyle(Theme.acc).lineLimit(1)
				.padding(.horizontal, 10).padding(.vertical, 4)
				.overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2))
				.fixedSize()
		}.buttonStyle(.plain)
	}
}

/// .eye: small mono upper-case label
struct Eye: View {
	let text: String
	init(_ t: String) { text = t }
	var body: some View {
		Text(text.uppercased()).font(Theme.mono(11.5)).kerning(0.5).foregroundStyle(Theme.faint)
	}
}

// MARK: cards

/// .cards: the recipe card grid (2-up on phones, auto-fill 210px wider)
struct CardGrid: View {
	let book: Book
	let drinks: [DrinkRef]
	var ranked = false
	@ObservedObject private var member = Member.shared
	@ObservedObject private var account = Account.shared
	@Environment(\.vw) private var vw
	var body: some View {
		// signed in with a bar: each card you can't make says what's missing, and with "Hide if
		// you cannot make" on, only the makeable ones show (pdt_canmake_js)
		let cm: (names: Set<String>, missing: [String: [String]])? = account.signedIn && !member.items.isEmpty ? member.canMake(book) : nil
		let hide = account.signedIn && member.hideUnmakeable && cm != nil
		let shown = hide ? drinks.filter { cm!.names.contains($0.name) } : drinks
		if drinks.isEmpty {
			Text(T("No cocktails found.")).font(Theme.mono(13.5)).foregroundStyle(Theme.faint).padding(.vertical, 26)
		} else {
			VStack(alignment: .leading, spacing: 14) {
				if hide && shown.count < drinks.count { HideNote(book: book) }
				if shown.isEmpty {
					Text(T("None of these can be made with Your Bar.")).font(Theme.mono(13.5)).foregroundStyle(Theme.faint).padding(.vertical, 10)
				}
				// .cards: as many 210px+ columns as fit (gap 34 x 26); phones two (gap 14)
				LazyVGrid(columns: Theme.phone(vw) ? Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 2)
						: [GridItem(.adaptive(minimum: 210), spacing: 26, alignment: .top)],
						alignment: .leading, spacing: Theme.phone(vw) ? 14 : 34) {
					ForEach(Array(shown.enumerated()), id: \.element.id) { i, d in
						NavigationLink(value: Route.recipe(book.key, name: d.name)) {
							DrinkCard(card: book.store.card(d), rank: ranked ? i + 1 : nil, missing: cm?.missing[d.name])
						}.buttonStyle(.plain)
					}
				}
			}
		}
	}
}

/// .cmnote: "Showing only the cocktails you can make with Your Bar. Your Bar · Show all"
struct HideNote: View {
	let book: Book
	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Text(T("Showing only the cocktails you can make with Your Bar.")).foregroundStyle(Theme.soft)
			NavigationLink(value: Route.bar(book.key, tab: "make")) { Text(T("Your Bar")).foregroundStyle(Theme.acc).underline() }.buttonStyle(.plain)
			Text("·").foregroundStyle(Theme.faint)
			Button { Member.shared.setHideUnmakeable(false) } label: { Text(T("Show all")).foregroundStyle(Theme.acc).underline() }.buttonStyle(.plain)
		}
		.font(Theme.sans(14))
		.padding(.horizontal, 14).padding(.vertical, 9)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
	}
}

/// .card: picture on white, name (with a small #rank), the ingredient line
struct DrinkCard: View {
	let card: Store.Card
	var rank: Int? = nil
	var description: String? = nil
	/// more below the description (a similar cocktail's comparison)
	var extra: AnyView? = nil
	/// what the member's bar lacks for it ("Missing: …"), nil = say nothing
	var missing: [String]? = nil
	@ObservedObject private var member = Member.shared
	@Environment(\.vw) private var vw
	var body: some View {
		// .card (phones: pdt_mobile.css's smaller picture, name and padding)
		let phone = Theme.phone(vw)
		VStack(alignment: .leading, spacing: 0) {
			Pic(url: card.image).frame(height: phone ? 104 : 120).frame(maxWidth: .infinity).padding(.vertical, phone ? 4 : 6).picBG(card.image)
				.overlay(alignment: .topTrailing) { MarkBadge(wish: member.isWish(card.id), made: member.isMade(card.id)) }
				.padding(.bottom, 8)
			(rankText + Text(card.name).font(Theme.sans(phone ? 16.5 : 19.5, .semibold)).foregroundColor(Theme.ink))
				.kerning(-0.15).lineSpacing(-1).fixedSize(horizontal: false, vertical: true)
			Text(description ?? card.ingredients).font(Theme.sans(phone ? 12.2 : 12.8)).foregroundStyle(Theme.soft).lineSpacing(2)
				.padding(.top, 7).fixedSize(horizontal: false, vertical: true)
			if let m = missing, !m.isEmpty {
				let shown = m.prefix(3).map { T($0) }.joined(separator: ", ") + (m.count > 3 ? " " + T("+{n} more", ["n": m.count - 3]) : "")
				(Text(T("Missing:")).fontWeight(.semibold) + Text(" " + shown)).font(Theme.sans(12.2)).foregroundStyle(Theme.acc)
					.lineSpacing(2).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
			}
			if let extra { extra }
			Spacer(minLength: 0)
		}
		.padding(phone ? 10 : 14)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(Theme.paper)
		.overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
		.contentShape(Rectangle())
	}
	private var rankText: Text {
		guard let rank else { return Text("") }
		return Text("#\(rank) ").font(Theme.mono(Theme.phone(vw) ? 10.5 : 9.8, .medium)).foregroundColor(Theme.faint)
	}
}

/// .cmk: a heart (wishlist) and/or check (made) in the top right of a card's picture; when both,
/// the check sits small on the heart. Fixed colours: the picture is white in dark mode too.
struct MarkBadge: View {
	let wish: Bool
	let made: Bool
	var body: some View {
		if wish || made {
			ZStack {
				if wish { Image(systemName: "heart.fill").font(.system(size: 16)).foregroundStyle(Color(hex: 0xFF3B1D)) }
				if made { Image(systemName: "checkmark").font(.system(size: wish ? 9 : 15, weight: .heavy)).foregroundStyle(Color(hex: 0x0A0A0A)).offset(y: wish ? -1 : 0) }
			}
			.frame(width: 18, height: 18).opacity(0.3).padding(6)
			.accessibilityElement().accessibilityLabel([wish ? T("On your wishlist") : nil, made ? T("You've made this") : nil].compactMap { $0 }.joined(separator: " · "))
		}
	}
}

/// .inggrid / .ingcard: square picture on white, name under a hairline
struct IngGrid: View {
	let items: [(label: String, image: URL?, route: Route)]
	var body: some View {
		// .inggrid: as many 118px+ columns as fit
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 13, alignment: .top)], alignment: .leading, spacing: 13) {
			ForEach(Array(items.enumerated()), id: \.offset) { _, it in
				NavigationLink(value: it.route) {
					VStack(alignment: .leading, spacing: 0) {
						Pic(url: it.image).aspectRatio(1, contentMode: .fit)
						Rectangle().fill(Theme.line).frame(height: 1)
						Text(it.label).font(Theme.sans(12.8, .semibold)).foregroundStyle(Theme.ink).lineSpacing(0)
							.padding(.horizontal, 10).padding(.vertical, 8)
							.fixedSize(horizontal: false, vertical: true)
						Spacer(minLength: 0)
					}
					.frame(maxHeight: .infinity, alignment: .top)
					.background(Theme.panel)
					.overlay(Rectangle().stroke(Theme.line))
				}.buttonStyle(.plain)
			}
		}
	}
}

// MARK: chips and rows

/// .lchip: mono upper-case chip, optional picture, count, selected (×) or dashed reset
struct Chip: View {
	let label: String
	var image: URL? = nil
	var count: Int? = nil
	var selected = false
	var reset = false
	var body: some View {
		HStack(spacing: 0) {
			if let image { Pic(url: image).frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 3)).padding(.trailing, 7) }
			Text(label.uppercased()).kerning(0.35)
			if let count { Text("\(count)").foregroundStyle(Theme.faint).padding(.leading, 8) }
			if selected { Text("×").fontWeight(.bold).padding(.leading, 8) }
		}
		.font(Theme.mono(11.5))
		.foregroundStyle(reset ? Theme.faint : selected ? Theme.ink : Theme.soft)
		.padding(.horizontal, 11).padding(.vertical, 6)
		.background(selected ? Theme.line : Color.clear)
		.overlay(Rectangle().stroke(Theme.line2, style: StrokeStyle(lineWidth: 1, dash: reset ? [3, 2] : [])))
	}
}

/// .pairs a: "Pairs most with" chips
struct PairChip: View {
	let label: String
	var count: Int? = nil
	var selected = false
	var body: some View {
		HStack(spacing: 5) {
			Text(label)
			if let count { Text("\(count)").foregroundStyle(Theme.faint) }
			if selected { Text("×") }
		}
		.font(Theme.mono(12.2))
		.foregroundStyle(selected ? Theme.acc : Theme.soft)
		.padding(.horizontal, 11).padding(.vertical, 6)
		.overlay(Rectangle().stroke(selected ? Theme.acc : Theme.line2))
	}
}

/// .srow: one base spirit: bottle, name, count, arrow
struct SpiritRow: View {
	let book: Book
	let key: String
	let count: Int
	var body: some View {
		NavigationLink(value: Route.spirit(book.key, key: key, and: "")) {
			VStack(spacing: 0) {
				Rectangle().fill(Theme.line).frame(height: 1)
				HStack(spacing: 18) {
					HStack(spacing: 11) {
						if let u = book.store.spiritImg(key) {
							Pic(url: u).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 7))
						} else {
							Circle().fill(Color(hexString: Store.spiritHex(key))).frame(width: 9, height: 9)
						}
						Text(Store.spiritLabel(key)).font(Theme.sans(21.6, .semibold)).kerning(-0.2).foregroundStyle(Theme.ink)
					}
					Spacer()
					Text("\(count)").font(Theme.mono(13.4)).foregroundStyle(Theme.ink)
					Text("→").font(Theme.mono(14)).foregroundStyle(Theme.faint).frame(width: 18, alignment: .trailing)
				}
				.padding(.vertical, 15).padding(.horizontal, 6)
			}
			.contentShape(Rectangle())
		}.buttonStyle(.plain)
	}
}

/// .ll: a link row with a dotted leader to its count
struct LinkRow: View {
	let label: String
	var image: URL? = nil
	var imageSize: CGFloat = 22
	let count: Int
	let route: Route
	var indent: CGFloat = 0
	var sub = false
	var topRule = true
	var body: some View {
		NavigationLink(value: route) {
			VStack(spacing: 0) {
				if topRule && !sub { Rectangle().fill(Theme.line).frame(height: 1) }
				HStack(alignment: .center, spacing: 8) {
					if let image { Pic(url: image).frame(width: imageSize, height: imageSize).clipShape(RoundedRectangle(cornerRadius: imageSize > 30 ? 6 : 5)) }
					Text(label).font(sub ? Theme.sans(14.7, .medium) : Theme.sans(16, .medium)).foregroundStyle(sub ? Theme.soft : Theme.ink)
					Dotted().frame(height: 1).padding(.top, 8)
					Text("\(count)").font(Theme.mono(12.5)).foregroundStyle(Theme.faint)
				}
				.padding(.vertical, sub ? 4 : 11).padding(.leading, 4 + indent).padding(.trailing, 4)
			}
			.contentShape(Rectangle())
		}.buttonStyle(.plain)
	}
}

struct Dotted: View {
	var body: some View {
		GeometryReader { g in
			Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: g.size.width, y: 0)) }
				.stroke(Theme.line2, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
		}
	}
}

/// .sortpill
struct SortPill: View {
	let label: String
	let on: Bool
	var body: some View {
		Text(label.uppercased()).font(Theme.mono(11.8)).kerning(0.35)
			.foregroundStyle(on ? Theme.ink : Theme.soft)
			.padding(.horizontal, 12).padding(.vertical, 7)
			.background(on ? Theme.line : Color.clear)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
			.clipShape(RoundedRectangle(cornerRadius: 8))
	}
}

/// "12 more in Death & Co →" pills (pdt_other_books_links)
struct OtherBookPills: View {
	let others: [(book: Book, n: Int, route: Route)]
	var body: some View {
		ForEach(Array(others.enumerated()), id: \.offset) { _, o in
			PillLink(label: T("{n} more in {book}", ["n": o.n, "book": o.book.short]), route: o.route)
		}
	}
}

// MARK: layout

/// Wrapping row layout (flex-wrap), for chips
struct FlowLayout: Layout {
	var spacing: CGFloat = 8
	var lineSpacing: CGFloat = 8
	/// a subview at its own size, or wrapped to the line when it's wider (a long breadcrumb name
	/// would otherwise run past the edge, under whatever sits beside it)
	private func size(_ s: LayoutSubview, _ w: CGFloat) -> CGSize {
		let sz = s.sizeThatFits(.unspecified)
		return sz.width > w && w.isFinite ? s.sizeThatFits(ProposedViewSize(width: w, height: nil)) : sz
	}
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let w = proposal.width ?? .infinity
		var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
		for s in subviews {
			let sz = size(s, w)
			if x > 0 && x + sz.width > w { y += rowH + lineSpacing; x = 0; rowH = 0 }
			x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
		}
		return CGSize(width: proposal.width ?? maxX, height: y + rowH)
	}
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
		for s in subviews {
			let sz = size(s, bounds.width)
			if x > bounds.minX && x + sz.width > bounds.maxX { y += rowH + lineSpacing; x = bounds.minX; rowH = 0 }
			s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
			x += sz.width + spacing; rowH = max(rowH, sz.height)
		}
	}
}

/// the white behind pictures (.card .viz, .rviz...), which goes in dark mode when every picture in it
/// has its cut-out (the site's :has(img.dkimg){background:transparent})
struct PicBG: ViewModifier {
	let urls: [URL?]
	@Environment(\.colorScheme) private var scheme
	func body(content: Content) -> some View {
		let clear = scheme == .dark && !urls.isEmpty && urls.allSatisfy { Img.dark($0) != nil }
		content.background(clear ? Color.clear : Theme.picBG)
	}
}
extension View {
	func picBG(_ urls: URL?...) -> some View { modifier(PicBG(urls: urls)) }
	func picBG(_ urls: [URL?]) -> some View { modifier(PicBG(urls: urls)) }
}
