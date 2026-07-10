import AVFoundation
import Foundation

@MainActor
final class QuakeAudioService: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var stopTimer: Timer?
    private(set) var lastRecordingURL: URL?
    var isRecording: Bool { recorder?.isRecording == true }

    var capturePermissionDescription: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not determined"
        @unknown default: return "unknown"
        }
    }

    nonisolated func requestCapturePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startMeetingClip(duration: TimeInterval = 30) throws -> URL {
        stopTimer?.invalidate()
        recorder?.stop()

        let directory = try recordingsDirectory()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("meeting-\(stamp).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AudioError.recordingDidNotStart
        }

        self.recorder = recorder
        self.lastRecordingURL = url
        stopTimer = Timer.scheduledTimer(withTimeInterval: max(1, duration), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
        return url
    }

    func stopRecording() {
        stopTimer?.invalidate()
        stopTimer = nil
        recorder?.stop()
        recorder = nil
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    private func recordingsDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("QuakeKit/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    enum AudioError: Error, CustomStringConvertible {
        case recordingDidNotStart

        var description: String {
            switch self {
            case .recordingDidNotStart:
                return "Audio recording did not start."
            }
        }
    }
}
