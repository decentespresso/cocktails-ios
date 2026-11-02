import SwiftUI

@main
struct CocktailsApp: App {
	init() {
		Lang.start()
		#if DEBUG
		// -dumpbar <book>: print what Your Bar computes for the signed-in member (compare with the
		// website's window.pdtBar.view() on /<book>/bar), then quit
		if let b = UserDefaults.standard.string(forKey: "dumpbar") {
			Task { @MainActor in
				await Member.shared.load()
				BarDump.print(Book.get(b))
				exit(0)
			}
		}
		// -checkfacts 1: compare the scale maker's facts with the recipe pages' for every recipe, then quit
		if UserDefaults.standard.bool(forKey: "checkfacts") {
			Task { @MainActor in FactsCheck.run(); exit(0) }
		}
		#endif
	}
	var body: some Scene {
		WindowGroup {
			RootView()
		}
	}
}

/// /cocktails/: the book chooser, with every page of the site pushed on one stack.
struct RootView: View {
	@State private var path = NavigationPath()
	@ObservedObject private var lang = LangState.shared
	@Environment(\.scenePhase) private var phase
	var body: some View {
		NavigationStack(path: $path) {
			BooksView()
				.navigationDestination(for: Route.self) { r in
					r.view.bookChrome(Book.get(r.bookKey))
				}
		}
		// a new language rebuilds every screen (T() reads the table as each view is built); the
		// pages open stay open
		.id(lang.code)
		.environment(\.locale, Lang.locale)
		.tint(Theme.acc)
		.environment(\.navPush) { path.append($0) }
		.environment(\.navRoot) { path = NavigationPath() }
		.onAppear {
			// debug / screenshots: launch straight onto a page, e.g. -open /cocktails/pdt/recipes/Negroni
			if let p = UserDefaults.standard.string(forKey: "open") { for r in Route.fromPath(p) { path.append(r) } }
		}
		// the member's lists and bar, fresh each time the app comes forward (the website may have changed them)
		.task { await Member.shared.load() }
		.onChange(of: phase) { _, p in if p == .active { Task { await Member.shared.load() } } }
		.onOpenURL { url in
			let r = Route.fromPath(url.path + (url.query.map { "?\($0)" } ?? ""))
			if !r.isEmpty { path = NavigationPath(); for x in r { path.append(x) } }
		}
	}
}

/// The site header for a book's pages: brand in the bar, and the nav links + search
/// (header.site / nav.main) as a strip under it.
struct BookChrome: ViewModifier {
	let book: Book
	@ObservedObject private var account = Account.shared
	@Environment(\.navRoot) private var toRoot
	func body(content: Content) -> some View {
		content
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				// the brand goes back to choosing a book, as the site's does (brandhref /cocktails/);
				// at the left of its space, signed in or out (centred, it moved when the account button
				// was missing), and just the book's name when the full one doesn't fit
				ToolbarItem(placement: .principal) {
					Button { toRoot() } label: {
						ViewThatFits(in: .horizontal) {
							Text("\(book.short) Cocktails")
							Text(book.short)
						}
						.font(Theme.sans(17, .bold)).kerning(-0.3).foregroundStyle(Theme.ink).lineLimit(1)
					}.buttonStyle(.plain)
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				ToolbarItemGroup(placement: .topBarTrailing) {
					NavigationLink(value: Route.search(book.key, q: "")) {
						Image(systemName: "magnifyingglass").foregroundStyle(Theme.soft)
					}
					LanguageMenu()
					accountButton
				}
			}
			.safeAreaInset(edge: .top, spacing: 0) { SiteNav(book: book) }
	}
	/// Log in, or the account menu (Your Bar, sign out)
	@ViewBuilder private var accountButton: some View {
		if account.signedIn {
			Menu {
				NavigationLink(value: Route.bar(book.key, tab: "make")) { Label(T("Your Bar"), systemImage: "wineglass") }
				NavigationLink(value: Route.bar(book.key, tab: "wish")) { Label(T("Wishlist"), systemImage: "heart") }
				NavigationLink(value: Route.bar(book.key, tab: "made")) { Label(T("Made"), systemImage: "checkmark") }
				Divider()
				Button(T("Sign out"), role: .destructive) { account.signOut() }
			} label: { Image(systemName: "person.crop.circle").foregroundStyle(Theme.soft) }
		}
	}
}

/// nav.main, the site's menu as a strip under the bar: on a book's pages Cocktails, Spirits,
/// Ingredients, Help and Your Bar (or Log in); on the book chooser (book nil) Help and Your Bar /
/// Log in (lib/direct.tcl navhtml; the site's "Decent Espresso" link is left out of the app)
struct SiteNav: View {
	let book: Book?
	@ObservedObject private var account = Account.shared
	@ObservedObject private var lang = LangState.shared
	@State private var helpOpen = false
	var body: some View {
		VStack(spacing: 0) {
			// wraps to a second line when a narrow window can't fit it all (never hides Log in off the edge)
			FlowLayout(spacing: 18, lineSpacing: 6) {
				Group {
					if let book {
						navLink(T("Cocktails"), .recipes(book.key, sort: "pop"))
						navLink(T("Spirits"), .spirits(book.key))
						navLink(T("Ingredients"), .ingredients(book.key))
					}
					Button { helpOpen = true } label: { label(T("Help")) }.buttonStyle(.plain)
					if account.signedIn { navLink(T("Your Bar"), .bar((book ?? Book.all[0]).key, tab: "make")) }
					else { Button { account.signIn() } label: { label(T("Log in")) }.buttonStyle(.plain).disabled(account.signingIn) }
				}
			}
			.padding(.horizontal, 16).padding(.vertical, 7)
			.frame(maxWidth: .infinity, alignment: .leading)
			Rectangle().fill(Theme.line2).frame(height: 1)
		}
		.background(.bar)
		// the site's help page (its clips show the website), in the chosen language
		.sheet(isPresented: $helpOpen) { SafariView(url: Lang.siteHost.appendingPathComponent("cocktails/help")).ignoresSafeArea() }
	}
	private func label(_ s: String) -> some View { Text(s).font(Theme.sans(13.5)).foregroundStyle(Theme.soft) }
	private func navLink(_ s: String, _ r: Route) -> some View {
		NavigationLink(value: r) { label(s) }.buttonStyle(.plain)
	}
}

import SafariServices
/// a web page in the app (SFSafariViewController)
struct SafariView: UIViewControllerRepresentable {
	let url: URL
	func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
	func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
/// the site's language menu: each language in its own words, the current one ticked
struct LanguageMenu: View {
	@ObservedObject private var lang = LangState.shared
	var body: some View {
		Menu {
			ForEach(Lang.all, id: \.code) { l in
				Button { Lang.choose(l.code) } label: {
					if l.code == lang.code { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
				}
			}
		} label: { Image(systemName: "globe").foregroundStyle(Theme.soft) }
		.accessibilityLabel(T("Languages"))
	}
}

extension View {
	func bookChrome(_ book: Book) -> some View { modifier(BookChrome(book: book)) }
}
