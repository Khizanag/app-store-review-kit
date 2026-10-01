@testable import AppStoreReviewKit
import Foundation
import Testing

@Suite("Review engine")
struct ReviewEngineTests {
    static let cameraCode = """
        import AVFoundation
        let session = AVCaptureSession()
        let launches = UserDefaults.standard.integer(forKey: "launches")
        """

    static let project = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objectVersion = 77;
            objects = {
                P1 = {isa = PBXProject; buildConfigurationList = L1; targets = (T1); };
                L1 = {isa = XCConfigurationList; buildConfigurations = (C1, C2); };
                C1 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {
                    IPHONEOS_DEPLOYMENT_TARGET = 17.0; }; };
                C2 = {isa = XCBuildConfiguration; name = Release; buildSettings = {
                    IPHONEOS_DEPLOYMENT_TARGET = 12.0; SDKROOT = iphoneos; }; };
                T1 = {isa = PBXNativeTarget; name = Demo; productType = "com.apple.product-type.application";
                    buildConfigurationList = L2; };
                L2 = {isa = XCConfigurationList; buildConfigurations = (C3); };
                C3 = {isa = XCBuildConfiguration; name = Release; buildSettings = {
                    GENERATE_INFOPLIST_FILE = YES;
                    INFOPLIST_KEY_NSCameraUsageDescription = "Scan receipts with the camera to add expenses.";
                    INFOPLIST_KEY_UILaunchScreen_Generation = YES;
                    INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
                }; };
            };
            rootObject = P1;
        }
        """

    @Test
    func reportsMissingManifestReasonAndPurposeString() throws {
        let fixture = try Fixture([
            "App/Camera.swift": Self.cameraCode,
            "App/Info.plist": Fixture.plist(["CFBundleName": "Demo", "UILaunchStoryboardName": "Launch"]),
        ])
        defer { fixture.remove() }
        let report = try fixture.review()

        #expect(report.ruleIDs.isSuperset(of: [
            "privacy.manifest-missing",
            "privacy.required-reason-undeclared",
            "permissions.usage-description-missing",
        ]))
        let reason = try #require(report.findings(for: "privacy.required-reason-undeclared").first)
        #expect(reason.instance == "privacy.required-reason-undeclared#NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(reason.locations == [Location(path: "App/Camera.swift", line: 3)])
        let camera = try #require(report.findings(for: "permissions.usage-description-missing").first)
        #expect(camera.message.contains("NSCameraUsageDescription"))
    }

    @Test
    func compliantProjectHasNoAutomatedFindings() throws {
        let fixture = try Fixture([
            "App/Camera.swift": Self.cameraCode,
            "App/PrivacyInfo.xcprivacy": Fixture.manifest(categories: [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            ]),
            "Demo.xcodeproj/project.pbxproj": Self.project.replacingOccurrences(of: "= 12.0", with: "= 17.0"),
        ])
        defer { fixture.remove() }
        let report = try fixture.review()

        #expect(report.findings.isEmpty, "\(report.findings.map(\.message))")
        #expect(!report.manual.isEmpty)
    }

    @Test
    func readsGeneratedInfoKeysAndReleaseSettings() throws {
        let fixture = try Fixture([
            "App/Camera.swift": Self.cameraCode,
            "Demo.xcodeproj/project.pbxproj": Self.project,
        ])
        defer { fixture.remove() }
        let report = try fixture.review()

        #expect(!report.ruleIDs.contains("permissions.usage-description-missing"))
        #expect(!report.ruleIDs.contains("build.launch-screen"))
        #expect(!report.ruleIDs.contains("legal.export-compliance"))
        let target = try #require(report.findings(for: "build.deployment-target").first)
        #expect(target.message.contains("12.0"))
        #expect(target.locations == [Location(path: "Demo.xcodeproj/project.pbxproj")])
    }

    @Test
    func flagsInvalidAndSDKOnlyReasonCodes() throws {
        let fixture = try Fixture([
            "App/PrivacyInfo.xcprivacy": Fixture.manifest(categories: [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1", "C56D.1", "ZZZZ.9"],
                "NSPrivacyAccessedAPICategoryMadeUp": ["CA92.1"],
            ]),
        ])
        defer { fixture.remove() }
        let messages = try fixture.review().findings(for: "privacy.required-reason-invalid").map(\.message)

        #expect(messages.count == 3)
        #expect(messages.contains { $0.contains("ZZZZ.9 is not an approved reason") })
        #expect(messages.contains { $0.contains("C56D.1 may only be declared by a third-party SDK") })
        #expect(messages.contains { $0.contains("NSPrivacyAccessedAPICategoryMadeUp") })
    }

    @Test
    func ignoresDebugCodeAndSilencedLines() throws {
        let code = """
            #if DEBUG
            let local = URL(string: "http://localhost:8080")
            #endif
            let staging = URL(string: "https://staging.example.com") // asrk:ignore build.debug-endpoints
            let live = URL(string: "https://api.example.com")
            """
        let fixture = try Fixture(["App/Network.swift": code])
        defer { fixture.remove() }
        #expect(!(try fixture.review().ruleIDs.contains("build.debug-endpoints")))

        let leaky = try Fixture(["App/Network.swift": "let url = \"http://192.168.1.10:3000/api\""])
        defer { leaky.remove() }
        let report = try leaky.review()
        #expect(report.ruleIDs.contains("build.debug-endpoints"))
        #expect(report.ruleIDs.contains("network.ipv4-literals"))
    }

    @Test
    func vaguePurposeStringsAndPlaceholders() throws {
        let fixture = try Fixture([
            "App/Info.plist": Fixture.plist([
                "NSCameraUsageDescription": "Needs camera",
                "NSMicrophoneUsageDescription": "TODO",
                "NSLocationAlwaysAndWhenInUseUsageDescription": "Shows nearby stores on the map while you browse.",
            ]),
            "App/Copy.swift": "let title = \"Lorem ipsum dolor\"",
        ])
        defer { fixture.remove() }
        let report = try fixture.review()

        #expect(report.findings(for: "permissions.usage-description-vague").count == 2)
        #expect(report.ruleIDs.contains("permissions.location-always-pair"))
        #expect(report.ruleIDs.contains("metadata.placeholder-text"))
    }

    @Test
    func appliesTraitGatedRulesOnlyWhenTheTraitIsPresent() throws {
        let code = """
            import AuthenticationServices
            let provider = ASAuthorizationAppleIDProvider()
            func signUp() {}
            """
        let fixture = try Fixture(["App/Auth.swift": code])
        defer { fixture.remove() }
        let report = try fixture.review()
        #expect(report.traits.contains("accounts"))
        #expect(report.ruleIDs.contains("account.deletion-missing"))

        let utility = try Fixture(["App/Main.swift": "let answer = 42"])
        defer { utility.remove() }
        let quiet = try utility.review()
        #expect(!quiet.traits.contains("accounts"))
        #expect(!quiet.manual.contains { $0.id == "account.login-required" })
        #expect(try utility.review(options: ReviewOptions(profile: "subscription")).traits.contains("accounts"))
    }

    @Test
    func checksStoreMetadataPerLocale() throws {
        let fixture = try Fixture([
            "App/Auth.swift": "let provider = ASAuthorizationAppleIDProvider()",
            "fastlane/metadata/en-US/name.txt": "Receipt Scanner Pro for iPhone and Android 2026",
            "fastlane/metadata/en-US/subtitle.txt": "The best free scanner",
            "fastlane/metadata/en-US/release_notes.txt": "Bug fixes and improvements.",
            "fastlane/metadata/ka/keywords.txt": String(repeating: "ქ", count: 40),
            "fastlane/metadata/review_information/notes.txt": "Tap Scan.",
        ])
        defer { fixture.remove() }
        let report = try fixture.review()

        let name = try #require(report.findings(for: "metadata.name-length").first)
        #expect(name.message == "The en-US name is 47 characters; the limit is 30.")
        let keywords = try #require(report.findings(for: "metadata.field-lengths").first)
        #expect(keywords.message.contains("120 bytes"))
        #expect(report.ruleIDs.isSuperset(of: [
            "metadata.other-platforms",
            "metadata.name-claims",
            "metadata.apple-trademarks",
            "metadata.whats-new-generic",
            "account.demo-account",
        ]))
    }

    @Test
    func skipsRulesWithoutEvidenceInsteadOfPassingThem() throws {
        let fixture = try Fixture(["App/Main.swift": "let answer = 42"])
        defer { fixture.remove() }
        let skipped = try fixture.review().skipped

        #expect(skipped.contains { $0.ruleID == "build.sdk-minimum" })
        #expect(skipped.allSatisfy { !$0.reason.isEmpty })

        let json = """
            {"schema_version": 1, "rules": [{"id": "build.launch-screen", "title": "Launch screen",
            "severity": "error", "evidence": ["binary"], "enforced_by": "upload", "summary": "S.", "fix": "F.",
            "check": {"id": "launch-screen", "confidence": "high"}}]}
            """
        let rulebook = try Rulebook(data: Data(json.utf8))
        let report = ReviewEngine(rulebook: rulebook).review(ProjectLoader().load(fixture.root))
        #expect(report.findings.isEmpty)
        #expect(report.skipped == [SkippedRule(ruleID: "build.launch-screen", reason: "needs binary evidence")])
    }
}
