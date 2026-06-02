import Foundation
import AVFoundation
import CoreAudio

/// 시스템 사운드 캡처 — **Core Audio 프로세스 탭** (macOS 14.2+, 14.4부터 안정).
/// 가상 오디오 장치(BlackHole) 불필요. Screen Recording이 아닌 가벼운
/// "시스템 오디오 녹음" TCC 권한(`NSAudioCaptureUsageDescription`) 사용.
///
/// 참고 구현: Apple "Capturing system audio with Core Audio taps", insidegui/AudioCap.
///
/// API 순서(Phase 2에서 구현):
///   1. CATapDescription(initStereoGlobalTapButExcludeProcesses: [self])  // 전체-자기제외
///   2. AudioHardwareCreateProcessTap(desc, &tapID)
///   3. 애그리게이트 dict에 kAudioAggregateDeviceTapListKey = [{kAudioSubTapUIDKey: desc.uuid}]
///      → AudioHardwareCreateAggregateDevice(dict, &aggID)
///   4. kAudioTapPropertyFormat 으로 실제 ASBD 읽기 (48k 스테레오 가정 금지)
///   5. AudioDeviceCreateIOProcIDWithBlock 으로 버퍼 수신 블록 등록 → AudioDeviceStart
final class SystemAudioCapture: AudioSource {
    var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?

    func start() async throws {
        // 1) 전체 시스템(스테레오) 탭, 자기 자신은 제외 가능(빈 배열 = 전체 캡처).
        //    initStereoGlobalTapButExcludeProcesses: 는 NS_REFINED_FOR_SWIFT 이므로
        //    Swift에서는 CATapDescription(stereoGlobalTapButExcludeProcesses:) 로 노출된다.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted   // CATapMuteBehavior; 재생은 그대로 두고 캡처만.

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &tap)
        guard status == noErr, tap != AudioObjectID(kAudioObjectUnknown) else {
            throw TranscriptionError.engineUnavailable("ProcessTap 생성 실패: \(status)")
        }
        self.tapID = tap

        // 2) 탭을 담는 비공개 애그리게이트 장치(가상 장치 노출 없이 탭만 읽음).
        let aggUID = UUID().uuidString
        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Echo-SystemTap",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: desc.uuid.uuidString]
            ],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &agg)
        guard status == noErr, agg != AudioObjectID(kAudioObjectUnknown) else {
            throw TranscriptionError.engineUnavailable("Aggregate 생성 실패: \(status)")
        }
        self.aggregateID = agg

        // 3) 런타임 ASBD 읽기 (48k 스테레오 가정 금지 — 실제 포맷으로 버퍼 래핑).
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw TranscriptionError.engineUnavailable("탭 포맷 읽기 실패: \(status)")
        }

        // 4) IO 블록 등록 — 실시간 스레드. 여기서는 버퍼를 래핑해 전달만(변환/할당 금지).
        //    onBuffer/format은 값 캡처. AVAudioPCMBuffer(bufferListNoCopy:)는 복사 없이
        //    inInputData를 감싸므로 콜백 동안에만 유효 — 소비자(TrackWriter)가 즉시 write/복사한다.
        let sink = self.onBuffer
        var newProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProcID, agg, nil) {
            _, inInputData, _, _, _ in
            guard let sink,
                  let buf = AVAudioPCMBuffer(pcmFormat: format,
                                             bufferListNoCopy: inInputData,
                                             deallocator: nil) else { return }
            sink(buf, AVAudioTime(hostTime: mach_absolute_time()))
        }
        guard status == noErr, let procID = newProcID else {
            throw TranscriptionError.engineUnavailable("IOProc 생성 실패: \(status)")
        }
        self.ioProcID = procID

        status = AudioDeviceStart(agg, procID)
        guard status == noErr else {
            throw TranscriptionError.engineUnavailable("AudioDeviceStart 실패: \(status)")
        }
    }

    func stop() {
        if let ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
        ioProcID = nil; aggregateID = 0; tapID = 0
    }
}
