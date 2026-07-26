import Foundation
import Testing
@testable import ShieldStatCore

@Suite("Listener lookup")
struct ListenerLookupTests {
    @Test("A named listener leads with the process, which is what is searchable")
    func leadsWithProcess() {
        let socket = ListeningSocket(port: 111, scope: .allInterfaces, process: "rpcbind")
        let query = ListenerLookup.query(for: socket)
        #expect(query.hasPrefix("\"rpcbind\""))
        #expect(query.contains("port 111"))
        #expect(query.contains("0.0.0.0"))
    }

    @Test("An unnamed port falls back to its description so the search is not just a number")
    func fallsBackToDescription() {
        let socket = ListeningSocket(port: 2049, scope: .allInterfaces)
        #expect(ListenerLookup.query(for: socket).contains("NFS"))
    }

    @Test("A loopback listener asks what it is, not whether exposing it is safe")
    func loopbackAsksDifferently() {
        let socket = ListeningSocket(port: 8000, scope: .loopback, process: "python3")
        let query = ListenerLookup.query(for: socket)
        #expect(query.contains("0.0.0.0") == false)
        #expect(query.contains("what is it"))
    }

    @Test("The URL is built and encoded")
    func buildsURL() throws {
        let socket = ListeningSocket(port: 5432, scope: .allInterfaces, process: "com.docker.backend")
        let url = try #require(ListenerLookup.searchURL(for: socket))
        #expect(url.host() == "www.google.com")
        #expect(url.absoluteString.contains("com.docker.backend"))
        // Spaces must not survive raw into a URL.
        #expect(url.absoluteString.contains(" ") == false)
    }
}
