# Sign-in demo

A SwiftUI app showing a two-step sign-in: a password, then the phone number
verified with secondfactor.ai's hosted page through `SecondFactor.verify`.

Open `SignInDemo.xcodeproj` and run it on an iOS 17.4 or later simulator. The
project uses this repository as a local Swift package, so it always builds
against the current `SecondFactor.swift`.

## Without a server (default)

`DemoServer.baseURL` is `nil`, so nothing leaves the device. Any email and
password sign in, and a stand-in for the hosted page asks for a code; any six
digits verify. The stand-in builds the same return URL the real page would,
and the app reads it with `SecondFactor.parseReturn`, so everything after the
page is the real flow.

## With your server

Set `DemoServer.baseURL` in `SignInDemo/DemoServer.swift` and
`DemoServer.returnURL` to the return URL your server uses. The server needs two
JSON endpoints, sharing a cookie session:

- `POST /verification/start` creates a session with `createSession`, stores its
  `sid`, and answers `{ "url": "<session.url>" }`.
- `POST /verification/finish` receives `{ "returnToken": "…" }`, calls
  `verifySession(storedSid, returnToken)`, and answers `{ "phone": "…" }`.

With Express and the `secondfactor` package:

```js
app.post("/verification/start", async (req, res) => {
  const session = await sf.createSession({ to: req.user.phone, returnUrl: "https://app.example.com/verified" });
  req.session.sfSid = session.sid;
  res.json({ url: session.url });
});

app.post("/verification/finish", express.json(), async (req, res) => {
  const storedSid = req.session.sfSid;
  delete req.session.sfSid;
  const { phone } = await sf.verifySession(storedSid, req.body.returnToken);
  res.json({ phone });
});
```

For the sheet to close by itself, the return URL's host must be listed in the
app's Associated Domains (`SignInDemo.entitlements`) and serve an
`apple-app-site-association` file naming the app. Change the bundle identifier
and set your team under Signing & Capabilities first.
