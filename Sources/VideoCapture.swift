import UIKit
import AVFoundation
import CoreVideo

public protocol VideoCaptureDelegate: class {
    func videoCapture(_ capture: VideoCapture,
                      didCapturePixelBuffer pixelBuffer: CVPixelBuffer,
                      timestamp: CMTime)
}

final public class VideoCapture: NSObject {

    public typealias VideoCaptureSetupCompletion = (Result<(), Swift.Error>) -> Void

    public enum Error: Swift.Error, LocalizedError {
        case noVideoDevicesAvailable
        case couldNotCreateAVCaptureDeviceInput

        public var errorDescription: String? {
            switch self {
                case .noVideoDevicesAvailable:
                    return "No video devices available"
                case .couldNotCreateAVCaptureDeviceInput:
                    return "Could not create AVCaptureDeviceInput"
            }
        }
    }

    public enum CameraPosition {
        case front
        case back
    }

    public weak var delegate: VideoCaptureDelegate?
    private var captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.eugenebokhan.video",
                                      qos: .userInteractive)
    
    public func setup(sessionPreset: AVCaptureSession.Preset = .high,
                      desiredFrameRate: Int = 30,
                      position: CameraPosition = .front,
                      completion: @escaping VideoCaptureSetupCompletion) {
        self.queue.async {
            do {
                try self.setupCamera(sessionPreset: sessionPreset,
                                     desiredFrameRate: desiredFrameRate,
                                     position: position)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func setupCamera(sessionPreset: AVCaptureSession.Preset,
                     desiredFrameRate: Int,
                     position: CameraPosition) throws {
        self.captureSession = .init()
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = sessionPreset

        var defaultVideoDevice: AVCaptureDevice?
        switch position {
        case .back:
            print("back")
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera,
                                                              for: .video, 
                                                              position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                                     for: .video,
                                                                     position: .back) {
                // If a rear dual camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            }
        case .front:
            print("front")
            defaultVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                         for: .video,
                                                         position: .front)
        }

        guard let captureDevice = defaultVideoDevice
        else { throw Error.noVideoDevicesAvailable }

        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice)
        else { throw Error.couldNotCreateAVCaptureDeviceInput }
        
        if self.captureSession.canAddInput(videoInput) {
            self.captureSession.addInput(videoInput)
        }

        let settings: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
        ]

        self.videoOutput.videoSettings = settings
        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
        if self.captureSession.canAddOutput(self.videoOutput) {
            self.captureSession.addOutput(self.videoOutput)
        }

        self.videoOutput
            .connection(with: AVMediaType.video)?
            .videoOrientation = .portrait

        let activeDimensions = CMVideoFormatDescriptionGetDimensions(captureDevice.activeFormat.formatDescription)
        for videoFormat in captureDevice.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(videoFormat.formatDescription)
            let ranges = videoFormat.videoSupportedFrameRateRanges as [AVFrameRateRange]
            guard let frameRate = ranges.first,
                      frameRate.maxFrameRate >= .init(desiredFrameRate) &&
                      frameRate.minFrameRate <= .init(desiredFrameRate) &&
                      activeDimensions.width == dimensions.width &&
                      activeDimensions.height == dimensions.height &&
                      CMFormatDescriptionGetMediaSubType(videoFormat.formatDescription) == 875704422 // full range 420f
            else { continue }

            do {
                try captureDevice.lockForConfiguration()
                captureDevice.activeFormat = videoFormat as AVCaptureDevice.Format
                captureDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1,
                                                                       timescale: .init(desiredFrameRate))
                captureDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1,
                                                                       timescale: .init(desiredFrameRate))
                captureDevice.unlockForConfiguration()
            } catch { continue }
        }
        #if DEBUG
        print("Camera format:", captureDevice.activeFormat)
        #endif

        self.captureSession.commitConfiguration()
    }

    public func start() {
        if !self.captureSession.isRunning {
            self.captureSession.startRunning()
        }
    }

    public func stop() {
        if self.captureSession.isRunning {
            self.captureSession.stopRunning()
        }
    }

}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        self.delegate?.videoCapture(self,
                                    didCapturePixelBuffer: imageBuffer,
                                    timestamp: timestamp)
    }

    public func captureOutput(_ output: AVCaptureOutput,
                              didDrop sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        #if DEBUG
        print("Did drop frame")
        #endif
    }
}
