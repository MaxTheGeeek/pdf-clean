import Foundation

#if os(macOS)
    import Darwin
#endif

/// Writes sanitised text to disk: UTF-8, no BOM, atomic; then on macOS strips every
/// extended attribute (tech spec §6.11), ignoring `EPERM`.
public struct CleanFileWriter: Sendable {
    /// Creates a writer.
    public init() {}

    /// Writes `text` to `url` as UTF-8 with no byte-order mark, atomically.
    public func write(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
        #if os(macOS)
            stripExtendedAttributes(at: url)
        #endif
    }

    #if os(macOS)
        private func stripExtendedAttributes(at url: URL) {
            let path = url.path
            let bufferSize = listxattr(path, nil, 0, 0)
            guard bufferSize > 0 else { return }

            var buffer = [CChar](repeating: 0, count: bufferSize)
            let actualSize = listxattr(path, &buffer, bufferSize, 0)
            guard actualSize > 0 else { return }

            var removedCount = 0
            buffer.withUnsafeBufferPointer { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var offset = 0
                while offset < actualSize {
                    let namePointer = base + offset
                    let name = String(cString: namePointer)
                    offset += name.utf8.count + 1
                    // removexattr fails with EPERM on some protected attributes; ignored —
                    // the write itself already succeeded, this cleanup is best-effort.
                    if removexattr(path, name, 0) == 0 {
                        removedCount += 1
                    }
                }
            }
            Log.event("writer.xattrsRemoved", ("count", removedCount))
        }
    #endif
}
