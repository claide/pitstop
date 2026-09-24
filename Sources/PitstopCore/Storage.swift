import Foundation

public enum PitstopPaths {
    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Pitstop", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public static var accounts: URL { supportDir.appendingPathComponent("accounts.json") }
    public static var snapshot: URL { supportDir.appendingPathComponent("snapshot.json") }
    public static var tickets: URL { supportDir.appendingPathComponent("tickets.jsonl") }
    public static var estimateTable: URL { supportDir.appendingPathComponent("estimate-table.json") }
}

public enum PitstopJSON {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    public static var lineEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

public enum AccountStore {
    public static let defaultAccounts: [Account] = [
        Account(id: "claude-personal", name: "Personal", provider: .claude),
        Account(id: "codex-personal", name: "Personal", provider: .codex),
    ]

    /// Loads accounts.json, creating it with defaults the first time.
    /// A broken file is never overwritten: defaults are used in memory and `problem` says why.
    public static func load() -> (accounts: [Account], problem: String?) {
        let url = PitstopPaths.accounts
        guard FileManager.default.fileExists(atPath: url.path) else {
            if let data = try? PitstopJSON.encoder.encode(defaultAccounts) {
                try? data.write(to: url, options: .atomic)
            }
            return (defaultAccounts, nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return (try JSONDecoder().decode([Account].self, from: data), nil)
        } catch {
            return (defaultAccounts, "accounts.json couldn't be read (\(error.localizedDescription)). Using default accounts.")
        }
    }
}

public enum SnapshotFile {
    public static func write(_ snapshots: [AccountSnapshot]) {
        guard let data = try? PitstopJSON.encoder.encode(snapshots) else { return }
        try? data.write(to: PitstopPaths.snapshot, options: .atomic)
    }

    public static func read() -> [AccountSnapshot]? {
        guard let data = try? Data(contentsOf: PitstopPaths.snapshot) else { return nil }
        return try? PitstopJSON.decoder.decode([AccountSnapshot].self, from: data)
    }
}
