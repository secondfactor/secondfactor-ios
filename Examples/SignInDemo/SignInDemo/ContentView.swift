import SecondFactor
import SwiftUI

/// The three steps of the demo sign-in.
private enum Step: Equatable {
    case signIn
    case verifyPhone(email: String)
    case signedIn(email: String, phone: String)
}

struct ContentView: View {
    @State private var step = Step.signIn

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .signIn:
                    SignInView { email in step = .verifyPhone(email: email) }
                case .verifyPhone(let email):
                    VerifyPhoneView(email: email,
                                    onVerified: { phone in step = .signedIn(email: email, phone: phone) },
                                    onBack: { step = .signIn })
                case .signedIn(let email, let phone):
                    SignedInView(email: email, phone: phone) { step = .signIn }
                }
            }
            .animation(.default, value: step)
        }
    }
}

// MARK: - Step 1: password

/// The first factor. A real app checks the password with its server here; the
/// demo accepts anything.
private struct SignInView: View {
    let onSignedIn: (String) -> Void
    @State private var email = "demo@example.com"
    @State private var password = "password"

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text("Welcome back").font(.title2.bold())
                    Text("Sign in to continue.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }

            Section {
                Button("Sign in") { onSignedIn(email) }
                    .frame(maxWidth: .infinity)
                    .disabled(email.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Sign in")
    }
}

// MARK: - Step 2: phone, with secondfactor.ai

private struct VerifyPhoneView: View {
    let email: String
    let onVerified: (String) -> Void
    let onBack: () -> Void

    private let server = DemoServer()
    @State private var busy = false
    @State private var message: String?
    @State private var showSimulatedPage = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Confirm it's you").font(.title2.bold())
            Text("We'll send a code to the phone number on your account. You'll enter it on a secure secondfactor.ai page.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await start() }
            } label: {
                Group {
                    if busy { ProgressView() } else { Text("Verify phone number") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy)
            Button("Use a different account", action: onBack).disabled(busy)
        }
        .padding(24)
        .navigationTitle("Two-step verification")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSimulatedPage) {
            SimulatedHostedPage { returned in
                showSimulatedPage = false
                Task { await finish(returned) }
            }
        }
    }

    /// Ask the server for a session, then open the hosted page.
    private func start() async {
        busy = true
        message = nil
        do {
            let url = try await server.startVerification()
            if DemoServer.isSimulated {
                // No server, so no real page: show the stand-in sheet instead.
                showSimulatedPage = true
                return
            }
            let back = try await SecondFactor.verify(url: url, returnURL: DemoServer.returnURL)
            await finish(back)
        } catch SecondFactorError.canceled {
            busy = false
        } catch {
            message = "Could not verify: \(error.localizedDescription)"
            busy = false
        }
    }

    /// Hand the return token to the server, which is the only judge of whether
    /// the phone was verified.
    private func finish(_ back: SecondFactor.VerificationReturn?) async {
        defer { busy = false }
        guard let token = back?.returnToken else {
            message = back == nil ? nil : "The phone was not verified. Try again."
            return
        }
        do {
            onVerified(try await server.finishVerification(returnToken: token))
        } catch {
            message = "Could not verify: \(error.localizedDescription)"
        }
    }
}

// MARK: - Step 3: done

private struct SignedInView: View {
    let email: String
    let phone: String
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're signed in").font(.title2.bold())
            LabeledContent("Account", value: email)
            LabeledContent("Verified phone", value: phone)
            Spacer()
            Button("Sign out", role: .destructive, action: onSignOut)
        }
        .padding(24)
        .navigationTitle("Home")
    }
}

// MARK: - Simulated hosted page

/// A stand-in for secondfactor.ai's hosted page, used only when `DemoServer`
/// has no `baseURL`. The real page opens in a system sheet through
/// `SecondFactor.verify`. This one builds the same return URL the real page
/// would and reads it with `SecondFactor.parseReturn`, so the rest of the flow
/// is the real one.
private struct SimulatedHostedPage: View {
    let onReturn: (SecondFactor.VerificationReturn?) -> Void
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the 6-digit code we sent to •••• •••• 0001.")
                    TextField("123456", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.monospacedDigit())
                } footer: {
                    Text("Simulated page: any 6 digits work.")
                }
                Button("Verify") {
                    var page = DemoServer.returnURL
                    page.append(queryItems: [
                        URLQueryItem(name: "sf_session_id", value: "VS_demo"),
                        URLQueryItem(name: "sf_return_token", value: "rt_demo"),
                    ])
                    onReturn(SecondFactor.parseReturn(page))
                }
                .disabled(code.count != 6)
            }
            .navigationTitle("secondfactor.ai")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onReturn(nil) }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

#Preview {
    ContentView()
}
