import CryptoKit
import Darwin
import Foundation
import zlib

/// The official Usage response already saved by Claude Desktop for the tray's organization.
/// Chromium's Simple Cache format is private. Open only known keys and skip its HTTP metadata.
enum ClaudeUsageCache {
    struct Sample: Equatable {
        let time: Date
        let fable: ClaudeLocalCalibration.Reading?
    }

    static func latest(in directory: URL, organization: String, at now: Date, previous: Sample?) -> Sample? {
        guard let org = UUID(uuidString: organization) else { return nil }
        let base = "1/0/https://claude.ai/api/organizations/" + org.uuidString.lowercased() + "/usage"
        var newest = previous.flatMap { $0.time <= now ? $0 : nil }
        for suffix in ["?skip_spend=1", "", "?cedar_ember=1&skip_spend=1"] {
            let key = Data((base + suffix).utf8)
            // Chromium names the file using the first eight SHA-1 bytes as a little-endian integer.
            let name = Insecure.SHA1.hash(data: key).prefix(8).reversed().map { String(format: "%02x", $0) }.joined() + "_0"
            guard let body = responseBody(in: directory.appendingPathComponent(name), key: key),
                  let sample = parse(body, at: now) else { continue }
            if let current = newest {
                if current.time > sample.time { continue }
                if current.time == sample.time && current != sample {
                    newest = Sample(time: current.time, fable: nil)
                    continue
                }
            }
            newest = sample
        }
        return newest
    }

    private static func parse(_ data: Data, at now: Date) -> Sample? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let breakdown = root["seven_day_breakdown"] as? [String: Any], let stamp = breakdown["as_of"] as? String,
              let time = ProviderQuotaSnapshot.date(stamp), time <= now,
              let rows = root["limits"] as? [[String: Any]], rows.count <= 64 else { return nil }
        let models = rows.filter { ClaudeQuotaClient.scopedModelKey($0) == "seven_day_fable" }
        guard !models.isEmpty else { return Sample(time: time, fable: nil) }
        guard models.count == 1, let window = ClaudeQuotaClient.scopedWindow(models[0]) else { return nil }
        guard let reset = window.resetsAt else {
            return window.notStarted ? Sample(time: time, fable: nil) : nil
        }
        let reading = ClaudeLocalCalibration.Reading(used: min(100, window.used), time: time, reset: reset)
        return reading.isInCycle(at: time) ? Sample(time: time, fable: reading) : nil
    }

    private static let bodyLimit = 256 * 1024

    private static func responseBody(in url: URL, key: Data) -> Data? {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 72 + key.count, info.st_size <= 512 * 1024 else { return nil }
        let size = Int(info.st_size)
        func read(_ offset: Int, _ count: Int) -> Data? {
            guard offset >= 0, count > 0, offset <= size - count else { return nil }
            do {
                try file.seek(toOffset: UInt64(offset))
                guard let bytes = try file.read(upToCount: count), bytes.count == count else { return nil }
                return bytes
            } catch { return nil }
        }
        // SimpleFileHeader and both SimpleFileEOF records are 24 bytes on disk (format version 5).
        let recordSize = 24
        let eofMagic: UInt64 = 0xf4fa6f45970d41d8
        guard let header = read(0, recordSize), header.uint64(at: 0) == 0xfcfb6d1ba7725c30,
              header.uint32(at: 8) == 5, header.uint32(at: 12) == key.count,
              read(recordSize, key.count) == key,
              let footer = read(size - recordSize, recordSize), footer.uint64(at: 0) == eofMagic else { return nil }
        let flags = footer.uint32(at: 8)
        guard flags & ~3 == 0 else { return nil }
        let hashOffset = size - recordSize - (flags & 2 == 0 ? 0 : 32)
        if flags & 2 != 0, read(hashOffset, 32) != Data(SHA256.hash(data: key)) { return nil }
        let bodyEnd = hashOffset - Int(footer.uint32(at: 16)) - recordSize
        let bodyStart = recordSize + key.count
        let length = bodyEnd - bodyStart
        guard (1...bodyLimit).contains(length), let end = read(bodyEnd, recordSize), end.uint64(at: 0) == eofMagic,
              end.uint32(at: 8) & ~1 == 0, let body = read(bodyStart, length) else { return nil }
        if end.uint32(at: 8) & 1 != 0 {
            let actual = body.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(length)) }
            guard actual == end.uint32(at: 12) else { return nil }
        }
        if body.starts(with: [0x28, 0xb5, 0x2f, 0xfd]) {
            #if CODEX_BATTERY_ZSTD
            return body.withUnsafeBytes { encoded in
                guard ZSTD_findFrameCompressedSize(encoded.baseAddress, length) == length else { return nil }
                let declared = ZSTD_getFrameContentSize(encoded.baseAddress, length)
                let capacity = declared == UInt64.max ? UInt64(bodyLimit) : declared
                guard capacity > 0, capacity <= UInt64(bodyLimit) else { return nil }
                var decoded = Data(count: Int(capacity))
                let count = decoded.withUnsafeMutableBytes {
                    ZSTD_decompress($0.baseAddress, $0.count, encoded.baseAddress, length)
                }
                guard ZSTD_isError(count) == 0, count > 0, count <= capacity else { return nil }
                decoded.count = count
                return decoded
            }
            #else
            return nil
            #endif
        }
        return body
    }
}

private extension Data {
    // Callers supply fixed, length-checked header/footer records.
    func uint32(at offset: Int) -> UInt32 {
        withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    func uint64(at offset: Int) -> UInt64 {
        withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }
}
