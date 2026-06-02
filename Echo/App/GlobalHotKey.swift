import Foundation
import Carbon.HIToolbox

/// 시스템 전역 핫키(다른 앱이 포커스일 때도 동작) — Carbon `RegisterEventHotKey` 기반.
/// 외부 의존성 없이 SDK 의 Carbon/HIToolbox 만 사용한다.
///
/// 기본 단축키: ⌃⌥⌘R (Control+Option+Command+R). 한 번 눌러 녹음 토글.
///
/// 한계(humanTODO): 글로벌 키 이벤트 가로채기는 macOS 의 **입력 모니터링/손쉬운 사용** 권한과
/// 무관하게 RegisterEventHotKey 로 동작하지만, 샌드박스 앱에서는 제약이 있을 수 있다(현재 앱은
/// App Sandbox OFF). `@convention(c)` 핸들러는 컨텍스트를 캡처할 수 없어 싱글턴으로 우회한다.
/// 실제 키 입력 검증은 사람이 다른 앱 포커스 상태에서 직접 눌러 확인해야 한다(런타임).
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// 핫키가 눌렸을 때 호출. MenuBarContent 가 녹음 토글로 연결한다.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var installed = false

    private init() {}

    /// 핫키 + 이벤트 핸들러를 1회 설치한다. 재호출은 무해(no-op).
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_R),
                  modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)) {
        guard !installed else { return }

        // 1) kEventHotKeyPressed 핸들러를 애플리케이션 이벤트 타깃에 설치.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            GlobalHotKey.hotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard status == noErr else { return }

        // 2) 핫키 등록.
        var hotKeyID = EventHotKeyID(signature: OSType(0x4543_484F /* 'ECHO' */), id: 1)
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard regStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return
        }
        installed = true
        _ = hotKeyID  // 등록 후 사용 끝
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        installed = false
    }

    /// `@convention(c)` 핸들러는 컨텍스트를 캡처할 수 없으므로 싱글턴의 onTrigger 로 디스패치.
    /// 핸들러는 임의 스레드에서 불릴 수 있어 MainActor 로 hop 한다.
    fileprivate static let hotKeyHandler: EventHandlerUPP = { _, _, _ -> OSStatus in
        Task { @MainActor in GlobalHotKey.shared.onTrigger?() }
        return noErr
    }
}
