import Foundation

/// Watches the BSD routing socket for address and interface changes.
///
/// This replaced `NWPathMonitor`, which is the obvious choice and the wrong one.
/// Measured on macOS 26.4: giving an interface a public IPv4 fired *neither* an
/// `NWPathMonitor` update nor an `SCDynamicStore` notification, because the
/// interface carried no default route and was not a SystemConfiguration network
/// service. Both APIs sit above the routing layer and filter out precisely the
/// case worth catching — an interface you have forgotten about quietly gaining
/// an address. `PF_ROUTE` sees it: the same change produced `RTM_NEWADDR`,
/// `RTM_DELADDR` and `RTM_IFINFO`.
final class RouteEventSource {
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var pending: DispatchWorkItem?

    /// One `ifconfig` invocation emits a burst — six messages inside the same
    /// millisecond was typical — so changes are coalesced rather than
    /// re-evaluated once per message.
    private static let coalescingWindow: DispatchTimeInterval = .milliseconds(300)

    private let queue = DispatchQueue(label: "dev.lucascaro.ShieldStat.route")

    func start(onChange: @escaping @Sendable @MainActor () -> Void) {
        guard descriptor < 0 else { return }

        descriptor = socket(PF_ROUTE, SOCK_RAW, AF_UNSPEC)
        guard descriptor >= 0 else { return }

        let read = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        read.setEventHandler { [weak self] in
            guard let self, self.readMessages() else { return }
            self.scheduleEvaluation(onChange)
        }
        read.setCancelHandler { [descriptor] in close(descriptor) }
        read.resume()
        source = read
    }

    func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Returns true when the batch contained something worth re-evaluating for.
    private func readMessages() -> Bool {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = read(descriptor, &buffer, buffer.count)
        guard count > 0 else { return false }

        var relevant = false
        var offset = 0
        let header = MemoryLayout<rt_msghdr>.size

        // A single read can carry several messages back to back.
        while offset + header <= count {
            let message = buffer.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
            }
            let length = Int(message.rtm_msglen)
            guard length >= header else { break }

            if isRelevant(Int32(message.rtm_type)) { relevant = true }
            offset += length
        }
        return relevant
    }

    /// Address and interface changes only. The socket also carries `RTM_MISS`
    /// for every failed route lookup, which is ordinary traffic noise and would
    /// otherwise drive a re-evaluation storm.
    private func isRelevant(_ type: Int32) -> Bool {
        switch type {
        case RTM_NEWADDR, RTM_DELADDR, RTM_IFINFO, RTM_IFINFO2: true
        default: false
        }
    }

    private func scheduleEvaluation(_ onChange: @escaping @Sendable @MainActor () -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem { Task { @MainActor in onChange() } }
        pending = work
        queue.asyncAfter(deadline: .now() + Self.coalescingWindow, execute: work)
    }
}
