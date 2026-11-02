import SwiftUI

/// /<book>/bar: Your Bar (pdt_bar_page + cocktails/js/bar.js). Tabs Wishlist, Made (by day),
/// You can make, Ingredients (what you own, add more, and What to buy); one inventory per
/// location, shared by every book and with the website.
struct BarView: View {
	let book: Book
	@State var tab: String
	@ObservedObject private var member = Member.shared
	@ObservedObject private var account = Account.shared
	@State private var makeSort = "pop"
	@State private var query = ""
	@State private var showAllBlockers = false
	@State private var showAllBottles = false
	@State private var expandedTypes = Set<String>()
	@State private var handOpen = false
	@State private var handKind = "gin"
	@State private var handDesc = ""
	@State private var renaming = false
	@State private var newLoc = false
	@State private var locName = ""
	@State private var confirmDelete = false

	private var ix: BarIndex { BarIndex.of(book) }
	private var recById: [Int: BarIndex.Rec] { Dictionary(ix.recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

	var body: some View {
		PageScroll {
			Crumb(items: [(T("Home"), .home(book.key)), (T("Your Bar"), nil)]).padding(.top, 10)
			HStack(alignment: .center) {
				H1(T("Your Bar"))
				Spacer()
				if account.signedIn { locationMenu }
			}
			.padding(.top, 8)
			if !account.signedIn {
				SignInCard().padding(.top, 18)
			} else {
				tabs.padding(.top, 18)
				switch tab {
				case "wish": marksView("wish")
				case "made": marksView("made")
				case "make": makeView
				default: ingredientsView
				}
			}
		}
		// an empty bar opens on Ingredients (bar.js buildShell), once the bar has loaded
		.onAppear { if member.loaded && member.items.isEmpty && tab == "make" { tab = "ing" } }
		.onChange(of: member.loaded) { _, l in if l && member.items.isEmpty && tab == "make" { tab = "ing" } }
		.refreshable { await member.load() }
		.alert(T("Rename this location:"), isPresented: $renaming) {
			TextField("", text: $locName)
			Button(T("Rename")) { member.renameLocation(locName) }
			Button(T("Cancel"), role: .cancel) {}
		}
		.alert(T("Name this bar location (e.g. Home, Office):"), isPresented: $newLoc) {
			TextField("", text: $locName)
			Button(T("Add")) { member.newLocation(locName); tab = "ing" }
			Button(T("Cancel"), role: .cancel) {}
		}
		.alert(T("Delete this location and its ingredients?"), isPresented: $confirmDelete) {
			Button(T("Delete"), role: .destructive) { member.deleteLocation() }
			Button(T("Cancel"), role: .cancel) {}
		} message: { Text(member.bar.current.name) }
	}

	// MARK: header

	private var locationMenu: some View {
		Menu {
			ForEach(member.bar.locs) { l in
				Button { member.setLocation(l.id) } label: { if l.id == member.bar.cur { Label(l.name, systemImage: "checkmark") } else { Text(l.name) } }
			}
			Divider()
			Button(T("Rename") + "…") { locName = member.bar.current.name; renaming = true }
			Button("+ " + T("New location")) { locName = ""; newLoc = true }
			if member.bar.locs.count > 1 { Button(T("Delete") + "…", role: .destructive) { confirmDelete = true } }
		} label: {
			HStack(spacing: 6) {
				Text(member.bar.current.name).font(Theme.mono(13)).foregroundStyle(Theme.ink)
				Text("▾").font(.system(size: 9)).foregroundStyle(Theme.faint)
			}
			.padding(.horizontal, 12).padding(.vertical, 7)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
		}
		.disabled(!member.canEditBar)
	}

	private var ownMarks: (wish: [Int], made: [Int]) { (member.wish.filter { recById[$0] != nil }, member.made.filter { recById[$0] != nil }) }

	private var tabs: some View {
		let o = ix.owned(member.items)
		let rows: [(String, String, Int)] = [("wish", T("Wishlist"), ownMarks.wish.count), ("made", T("Made"), ownMarks.made.count),
			("make", T("You can make"), ix.makeable(o).count), ("ing", T("Ingredients"), member.items.count)]
		// one line that scrolls sideways when the tabs don't fit (a phone, or a longer language),
		// the chosen tab kept in view
		return VStack(spacing: 0) {
			ScrollViewReader { sv in ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 4) {
				ForEach(rows, id: \.0) { k, label, n in
					Button { tab = k } label: {
						HStack(spacing: 6) {
							Text(label).font(Theme.sans(15, tab == k ? .semibold : .medium)).foregroundStyle(tab == k ? Theme.ink : Theme.soft)
							Text("\(n)").font(Theme.mono(11.5)).foregroundStyle(tab == k ? Theme.acc : Theme.faint)
								.padding(.horizontal, 6).padding(.vertical, 1).background(Theme.panel, in: Capsule())
						}
						.padding(.horizontal, 14).padding(.vertical, 9)
						.overlay(alignment: .bottom) { if tab == k { Rectangle().fill(Theme.acc).frame(height: 2) } }
					}.buttonStyle(.plain).id(k)
				}
			} }
			.onAppear { sv.scrollTo(tab) }
			.onChange(of: tab) { _, t in withAnimation { sv.scrollTo(t) } } }
			Rectangle().fill(Theme.line).frame(height: 1)
		}
	}

