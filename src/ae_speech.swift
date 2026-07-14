// C-ABI shim over macOS 26 SpeechAnalyzer/SpeechTranscriber, mirroring the
// ae_whisper_* interface in transcribe.nim: raw mono f32 @16kHz in, per-segment
// (text, t0_ms, t1_ms) callback out, all synchronous from the caller's view.
// Built by config.nims (swiftc -emit-library -static) when the host is macOS 26+.
import Foundation
import Speech
import AVFoundation

typealias SegCb = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>?, Int64, Int64) -> Void

// Compiled with a macOS 14 deployment target so release binaries still launch
// on older systems (Speech's new symbols get weak-linked); the #available
// guards below make `apple` fail cleanly there instead.
// Holds only the resolved locale: a SpeechTranscriber's `results` stream ends
// permanently once its analyzer finishes, so each run needs a fresh one.
final class SpeechCtx {
    let locale: Locale
    init(locale: Locale) { self.locale = locale }
}

// Single construction site so the options ae_speech_init checks assets for
// always match what ae_speech_run actually requests.
@available(macOS 26.0, *)
private func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(locale: locale, transcriptionOptions: [],
                      reportingOptions: [], attributeOptions: [.audioTimeRange])
}

// Returns an opaque context, or nil if the locale is unsupported or asset
// download fails. Blocks while downloading model assets on first use.
@_cdecl("ae_speech_init")
func ae_speech_init(_ localeId: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard #available(macOS 26.0, *) else { return nil }
    let id = localeId.map { String(cString: $0) } ?? "en_US"
    let sem = DispatchSemaphore(value: 0)
    var ctx: SpeechCtx? = nil
    Task {
        defer { sem.signal() }
        let wanted = Locale(identifier: id)
        let supported = await SpeechTranscriber.supportedLocales
        // Exact match first, then language-only ("en" → first en_* locale).
        var locale = supported.first { $0.identifier(.bcp47) == wanted.identifier(.bcp47) }
        if locale == nil {
            locale = supported.first { $0.language.languageCode == wanted.language.languageCode }
        }
        guard let locale else { return }
        let t = makeTranscriber(locale)
        do {
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                FileHandle.standardError.write("Downloading speech model for \(locale.identifier)...\n".data(using: .utf8)!)
                try await req.downloadAndInstall()
            }
            ctx = SpeechCtx(locale: locale)
        } catch { return }
    }
    sem.wait()
    return ctx.map { Unmanaged.passRetained($0).toOpaque() }
}

// Transcribe one utterance of mono f32 16kHz samples. Calls on_segment once per
// final result (or once per word when splitWords != 0) with ms timestamps
// relative to the start of `samples`, on this thread, before returning.
// Returns 0 on success.
@_cdecl("ae_speech_run")
func ae_speech_run(_ opaque: UnsafeMutableRawPointer?,
                   _ samples: UnsafePointer<Float>?, _ nSamples: Int32,
                   _ splitWords: Int32,
                   _ onSegment: SegCb?, _ user: UnsafeMutableRawPointer?) -> Int32 {
    guard #available(macOS 26.0, *) else { return -1 }
    guard let opaque, let samples, nSamples > 0, let onSegment else { return -1 }
    let ctx = Unmanaged<SpeechCtx>.fromOpaque(opaque).takeUnretainedValue()

    // SpeechTranscriber requires 16-bit signed integer samples (it traps on f32).
    guard let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                  channels: 1, interleaved: true),
          let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(nSamples))
    else { return -1 }
    buf.frameLength = AVAudioFrameCount(nSamples)
    let dst = buf.int16ChannelData![0]
    for i in 0..<Int(nSamples) {
        dst[i] = Int16(max(-1.0, min(1.0, samples[i])) * 32767.0)
    }

    struct Seg { let text: String; let t0: Int64; let t1: Int64 }
    let sem = DispatchSemaphore(value: 0)
    var segs: [Seg] = []
    var rc: Int32 = 0

    Task {
        defer { sem.signal() }
        do {
            let transcriber = makeTranscriber(ctx.locale)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, cont) = AsyncStream.makeStream(of: AnalyzerInput.self)
            cont.yield(AnalyzerInput(buffer: buf))
            cont.finish()

            async let collect: [Seg] = {
                var out: [Seg] = []
                for try await result in transcriber.results where result.isFinal {
                    // Runs are split on audioTimeRange boundaries, i.e. per word.
                    var words: [Seg] = []
                    for run in result.text.runs {
                        guard let r = run.audioTimeRange else { continue }
                        let word = String(result.text[run.range].characters)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if word.isEmpty { continue }
                        words.append(Seg(text: word,
                                         t0: max(Int64(r.start.seconds * 1000), 0),
                                         t1: max(Int64(r.end.seconds * 1000), 0)))
                    }
                    if splitWords != 0 {
                        out.append(contentsOf: words)
                    } else {
                        // No timed runs at all: span the whole buffer rather
                        // than emitting a zero-length segment.
                        out.append(Seg(text: String(result.text.characters),
                                       t0: words.first?.t0 ?? 0,
                                       t1: words.last?.t1 ?? Int64(nSamples) * 1000 / 16000))
                    }
                }
                return out
            }()

            let last = try await analyzer.analyzeSequence(stream)
            if let last { try await analyzer.finalizeAndFinish(through: last) }
            else { await analyzer.cancelAndFinishNow() }
            segs = try await collect
        } catch {
            rc = -1
        }
    }
    sem.wait()

    for s in segs {
        s.text.withCString { c in
            onSegment(user, UnsafeMutablePointer(mutating: c), s.t0, s.t1)
        }
    }
    return rc
}

@_cdecl("ae_speech_free")
func ae_speech_free(_ opaque: UnsafeMutableRawPointer?) {
    guard #available(macOS 26.0, *) else { return }
    if let opaque { Unmanaged<SpeechCtx>.fromOpaque(opaque).release() }
}
