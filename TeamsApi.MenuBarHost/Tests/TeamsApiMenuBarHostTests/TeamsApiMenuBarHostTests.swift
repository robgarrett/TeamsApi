import Foundation
import Testing
@testable import TeamsApiMenuBarHost

@Test func outputParserPersistsTokenWithoutForwardingIt() async throws {
    var savedToken: String?
    let parser = OutputParser(
        onMeetingStateChanged: nil,
        onTokenChanged: { savedToken = $0 }
    )

    let output = parser.ingest(Data("TEAMS_TOKEN:cmVmcmVzaGVkLXRva2Vu\n".utf8))

    #expect(savedToken == "refreshed-token")
    #expect(output.isEmpty)
}

@Test func outputParserForwardsNormalOutputAndPublishesMeetingState() async throws {
    var meetingState: Bool?
    let parser = OutputParser(
        onMeetingStateChanged: { meetingState = $0 }
    )

    let output = parser.ingest(Data("host output\nMEETING_STATE:in\n".utf8))

    #expect(meetingState == true)
    #expect(String(data: output, encoding: .utf8) == "host output\nMEETING_STATE:in\n")
}
