import Foundation

public enum RegistryReader {
    /// Decodes every `<pid>.json` in the registry directory, skipping keys and malformed files.
    public static func read(dir: URL) -> [SessionRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let decoder = JSONDecoder()
        return names.compactMap { name -> SessionRecord? in
            guard name.hasSuffix(".json"),
                  !name.dropLast(5).isEmpty,
                  name.dropLast(5).allSatisfy(\.isNumber),
                  let data = FileManager.default.contents(atPath: dir.appendingPathComponent(name).path)
            else { return nil }
            return try? decoder.decode(SessionRecord.self, from: data)
        }
    }
}