	// MARK: Wishlist / Made

	@ViewBuilder private func marksView(_ kind: String) -> some View {
		let ids = kind == "wish" ? ownMarks.wish : ownMarks.made
		let all = kind == "wish" ? member.wish : member.made
		VStack(alignment: .leading, spacing: 0) {
			Text(kind == "wish" ? T("Wishlist") : T("Made")).font(Theme.mono(12)).kerning(0.6).foregroundStyle(Theme.faint)
				.textCase(.uppercase).padding(.top, 22).padding(.bottom, 14)
			if ids.isEmpty && otherBookCounts(all).isEmpty {
				empty(kind == "wish" ? T("No cocktails on your wishlist yet — tap the heart on any recipe.") : T("Nothing marked made yet — tap Made on a recipe, or finish one on the scale."))
			}
			if kind == "made" { madeDays(ids) } else { grid(ids.compactMap { recById[$0] }.sorted(by: BarIndex.byPop)) }
			ForEach(otherBookCounts(all), id: \.0.key) { ob, n in
				NavigationLink(value: Route.bar(ob.key, tab: kind)) {
					Text(T("{n} more at {other}", ["n": n, "other": ob.short])).font(Theme.sans(14.4)).foregroundStyle(Theme.acc).underline()
				}.buttonStyle(.plain).padding(.top, 16)
			}
		}
	}
	/// "{n} cocktails you can't make yet", the number as "+N" in the accent colour (bar.js blocks1/blocksN)
	private func blocksLine(_ n: Int) -> Text {
		let parts = T(n == 1 ? "{n} cocktail you can't make yet" : "{n} cocktails you can't make yet").components(separatedBy: "{n}")
		var t = Text(parts[0])
		for p in parts.dropFirst() { t = t + Text("+\(n)").foregroundColor(Theme.acc).fontWeight(.semibold) + Text(p) }
		return t
	}
	private func otherBookCounts(_ ids: [Int]) -> [(Book, Int)] {
		Book.all.filter { $0 != book }.compactMap { ob in
			let rs = Set(BarIndex.of(ob).recipes.map(\.id))
			let n = ids.filter { rs.contains($0) }.count
			return n > 0 ? (ob, n) : nil
		}
	}
	/// by the day each was last made: Today, Yesterday, then the date; undated last under Earlier
	@ViewBuilder private func madeDays(_ ids: [Int]) -> some View {
		let recs = ids.compactMap { recById[$0] }
		let ts: (BarIndex.Rec) -> Int = { member.madeOn[String($0.id)] ?? 0 }
		let dated = recs.filter { ts($0) > 0 }.sorted { ts($0) != ts($1) ? ts($0) > ts($1) : BarIndex.byPop($0, $1) }
		let undated = recs.filter { ts($0) == 0 }.sorted(by: BarIndex.byPop)
		if dated.isEmpty {
			grid(undated)
		} else {
			let groups = Self.dayGroups(dated, ts) + (undated.isEmpty ? [] : [(T("Earlier"), undated)])
			ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
				HStack(spacing: 8) {
					Text(g.0).font(Theme.sans(18, .semibold)).foregroundStyle(Theme.ink)
					Text("\(g.1.count)").font(Theme.mono(11.5)).foregroundStyle(Theme.soft)
						.padding(.horizontal, 7).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line2))
				}
				.padding(.top, i == 0 ? 0 : 26).padding(.bottom, 12)
				.frame(maxWidth: .infinity, alignment: .leading)
				.overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) } }
				grid(g.1)
			}
		}
	}
	private static func dayGroups(_ recs: [BarIndex.Rec], _ ts: (BarIndex.Rec) -> Int) -> [(String, [BarIndex.Rec])] {
		let cal = Calendar.current
		var out: [(String, [BarIndex.Rec])] = []
		var lastDay: Date? = nil
		for r in recs {
			let d = Date(timeIntervalSince1970: TimeInterval(ts(r)))
			let day = cal.startOfDay(for: d)
			if day == lastDay { out[out.count - 1].1.append(r); continue }
			lastDay = day
			let label: String
			if cal.isDateInToday(d) { label = T("Today") }
			else if cal.isDateInYesterday(d) { label = T("Yesterday") }
			else {
				// in the chosen language, as bar.js uses the page language (toLocaleDateString)
				var f = Date.FormatStyle(locale: Lang.locale).weekday(.wide).day().month(.wide)
				if !cal.isDate(d, equalTo: Date(), toGranularity: .year) { f = f.year() }
				label = d.formatted(f)
			}
			out.append((label, [r]))
		}
		return out
	}

	// MARK: You can make

	@ViewBuilder private var makeView: some View {
		let o = ix.owned(member.items)
		let list = ix.makeable(o).sorted(by: makeSort == "az" ? { $0.name.localizedCompare($1.name) == .orderedAscending } : BarIndex.byPop)
		VStack(alignment: .leading, spacing: 14) {
			HStack {
				Toggle(isOn: Binding(get: { member.hideUnmakeable }, set: { member.setHideUnmakeable($0) })) {
					Text(T("Hide if you cannot make")).font(Theme.sans(14)).foregroundStyle(Theme.soft)
				}
				.toggleStyle(CheckboxStyle())
				Spacer()
				if list.count > 1 {
					HStack(spacing: 6) {
						Button { makeSort = "pop" } label: { SortPill(label: T("most popular"), on: makeSort == "pop") }.buttonStyle(.plain)
						Button { makeSort = "az" } label: { SortPill(label: T("A–Z"), on: makeSort == "az") }.buttonStyle(.plain)
					}
				}
			}
			.padding(.top, 20)
			if member.items.isEmpty {
				empty(T("Add the ingredients you own on the Ingredients tab, then this shows the cocktails you can make."))
			} else if list.isEmpty {
				empty(T("No full matches yet — see What to buy for the ingredients that unlock the most cocktails."))
			} else {
				grid(list) { r in
					// made with a generic standing in for the bottle it lists: name the generic(s)
					var gens: [String] = []
					for q in r.req where !o.ex.contains(q.id) && !q.kind.isEmpty && o.gen.contains(q.kind) {
						let l = ix.kindByKey[q.kind]?.label ?? q.kind
						if !gens.contains(l) { gens.append(l) }
					}
					return gens.isEmpty ? nil : T("with your {items}", ["items": gens.joined(separator: ", ")])
				}
			}
		}
	}

	// MARK: Ingredients + What to buy

	@ViewBuilder private var ingredientsView: some View {
		VStack(alignment: .leading, spacing: 0) {
			if member.items.isEmpty {
				empty(T("Nothing here yet — add the bottles and ingredients you own below.")).padding(.top, 18)
			} else {
				ownedGroups.padding(.top, 8)
			}
			addSection.padding(.top, 26)
			buySection.padding(.top, 30)
		}
	}

	private func typeLabel(_ k: String) -> String { BarIndex.types.first { $0.k == k }.map { T($0.label) } ?? T("Other") }
	private var typeOrder: [String] { BarIndex.types.map(\.k) + ["_other"] }

	private var ownedGroups: some View {
		let groups = Dictionary(grouping: member.items) { it in ix.typeOf(it.t == "i" ? "i:\(it.id ?? 0)" : "b:\(it.b ?? "")") }
		return VStack(alignment: .leading, spacing: 18) {
			ForEach(typeOrder.filter { groups[$0] != nil }, id: \.self) { t in
				VStack(alignment: .leading, spacing: 10) {
					groupHead(typeLabel(t), groups[t]!.count)
					FlowLayout(spacing: 8) {
						ForEach(groups[t]!, id: \.key) { it in ownedChip(it) }
					}
				}
			}
		}
		.padding(.top, 14)
	}
	private func groupHead(_ label: String, _ n: Int) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 8) {
				Text(label.uppercased()).font(Theme.mono(11.5)).kerning(0.6).foregroundStyle(Theme.soft)
				Text("\(n)").font(Theme.mono(11)).foregroundStyle(Theme.faint)
					.padding(.horizontal, 6).padding(.vertical, 1).overlay(Capsule().stroke(Theme.line2))
			}
			Rectangle().fill(Theme.line).frame(height: 1)
		}
	}
	private func ownedChip(_ it: Bar.Item) -> some View {
		let key = it.t == "i" ? "i:\(it.id ?? 0)" : "b:\(it.b ?? "")"
		return HStack(spacing: 8) {
			Group {
				if let r = itemRoute(it) {
					NavigationLink(value: r) { chipBody(it, key) }.buttonStyle(.plain)
				} else {
					chipBody(it, key)
				}
			}
			Button { member.remove(it) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint) }
				.buttonStyle(.plain).accessibilityLabel(T("Remove"))
		}
		.padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 6)
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
	}
	private func chipBody(_ it: Bar.Item, _ key: String) -> some View {
		HStack(spacing: 8) {
			Pic(url: ix.keyImage(key)).frame(width: 28, height: 28)
			Text(ix.itemLabel(it)).font(Theme.sans(14)).foregroundStyle(Theme.ink)
			if it.t == "b" { kindTag(it.b ?? "") }
			if it.t == "c" { tag(ix.kindByKey[it.b ?? ""]?.label ?? (it.b ?? "")) }
		}
	}
	private func itemRoute(_ it: Bar.Item) -> Route? {
		if it.t == "i", let g = it.id.flatMap({ ix.ingById[$0] }) { return .ingredient(g.book, name: g.name, with: "") }
		if let b = it.b, Store.baseSpirits.contains(b) { return .spirit(book.key, key: b, and: "") }
		return nil
	}
	private func kindTag(_ k: String) -> some View { tag(ix.isProduce(k) ? T("whole") : T("any")) }
	private func tag(_ s: String) -> some View {
		Text(s.uppercased()).font(Theme.mono(9.5)).kerning(0.4).foregroundStyle(Theme.faint)
			.lineLimit(1).fixedSize()
			.padding(.horizontal, 5).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line2))
	}

	private var addSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(T("Add ingredients").uppercased()).font(Theme.mono(11.5)).kerning(0.6).foregroundStyle(Theme.soft)
			TextField(T("Search ingredients, or type a spirit…"), text: $query)
				.font(Theme.sans(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
				.padding(.horizontal, 12).padding(.vertical, 10)
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
			if !query.trimmingCharacters(in: .whitespaces).isEmpty {
				let res = ix.search(query)
				VStack(alignment: .leading, spacing: 0) {
					if res.isEmpty { Text(T("No ingredient matches.")).font(Theme.sans(14)).foregroundStyle(Theme.faint).padding(10) }
					ForEach(res, id: \.key) { it in resultRow(it) }
					Button { handDesc = query; query = ""; handOpen = true } label: {
						Text("+ " + T("Add by hand (choose what it stands in for)")).font(Theme.sans(14)).foregroundStyle(Theme.acc)
							.frame(maxWidth: .infinity, alignment: .leading).padding(10)
					}.buttonStyle(.plain)
				}
				.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
			}
			if handOpen { handEntry } else {
				Button { handDesc = ""; handOpen = true } label: { Text(T("Can't find it? Add by hand →")).font(Theme.sans(14)).foregroundStyle(Theme.soft) }.buttonStyle(.plain)
			}
		}
	}
	private func resultRow(_ it: Bar.Item) -> some View {
		let owned = member.has(it)
		return Button { if !owned { member.add(it); query = "" } } label: {
			HStack(spacing: 8) {
				Text(ix.itemLabel(it)).font(Theme.sans(14.5)).foregroundStyle(owned ? Theme.faint : Theme.ink)
				if it.t == "b", let k = ix.kindByKey[it.b ?? ""] {
					tag(k.produce ? T("whole — gives you") + " " + k.gives : T("any — generic"))
				} else if it.t == "i", let g = it.id.flatMap({ ix.ingById[$0] }), !g.kind.isEmpty {
					tag(ix.kindByKey[g.kind]?.label ?? g.kind)
				}
				Spacer()
				if owned { Text("✓ " + T("in your bar")).font(Theme.sans(12.5)).foregroundStyle(Theme.green) }
			}
			.padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
	}
	private var handEntry: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(T("Pick what it stands in for, then describe it:")).font(Theme.sans(13)).foregroundStyle(Theme.soft)
			HStack(spacing: 8) {
				Picker("", selection: $handKind) {
					ForEach(ix.kinds.filter { !$0.produce }, id: \.k) { Text($0.label).tag($0.k) }
				}.labelsHidden()
				TextField(T("Description, e.g. Bombay Sapphire gin"), text: $handDesc)
					.font(Theme.sans(15)).padding(.horizontal, 10).padding(.vertical, 8)
					.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
					.onSubmit(addHand)
				Button(T("Add"), action: addHand).buttonStyle(.bordered)
			}
			Button(T("Cancel")) { handOpen = false }.font(Theme.sans(13)).foregroundStyle(Theme.soft).buttonStyle(.plain)
		}
		.padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
	}
	private func addHand() {
		let d = handDesc.trimmingCharacters(in: .whitespaces)
		guard !d.isEmpty else { return }
		member.add(Bar.Item(t: "c", b: handKind, d: String(d.prefix(60))))
		handOpen = false; handDesc = ""
	}

	// MARK: What to buy

	@ViewBuilder private var buySection: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text(T("What to buy").uppercased()).font(Theme.mono(11.5)).kerning(0.6).foregroundStyle(Theme.soft)
			if member.items.isEmpty {
				empty(T("Add a few ingredients you own, then this ranks what to buy next."))
			} else {
				blockersBox
				bottlesBox
				sectionHead(T("What is still missing"), nil)
				missingGroups
			}
		}
	}
	private func sectionHead(_ t: String, _ toggle: Binding<Bool>?) -> some View {
		HStack {
			Text(t.uppercased()).font(Theme.mono(11.5)).kerning(0.6).foregroundStyle(Theme.soft)
			Spacer()
			if let toggle {
				Button { toggle.wrappedValue.toggle() } label: {
					Text((toggle.wrappedValue ? T("Show fewer") : T("Show all")).uppercased()).font(Theme.mono(10.5)).kerning(0.4).foregroundStyle(Theme.soft)
						.padding(.horizontal, 12).padding(.vertical, 6).overlay(Capsule().stroke(Theme.line2))
				}.buttonStyle(.plain)
			}
		}
		.padding(.top, 8)
	}
	@ViewBuilder private var blockersBox: some View {
		let all = ix.blockers(member.items)
		if !all.isEmpty {
			sectionHead(T("Your top recipe blockers"), all.count > 8 || showAllBlockers ? $showAllBlockers : nil)
			planList(Array((showAllBlockers ? all : Array(all.prefix(8))).map { b in
				(b.key, AnyView(blocksLine(b.count).foregroundStyle(Theme.soft)))
			}))
		}
	}
	@ViewBuilder private var bottlesBox: some View {
		let basics = ix.basics.filter { ix.ingById[$0] != nil }
		let plan: [BarIndex.PlanStep] = {
			var p = ix.bestPlan(member.items, showAllBottles ? 150 : 10, assume: basics, only: ix.isBottle)
			if showAllBottles { while let l = p.last, l.recipes.isEmpty { p.removeLast() } }
			return p
		}()
		let total = plan.reduce(0) { $0 + $1.recipes.count }
		if !plan.isEmpty && total > 0 {
			sectionHead(T("Best bottles for you to buy"), plan.count >= 10 || showAllBottles ? $showAllBottles : nil)
			VStack(alignment: .leading, spacing: 10) {
				(Text(T("Buy these {n} to make", ["n": plan.count]) + " ") + Text(T("{n} more cocktails", ["n": total])).fontWeight(.bold))
					.font(Theme.sans(15)).foregroundStyle(Theme.ink)
				let missingBasics = basics.filter { !member.has(.ing($0)) }
				if !missingBasics.isEmpty {
					VStack(alignment: .leading, spacing: 6) {
						Text(T("Counting kitchen basics (lemons, limes, sugar, eggs, soda, Angostura) as on hand.")).font(Theme.sans(13)).foregroundStyle(Theme.soft)
						Button(T("Add kitchen basics")) { member.add(missingBasics.map { .ing($0) }) }
							.font(Theme.sans(13, .semibold)).buttonStyle(.bordered)
					}
				}
				planList(plan.map { p in
					(p.key, AnyView(p.recipes.isEmpty ? AnyView(EmptyView()) : AnyView(recipeLinks(p.recipes, lead: "+\(p.recipes.count)"))))
				}, boxed: false)
			}
			.padding(14).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
		}
	}
	/// rows: picture, name (+ any/whole tag), a line under it, and an Add button
	private func planList(_ rows: [(String, AnyView)], boxed: Bool = true) -> some View {
		VStack(spacing: 0) {
			ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
				HStack(alignment: .center, spacing: 12) {
					Pic(url: ix.keyImage(row.0)).frame(width: 40, height: 40)
					VStack(alignment: .leading, spacing: 3) {
						HStack(spacing: 6) {
							Text(ix.keyLabel(row.0)).font(Theme.sans(15.5, .semibold)).foregroundStyle(Theme.ink)
							if row.0.hasPrefix("b") { kindTag(String(row.0.dropFirst(2))) }
						}
						row.1.font(Theme.sans(13))
					}
					Spacer(minLength: 8)
					addButton(ix.keyItem(row.0))
				}
				.padding(.vertical, 10)
				.overlay(alignment: .bottom) { if i < rows.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) } }
			}
		}
		.padding(.horizontal, boxed ? 14 : 0)
		.overlay { if boxed { RoundedRectangle(cornerRadius: 12).stroke(Theme.line) } }
	}
	private func addButton(_ it: Bar.Item) -> some View {
		Button { member.add(it) } label: {
			Text(T("Add")).font(Theme.sans(13.5, .semibold)).foregroundStyle(Theme.ink)
				.padding(.horizontal, 14).padding(.vertical, 7).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
		}.buttonStyle(.plain)
	}
	/// "+3 Daiquiri, Bronx, …": the first six, each a link
	private func recipeLinks(_ rs: [BarIndex.Rec], lead: String? = nil) -> some View {
		FlowLayout(spacing: 4) {
			if let lead { Text(lead).font(Theme.sans(13, .semibold)).foregroundStyle(Theme.acc) }
			ForEach(Array(rs.prefix(6).enumerated()), id: \.offset) { i, r in
				NavigationLink(value: Route.recipe(book.key, name: r.name)) {
					Text(r.name + (i < min(rs.count, 6) - 1 || rs.count > 6 ? "," : "")).font(Theme.sans(13)).foregroundStyle(Theme.soft).underline(color: Theme.line2)
				}.buttonStyle(.plain)
			}
			if rs.count > 6 { Text("…").font(Theme.sans(13)).foregroundStyle(Theme.soft) }
		}
	}
	@ViewBuilder private var missingGroups: some View {
		let list = ix.computeBuy(member.items).filter { !$0.now.isEmpty || !$0.next.isEmpty }
		if list.isEmpty {
			empty(T("Nothing high-impact to add right now."))
		} else {
			let groups = Dictionary(grouping: list) { ix.typeOf($0.key) }
			ForEach(typeOrder.filter { groups[$0] != nil }, id: \.self) { t in
				let cs = groups[t]!
				VStack(alignment: .leading, spacing: 4) {
					groupHead(typeLabel(t), cs.count).padding(.top, 10)
					ForEach(Array((expandedTypes.contains(t) ? cs : Array(cs.prefix(8))).enumerated()), id: \.offset) { _, c in buyRow(c) }
					if cs.count > 8 && !expandedTypes.contains(t) {
						Button(T("Show {n} more", ["n": cs.count - 8])) { expandedTypes.insert(t) }
							.font(Theme.sans(13.5)).foregroundStyle(Theme.acc).buttonStyle(.plain).padding(.top, 6)
					}
				}
			}
		}
	}
	private struct Partner { let label: String; let rs: [BarIndex.Rec] }
	/// which second item completes the near-misses, the one completing most first
	private func partners(_ c: BarIndex.Buy) -> [Partner] {
		let ps: [Partner] = c.pairs.map { Partner(label: ix.keyLabel($0.key), rs: $0.value) }
		return ps.sorted { a, b in a.rs.count != b.rs.count ? a.rs.count > b.rs.count : a.label.localizedCompare(b.label) == .orderedAscending }
	}
	/// "2 now · +1 with Cola · +1 with Lemongrass Syrup · +2 with other items"
	private func buyStats(_ c: BarIndex.Buy, _ partners: [Partner]) -> [String] {
		var stats: [String] = []
		if !c.now.isEmpty { stats.append(T("{n} now", ["n": c.now.count])) }
		var rest = 0
		for (i, p) in partners.enumerated() {
			if i < 2 { stats.append(T("+{n} with {item}", ["n": p.rs.count, "item": p.label])) } else { rest += p.rs.count }
		}
		if rest > 0 { stats.append(T("+{n} with other items", ["n": rest])) }
		return stats
	}
	private func buyRow(_ c: BarIndex.Buy) -> some View {
		let partners = partners(c)
		let stats = buyStats(c, partners)
		return HStack(alignment: .top, spacing: 12) {
			Pic(url: ix.keyImage(c.key)).frame(width: 40, height: 40)
			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 6) {
					Text(ix.keyLabel(c.key)).font(Theme.sans(15.5, .semibold)).foregroundStyle(Theme.ink)
					if c.key.hasPrefix("b") { kindTag(String(c.key.dropFirst(2))) }
				}
				if !stats.isEmpty { Text(stats.joined(separator: " · ")).font(Theme.mono(11.5)).foregroundStyle(Theme.soft) }
				if !c.now.isEmpty {
					HStack(alignment: .firstTextBaseline, spacing: 4) {
						Text(T("Unlocks:")).font(Theme.sans(13)).foregroundStyle(Theme.faint)
						recipeLinks(c.now)
					}
				} else {
					ForEach(Array(partners.prefix(2).enumerated()), id: \.offset) { (_, p: Partner) in
						HStack(alignment: .firstTextBaseline, spacing: 4) {
							Text(T("Plus {item}:", ["item": p.label])).font(Theme.sans(13)).foregroundStyle(Theme.faint)
							recipeLinks(p.rs)
						}
					}
				}
			}
			Spacer(minLength: 8)
			addButton(ix.keyItem(c.key))
		}
		.padding(.vertical, 10)
		.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
	}

	// MARK: shared

	private func empty(_ s: String) -> some View {
		Text(s).font(Theme.sans(14.5)).foregroundStyle(Theme.faint).padding(.vertical, 18).fixedSize(horizontal: false, vertical: true)
	}
	/// the site's cocktail cards, with the one-line description; `via` adds a line under it
	private func grid(_ rs: [BarIndex.Rec], via: ((BarIndex.Rec) -> String?)? = nil) -> some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 400), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
			ForEach(rs, id: \.id) { r in
				NavigationLink(value: Route.recipe(book.key, name: r.name)) {
					let d = book.store.db.one("SELECT description FROM drink_description WHERE drink_id=?1", r.id).string
					DrinkCard(card: book.store.card(DrinkRef(id: r.id, name: r.name)), description: d.isEmpty ? nil : T(d),
						extra: via?(r).map { v in AnyView(Text(v).font(Theme.sans(12.2, .medium)).foregroundStyle(Theme.green).padding(.top, 6)) })
				}.buttonStyle(.plain)
			}
		}
	}
}

