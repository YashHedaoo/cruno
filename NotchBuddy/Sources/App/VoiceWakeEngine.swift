@preconcurrency import AVFoundation
@preconcurrency import Speech

// MARK: - Voice phase

enum VoicePhase: Equatable {
    case idle
    case listening   // wake word heard, recording user query
    case thinking    // query sent to AI, waiting
    case responding  // streaming AI reply
}

// MARK: - Thread-safe audio buffer forwarder
//
// The AVAudioEngine tap callback runs on the audio render thread.
// VoiceWakeEngine is @MainActor, so its stored properties are main-thread-only.
// AudioForwarder holds the recognition requests under a lock so the audio thread
// can append buffers without ever touching @MainActor state.

private final class AudioForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var slideReq:   SFSpeechAudioBufferRecognitionRequest?
    private var captureReq: SFSpeechAudioBufferRecognitionRequest?

    func set(slide: SFSpeechAudioBufferRecognitionRequest?,
             capture: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock {
            slideReq   = slide
            captureReq = capture
        }
    }

    // Called from the audio render thread — no @MainActor access.
    func forward(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            slideReq?.append(buffer)
            captureReq?.append(buffer)
        }
    }
}

// MARK: - Wake engine

/// Always-on on-device speech engine.
///
/// Architecture:
///   • @MainActor owns logical state (requests, tasks, flags)
///   • `audioQ` (background serial queue) owns AVAudioEngine operations —
///     AVAudioEngine / CoreAudio assert they are NOT called on the main thread.
///   • AudioForwarder bridges the audio render thread to the recognition requests.
@MainActor
final class VoiceWakeEngine: NSObject {
    static let shared = VoiceWakeEngine()

    var onWake:         (() -> Void)?
    var onQuery:        ((String) -> Void)?
    var onPartialQuery: ((String) -> Void)?
    // @Sendable: captured by value into audioQ.async before the engine starts
    var onAudioLevel:   (@Sendable (Float) -> Void)?

    // Recognition state — @MainActor only
    private var recognizer:     SFSpeechRecognizer?
    private var slideRequest:   SFSpeechAudioBufferRecognitionRequest?
    private var slideTask:      SFSpeechRecognitionTask?
    private var captureRequest: SFSpeechAudioBufferRecognitionRequest?
    private var captureTask:    SFSpeechRecognitionTask?

    private var isRunning       = false
    private var isCapturing     = false
    private var slideTimer:     Timer?
    private var silenceTimer:   Timer?
    private var lastCapture     = ""
    private var cooldownUntil:  Date = .distantPast

    // Audio-engine state — only touched on audioQ
    private let audioQ    = DispatchQueue(label: "com.cruno.voice.audioengine", qos: .userInteractive)
    private let forwarder = AudioForwarder()
    // tapInstalled is written from @MainActor and audioQ under a lock
    private let tapLock   = NSLock()
    private var _tapInstalled = false
    // nonisolated(unsafe): exclusively accessed on audioQ; @MainActor class can't own it
    nonisolated(unsafe) private var audioEngine = AVAudioEngine()

    private var tapInstalled: Bool {
        get { tapLock.withLock { _tapInstalled } }
        set { tapLock.withLock { _tapInstalled = newValue } }
    }

    private static let wakeWords: Set<String> = [
        "cruno", "crono", "chrono", "kruno", "krono",
        "kronos", "chronos", "bruno", "pruno", "crudo",
        "curono", "colonel", "crone", "corona", "creno",
        "kru", "kuro", "corno", "bruna", "cruna"
    ]

    override private init() {
        super.init()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer?.defaultTaskHint = .unspecified
    }

    // MARK: - Permissions + start

    nonisolated func requestPermissionsAndStart() {
        DispatchQueue.main.async { [weak self] in
            guard AppState.shared.voiceEnabled else {
                self?.stop()
                return
            }
            self?.performPermissionsAndStart()
        }
    }

