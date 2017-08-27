
import UIKit
import AVFoundation
import CoreImage

class CaptureViewController: UIViewController {
    
    let cameraShutterSoundID: SystemSoundID = 1108
    //MARK: - Properties
    
    
    var sampleBufferQueue = DispatchQueue.global(qos: .userInitiated)
    
    lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        return session
    }()

    var previewLayer: AVCaptureVideoPreviewLayer?
    
    let ciContext = CIContext()
    
    lazy var rectDetector: CIDetector = {
           return CIDetector(ofType: CIDetectorTypeRectangle,
                              context: self.ciContext,
                              options: [CIDetectorAccuracy : CIDetectorAccuracyHigh
                             ])!
    }()
    
    lazy var boxLayer: CAShapeLayer = {
            let layer = CAShapeLayer()
            layer.backgroundColor = UIColor.clear.cgColor
            layer.cornerRadius = 8.0
            layer.isOpaque = false
            layer.opacity = 0
            layer.frame = self.view.bounds
            self.view.layer.addSublayer(layer)
            return layer
    }()
    
    var hideBoxTimer: Timer?
    
    var flashLayer: CALayer?
    
    //MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapView(_:)))
        view.addGestureRecognizer(tap)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            setupCaptureSession()
            
        } else {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { (authorized) in
                DispatchQueue.main.async {
                    if authorized {
                        self.setupCaptureSession()
                    }
                }
                
            })
        }
        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.bounds = view.frame
        
        
    }
    
    //MARK: - Actions
    @objc func didTapView(_ tap: UITapGestureRecognizer) {
        
        AudioServicesPlayAlertSound(cameraShutterSoundID)
        flashScreen()
        
        //save the photo
        
    }
    
    private func flashScreen() {
        let flash = CALayer()
        flash.frame = view.bounds
        flash.backgroundColor = UIColor.white.cgColor
        view.layer.addSublayer(flash)
        
        flash.opacity = 0

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0
        anim.toValue = 1
        anim.duration = 0.15
        anim.autoreverses = true
        anim.isRemovedOnCompletion = true
        anim.delegate = self
        
        flash.add(anim, forKey: "flashAnimation")
        
        self.flashLayer = flash
    }
    

    //MARK: - Rotation
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.portrait]
    }
    
    //MARK: - Camera Capture
    
    private func findCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            AVCaptureDevice.DeviceType.builtInDualCamera,
            .builtInTelephotoCamera,
            .builtInWideAngleCamera
        ]
        
        let discover = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
        
        return discover.devices.first
    }
    
    private func setupCaptureSession() {
        guard captureSession.inputs.isEmpty else { return }
        guard let camera = findCamera() else { return }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            captureSession.addInput(cameraInput)
            
            let preview = AVCaptureVideoPreviewLayer(session: captureSession)
            preview.frame = view.bounds
            preview.backgroundColor = UIColor.black.cgColor
            preview.videoGravity = .resizeAspect
            view.layer.addSublayer(preview)
            self.previewLayer = preview
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
            
            captureSession.addOutput(output)
            
            captureSession.startRunning()
            
        } catch  _ {
            //error
        }
        
        
        
        
        
    }
    
    private func displayQuad(points: (tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint)) {
            let path = UIBezierPath()
            path.move(to: points.tl)
            path.addLine(to: points.tr)
            path.addLine(to: points.br)
            path.addLine(to: points.bl)
            path.addLine(to: points.tl)
        
            boxLayer.strokeColor = UIColor.green.cgColor
        
            let cgPath = path.cgPath.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 0)
            boxLayer.path = cgPath
        
            boxLayer.opacity = 1

    }
    
    private func displayRect(rect: CGRect) {
        hideBoxTimer?.invalidate()

        boxLayer.frame = rect
        boxLayer.opacity = 1
        
        
        hideBoxTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false, block: { (timer) in
            self.boxLayer.opacity = 0
            timer.invalidate()
        })
    }
    
}

extension CaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
      
        let image = CIImage(cvImageBuffer: imageBuffer)
        for feature in rectDetector.features(in: image, options: nil) {
            guard let rectFeature = feature as? CIRectangleFeature else { continue }
         
            let imageWidth = image.extent.height
            let imageHeight = image.extent.width
            
            DispatchQueue.main.sync {
                let imageScale = min(view.frame.size.width / imageWidth,
                                     view.frame.size.height / imageHeight)
                
                let bl = CGPoint(x: rectFeature.topLeft.y * imageScale,
                                 y: rectFeature.topLeft.x * imageScale)
                let tl = CGPoint(x: rectFeature.topRight.y * imageScale,
                                 y: rectFeature.topRight.x * imageScale)
                
                let tr = CGPoint(x: rectFeature.bottomRight.y * imageScale,
                                 y: rectFeature.bottomRight.x * imageScale)
                
                let br = CGPoint(x: rectFeature.bottomLeft.y * imageScale,
                                 y: rectFeature.bottomLeft.x * imageScale)
                
                
                self.displayQuad(points: (tl: tl, tr: tr, br: br, bl: bl))
                
            }
        }
        
    }
}

extension CaptureViewController: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        flashLayer?.removeFromSuperlayer()
        flashLayer = nil
    }
}
