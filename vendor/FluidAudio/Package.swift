// swift-tools-version: 6.0
import PackageDescription

// Echo 로컬 vendoring(v0.9.1). 우리는 화자 구분(FluidAudio 라이브러리)만 쓰므로
// TTS(ESpeakNG ~89MB)·CLI·테스트 타깃은 제거했다. 또 Streaming ASR가 Swift 6
// strict-concurrency에서 컴파일 실패하여 이 타깃만 Swift 5 모드로 빌드한다.
let package = Package(
    name: "FluidAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "FluidAudio",
            targets: ["FluidAudio"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FluidAudio",
            dependencies: [
                "FastClusterWrapper",
                "MachTaskSelfWrapper",
            ],
            path: "Sources/FluidAudio",
            exclude: [
                "Frameworks",
                "ASR/ContextBiasing",
                "ASR/CtcModels.swift",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "FastClusterWrapper",
            path: "Sources/FastClusterWrapper",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MachTaskSelfWrapper",
            path: "Sources/MachTaskSelfWrapper",
            publicHeadersPath: "include"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
