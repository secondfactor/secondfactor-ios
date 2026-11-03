// SecondFactor.swift
//
// secondfactor.ai for iOS: the client half of hosted verification.
// One file, no dependencies. Copy it into your app target, or add this
// repository as a Swift package.
//
// secondfactor.ai verifies a phone number on its own hosted page, much like
// Stripe Checkout. Your server creates a verification session with its API key
// (the `secondfactor` package on npm or PyPI) and gets back the page's `url`.
// This file does the two things left for the app:
//
//     // Open our page in a system sheet and wait for the user to come back.
//     let back = try await SecondFactor.verify(url: url, returnURL: returnURL)
//
//     // Send back.returnToken to your server, which passes it to verifySession.
//
// It never calls the secondfactor.ai API and never holds a key, a phone number
// or a code. Nothing it reports is proof that a number was verified: only your
// server's `verifySession` call is.
//
// MIT License. Copyright (c) 2026 Lambda Payments.

import Foundation
#if os(iOS)
import AuthenticationServices
import UIKit
#endif

/// The client half of secondfactor.ai hosted verification.
public enum SecondFactor {
    /// This file's version. Bump it together with `CHANGELOG.md`.
    public static let version = "0.1.0"

    /// The two parameters the hosted page adds to your return URL.
    public struct VerificationReturn: Equatable, Sendable {
        /// `sf_session_id`. Tells you which stored session to look up. Anyone
        /// can edit a URL, so your server must always confirm the session ID it
        /// stored instead of this one.
        public let sessionId: String

        /// `sf_return_token`. Present only when the user verified; `nil` when
        /// they canceled, ran out of attempts or the session expired. Send it
        /// to your server, which passes it to `verifySession`. It works once.
        public let returnToken: String?
    }

    static let sessionParameter = "sf_session_id"
    static let tokenParameter = "sf_return_token"

