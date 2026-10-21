import Foundation

// MARK: - Voice coordinator

/// Wires VoiceWakeEngine → AppState → AI call → auto-dismiss.
/// Single source of truth for the voice assistant lifecycle.
@MainActor
final class VoiceCoordinator {
    static let shared = VoiceCoordinator()

    private var autoCloseTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?

    private init() {}

    // MARK: - Setup (called once at launch)

    func setup() {
        let wake = VoiceWakeEngine.shared
        // onWake / onQuery are always called on @MainActor (from handleWake / finishCapture),
        // but their types are plain closures so we hop via Task to satisfy Swift 6.
        wake.onWake = { Task { @MainActor [weak self] in self?.handleWake() } }
        wake.onQuery = { text in Task { @MainActor [weak self] in self?.handleQuery(text) } }
        wake.onPartialQuery = { text in
            MainActor.assumeIsolated {
                AppState.shared.voiceTranscript = text
            }
        }
        // onAudioLevel is called on the main queue (DispatchQueue.main.async in the tap).
        // Accessing AppState from DispatchQueue.main.async isn't @MainActor-safe in Swift 6,
        // so hop via MainActor.assumeIsolated — safe because DispatchQueue.main IS the main actor.
        wake.onAudioLevel = { level in
            MainActor.assumeIsolated {
                AppState.shared.voiceAudioLevel = level
            }
        }
        if AppState.shared.voiceEnabled {
            wake.requestPermissionsAndStart()
        } else {
            wake.stop()
        }
    }

    func setEnabled(_ enabled: Bool) {
        AppState.shared.voiceEnabled = enabled
        if enabled {
            VoiceWakeEngine.shared.requestPermissionsAndStart()
        } else {
            VoiceWakeEngine.shared.stop()
            dismiss()
        }
    }

    // MARK: - Activate manually (e.g. from Notch tab)

    func activate() {
        guard AppState.shared.voiceEnabled else { return }
        cancelAutoClose()
        let s = AppState.shared
        s.voicePhase = .listening
        s.voiceResponse = ""
        s.voiceTranscript = ""
        s.stateOverride = .listening
        openVoiceView()
        VoiceWakeEngine.shared.startListeningNow()
        SoundEngine.shared.play("blip")
    }

    // MARK: - Wake

    private func handleWake() {
        cancelAutoClose()
        let s = AppState.shared
        s.voicePhase = .listening
        s.voiceResponse = ""
        s.voiceTranscript = ""
        s.stateOverride = .listening
        openVoiceView()
        SoundEngine.shared.play("blip")
    }

    // MARK: - Query ready

    private func handleQuery(_ text: String) {
        let s = AppState.shared
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing heard → just dismiss after a short pause
        if query.isEmpty {
            s.voicePhase = .idle
            s.stateOverride = nil
            scheduleAutoClose(after: 2)
            return
        }

        s.voiceTranscript = query
        s.voicePhase = .thinking
        s.stateOverride = .thinking

        streamTask?.cancel()
        streamTask = Task {
            await callAI(query: query)
        }
    }

    // MARK: - AI call

    private func callAI(query: String) async {
        let s = AppState.shared

        // Build a context-aware system prompt
        let contextSnippet = buildSessionContext()
        let systemPrompt = """
        You are Cruno, a voice-activated AI assistant living in the notch of the user's MacBook.
        \(contextSnippet)
        Give a SHORT, direct answer — the notch is tiny and the user is hands-free. \
        No markdown, no headers, no lists. 2-4 sentences max unless the question truly requires more.
        """

        // Determine provider and call
        switch s.chatProvider {
        case .anthropic:
            await callAnthropicVoice(query: query, systemPrompt: systemPrompt)
        default:
            await callOpenAICompatibleVoice(query: query, systemPrompt: systemPrompt)
        }
    }

    private func buildSessionContext() -> String {
        let tasks = AppState.shared.tasks.filter { !$0.isIntegration }
        if tasks.isEmpty { return "" }
        let lines = tasks.prefix(3).map { t in
            "\(t.name): \(t.state.rawValue)\(t.steps.last.map { " — \($0)" } ?? "")"
        }
        return "Current agent sessions: \(lines.joined(separator: "; "))."
    }

