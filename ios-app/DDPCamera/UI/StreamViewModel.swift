import SwiftUI
import AVFoundation

enum Resolution: String, CaseIterable {
    case uhd4k  = "4K"
    case hd1080 = "1080p"
    case hd720  = "720p"

    var preset: AVCaptureSession.Preset {
        switch self {
        case .uhd4k:  return .hd4K3840x2160
        case .hd1080: return .hd1920x1080
        case .hd720:  return .hd1280x720
        }
    }

    var size: (width: Int32, height: Int32) {
        switch self {
        case .uhd4k:  return (3840, 2160)
        case .hd1080: return (1920, 1080)
        case .hd720:  return (1280, 720)
        }
    }

    // Bitrate base en Kbps para All-Intra (cada frame es keyframe = necesita mas bits)
    var baseBitrateKbps: Int32 {
        switch self {
        case .uhd4k:  return 120_000  // 120 Mbps
        case .hd1080: return 60_000   // 60 Mbps
        case .hd720:  return 30_000   // 30 Mbps
        }
    }
}

@MainActor
final class StreamViewModel: ObservableObject {
    @Published var host               = "192.168.1.1"
    @Published var port               = "5151"
    @Published var resolution         = Resolution.hd1080
    @Published var bitrateMultiplier  = 1.0
    @Published var isStreaming        = false
    @Published var stats              = ""

    private let camera   = CameraManager()
    private let encoder  = VideoEncoder()
    private let streamer = UDPStreamer()

    private var frameCount  = 0
    private var statsTimer: Timer?
    private let fps: Int32  = 60

    var cameraSession: AVCaptureSession { camera.session }

    // MARK: - Lifecycle

    func setup() {
        camera.configure(resolution: resolution.preset, fps: fps)
        camera.start()

        camera.onFrame = { [weak self] sampleBuffer in
            self?.encoder.encode(sampleBuffer)
        }

        encoder.onEncodedFrame = { [weak self] data in
            guard let self else { return }
            let size = self.resolution.size
            self.streamer.sendFrame(data,
                                    width:  UInt16(size.width),
                                    height: UInt16(size.height))
            self.frameCount += 1
        }
    }

    // MARK: - Stream control

    func startStream() {
        guard let portNum = UInt16(port) else { return }

        let bitrate = Int32(Double(resolution.baseBitrateKbps) * bitrateMultiplier)

        // Reconfigurar camara si cambio resolucion
        camera.stop()
        camera.configure(resolution: resolution.preset, fps: fps)
        camera.start()

        encoder.configure(
            width:        resolution.size.width,
            height:       resolution.size.height,
            fps:          fps,
            bitrateKbps:  bitrate
        )

        streamer.connect(host: host, port: portNum)

        // Handshake inicial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.streamer.sendHandshake(
                width:       UInt16(self.resolution.size.width),
                height:      UInt16(self.resolution.size.height),
                fps:         UInt8(self.fps),
                bitrateKbps: UInt32(bitrate)
            )
        }

        isStreaming = true
        startStatsTimer()
    }

    func stopStream() {
        streamer.disconnect()
        encoder.invalidate()
        isStreaming = false
        statsTimer?.invalidate()
        statsTimer = nil
        stats = ""
    }

    // MARK: - Stats

    private func startStatsTimer() {
        frameCount = 0
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.stats = "\(self.frameCount) fps"
                self.frameCount = 0
            }
        }
    }
}
