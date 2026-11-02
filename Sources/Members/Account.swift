import AuthenticationServices
import Foundation
import Security
import UIKit

/// The member's decentespresso.com account: OAuth sign-in (the /support/oauth2 Authorization Code +
/// PKCE flow, as dcamp-ios; client "cocktails-ios", redirect decentcocktails://auth), the bearer
/// token in the Keychain, and the calls to the member API (/cocktails/api/me). The older
/// permacookie calls (/support/api/permacookie_get.adp, permacookie_set.adp) are kept for anything else.
@MainActor
final class Account: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
	static let shared = Account()
	static let clientId = "cocktails-ios"
	static let redirect = "decentcocktails://auth"

	@Published private(set) var token: String?
	@Published var signingIn = false
	@Published var error: String?
	var signedIn: Bool { token != nil }

	/// the website; debug builds take another with the launch argument -server http://localhost:8000
	let server: URL = {
		#if DEBUG
		if let s = UserDefaults.standard.string(forKey: "server"), let u = URL(string: s) { return u }
		#endif
		return URL(string: "https://decentespresso.com")!
	}()

	private var session: ASWebAuthenticationSession?

	override init() {
		super.init()
		#if DEBUG
		// screenshots and tests: -token <bearer> signs in without the web sheet
		if let t = UserDefaults.standard.string(forKey: "token"), !t.isEmpty { token = t; return }
		#endif
		token = Keychain.get(keychainKey)
	}
	private var keychainKey: String { "token:" + (server.host ?? "") }

	// MARK: sign in / out

	func signIn() {
		guard !signingIn else { return }
		error = nil
		let verifier = Self.randomString(64)
		let state = Self.randomString(24)
		var c = URLComponents(url: server.appendingPathComponent("support/oauth2/authorize"), resolvingAgainstBaseURL: false)!
		c.queryItems = [
			.init(name: "client_id", value: Self.clientId), .init(name: "redirect_uri", value: Self.redirect),
			.init(name: "state", value: state), .init(name: "code_challenge", value: Self.challenge(verifier)),
			.init(name: "code_challenge_method", value: "S256"),
		]
		signingIn = true
		let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "decentcocktails") { [weak self] url, err in
			Task { @MainActor in
				guard let self else { return }
				self.session = nil
				guard let url, err == nil else { self.signingIn = false; return }   // cancelled
				let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
				guard q.first(where: { $0.name == "state" })?.value == state,
					  let code = q.first(where: { $0.name == "code" })?.value else {
					self.signingIn = false; self.error = T("Sign-in failed. Please try again."); return
				}
				await self.redeem(code: code, verifier: verifier)
			}
		}
		s.presentationContextProvider = self
		s.prefersEphemeralWebBrowserSession = false   // a browser already signed in to decentespresso.com skips the form
		session = s
		s.start()
	}

	private func redeem(code: String, verifier: String) async {
		defer { signingIn = false }
		var req = URLRequest(url: server.appendingPathComponent("support/oauth2/token"))
		req.httpMethod = "POST"
		req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		req.httpBody = Self.form([
			"grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": Self.redirect,
			"client_id": Self.clientId, "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "",
		])
		guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
			  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tok = j["access_token"] as? String, !tok.isEmpty else {
			error = T("Sign-in failed. Please try again."); return
		}
		Keychain.set(keychainKey, tok)
		token = tok
		await Member.shared.load()
	}

	func signOut() {
		Keychain.delete(keychainKey)
		token = nil
		Member.shared.clear()
	}

	nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
		MainActor.assumeIsolated {
			UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
		}
	}

	// MARK: permacookies

	enum Fetch { case value(String), signedOut, failed }

	/// one permacookie's value ("" when unset)
	func get(_ key: String) async -> Fetch {
		guard let token else { return .signedOut }
		var c = URLComponents(url: server.appendingPathComponent("support/api/permacookie_get.adp"), resolvingAgainstBaseURL: false)!
		c.queryItems = [.init(name: "key", value: key)]
		var req = URLRequest(url: c.url!)
		req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		req.cachePolicy = .reloadIgnoringLocalCacheData
		guard let (data, resp) = try? await URLSession.shared.data(for: req), let h = resp as? HTTPURLResponse else { return .failed }
		guard h.statusCode == 200 else { return .failed }
		return .value(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
	}

	@discardableResult
	func set(_ key: String, _ value: String) async -> Bool {
		guard let token else { return false }
		var req = URLRequest(url: server.appendingPathComponent("support/api/permacookie_set.adp"))
		req.httpMethod = "POST"
		req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		req.httpBody = Self.form(["key": key, "value": value])
		guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
		// the reply is 1 when saved, 0 when the token no longer signs anyone in
		let ok = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "1"
		if !ok { lapsed() }
		return ok
	}
	// MARK: member API (/cocktails/api/me, lib/cocktails_member.tcl on the site)

	/// everything the site keeps for the member: liked, made, notes, bar, prefs, following
	func me() async -> [String: Any]? {
		guard let token else { return nil }
		var req = URLRequest(url: server.appendingPathComponent("cocktails/api/me"))
		req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		req.cachePolicy = .reloadIgnoringLocalCacheData
		guard let (data, resp) = try? await URLSession.shared.data(for: req), let h = resp as? HTTPURLResponse else { return nil }
		if h.statusCode == 401 { lapsed(); return nil }
		guard h.statusCode == 200 else { return nil }
		return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
	}
	/// one change: PUT / DELETE / POST /cocktails/api/me/<path>, with form fields
	@discardableResult
	func api(_ method: String, _ path: String, query: [String: String] = [:], fields: [String: String] = [:]) async -> Bool {
		guard let token else { return false }
		var c = URLComponents(url: server.appendingPathComponent("cocktails/api/me/" + path), resolvingAgainstBaseURL: false)!
		if !query.isEmpty { c.queryItems = query.map { .init(name: $0.key, value: $0.value) } }
		var req = URLRequest(url: c.url!)
		req.httpMethod = method
		req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		if !fields.isEmpty {
			req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
			req.httpBody = Self.form(fields)
		}
		guard let (_, resp) = try? await URLSession.shared.data(for: req), let h = resp as? HTTPURLResponse else { return false }
		if h.statusCode == 401 { lapsed(); return false }
		return h.statusCode == 200
	}

	/// the token stopped working (revoked, or the account closed): back to signed out
	private func lapsed() {
		Keychain.delete(keychainKey)
		token = nil
		error = T("You've been signed out. Please sign in again.")
		Member.shared.clear()
	}

	// MARK: helpers

	private static func form(_ d: [String: String]) -> Data {
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-._~")
		return Data(d.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
	}
	private static func randomString(_ n: Int) -> String {
		let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
		var bytes = [UInt8](repeating: 0, count: n)
		_ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
		return String(bytes.map { chars[Int($0) % chars.count] })
	}
	/// PKCE S256: base64url(sha256(verifier))
	private static func challenge(_ v: String) -> String {
		Data(SHA256.hash(data: Data(v.utf8))).base64EncodedString()
			.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
	}
}

import CryptoKit

/// the token's home: a generic password item per server
enum Keychain {
	private static func query(_ key: String) -> [String: Any] {
		var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.decentespresso.cocktails", kSecAttrAccount as String: key]
		#if targetEnvironment(macCatalyst)
		// the Mac app is Developer-ID signed without a provisioning profile, so it can't use the
		// iOS-style data-protection keychain (that needs a keychain-access-groups entitlement):
		// keep the token in the login keychain instead
		q[kSecUseDataProtectionKeychain as String] = false
		#endif
		return q
	}
	static func get(_ key: String) -> String? {
		var q = query(key)
		q[kSecReturnData as String] = true
		q[kSecMatchLimit as String] = kSecMatchLimitOne
		var out: AnyObject?
		guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
		return String(data: d, encoding: .utf8)
	}
	static func set(_ key: String, _ value: String) {
		delete(key)
		var q = query(key)
		q[kSecValueData as String] = Data(value.utf8)
		q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
		SecItemAdd(q as CFDictionary, nil)
	}
	static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
