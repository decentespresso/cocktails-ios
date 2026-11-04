import SwiftUI
import PhotosUI

// Your Bar's sharing and photographed bottles, as on the site (cocktails/js/bar.js renderSettings,
// renderPeople; /cocktails/<book>/bar/photo): the Settings tab, the list of people who share their
// bar, and "Bottle not here? Take a photo".

extension BarView {
	/// Settings: what you share, your pages' links, and the name other members see
	@ViewBuilder var settingsView: some View {
		let member = Member.shared
		VStack(alignment: .leading, spacing: 14) {
			Text(T("Share").uppercased()).font(Theme.mono(12)).kerning(0.6).foregroundStyle(Theme.faint).padding(.top, 22)
			let s = member.share ?? Member.Share(made: true, liked: true)
			Toggle(isOn: Binding(get: { s.made }, set: { member.setShare(Member.Share(made: $0, liked: s.liked)) })) {
				Text(T("Share what I made")).font(Theme.sans(15)).foregroundStyle(Theme.ink)
			}.toggleStyle(CheckboxStyle())
			Toggle(isOn: Binding(get: { s.liked }, set: { member.setShare(Member.Share(made: s.made, liked: $0)) })) {
				Text(T("Share what I liked")).font(Theme.sans(15)).foregroundStyle(Theme.ink)
			}.toggleStyle(CheckboxStyle())
			Text(T("Members who add you under Other people's bars see what you share, listed as {name}.", ["name": member.shareName]))
				.font(Theme.sans(13.5)).foregroundStyle(Theme.soft).fixedSize(horizontal: false, vertical: true)
			if s.made || s.liked {
				Text(T("Your pages to share with other members:")).font(Theme.sans(14)).foregroundStyle(Theme.soft).padding(.top, 6)
				if s.made, let u = member.shareURL("made", book) { shareRow(T("What I made"), u) }
				if s.liked, let u = member.shareURL("liked", book) { shareRow(T("What I liked"), u) }
			}
			ShareNameEditor().padding(.top, 10)
		}
		// the first visit saves the prechecked choice, once the member's data is in
		.task(id: member.loaded) { member.openedSettings() }
	}
	private func shareRow(_ label: String, _ url: URL) -> some View {
		HStack(spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(label).font(Theme.sans(14.5, .semibold)).foregroundStyle(Theme.ink)
				Text(url.absoluteString).font(Theme.mono(11.5)).foregroundStyle(Theme.soft).lineLimit(1).truncationMode(.middle)
			}
			Spacer(minLength: 8)
			ShareLink(item: url) { Image(systemName: "square.and.arrow.up").font(.system(size: 16)).foregroundStyle(Theme.acc) }
		}
		.padding(12).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2))
	}
}

/// "Name other members see": the site's share name (Cocktails and Cookbooks share it)
struct ShareNameEditor: View {
	@ObservedObject private var member = Member.shared
	@State private var draft = ""
	@State private var editing = false
	@State private var error: String?
	@State private var saving = false
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(T("Name other members see")).font(Theme.sans(14.5, .semibold)).foregroundStyle(Theme.ink)
			if editing {
				HStack(spacing: 8) {
					TextField("", text: $draft).font(Theme.sans(15)).textInputAutocapitalization(.words).autocorrectionDisabled()
						.padding(.horizontal, 10).padding(.vertical, 8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
						.onSubmit(save)
					Button(T("Save"), action: save).buttonStyle(.bordered).disabled(saving)
					Button(T("Cancel")) { editing = false; error = nil }.buttonStyle(.plain).foregroundStyle(Theme.soft)
				}
				Text(T("Leave empty to use {name} from your account.", ["name": member.shareName])).font(Theme.sans(13)).foregroundStyle(Theme.faint)
				Text(T("This name is also used in Decent Cookbooks.")).font(Theme.sans(13)).foregroundStyle(Theme.faint)
				if let error { Text(error).font(Theme.sans(13.5)).foregroundStyle(Theme.acc) }
			} else {
				HStack(spacing: 10) {
					Text(member.shareName.isEmpty ? "—" : member.shareName).font(Theme.sans(15)).foregroundStyle(Theme.ink)
					Button(T("Choose")) { draft = member.shareName; editing = true }.font(Theme.sans(14)).foregroundStyle(Theme.acc).buttonStyle(.plain)
				}
			}
		}
	}
	private func save() {
		saving = true
		Task {
			let e = await member.setShareName(draft)
			saving = false; error = e
			if e == nil { editing = false }
		}
	}
}

