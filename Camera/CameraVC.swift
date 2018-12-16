//
//  CameraVC.swift
//  Camera
//
//  Created by mac-226 on 10/15/18.
//  Copyright © 2018 HeyMan. All rights reserved.
//

import UIKit
import AVKit
import Vision

class CameraVC: UIViewController {
 
    @IBOutlet weak var cameraView: UIView!
    
    var cameraLayer: AVCaptureVideoPreviewLayer!
    var captureSession: AVCaptureSession!
    let outputProcessingQueue = DispatchQueue(label: "outputProcessingQueue")
    var displayedRects = [CALayer]()
    var boundingRects = [CALayer]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        checkPermissions()
        cameraAccessSetup()
        setupLayer()
        setupOutput()
        captureSession.startRunning()
//        setupVision()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    // ******************************* MARK: - Camera
    
    func setupOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: outputProcessingQueue)
        self.captureSession.addOutput(videoOutput)
    }
    
    func setupLayer() {
        cameraLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        cameraLayer?.frame = cameraView.layer.bounds
//        cameraLayer.videoGravity = .resize
        cameraView.layer.addSublayer(cameraLayer!)
    }
    
    func cameraAccessSetup() {
        let session = AVCaptureSession()
        
        guard let camera = getCameraDevice() else {
            print("can't get camera device")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                self.captureSession = session
            } else {
                print("session.canAddInput(\(input)) = false ")
            }
        } catch {
            print("can't get camera input \(error)")
        }
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in })
        default:
            print("idi nahui")
        }
    }
    
    func getCameraDevice() -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) { return device }
        else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) { return device }
        else { return nil }
    }
    
    // ******************************* MARK: - Vision

    
    func processObservationsWithDrawingBox(_ results: [VNRectangleObservation]) {
        displayedRects.forEach { $0.removeFromSuperlayer() }
        boundingRects.forEach { $0.removeFromSuperlayer() }
        
        results.forEach {
            
            
            let rect = drawRect(for: $0, on: cameraView)
            displayedRects.append(rect)
        }
    }
    

    
    func drawRect(for observation: VNRectangleObservation, on view: UIView) -> CALayer {
        let points = transform(observation: observation, toRectOf: cameraLayer)
        let rwPath = UIBezierPath()
        let rectLayer = CAShapeLayer()
        rwPath.move(to: points.first!)
        points.dropFirst().forEach { rwPath.addLine(to: $0) }
//        rwPath.addLine(to: points.first!)
        rwPath.close()
        rectLayer.fillColor = lightYellow
        rectLayer.path = rwPath.cgPath
//        rectLayer.strokeColor = UIColor.red.cgColor
//        rectLayer.lineWidth = 1.0
        view.layer.addSublayer(rectLayer)
        return rectLayer
    }
    
    let lightYellow = UIColor.yellow.withAlphaComponent(0.4).cgColor
    func drawBoundingBox(for observation: VNDetectedObjectObservation, on view: UIView) -> CALayer {
        
        var transformedRect = observation.boundingBox
        transformedRect.origin.y = 1 - (transformedRect.origin.y + transformedRect.height)
        
        let uiKitFrame = cameraLayer.layerRectConverted(fromMetadataOutputRect: transformedRect)
        let rectLayer = CALayer()
        
        
        rectLayer.borderColor = UIColor.blue.cgColor
        rectLayer.borderWidth = 1
        rectLayer.backgroundColor = lightYellow
        rectLayer.frame = uiKitFrame
        
        view.layer.addSublayer(rectLayer)
        return rectLayer
    }
    
    private func transform(observation: VNRectangleObservation, toRectOf layer: AVCaptureVideoPreviewLayer) -> [CGPoint] {
        var observationPoints = [CGPoint]()
        observationPoints = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
        let foundationCoordinatedObservationPoints = observationPoints.map { CGPoint(x: $0.x, y: 1 - $0.y) }
        let uiKitCoordinatedObservationPoints = foundationCoordinatedObservationPoints.map { layer.layerPointConverted(fromCaptureDevicePoint: $0) }
        return uiKitCoordinatedObservationPoints
    }
    
    var displayedObservations = [CALayer]()
    
    func showTrackingResults(_ observations: [VNRectangleObservation]) {
        DispatchQueue.main.async { [unowned self] in
            let viewForDisplay = self.cameraView!
            self.displayedObservations.forEach { $0.removeFromSuperlayer() }
            self.displayedObservations = observations.map { self.drawRect(for: $0, on: viewForDisplay) }
//            self.view.backgroundColor = .white
        }
    }
    var trackingHandler = VNSequenceRequestHandler()
    
    var needTrackObservationsAsap = false
    
    func processTrackingRequests(cvPixelBuffer: CVPixelBuffer) {
        guard !observationsToTrack.isEmpty else { return }
        
        let trackingRequestsArray = observationsToTrack.map { obsrervation -> VNTrackRectangleRequest in
            let request: VNTrackRectangleRequest = VNTrackRectangleRequest(rectangleObservation: obsrervation)
//            request.trackingLevel = .accurate
            return request
        }//(VNTrackRectangleRequest.init(rectangleObservation: ))
        do {
            try trackingHandler.perform(trackingRequestsArray, on: cvPixelBuffer)
        } catch {
          let er = error
          print(er)
            print("trackingHandler fails trackingRequests, error: \(error.localizedDescription)")
            needTrackObservationsAsap = true
            trackingObservations = [:]
            observationsToTrack = []
            trackingHandler = VNSequenceRequestHandler()
            DispatchQueue.main.async {
                self.displayedObservations.forEach { $0.removeFromSuperlayer() }
//                self.view.backgroundColor = .gray
            }
            return
        }
        let trackResults = trackingRequestsArray
            .compactMap { request -> VNRectangleObservation? in
                print("tracking request found results: \(request.results?.count ?? -1)")
                return request.results?.first as? VNRectangleObservation
            }
            .filter { $0.confidence >= 0.6 }
        
        observationsToTrack = trackResults
        
        
        print("got tracking update for: \(trackResults.shortContent())")
        showTrackingResults(trackResults)
    }
    
    
    let searchNewRectangleRequest: VNDetectRectanglesRequest = { let a = VNDetectRectanglesRequest();
        a.maximumObservations = 0;
        a.minimumConfidence = 0.6
        return a
    }()
    var trackingObservations: [UUID: VNRectangleObservation] = [:]
    
    var observationsToTrack: [VNRectangleObservation] = []
    
    func checkForNewRectangles(cvPixelBuffer: CVPixelBuffer) {
        let newRectanglesRequestHandler = VNImageRequestHandler(cvPixelBuffer: cvPixelBuffer, options: [:])
        do {
            try newRectanglesRequestHandler.perform([searchNewRectangleRequest])
        } catch {
            print("newRectanglesRequestHandler fails searchNewRectangleRequest, error: \(error)")
        }
        guard let results = searchNewRectangleRequest.results as? [VNRectangleObservation],
            !results.isEmpty else {
                return
        }
        needTrackObservationsAsap = false

        let newObservations = results
        
        newObservations
            .forEach { notTrackedObservation in
                trackingObservations[notTrackedObservation.uuid] = notTrackedObservation
        }
        
        print("setting new observations to track: \(newObservations.shortContent())")
        observationsToTrack = results
        
    }
    
    var newRectanglesSearchDate: Date = Date(timeIntervalSince1970: 0)
}


extension CameraVC: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let currDate = Date()
        let needNewRectangleSearch = currDate.timeIntervalSince(newRectanglesSearchDate) > 1.0
        
        
        if needNewRectangleSearch || needTrackObservationsAsap {
            if needTrackObservationsAsap && !needNewRectangleSearch { print("checkForNewRects because of needTrackObservationsAsap") }
            
            newRectanglesSearchDate = currDate
            checkForNewRectangles(cvPixelBuffer: pixelBuffer)
            trackingHandler = VNSequenceRequestHandler()
        }
        processTrackingRequests(cvPixelBuffer: pixelBuffer)
    }
}


extension UUID {
    var last4: String {
        return String(uuidString.suffix(4))
    }
}

extension Collection where Element == VNRectangleObservation {
    func shortContent() -> String {
        return map { $0.uuid }.shortContent()
    }
}

extension Collection where Element == UUID {
    func shortContent() -> String {
        return "\(map{ $0.last4 })"
    }
}