    // Plain http:// is accepted only for these hosts, so a local verify page can
    // be used in development. `*.localhost` always resolves to the machine itself.
    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "[::1]"]

    /// Whether `url` has the shape of a hosted verification page.
    ///
    /// That means `https://` (or plain `http://` on a loopback host), no user
    /// name or password, and the session's client token (`#vst_…`) in the
    /// fragment, where the page reads it. `verify(url:returnURL:)` refuses any
    /// other URL, so a URL that reached your app some other way is never opened.
    ///
    /// - Parameter url: The `url` your server received from `createSession`.
    /// - Returns: `true` when the URL may be opened as a verification page.
    public static func isVerificationPageURL(_ url: URL) -> Bool {
        let string = url.absoluteString
        guard !string.isEmpty, string.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            return false
        }
        let page = #/([a-z][a-z0-9+.\-]*)://([^/?#\\@]+)[^#\\]*#vst_[A-Za-z0-9_\-]+/#.ignoresCase()
        let authority = #/(\[[0-9a-f:.]+\]|[a-z0-9._\-]+)(?::[0-9]{1,5})?/#.ignoresCase()
        guard let parts = string.wholeMatch(of: page),
              let host = parts.output.2.wholeMatch(of: authority) else {
            return false
        }
        let scheme = parts.output.1.lowercased()
        let hostname = host.output.1.lowercased()
        return scheme == "https"
            || (scheme == "http" && (loopbackHosts.contains(hostname) || hostname.hasSuffix(".localhost")))
    }

    /// The hosted page's parameters on a URL the user returned to.
    ///
    /// `verify(url:returnURL:)` calls this for you. Call it yourself when your
    /// app receives the return URL another way, such as through a universal
    /// link delivered to `onOpenURL`. Nothing here is checked against
    /// secondfactor.ai: your server does that when it confirms the session.
    ///
    /// - Parameter url: The URL the user returned to.
    /// - Returns: The session ID and, when the user verified, the return token;
    ///   `nil` when the URL carries no `sf_session_id`.
    public static func parseReturn(_ url: URL) -> VerificationReturn? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        // The first value wins. The hosted page replaces any parameter of the
        // same name rather than adding a second, so a repeat did not come from it.
        func first(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let sessionId = first(sessionParameter), !sessionId.isEmpty else {
            return nil
        }
        let token = first(tokenParameter)
        return VerificationReturn(sessionId: sessionId, returnToken: token?.isEmpty == false ? token : nil)
    }

    #if os(iOS)
    /// Open the hosted verification page in a system sheet and wait for the
    /// user to come back.
    ///
    /// The page opens in an `ASWebAuthenticationSession`, which closes by
    /// itself when the page sends the user to `returnURL`. Your app needs the
    /// Associated Domains entitlement `webcredentials:<returnURL host>`, and
    /// that host must serve an `apple-app-site-association` file listing the
    /// app, or the system will not hand the return back.
    ///
    /// - Parameters:
    ///   - url: The `url` your server received from `createSession`. It is
    ///     checked with `isVerificationPageURL(_:)` before anything opens.
    ///   - returnURL: The same `https://` URL your server passed to
    ///     `createSession` as `returnUrl`. Only its host and path are used.
    /// - Returns: The parameters the page returned with. Check `returnToken`:
    ///   `nil` means the user did not verify.
    /// - Throws: `SecondFactorError.notAVerificationPage` or `.invalidReturnURL`
    ///   for bad arguments, `.canceled` when the user closed the sheet,
    ///   `.missingReturnParameters` when the return URL carried no session,
    ///   `.couldNotStart` when there is no window to present from, and any
    ///   other error `ASWebAuthenticationSession` reports, unchanged.
    @available(iOS 17.4, *)
    @MainActor
    public static func verify(url: URL, returnURL: URL) async throws -> VerificationReturn {
        guard isVerificationPageURL(url) else {
            throw SecondFactorError.notAVerificationPage
        }
        guard returnURL.scheme?.lowercased() == "https", let host = returnURL.host(), !host.isEmpty else {
            throw SecondFactorError.invalidReturnURL
        }
        guard let anchor = presentationWindow() else {
            throw SecondFactorError.couldNotStart
        }
        let path = returnURL.path().isEmpty ? "/" : returnURL.path()

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let presenter = WebSessionPresenter(anchor: anchor, continuation: continuation)
            // The completion handler holds the presenter, and the presenter holds
            // the session, so both live exactly until the user returns or closes
            // the sheet. `finish` then drops the session, breaking the cycle.
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: host, path: path),
                completionHandler: { callbackURL, error in
                    Task { @MainActor in presenter.finish(callbackURL: callbackURL, error: error) }
                }
            )
            session.presentationContextProvider = presenter
            // The hosted page needs no cookies from Safari, and none of its own
            // should outlive this one verification.
            session.prefersEphemeralWebBrowserSession = true
            presenter.session = session
            if !session.start() {
                presenter.finish(callbackURL: nil, error: SecondFactorError.couldNotStart)
            }
        }

        guard let back = parseReturn(callbackURL) else {
            throw SecondFactorError.missingReturnParameters
        }
        return back
    }

    /// The window to present the sheet over: the key window of a connected
    /// scene, or failing that the first window found.
    @MainActor
    private static func presentationWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
    #endif
}

/// Why `SecondFactor.verify(url:returnURL:)` did not return.
public enum SecondFactorError: Error, Equatable, Sendable {
    /// `url` is not a hosted verification page. Pass the `url` your server
    /// received from `createSession`, unchanged.
    case notAVerificationPage
    /// `returnURL` is not an `https://` URL with a host.
    case invalidReturnURL
    /// The user closed the sheet before finishing. Nothing was verified.
    case canceled
    /// The page returned to a URL without `sf_session_id`.
    case missingReturnParameters
    /// The sheet could not be shown, for example because the app has no window.
    case couldNotStart
}

#if os(iOS)
/// Keeps an `ASWebAuthenticationSession` alive while it is shown, tells it
/// where to present, and resumes the waiting caller exactly once.
@MainActor
private final class WebSessionPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: UIWindow
    private var continuation: CheckedContinuation<URL, Error>?
    var session: ASWebAuthenticationSession?

    init(anchor: UIWindow, continuation: CheckedContinuation<URL, Error>) {
        self.anchor = anchor
        self.continuation = continuation
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }

    /// Resume the caller with the return URL or the error. Later calls do
    /// nothing, because a continuation must be resumed only once and the
    /// system may report a failed start both from `start()` and to the
    /// completion handler.
    func finish(callbackURL: URL?, error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        session = nil
        if let callbackURL {
            continuation.resume(returning: callbackURL)
        } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            continuation.resume(throwing: SecondFactorError.canceled)
        } else {
            continuation.resume(throwing: error ?? SecondFactorError.couldNotStart)
        }
    }
}
#endif