/// "Other people's bars": members who share, each with + to add them to your location menu
struct PeopleSheet: View {
	let book: Book
	let pick: (Member.Person) -> Void
	@ObservedObject private var member = Member.shared
	@Environment(\.dismiss) private var dismiss
	@State private var people: [Member.Sharer]?
	@State private var q = ""
	var body: some View {
		NavigationStack {
			List {
				if let people {
					if people.isEmpty { Text(T("Nobody shares their bar yet.")).foregroundStyle(Theme.faint) }
					ForEach(people.filter { q.isEmpty || BarIndex.fold($0.name).contains(BarIndex.fold(q)) }) { p in
						let added = member.following.contains { $0.u == p.u }
						HStack(spacing: 12) {
							Button { dismiss(); pick(Member.Person(u: p.u, name: p.name)) } label: {
								VStack(alignment: .leading, spacing: 3) {
									Text(p.name).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
									Text([p.made > 0 ? T("{n} made", ["n": p.made]) : nil, p.wish > 0 ? T("{n} liked", ["n": p.wish]) : nil].compactMap { $0 }.joined(separator: " · "))
										.font(Theme.mono(11.5)).foregroundStyle(Theme.soft)
								}.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
							}.buttonStyle(.plain)
							Button { added ? member.unfollow(p.u) : member.follow(Member.Person(u: p.u, name: p.name)) } label: {
								Text(added ? "✓ " + T("Added") : "+").font(Theme.sans(14, .semibold)).foregroundStyle(added ? Theme.green : Theme.acc)
									.padding(.horizontal, 12).padding(.vertical, 6).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
							}.buttonStyle(.plain)
						}
					}
				} else {
					ProgressView()
				}
			}
			.searchable(text: $q, prompt: T("Search by name…"))
			.navigationTitle(T("People who share their bar"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .cancellationAction) { Button(T("Close")) { dismiss() } } }
			.task { people = await member.sharers(book) ?? [] }
		}
	}
}

/// "Bottle not here? Take a photo": the camera (or a photo you have), sent to the site, which
/// works out what the bottle is and adds it to Your Bar
struct BottlePhotoSheet: View {
	@ObservedObject private var member = Member.shared
	@Environment(\.dismiss) private var dismiss
	@State private var item: PhotosPickerItem?
	@State private var camera = false
	@State private var image: UIImage?
	@State private var busy = false
	@State private var result: (ok: Bool, message: String)?
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					Text(T("Take a photo of the front of the bottle, with the label filling most of the picture. We'll work out what it is and add it to Your Bar."))
						.font(Theme.sans(15.5)).foregroundStyle(Theme.soft).fixedSize(horizontal: false, vertical: true)
					HStack(spacing: 10) {
						if UIImagePickerController.isSourceTypeAvailable(.camera) {
							Button { camera = true } label: { Label(T("Take a photo"), systemImage: "camera") }.buttonStyle(.borderedProminent).tint(Theme.acc)
						}
						PhotosPicker(selection: $item, matching: .images) { Label(T("Choose a photo"), systemImage: "photo") }.buttonStyle(.bordered)
					}
					.disabled(busy)
					if let image {
						Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 320, maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 10))
					}
					if busy { HStack(spacing: 10) { ProgressView(); Text(T("Looking at your bottle…")).foregroundStyle(Theme.soft) } }
					if let result {
						Text(result.message).font(Theme.sans(15, result.ok ? .semibold : .regular)).foregroundStyle(result.ok ? Theme.ink : Theme.acc)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
				.padding(20)
			}
			.navigationTitle(T("Add a bottle from a photo"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .confirmationAction) { Button(result?.ok == true ? T("Done") : T("Close")) { dismiss() } } }
			.onChange(of: item) { _, it in
				guard let it else { return }
				Task { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { send(img) } }
			}
			.fullScreenCover(isPresented: $camera) { CameraPicker { img in camera = false; if let img { send(img) } }.ignoresSafeArea() }
		}
	}
	/// shrunk to 1600px (as the site's page does in the browser) and uploaded
	private func send(_ img: UIImage) {
		image = img; result = nil; busy = true
		let s = min(1, 1600 / max(img.size.width, img.size.height))
		let size = CGSize(width: (img.size.width * s).rounded(), height: (img.size.height * s).rounded())
		let small = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
		guard let jpeg = small.jpegData(compressionQuality: 0.88) else { busy = false; return }
		Task {
			result = await member.addBottle(photo: jpeg)
			busy = false; item = nil
		}
	}
}

/// the system camera (UIImagePickerController)
struct CameraPicker: UIViewControllerRepresentable {
	let done: (UIImage?) -> Void
	func makeUIViewController(context: Context) -> UIImagePickerController {
		let p = UIImagePickerController()
		p.sourceType = .camera
		p.delegate = context.coordinator
		return p
	}
	func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
	func makeCoordinator() -> Coordinator { Coordinator(done) }
	final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
		let done: (UIImage?) -> Void
		init(_ d: @escaping (UIImage?) -> Void) { done = d }
		func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { done(info[.originalImage] as? UIImage) }
		func imagePickerControllerDidCancel(_ p: UIImagePickerController) { done(nil) }
	}
}
