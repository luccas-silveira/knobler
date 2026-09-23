import Foundation

@main
enum ScreenshotCheck {
    static func main() {
        let start = Date(timeIntervalSince1970: 2_000)
        let path = "/tmp/captura.png"
        // Uma captura antiga pode aparecer como adicionada após o gathering.
        assert(!ScreenshotWatcher.isNewScreenshot(
            path: path, createdAt: start.addingTimeInterval(-1), since: start))
        assert(!ScreenshotWatcher.isNewScreenshot(
            path: path, createdAt: nil, since: start))
        assert(ScreenshotWatcher.isNewScreenshot(
            path: path, createdAt: start, since: start))
        assert(ScreenshotWatcher.isNewScreenshot(
            path: path, createdAt: start.addingTimeInterval(1), since: start))
        assert(!ScreenshotWatcher.isNewScreenshot(
            path: "/tmp/.captura.png", createdAt: start, since: start))
        // Religou o recurso: prints do período anterior continuam de fora.
        assert(!ScreenshotWatcher.isNewScreenshot(
            path: path, createdAt: start, since: start.addingTimeInterval(10)))
        print("screenshotcheck: ok")
    }
}
