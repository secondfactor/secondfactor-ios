import Foundation
import Testing
import SecondFactor

@Suite struct VerificationPageURL {
    @Test(arguments: [
        "https://verify.secondfactor.ai/s#vst_abc123",
        "HTTPS://Verify.SecondFactor.ai:443/s?x=1#vst_A-b_9",
        "http://localhost:8080/s#vst_abc",
        "http://127.0.0.1/s#vst_abc",
        "http://[::1]:3000/s#vst_abc",
        "http://dev.localhost/s#vst_abc",
    ])
    func accepts(_ string: String) {
        #expect(SecondFactor.isVerificationPageURL(URL(string: string)!))
    }

    @Test(arguments: [
        "javascript:alert(1)//#vst_abc",
        "http://verify.secondfactor.ai/s#vst_abc",   // Plain HTTP off loopback.
        "https://verify.secondfactor.ai/s",          // No client token.
        "https://verify.secondfactor.ai/s#other",
        "https://user:pass@verify.secondfactor.ai/s#vst_abc",
        "https://evil.example\\@verify.secondfactor.ai/s#vst_abc",
        "http://localhost.evil.example/s#vst_abc",
        "ftp://verify.secondfactor.ai/s#vst_abc",
    ])
    func refuses(_ string: String) {
        // Some of these are not even valid URLs, which is a refusal too.
        if let url = URL(string: string) {
            #expect(!SecondFactor.isVerificationPageURL(url))
        }
    }
}

@Suite struct ParseReturn {
    @Test func verified() {
        let back = SecondFactor.parseReturn(URL(string: "https://app.example.com/verified?a=1&sf_session_id=VS1&sf_return_token=rt_1#frag")!)
        #expect(back?.sessionId == "VS1")
        #expect(back?.returnToken == "rt_1")
    }

    @Test func notVerifiedHasNoToken() {
        let back = SecondFactor.parseReturn(URL(string: "https://app.example.com/verified?sf_session_id=VS1&sf_return_token=")!)
        #expect(back?.sessionId == "VS1")
        #expect(back?.returnToken == nil)
    }

    @Test func firstValueWins() {
        let back = SecondFactor.parseReturn(URL(string: "https://app.example.com/v?sf_session_id=VS1&sf_session_id=VS2&sf_return_token=a&sf_return_token=b")!)
        #expect(back?.sessionId == "VS1")
        #expect(back?.returnToken == "a")
    }

    @Test(arguments: [
        "https://app.example.com/verified",
        "https://app.example.com/verified?sf_session_id=",
        "https://app.example.com/verified?sf_return_token=rt_1",
        "https://app.example.com/verified#sf_session_id=VS1",
    ])
    func noSession(_ string: String) {
        #expect(SecondFactor.parseReturn(URL(string: string)!) == nil)
    }
}
