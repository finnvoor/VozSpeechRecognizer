# VozSpeechRecognizer

Use [Desert Ant Labs' Voz](https://huggingface.co/desert-ant-labs/voz) with [AnySpeechRecognizer](https://github.com/mattt/AnySpeechRecognizer).

```swift
.package(url: "https://github.com/finnvoor/VozSpeechRecognizer", branch: "main")
```

```swift
import AnySpeechRecognizer
import VozSpeechRecognizer

let transcriber = SpeechTranscriber(
    model: VozSpeechModel(),
    transcriptionOptions: [],
    reportingOptions: [],
    attributeOptions: [.audioTimeRange]
)
```

Install assets and run the analyzer as usual. Results are final only (no volatile results).

## License

Voz is available under the [Desert Ant Labs Source-Available License](https://license.desertant.com/1.0).
