// WhisperCppKit wraps the ggml-org/whisper.cpp XCFramework and re-exports its C API.
//
// 利用側コードは `import WhisperCppKit` で whisper.cpp の C API を呼べる。
// XCFramework が提供する module 名は `whisper` だが、本ラッパー経由で
// 名前空間を統一し Swift パッケージ境界を明確化する。

@_exported import whisper
