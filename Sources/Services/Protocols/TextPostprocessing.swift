import Foundation

/// テキスト後処理のプロトコル（空白正規化、繰り返し除去）
protocol TextPostprocessing {
    func process(_ text: String) -> String
}