    // Anthropic streaming
    private func callAnthropicVoice(query: String, systemPrompt: String) async {
        guard let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else {
            await showVoiceError("No Anthropic API key — add it in Settings.")
            return
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
        let model = AppState.shared.claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)

        let body: [String: Any] = [
            "model": model.isEmpty ? AppState.defaultClaudeModel : model,
            "max_tokens": 512,
            "stream": true,
            "system": systemPrompt,
            "messages": [["role": "user", "content": query]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        await streamAnthropicSSE(request: req)
    }

    private func streamAnthropicSSE(request: URLRequest) async {
        let s = AppState.shared
        await MainActor.run {
            s.voicePhase = .responding
            s.stateOverride = .speaking
        }
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var accumulated = ""
            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                if line.hasPrefix("data: ") {
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    if let data = payload.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let delta = (json["delta"] as? [String: Any]),
                       let text = delta["text"] as? String {
                        accumulated += text
                        let snap = accumulated
                        await MainActor.run { s.voiceResponse = snap }
                    }
                }
            }
        } catch { }
        await finishResponse()
    }

    // OpenAI-compatible streaming (Google, OpenAI, Ollama, LM Studio)
    private func callOpenAICompatibleVoice(query: String, systemPrompt: String) async {
        let s = AppState.shared
        let provider = s.chatProvider

        let baseURL: String
        switch provider {
        case .google:   baseURL = "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openai:   baseURL = "https://api.openai.com/v1"
        case .opencode: baseURL = "https://openrouter.ai/api/v1"
        case .ollama:   baseURL = LocalChat.normaliseURL(s.ollamaServerURL)
        case .lmstudio: baseURL = LocalChat.normaliseURL(s.lmstudioServerURL)
        case .anthropic: return
        }
        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/chat/completions") else {
            await showVoiceError("Provider not configured.")
            return
        }

        let authHeader: String
        if provider.isLocal {
            authHeader = "Bearer ollama"
        } else {
            guard let key = KeychainStore.shared.get(provider.keychainKey), !key.isEmpty else {
                await showVoiceError("\(provider.displayName) API key missing.")
                return
            }
            authHeader = "Bearer \(key)"
        }

        let body: [String: Any] = [
            "model": s.activeChatModel,
            "max_tokens": 512,
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": query]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        if provider == .opencode {
            req.setValue("https://cruno.app", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("Cruno", forHTTPHeaderField: "X-Title")
        }

        await streamOpenAISSE(request: req)
    }

    private func streamOpenAISSE(request: URLRequest) async {
        let s = AppState.shared
        await MainActor.run {
            s.voicePhase = .responding
            s.stateOverride = .speaking
        }
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var accumulated = ""
            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                if let chunk = LocalChat.parseSSEDelta(line) {
                    accumulated += chunk
                    let snap = accumulated
                    await MainActor.run { s.voiceResponse = snap }
                }
            }
        } catch { }
        await finishResponse()
    }

    // MARK: - Finish / dismiss

    private func finishResponse() async {
        await MainActor.run {
            let s = AppState.shared
            s.voicePhase = .idle
            s.stateOverride = nil
        }
        scheduleAutoClose(after: 8)
    }

    private func showVoiceError(_ message: String) async {
        await MainActor.run {
            let s = AppState.shared
            s.voiceResponse = message
            s.voicePhase = .idle
            s.stateOverride = nil
        }
        scheduleAutoClose(after: 5)
    }

    func dismiss() {
        cancelAutoClose()
        streamTask?.cancel()
        streamTask = nil
        let s = AppState.shared
        s.voicePhase = .idle
        s.voiceResponse = ""
        s.voiceTranscript = ""
        s.stateOverride = nil
        if s.mochiOnDesktop {
            DesktopMochiController.shared.closeVoiceOverlay(animated: true)
        } else {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }

    private func scheduleAutoClose(after seconds: Double) {
        cancelAutoClose()
        autoCloseTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self.dismiss() }
        }
    }

    private func cancelAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
    }

    private func openVoiceView() {
        if AppState.shared.mochiOnDesktop {
            DesktopMochiController.shared.showVoiceOverlay()
        } else {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.voice)
        }
    }
}