/// signed out: what Your Bar is, and the sign-in button
struct SignInCard: View {
	@ObservedObject private var account = Account.shared
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(T("Sign in with your decentespresso.com account to keep Your Bar, your Wishlist and the cocktails you've made — the same as on the website."))
				.font(Theme.sans(15)).foregroundStyle(Theme.soft).fixedSize(horizontal: false, vertical: true)
			Button { account.signIn() } label: {
				Text(account.signingIn ? T("Signing in…") : T("Log in")).font(Theme.sans(16, .semibold)).foregroundStyle(.white)
					.padding(.horizontal, 22).padding(.vertical, 11).background(Theme.acc, in: RoundedRectangle(cornerRadius: 10))
			}.buttonStyle(.plain).disabled(account.signingIn)
			if let e = account.error { Text(e).font(Theme.sans(13.5)).foregroundStyle(Theme.acc) }
		}
		.padding(18).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
	}
}

/// a square checkbox, as the site's
struct CheckboxStyle: ToggleStyle {
	func makeBody(configuration: Configuration) -> some View {
		Button { configuration.isOn.toggle() } label: {
			HStack(spacing: 8) {
				Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square").foregroundStyle(configuration.isOn ? Theme.acc : Theme.faint)
				configuration.label
			}
		}.buttonStyle(.plain)
	}
}
