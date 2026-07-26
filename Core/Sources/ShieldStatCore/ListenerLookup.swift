import Foundation

/// Builds a web search for "what is this thing and should it be listening".
///
/// Pure so the query is testable without opening a browser. Deliberately not a
/// built-in database of verdicts: the honest answer for most ports is "it
/// depends what you installed", and a tool that guessed would be trusted more
/// than it deserved.
public enum ListenerLookup {
    /// A search that leads with what the user can see, then asks the question
    /// they actually have. Process name first when known, because "rpcbind" is
    /// far more searchable than "port 111".
    public static func query(for listener: ListeningSocket) -> String {
        var terms: [String] = []
        // Unquoted. Quoting looked like precision and is the opposite: a quoted
        // term is a hard exact-match requirement, and intersecting that with a
        // long natural-language query returns nothing for anything obscure —
        // which is exactly what a user needs to look up. Measured on symptomsd:
        // quoted returned no results, bare returned useful ones.
        if let process = listener.process { terms.append(process) }
        terms.append("port \(listener.port)")
        if let description = WellKnownPorts.description(of: listener.port),
           listener.process == nil {
            terms.append(description)
        }
        terms.append(listener.isReachable
            ? "why is it listening on 0.0.0.0 is it safe"
            : "what is it")
        return terms.joined(separator: " ")
    }

    /// Nil only if the query somehow cannot be percent-encoded.
    public static func searchURL(for listener: ListeningSocket) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query(for: listener))]
        return components?.url
    }
}
