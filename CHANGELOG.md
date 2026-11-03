# Changelog

All notable changes to secondfactor.ai for iOS are recorded here. The project
follows [Semantic Versioning](https://semver.org/).

## 0.1.0 — 2026-11-02

First release.

### Added

- `SecondFactor.verify(url:returnURL:)` opens the hosted verification page in
  an `ASWebAuthenticationSession` and returns the session ID and return token
  the page came back with. A URL that is not a verification page is refused
  before anything opens.
- `SecondFactor.parseReturn(_:)` reads `sf_session_id` and `sf_return_token`
  from any URL, for apps that receive the return through a universal link.
- `SecondFactor.isVerificationPageURL(_:)`.
- `Examples/SignInDemo`, a SwiftUI sign-in app using the library.
