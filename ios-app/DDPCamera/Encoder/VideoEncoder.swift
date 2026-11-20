import Foundation
import VideoToolbox
import CoreMedia

final class VideoEncoder {
    var onEncodedFrame: ((Data) -> Void)?

    private var session:     VTCompressionSession?
    private var width:       Int32 = 0
    private var height:      Int32 = 0
    private var frameCount:  Int64 = 0

    // MARK: - Setup

    func configure(width: Int32, height: Int32, fps: Int32, bitrateKbps: Int32) {
        self.width  = width
        self.height = height
        self.frameCount = 0

        if session != nil { invalidate() }

        VTCompressionSessionCreate(
            allocator:                      nil,
            width:                          width,
            height:                         height,
            codecType:                      kCMVideoCodecType_H264,
            encoderSpecification:           nil,
            imageBufferAttributes:          nil,
            compressedDataAllocator:        nil,
            outputCallback:                 encoderOutputCallback,
            refcon:                         Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut:          &session
        )

        guard let s = session else { return }

        // --- Propiedades criticas para minima latencia ---

        // Real-time: el encoder prioriza latencia sobre calidad
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime,
                             value: kCFBooleanTrue)

        // Sin B-frames: cada frame se puede decodificar independientemente
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)

        // All-Intra: GOP = 1, cada frame es keyframe
        // Maxima latencia de decode = 0 frames de buffer
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: 1 as CFNumber)

        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: 0 as CFNumber)

        // Bitrate alto para maxima calidad (All-Intra necesita mas bits)
        let bitrate = bitrateKbps * 1000
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: bitrate as CFNumber)

        // Limitar variacion de bitrate (CBR-like para red estable)
        let dataRate = [bitrate * 2, 1] as CFArray  // max bytes por segundo
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: dataRate)

        // Perfil High para mejor compresion a igual bitrate
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)

        // FPS esperado — ayuda al encoder a asignar bits por frame
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: fps as CFNumber)

        VTCompressionSessionPrepareToEncodeFrames(s)
    }

    // MARK: - Encode

    func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let s = session,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dur = CMSampleBufferGetDuration(sampleBuffer)

        VTCompressionSessionEncodeFrame(
            s,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: dur,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    func invalidate() {
        guard let s = session else { return }
        VTCompressionSessionInvalidate(s)
        session = nil
    }
}

// MARK: - Output callback (C function)

private func encoderOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon:    UnsafeMutableRawPointer?,
    status:               OSStatus,
    infoFlags:            VTEncodeInfoFlags,
    sampleBuffer:         CMSampleBuffer?
) {
    guard status == noErr,
          let sampleBuffer,
          let refCon = outputCallbackRefCon
    else { return }

    let encoder = Unmanaged<VideoEncoder>.fromOpaque(refCon).takeUnretainedValue()
    encoder.handleEncodedSample(sampleBuffer)
}

extension VideoEncoder {
    fileprivate func handleEncodedSample(_ sampleBuffer: CMSampleBuffer) {
        // Extraer los NAL units con start codes (0x00 0x00 0x00 0x01)
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard let ptr = dataPointer else { return }

        var annexB = Data()

        // SPS / PPS en el primer keyframe
        if CMSampleBufferGetAttachments(sampleBuffer, createIfNecessary: false) != nil {
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
                appendParameterSets(from: format, to: &annexB)
            }
        }

        // Convertir formato AVCC (length-prefixed) a Annex B (start-code)
        var offset = 0
        while offset < totalLength {
            guard offset + 4 <= totalLength else { break }

            var nalLength: UInt32 = 0
            memcpy(&nalLength, ptr + offset, 4)
            nalLength = CFSwapInt32BigToHost(nalLength)

            offset += 4
            guard offset + Int(nalLength) <= totalLength else { break }

            // Start code
            annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            annexB.append(UnsafeBufferPointer(
                start: (ptr + offset).withMemoryRebound(to: UInt8.self, capacity: Int(nalLength)) { $0 },
                count: Int(nalLength)
            ))

            offset += Int(nalLength)
        }

        onEncodedFrame?(annexB)
    }

    private func appendParameterSets(from format: CMFormatDescription, to data: inout Data) {
        var spsCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: 0, parameterSetPointerOut: nil,
            parameterSetSizeOut: nil, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil
        )

        for i in 0 ..< spsCount {
            var psPointer: UnsafePointer<UInt8>?
            var psSize = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: i,
                parameterSetPointerOut: &psPointer,
                parameterSetSizeOut: &psSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            if let p = psPointer {
                data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                data.append(UnsafeBufferPointer(start: p, count: psSize))
            }
        }
    }
}
