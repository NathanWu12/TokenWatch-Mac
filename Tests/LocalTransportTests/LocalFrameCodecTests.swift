import Foundation
import LocalTransport
import Testing

@Suite("Local transport framing")
struct LocalFrameCodecTests {
    @Test("round trips frames across arbitrary TCP chunks")
    func chunkedRoundTrip() throws {
        let first = Data("pairing".utf8)
        let second = Data(repeating: 0x5a, count: 513)
        let stream = try LocalFrameEncoder.encode(first)
            + LocalFrameEncoder.encode(second)
        var decoder = LocalFrameDecoder()
        var decoded: [Data] = []

        for byte in stream {
            decoded += try decoder.append(Data([byte]))
        }

        #expect(decoded == [first, second])
    }

    @Test("accepts multiple complete frames in one read")
    func coalescedFrames() throws {
        let payloads = [Data([1]), Data([2, 3]), Data([4, 5, 6])]
        let stream = try payloads.reduce(into: Data()) {
            $0.append(try LocalFrameEncoder.encode($1))
        }
        var decoder = LocalFrameDecoder()

        #expect(try decoder.append(stream) == payloads)
    }

    @Test("rejects empty, oversized and unbounded input")
    func rejectsInvalidInput() throws {
        #expect(throws: LocalFrameError.emptyFrame) {
            try LocalFrameEncoder.encode(Data())
        }
        #expect(throws: LocalFrameError.frameTooLarge) {
            try LocalFrameEncoder.encode(Data(repeating: 0, count: 9), maximumFrameSize: 8)
        }

        var oversized = LocalFrameDecoder(maximumFrameSize: 8)
        #expect(throws: LocalFrameError.frameTooLarge) {
            try oversized.append(Data([0, 0, 0, 9]))
        }

        var unbounded = LocalFrameDecoder(maximumFrameSize: 8)
        _ = try unbounded.append(Data([0, 0, 0, 8, 1, 2, 3, 4]))
        #expect(throws: LocalFrameError.bufferTooLarge) {
            try unbounded.append(Data(repeating: 5, count: 9))
        }
    }
}
