import Foundation

public enum LocalFrameError: Error, Equatable, Sendable {
    case emptyFrame
    case frameTooLarge
    case bufferTooLarge
}

/// Length-prefixed framing for the authenticated Bonjour TCP channel.
///
/// A frame is a four-byte big-endian payload length followed by that payload.
/// The decoder accepts arbitrary TCP chunk boundaries and rejects unbounded input.
public struct LocalFrameDecoder: Sendable {
    public static let defaultMaximumFrameSize = 1_048_576

    private var buffer = Data()
    private let maximumFrameSize: Int

    public init(maximumFrameSize: Int = Self.defaultMaximumFrameSize) {
        self.maximumFrameSize = maximumFrameSize
    }

    public mutating func append(_ data: Data) throws -> [Data] {
        guard buffer.count <= maximumFrameSize + 4 - data.count else {
            throw LocalFrameError.bufferTooLarge
        }
        buffer.append(data)

        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) {
                ($0 << 8) | Int($1)
            }
            guard length > 0 else {
                throw LocalFrameError.emptyFrame
            }
            guard length <= maximumFrameSize else {
                throw LocalFrameError.frameTooLarge
            }
            guard buffer.count >= length + 4 else { break }
            frames.append(buffer.subdata(in: 4..<(length + 4)))
            buffer.removeSubrange(0..<(length + 4))
        }
        return frames
    }
}

public enum LocalFrameEncoder {
    public static func encode(
        _ payload: Data,
        maximumFrameSize: Int = LocalFrameDecoder.defaultMaximumFrameSize
    ) throws -> Data {
        guard !payload.isEmpty else {
            throw LocalFrameError.emptyFrame
        }
        guard payload.count <= maximumFrameSize,
              payload.count <= Int(UInt32.max) else {
            throw LocalFrameError.frameTooLarge
        }
        let length = UInt32(payload.count)
        var frame = Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
        ])
        frame.append(payload)
        return frame
    }
}
