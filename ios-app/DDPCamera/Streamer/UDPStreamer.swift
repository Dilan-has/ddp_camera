import Foundation
import Network

final class UDPStreamer {
    private var connection: NWConnection?
    private var sequence:   UInt16 = 0
    private var frameId:    UInt32 = 0
    private let startTime:  UInt64 = currentMicroseconds()

    private(set) var isConnected = false

    // MARK: - Connect / Disconnect

    func connect(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        connection = NWConnection(to: endpoint, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
            case .failed, .cancelled:
                self?.isConnected = false
            default:
                break
            }
        }
        connection?.start(queue: .global(qos: .userInteractive))
    }

    func disconnect() {
        connection?.cancel()
        connection    = nil
        isConnected   = false
        sequence      = 0
        frameId       = 0
    }

    // MARK: - Send handshake

    func sendHandshake(width: UInt16, height: UInt16, fps: UInt8, bitrateKbps: UInt32) {
        let pkt = DDPProtocol.makeHandshake(
            sequence:    nextSequence(),
            timestampUs: timestamp(),
            width:       width,
            height:      height,
            fps:         fps,
            bitrateKbps: bitrateKbps
        )
        send(pkt)
    }

    // MARK: - Send video frame (fragmenta si es necesario)

    func sendFrame(_ data: Data, width: UInt16, height: UInt16) {
        let maxPayload = DDPProtocol.maxPayload
        let count      = max(1, (data.count + maxPayload - 1) / maxPayload)
        let ts         = timestamp()
        let fid        = nextFrameId()

        for i in 0 ..< count {
            let start   = i * maxPayload
            let end     = min(start + maxPayload, data.count)
            let payload = data[start ..< end]

            let pkt = DDPProtocol.makeVideoPacket(
                sequence:      nextSequence(),
                timestampUs:   ts,
                frameId:       fid,
                fragmentIndex: UInt16(i),
                fragmentCount: UInt16(count),
                width:         width,
                height:        height,
                payload:       payload
            )
            send(pkt)
        }
    }

    // MARK: - Private

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .idempotent)
    }

    private func nextSequence() -> UInt16 {
        defer { sequence &+= 1 }
        return sequence
    }

    private func nextFrameId() -> UInt32 {
        defer { frameId &+= 1 }
        return frameId
    }

    private func timestamp() -> UInt64 {
        currentMicroseconds() - startTime
    }
}

private func currentMicroseconds() -> UInt64 {
    var ts = timespec()
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts)
    return UInt64(ts.tv_sec) * 1_000_000 + UInt64(ts.tv_nsec) / 1_000
}
