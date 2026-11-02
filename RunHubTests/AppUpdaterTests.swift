import Foundation
import Testing
@testable import RunHub

@MainActor
struct AppUpdaterTests {
    @Test func bundledUpdaterConfigurationIsValid() throws {
        let bundle = Bundle(for: AppUpdater.self)
        let feed = try #require(bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)
        #expect(URL(string: feed)?.scheme == "https")
        #expect(feed == "https://raw.githubusercontent.com/yumaitau/RunHub/main/appcast.xml")
        let key = try #require(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        #expect(bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == true)
        #expect(bundle.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool == true)
        #expect(bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true)
    }
}
