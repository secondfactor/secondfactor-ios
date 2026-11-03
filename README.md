# secondfactor.ai for iOS

The client half of [secondfactor.ai](https://secondfactor.ai) hosted
verification for iOS apps. Your users verify their phone number on our page,
much like Stripe Checkout; this library opens that page in a system sheet and
reads the result when the user comes back. One Swift file, no dependencies.

This library runs on the **user's device**. It never calls the secondfactor.ai
API, and never holds your API key, a phone number or a code. Your server holds
the key and uses the server library,
[`secondfactor`](https://github.com/secondfactor/secondfactor-node) on npm
(or [`secondfactor`](https://github.com/secondfactor/secondfactor-python) on
PyPI).

> **Act on the result on your server.** What this library reads from a URL is
> not proof of anything: anyone can craft a URL. Your server confirms the
> session it stored, once, and that answer is the proof.

## Requirements

- iOS 17.4 or later for `SecondFactor.verify`, which uses
  `ASWebAuthenticationSession` with an `https://` callback.
  `parseReturn` and `isVerificationPageURL` work from iOS 16.
- Xcode 15.3 or later. The file compiles in Swift 5 and Swift 6 language modes.

## Install

Pick one.

**Copy the file.** Download
[`Sources/SecondFactor/SecondFactor.swift`](Sources/SecondFactor/SecondFactor.swift)
and drag it into your app target in Xcode. Nothing else is needed, and you
do not write `import SecondFactor`.

**Swift Package Manager.** In Xcode, choose File → Add Package Dependencies…
and enter this repository's URL, or add it to `Package.swift`:

```swift
.package(url: "https://github.com/secondfactor/secondfactor-ios", from: "0.1.0"),
```

Then `import SecondFactor` where you use it.

## Set up

1. In the secondfactor.ai dashboard, under **Settings → Hosted verification**,
   add your return origin, such as `https://app.example.com`. Custom URL
   schemes are not accepted.
2. Give your app the **Associated Domains** capability with
   `webcredentials:app.example.com`.
3. Serve `https://app.example.com/.well-known/apple-app-site-association`
   listing your app under `webcredentials`:

   ```json
   { "webcredentials": { "apps": ["TEAMID.com.example.yourapp"] } }
   ```

   Without steps 2 and 3, iOS will not hand the return back to your app and
   the sheet will not close by itself.

## How it fits together

1. **Your server** creates a session for the number it wants verified, keeps
   its `sid`, and gives the page's `url` to your app:

   ```js
   // Node, with the `secondfactor` package.
   const session = await sf.createSession({
     to: user.phone,
     returnUrl: "https://app.example.com/verified",
   });
   req.session.sfSid = session.sid;
   res.json({ url: session.url });
   ```

2. **Your app** opens our page and waits for the user to come back:

   ```swift
   let url = try await api.startVerification()        // the `url` from step 1
   let back = try await SecondFactor.verify(
       url: url,
       returnURL: URL(string: "https://app.example.com/verified")!
   )
   ```

   We send the code, the user types it on our page, and the sheet closes.

3. **Your app** hands the return token to your server:

   ```swift
   if let token = back.returnToken {
       try await api.finishVerification(returnToken: token)
   } else {
       // The user ran out of attempts or the session expired.
   }
   ```

4. **Your server** confirms the session it stored, once, and acts on that:

   ```js
   const { phone } = await sf.verifySession(req.session.sfSid, req.body.returnToken);
   ```

## Usage

A complete verification in SwiftUI, from asking your server for the page to
telling the user how it went. `MyAPI` stands for your app's own client for
your server, with the two endpoints from the steps above. If you copied the
file instead of adding the package, leave out `import SecondFactor`. If your
app's deployment target is iOS 17.4 or later, leave out the `@available`
lines.

```swift
import SecondFactor
import SwiftUI

/// Your app's client for your own server.
protocol MyAPI: Sendable {
    /// Asks your server to call `createSession`, and returns the page's `url`.
    func startVerification() async throws -> URL

    /// Hands the return token to your server, which calls `verifySession`.
    func finishVerification(returnToken: String) async throws
}

/// The same `https://` URL your server passes to `createSession`.
let returnURL = URL(string: "https://app.example.com/verified")!

/// Runs one verification and returns a message to show the user.
@available(iOS 17.4, *)
@MainActor
func verifyPhone(api: some MyAPI) async throws -> String {
    let url = try await api.startVerification()

    let back: SecondFactor.VerificationReturn
    do {
        back = try await SecondFactor.verify(url: url, returnURL: returnURL)
    } catch SecondFactorError.canceled {
        return "Verification canceled."
    } catch SecondFactorError.couldNotStart {
        return "The verification page could not be opened."
    }
    // Any other error means the app and the server disagree about a URL, or
    // the system failed. That is a bug to fix, not something the user can act
    // on, so it reaches the caller.

    guard let token = back.returnToken else {
        // The user ran out of attempts, or the session expired.
        return "Your number was not verified. Please try again."
    }
    try await api.finishVerification(returnToken: token)
    return "Your number is verified."
}

/// A button that runs `verifyPhone` and shows the result.
@available(iOS 17.4, *)
struct VerifyPhoneButton<API: MyAPI>: View {
    let api: API

    @State private var busy = false
    @State private var message = ""

    var body: some View {
        VStack {
            Button("Verify phone number") {
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        message = try await verifyPhone(api: api)
                    } catch {
                        print("Verification failed: \(error)") // Send this to your error reporting.
                        message = "Something went wrong. Please try again."
                    }
                }
            }
            .disabled(busy)
            Text(message)
        }
    }
}
```

The button is disabled while a verification is open, so only one sheet is
shown at a time.

## API

### `SecondFactor.verify(url:returnURL:) async throws -> VerificationReturn`

Opens the hosted page in an `ASWebAuthenticationSession` and returns when the
page sends the user to `returnURL`. `url` must be the `url` your server got
from `createSession`; anything else throws `.notAVerificationPage` and is not
opened. `returnURL` must be the same `https://` URL your server passed as
`returnUrl`. Call it on the main actor.

The sheet uses an ephemeral browser session, so it shares no cookies with
Safari and keeps none afterwards.

### `SecondFactor.parseReturn(_ url: URL) -> VerificationReturn?`

Reads `sf_session_id` and `sf_return_token` from any URL. `verify` calls it for
you; call it yourself if the return reaches your app another way, such as a
universal link delivered to `onOpenURL`.

### `SecondFactor.isVerificationPageURL(_ url: URL) -> Bool`

Whether `url` has the shape of a hosted page: `https://` (plain `http://` only
for `localhost`, `127.0.0.1`, `[::1]` and `*.localhost`), no user name or
password, and a `#vst_…` fragment.

### `VerificationReturn`

- `sessionId`: tells you which stored session the user came back from. Your
  server must always confirm the `sid` it stored, never this one.
- `returnToken`: present only when the user verified. It works once.

### `SecondFactorError`

| Case | Meaning |
|---|---|
| `.notAVerificationPage` | `url` is not a hosted page. Pass the server's `url` unchanged. |
| `.invalidReturnURL` | `returnURL` is not `https://` with a host. |
| `.canceled` | The user closed the sheet. Nothing was verified. |
| `.missingReturnParameters` | The page returned without `sf_session_id`. |
| `.couldNotStart` | The sheet could not be shown, for example with no window. |

Any other error from `ASWebAuthenticationSession` is thrown unchanged.

## Example

[`Examples/SignInDemo`](Examples/SignInDemo) is a SwiftUI app with a complete
password-then-phone sign-in. It runs with no server, simulating the hosted
page, or against your own server.

## Development

```bash
swift test
```

## License

MIT
