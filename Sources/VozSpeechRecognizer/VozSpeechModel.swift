import AVFoundation
import AnySpeechRecognizer
import CoreMedia
import Foundation
import Speech
import Voz

/// Desert Ant Labs' Voz model as an AnySpeechRecognizer engine.
///
/// ```swift
/// let transcriber = SpeechTranscriber(model: VozSpeechModel(), attributeOptions: [.audioTimeRange])
/// ```
///
/// Voz transcribes whole recordings, so results are final and arrive when the analyzer
/// finalizes, or at a gap in the input. Word timing is supported; volatile results are not.
public struct VozSpeechModel: SpeechRecognitionModel {
    /// Names and terms the audio likely contains, cased as they should be written.
    public let vocabulary: [String]

    public let modelID = "desert-ant-labs/voz"

    public let capabilities = SpeechRecognitionCapabilities(
        transcription: .init(reportingOptions: [], attributeOptions: [.audioTimeRange]))

    /// Creates a configuration without loading or downloading the model.
    /// - Parameter vocabulary: Names and terms to prefer when they are spoken.
    public init(vocabulary: [String] = []) {
        self.vocabulary = vocabulary
    }

    public func makeExecutor() -> any SpeechRecognitionExecutor { VozExecutor(model: self) }

    public func availability() async -> SpeechRecognitionAvailability {
        Voz.isDownloaded() ? .ready : .missingAssets
    }

    public func assetInstallationRequest() async throws -> AnySpeechRecognizer.AssetInstallationRequest? {
        guard !Voz.isDownloaded() else { return nil }
        let progress = Progress(totalUnitCount: 1000)
        return AnySpeechRecognizer.AssetInstallationRequest(progress: progress) {
            try await Voz.download { update in
                progress.completedUnitCount = Int64(update.fraction * 1000)
            }
            progress.completedUnitCount = 1000
        }
    }
}

actor VozExecutor: SpeechRecognitionExecutor {
    private static let sampleRate = 16_000

    let model: VozSpeechModel
    private var voz: Voz?
    private var results: SpeechRecognitionResultSink?
    private var includeTiming = false
    /// Samples that no result covers yet, starting at `origin`.
    private var buffered: [Float] = []
    private var origin = CMTime.zero
    private var expected: CMTime?
    /// Keeps transcriptions and their results in source order.
    private var tail: Task<Void, any Error>?
    private var publishedText = false

    init(model: VozSpeechModel) { self.model = model }

    func prepare(
        request: SpeechRecognitionRequest, format: AVAudioFormat, context: AnalysisContext
    ) async throws {
        guard case .transcription = request else {
            throw SpeechRecognitionError.unsupportedConfiguration(
                "Voz does not support DictationTranscriber.")
        }
        try request.validate(for: model.capabilities)
        guard Voz.isDownloaded() else {
            throw SpeechRecognitionError.missingAssets(
                "Install Voz with AssetInventory before analysis.")
        }
        includeTiming = request.includesAudioTimeRange
        voz = try await Voz()
    }

    func analyze(_ input: SpeechAnalysisInput, results: SpeechRecognitionResultSink) async throws {
        self.results = results
        for try await buffer in input {
            guard let samples = buffer.buffer.floatChannelData?[0] else {
                throw SpeechRecognitionError.invalidAudio("Voz requires Float32 samples.")
            }
            // A gap in the input ends the current recording.
            if let expected, buffer.startTime > expected + CMTime(value: 1, timescale: 16_000) {
                try await transcribe(count: buffered.count)
            }
            if buffered.isEmpty { origin = buffer.startTime }
            buffered += UnsafeBufferPointer(start: samples, count: Int(buffer.buffer.frameLength))
            expected = buffer.endTime
        }
    }

    func finalize(through time: CMTime) async throws {
        let offset = time - origin
        guard !buffered.isEmpty, offset >= .zero else { return }
        let count = Int(
            CMTimeConvertScale(offset, timescale: 16_000, method: .roundTowardPositiveInfinity)
                .value) + 1
        try await transcribe(count: min(count, buffered.count))
    }

    func cancel() async {
        tail?.cancel()
        voz = nil
        results = nil
        buffered = []
    }

    /// Transcribes and removes the first `count` buffered samples, and publishes their text.
    private func transcribe(count: Int) async throws {
        guard count > 0 else { return }
        let samples = Array(buffered[..<count])
        let start = origin
        buffered.removeFirst(count)
        origin = start + CMTime(value: CMTimeValue(count), timescale: CMTimeScale(Self.sampleRate))
        let end = origin
        let previous = tail
        let task = Task {
            try await previous?.value
            guard let voz, let results else { throw CancellationError() }
            let transcript = try await voz.transcribe(
                samples: samples, sampleRate: Double(Self.sampleRate),
                vocabulary: model.vocabulary)
            guard let result = makeResult(transcript, range: CMTimeRange(start: start, end: end))
            else { return }
            try await results.emit(result)
        }
        tail = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func makeResult(_ transcript: Voz.Result, range: CMTimeRange)
        -> SpeechRecognitionResult?
    {
        var text = AttributedString()
        if includeTiming {
            for word in transcript.words {
                if publishedText || !text.characters.isEmpty { text += AttributedString(" ") }
                var run = AttributedString(word.text)
                let wordStart = min(range.start + seconds(word.start), range.end)
                let wordEnd = min(max(range.start + seconds(word.end), wordStart), range.end)
                run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
                    start: wordStart, end: wordEnd)
                text += run
            }
        } else {
            let trimmed = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                text = AttributedString(publishedText ? " " + trimmed : trimmed)
            }
        }
        guard !text.characters.isEmpty else { return nil }
        publishedText = true
        return SpeechRecognitionResult(text: text, range: range, resultsFinalizationTime: range.end)
    }

    private func seconds(_ value: TimeInterval) -> CMTime {
        CMTime(seconds: value, preferredTimescale: CMTimeScale(Self.sampleRate))
    }
}
