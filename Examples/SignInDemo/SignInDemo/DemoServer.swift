import Foundation

/// Stands in for your own server, which holds the secondfactor.ai API key.
///
/// The app never talks to secondfactor.ai's API. It asks your server to start
/// a verification, opens the page URL the server returns, and hands the return
/// token back to your server, which confirms it with `verifySession`.
///
/// Leave `baseURL` as `nil` to run the demo without any server: the hosted
/// page is then simulated inside the app. Set it to a server implementing the
/// two endpoints described in `README.md` to run the real flow.
struct DemoServer {
    /// Your server. `nil` simulates everything.
    static let baseURL: URL? = nil

    /// The `returnUrl` your server passes to `createSession`. The app must use
    /// the same one, and needs the Associated Domains entitlement for its host.
    static let returnURL = URL(string: "https://app.example.com/verified")!

    static var isSimulated: Bool { baseURL == nil }

    /// Ask the server to create a verification session for the signed-in
    /// user's phone number. Returns the hosted page's URL.
    func startVerification() async throws -> URL {
        guard let baseURL = Self.baseURL else {
            try await Task.sleep(for: .milliseconds(600))
            return URL(string: "https://verify.secondfactor.ai/s#vst_demo")!
        }
        struct Started: Decodable { let url: URL }
        let started: Started = try await post(baseURL.appending(path: "verification/start"), body: [:])
        return started.url
    }

    /// Hand the return token to the server, which confirms the session it
    /// stored. Returns the phone number that was proven.
    func finishVerification(returnToken: String) async throws -> String {
        guard let baseURL = Self.baseURL else {
            try await Task.sleep(for: .milliseconds(600))
            return "+977 984-1000001"
        }
        struct Finished: Decodable { let phone: String }
        let finished: Finished = try await post(baseURL.appending(path: "verification/finish"), body: ["returnToken": returnToken])
        return finished.phone
    }

    /// POST a JSON body and decode the JSON answer. The shared URLSession keeps
    /// your server's session cookie, which ties both calls to one sign-in.
    private func post<Answer: Decodable>(_ url: URL, body: [String: String]) async throws -> Answer {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Answer.self, from: data)
    }
}
