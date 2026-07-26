import Foundation

/// Short descriptions for ports a Mac commonly listens on, and the baseline of
/// services macOS starts by itself.
public enum WellKnownPorts {
    /// A human-readable note for a port, used where no process name is
    /// available — which is precisely the case where a bare number tells the
    /// user nothing and a dismissal would be a guess.
    public static func description(of port: UInt16) -> String? {
        switch port {
        case 22: "SSH — Remote Login"
        case 53: "DNS"
        case 88: "Kerberos"
        case 111: "RPC portmapper"
        case 137, 138, 139, 445: "SMB file sharing"
        case 311: "Server admin"
        case 548: "AFP file sharing"
        case 631: "CUPS printing"
        case 2049: "NFS"
        case 3283: "Apple Remote Desktop"
        case 5000, 7000: "AirPlay receiver"
        case 5432: "PostgreSQL"
        case 5900: "Screen Sharing (VNC)"
        case 6379: "Redis"
        case 3306: "MySQL"
        case 8000, 8080, 3000: "HTTP (development)"
        case 27017: "MongoDB"
        case 62078: "iOS device sync"
        // Below 1024 a port is reserved and can only be bound by root, so even
        // without knowing the service the user learns something: a privileged
        // process opened it. Above that, a bare number really says nothing.
        case ..<1024: "System service (privileged port)"
        default: nil
        }
    }
}

/// The listeners macOS starts on its own behalf.
///
/// Auto-dismissing anything is a deliberate blind spot, so the line is drawn at
/// services the operating system manages and the user did not switch on. NFS,
/// RPC, SMB and SSH are all things somebody enabled, so they stay visible even
/// though they are "well known".
public enum SystemServiceBaseline {
    /// Matched on process name, which survives the ports these rotate through.
    public static let processes: Set<String> = [
        "ControlCenter",        // AirPlay receiver, 5000 and 7000
        "rapportd",             // Continuity, Handoff, Universal Control
        "sharingd",             // AirDrop and Handoff transport
        "AirPlayXPCHelper",
        "remotepairingdeviced", // developer device pairing
        "identityservicesd",    // iMessage and FaceTime
    ]

    public static var keys: Set<ListenerKey> {
        Set(processes.map(ListenerKey.process))
    }

    public static func covers(_ listener: ListeningSocket) -> Bool {
        guard let process = listener.process else { return false }
        return processes.contains(process)
    }
}