    private nonisolated func performPermissionsAndStart() {
        print("[Voice] Checking Speech & Microphone permissions...")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            print("[Voice] Speech recognition authorization status: \(status.rawValue)")
            guard status == .authorized else {
                print("[Voice] Speech recognition not authorized. Status: \(status.rawValue)")
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                print("[Voice] Microphone access granted: \(granted)")
                guard granted else { return }
                DispatchQueue.main.async {
                    guard AppState.shared.voiceEnabled else { return }
                    self?.isRunning = true
                    self?.startSlideWindow()
                }
            }
        }
    }

    func stop() {
        isRunning = false
        slideTimer?.invalidate();  slideTimer  = nil
        silenceTimer?.invalidate(); silenceTimer = nil
        teardownSlide()
        teardownCapture()
        let ae  = audioEngine
        let fwd = forwarder
        let alreadyInstalled = tapInstalled
        tapInstalled = false
        audioQ.async {
            if alreadyInstalled { ae.inputNode.removeTap(onBus: 0) }
            if ae.isRunning     { ae.stop() }
            fwd.set(slide: nil, capture: nil)
        }
    }

    // MARK: - Phase 1: sliding window

    private func startSlideWindow() {
        guard isRunning else { return }
        guard !isCapturing else { return }
        guard let recognizer, recognizer.isAvailable else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

        teardownSlide()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults  = true
        slideRequest = req
        forwarder.set(slide: req, capture: captureRequest)

        // SFSpeechRecognizer calls resultHandler on a background concurrent queue.
        // makeSlideHandler creates a nonisolated closure so Swift 6 does not inject
        // a @MainActor precondition check that crashes libdispatch.
        slideTask = recognizer.recognitionTask(with: req, resultHandler: Self.makeSlideHandler(for: self))

        installAndStartAudioEngine()

        slideTimer?.invalidate()
        slideTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, !self.isCapturing else { return }
                self.teardownSlide()
                self.startSlideWindow()
            }
        }
    }

    private nonisolated static func makeSlideHandler(for engine: VoiceWakeEngine) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        return { [weak engine] result, error in
            if let error {
                print("[Voice] Slide recognizer error: \(error.localizedDescription)")
            }
            let text = result?.bestTranscription.formattedString.lowercased()
            let isFinal = result?.isFinal ?? false
            let hasError = (error != nil)
            DispatchQueue.main.async {
                engine?.processSlideText(text: text, isFinal: isFinal, hasError: hasError)
            }
        }
    }

    private func processSlideText(text: String?, isFinal: Bool, hasError: Bool) {
        guard isRunning, !isCapturing else { return }
        if let text {
            print("[Voice] Hearing: \"\(text)\"")
            if contains(wakeWord: text) && Date() > cooldownUntil {
                print("[Voice] Wake word detected in: \"\(text)\"")
                handleWake()
                return
            }
        }
        if hasError || isFinal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.isRunning, !self.isCapturing else { return }
                self.startSlideWindow()
            }
        }
    }

    private func teardownSlide() {
        slideTimer?.invalidate(); slideTimer = nil
        slideRequest?.endAudio()
        slideTask?.cancel()
        slideRequest = nil
        slideTask    = nil
        forwarder.set(slide: nil, capture: captureRequest)
    }

    private func contains(wakeWord text: String) -> Bool {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        for t in tokens {
            if Self.wakeWords.contains(t) { return true }
            if t.hasPrefix("crun") || t.hasPrefix("krun") || t.hasPrefix("cron") {
                return true
            }
        }
        return false
    }

    // MARK: - Phase 2: utterance capture

    func startListeningNow() {
        if !isRunning {
            requestPermissionsAndStart()
        }
        handleWake()
    }

    private func handleWake() {
        guard isRunning, !isCapturing else { return }
        isCapturing   = true
        cooldownUntil = Date().addingTimeInterval(2.0)
        teardownSlide()
        onWake?()

        guard let recognizer, recognizer.isAvailable else {
            finishCapture(result: "")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults  = true
        req.taskHint = .dictation
        captureRequest = req
        forwarder.set(slide: slideRequest, capture: req)
        lastCapture = ""

        captureTask = recognizer.recognitionTask(with: req, resultHandler: Self.makeCaptureHandler(for: self))

        installAndStartAudioEngine()
        armSilenceTimer()
    }

    private nonisolated static func makeCaptureHandler(for engine: VoiceWakeEngine) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        return { [weak engine] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = (error != nil)
            DispatchQueue.main.async {
                engine?.processCaptureText(text: text, isFinal: isFinal, hasError: hasError)
            }
        }
    }

    private func processCaptureText(text: String?, isFinal: Bool, hasError: Bool) {
        guard isCapturing else { return }
        if let text {
            print("[Voice] Capturing: \"\(text)\"")
            lastCapture = strip(wakeWordFrom: text)
            onPartialQuery?(lastCapture)
            armSilenceTimer()
        }
        if hasError || isFinal {
            print("[Voice] Finished capturing query: \"\(lastCapture)\"")
            finishCapture(result: lastCapture)
        }
    }

    private func strip(wakeWordFrom text: String) -> String {
        var words = text.components(separatedBy: " ")
        if let first = words.first {
            let cleanedFirst = first.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if Self.wakeWords.contains(cleanedFirst) || cleanedFirst == "hey" {
                words.removeFirst()
                if let second = words.first {
                    let cleanedSecond = second.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    if Self.wakeWords.contains(cleanedSecond) {
                        words.removeFirst()
                    }
                }
            }
        }
        return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.finishCapture(result: self.lastCapture)
            }
        }
    }

    private func teardownCapture() {
        silenceTimer?.invalidate(); silenceTimer = nil
        captureRequest?.endAudio()
        captureTask?.cancel()
        captureRequest = nil
        captureTask    = nil
        isCapturing    = false
        forwarder.set(slide: slideRequest, capture: nil)
    }

    private func finishCapture(result: String) {
        teardownCapture()
        let query = result.trimmingCharacters(in: .whitespacesAndNewlines)
        onQuery?(query)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isRunning else { return }
            self.startSlideWindow()
        }
    }

    // MARK: - Audio engine (always on audioQ, never on main)

    private func installAndStartAudioEngine() {
        guard !tapInstalled else { return }
        tapInstalled = true  // mark before dispatch so concurrent calls don't double-install

        let ae  = audioEngine
        let fwd = forwarder
        let lvl = onAudioLevel   // capture value; safe — onAudioLevel is set once before start

        audioQ.async { [weak self] in
            // outputFormat must be called on a non-main thread (AVAudioEngine assertion)
            let node = ae.inputNode
            let fmt  = node.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0 else {
                // No valid audio device — reset flag on main
                DispatchQueue.main.async { self?.tapInstalled = false }
                return
            }

            // Tap closure ONLY touches AudioForwarder and does arithmetic.
            // No @MainActor state accessed here.
            node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, _ in
                fwd.forward(buffer)
                guard let ch = buffer.floatChannelData?[0] else { return }
                let n = Int(buffer.frameLength)
                guard n > 0 else { return }
                var rms: Float = 0
                for i in 0..<n { rms += ch[i] * ch[i] }
                let level = min(1.0, sqrtf(rms / Float(n)) * 20)
                DispatchQueue.main.async { lvl?(level) }
            }

            do    { try ae.start() }
            catch { DispatchQueue.main.async { self?.tapInstalled = false } }
        }
    }
}
