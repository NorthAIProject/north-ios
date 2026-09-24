import AVFAudio
import Speech

/// Transcribes on this iPhone with `SpeechAnalyzer`.
///
/// Nothing leaves the device: the audio goes from the microphone to Apple's
/// on-device model and only the words reach the text box. The model for the
/// person's language is downloaded once, the first time they dictate.
actor OnDeviceTranscriber: SpeechTranscribing {
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?

    func isAvailable() async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: .current) != nil
    }

    func start() async throws -> AsyncThrowingStream<Transcript, Error> {
        await stop()

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw DictationError.unsupportedLocale
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await download.downloadAndInstall()
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let microphone = engine.inputNode.outputFormat(forBus: 0)
        guard microphone.channelCount > 0,
              let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: microphone),
              let converter = BufferConverter(from: microphone, to: format)
        else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw DictationError.noMicrophone
        }

        let (audio, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: audio)

        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphone, block: Self.tap(converter, into: input))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            input.finish()
            await analyzer.cancelAndFinishNow()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        self.engine = engine
        self.analyzer = analyzer
        self.input = input

        return AsyncThrowingStream { continuation in
            let reading = Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(Transcript(text: String(result.text.characters), isFinal: result.isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
    }

    func stop() async {
        guard let analyzer else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        input?.finish()
        // Settles the volatile words still on screen; without it the last
        // phrase would vanish when the person stops.
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        self.engine = nil
        self.analyzer = nil
        self.input = nil
    }

    /// The tap runs on the audio thread. Built outside the actor so it is not
    /// isolated to it: an isolated closure there traps on its first buffer.
    private nonisolated static func tap(
        _ converter: BufferConverter,
        into input: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in
            if let converted = converter.convert(buffer) {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
    }
}

/// Resamples microphone buffers into the format the model wants. Only ever
/// used from the audio tap, one buffer at a time.
private nonisolated final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat

    init?(from source: AVAudioFormat, to format: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: source, to: format) else { return nil }
        self.converter = converter
        self.format = format
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}
