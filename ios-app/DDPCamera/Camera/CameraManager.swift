import AVFoundation
import CoreMedia

final class CameraManager: NSObject {
    var onFrame: ((CMSampleBuffer) -> Void)?

    let session              = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private let queue       = DispatchQueue(label: "ddp.camera", qos: .userInteractive)

    var currentResolution: (width: Int32, height: Int32) = (1920, 1080)

    // MARK: - Setup

    func configure(resolution: AVCaptureSession.Preset = .hd1920x1080, fps: Int32 = 60) {
        session.beginConfiguration()
        session.sessionPreset = resolution

        currentResolution = resolutionFor(preset: resolution)

        // Input — camara trasera por defecto (mejor calidad)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video, position: .back),
              let input  = try? AVCaptureDeviceInput(device: device)
        else { return }

        if session.canAddInput(input) { session.addInput(input) }

        // FPS maximo
        configureFPS(device: device, fps: fps)

        // Output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true  // nunca acumular frames
        videoOutput.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Orientacion
        if let conn = videoOutput.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(0) {
                conn.videoRotationAngle = 0  // landscape
            }
        }

        session.commitConfiguration()
    }

    func start() { session.startRunning() }
    func stop()  { session.stopRunning()  }

    // MARK: - Private

    private func configureFPS(device: AVCaptureDevice, fps: Int32) {
        guard let range = device.activeFormat.videoSupportedFrameRateRanges
            .first(where: { $0.maxFrameRate >= Double(fps) })
        else { return }

        try? device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        device.unlockForConfiguration()
        _ = range  // silencia warning
    }

    private func resolutionFor(preset: AVCaptureSession.Preset) -> (Int32, Int32) {
        switch preset {
        case .hd4K3840x2160: return (3840, 2160)
        case .hd1920x1080:   return (1920, 1080)
        case .hd1280x720:    return (1280, 720)
        default:             return (1920, 1080)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection)
    {
        onFrame?(sampleBuffer)
    }
}
