import Foundation

// Espejo del protocol/packet.h en Swift
enum DDPProtocol {
    static let version:     UInt8  = 1
    static let defaultPort: UInt16 = 5151
    static let maxPayload:  Int    = 65000

    enum PacketType: UInt8 {
        case video     = 0x01
        case handshake = 0x02
        case keepalive = 0x03
    }

    // 12 bytes
    struct Header {
        var version:     UInt8
        var packetType:  UInt8
        var sequence:    UInt16
        var timestampUs: UInt64

        func toData() -> Data {
            var d = Data(count: 12)
            d[0] = version
            d[1] = packetType
            d.storeLE(sequence,    at: 2)
            d.storeLE(timestampUs, at: 4)
            return d
        }
    }

    // Header (12) + frame_id(4) + frag_index(2) + frag_count(2) + w(2) + h(2) + payload_size(4) = 28 bytes
    static let videoHeaderSize = 28

    static func makeVideoPacket(
        sequence:      UInt16,
        timestampUs:   UInt64,
        frameId:       UInt32,
        fragmentIndex: UInt16,
        fragmentCount: UInt16,
        width:         UInt16,
        height:        UInt16,
        payload:       Data
    ) -> Data {
        var pkt = Data(count: videoHeaderSize + payload.count)
        pkt[0]  = version
        pkt[1]  = PacketType.video.rawValue
        pkt.storeLE(sequence,      at: 2)
        pkt.storeLE(timestampUs,   at: 4)
        pkt.storeLE(frameId,       at: 12)
        pkt.storeLE(fragmentIndex, at: 16)
        pkt.storeLE(fragmentCount, at: 18)
        pkt.storeLE(width,         at: 20)
        pkt.storeLE(height,        at: 22)
        pkt.storeLE(UInt32(payload.count), at: 24)
        pkt.replaceSubrange(videoHeaderSize..., with: payload)
        return pkt
    }

    static func makeHandshake(
        sequence:    UInt16,
        timestampUs: UInt64,
        width:       UInt16,
        height:      UInt16,
        fps:         UInt8,
        bitrateKbps: UInt32
    ) -> Data {
        // Header(12) + w(2) + h(2) + fps(1) + bitrate(4) = 21 bytes
        var pkt = Data(count: 21)
        pkt[0]  = version
        pkt[1]  = PacketType.handshake.rawValue
        pkt.storeLE(sequence,    at: 2)
        pkt.storeLE(timestampUs, at: 4)
        pkt.storeLE(width,       at: 12)
        pkt.storeLE(height,      at: 14)
        pkt[16] = fps
        pkt.storeLE(bitrateKbps, at: 17)
        return pkt
    }
}

// Helpers para escribir little-endian en Data
private extension Data {
    mutating func storeLE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { src in
            replaceSubrange(offset ..< offset + MemoryLayout<T>.size, with: src)
        }
    }
}
