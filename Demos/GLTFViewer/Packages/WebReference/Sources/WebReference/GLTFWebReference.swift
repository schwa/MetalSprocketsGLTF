import CoreGraphics
import Foundation
import ImageIO
import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import UniformTypeIdentifiers
import WebKit

/// Renders glTF files with three.js in a `WKWebView`, as a reference to compare ``GLTFRenderer`` against.
///
/// Takes the same view and projection matrices and ``PBRLighting`` as `GLTFRenderer`, so both show the same view.
@preconcurrency
@MainActor
public final class GLTFWebReference: NSObject {
    public enum LightingMode: String, CaseIterable, Sendable {
        /// The same punctual lights and environment as `GLTFRenderer`.
        case matched
        /// three.js `RoomEnvironment` image-based lighting.
        case environment
    }

    public enum Error: Swift.Error {
        case pageFailedToLoad(String)
        case snapshotFailed
        /// WebKit killed the page's process (for example under memory pressure). The reference reloads the page, so
        /// the operation can be retried after loading the model and setting the view and lighting again.
        case contentProcessTerminated
    }

    public let webView: WKWebView

    /// Where the page's three.js files come from on first use; they are then served from ``cacheDirectory``.
    nonisolated(unsafe) public static var cdnBaseURL = URL(string: "https://cdn.jsdelivr.net")!
    /// Downloaded three.js files, so the reference works offline after its first run.
    nonisolated(unsafe) public static var cacheDirectory = URL.cachesDirectory.appending(path: "MetalSprocketsGLTFWebReference")
    nonisolated static let threeModulePath = "npm/three@0.186.1/build/three.module.js"

    /// Whether the page can load three.js: it is cached, or the CDN answers within a few seconds.
    nonisolated public static var isAvailable: Bool {
        if FileManager.default.fileExists(atPath: cacheDirectory.appending(path: threeModulePath).path) {
            return true
        }
        var request = URLRequest(url: cdnBaseURL.appending(path: threeModulePath), timeoutInterval: 5)
        request.httpMethod = "HEAD"
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var reachable = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return reachable
    }
    private let schemeHandler = SchemeHandler()
    private var readyContinuations: [CheckedContinuation<Void, Swift.Error>] = []
    private var isReady = false
    private var navigationObserver: NavigationObserver?
    private var fixedSize: (width: Int, height: Int)?
    private var pageURL: URL!
    private var pageLoadCount = 0
    private var background: SIMD3<Float>?
    /// How many times WebKit has killed the page's process. Calls in flight at the time fail (sometimes with a
    /// misleading WebKit error), so a caller can compare this before and after to decide whether to retry.
    public private(set) var terminationCount = 0
    private var sentEnvironment: ObjectIdentifier?
    private var loadFailure: Error?
    /// Whether WebGL multisampling is on; fixed when the page's context is created.
    public let antialias: Bool

    /// `antialias` turns on WebGL multisampling. It is off by default to match `GLTFRenderer`'s single-sampled
    /// output, so comparisons measure shading rather than edge aliasing.
    public init(antialias: Bool = false) {
        self.antialias = antialias
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: SchemeHandler.scheme)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 512, height: 512), configuration: configuration)
        super.init()
        configuration.userContentController.add(MessageHandler(owner: self), name: "ready")
        let navigationObserver = NavigationObserver(owner: self)
        self.navigationObserver = navigationObserver
        webView.navigationDelegate = navigationObserver
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        #endif
        pageURL = URL(string: "\(SchemeHandler.scheme)://app/index.html?antialias=\(antialias ? 1 : 0)")!
        loadPage()
    }

    private func loadPage() {
        pageLoadCount += 1
        let pageLoad = pageLoadCount
        webView.load(URLRequest(url: pageURL))
        // three.js comes from a CDN; without it the page never reports ready.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, pageLoadCount == pageLoad else { return }
            failIfNotReady()
        }
    }

    /// Loads a .gltf or .glb file, replacing any previous model.
    public func load(_ url: URL) async throws {
        try await waitUntilReady()
        schemeHandler.modelURL = url
        // A unique path defeats WebKit's cache when switching models.
        try await call("return await reference.load(url)", ["url": "\(SchemeHandler.scheme)://model/\(UUID().uuidString)/\(url.lastPathComponent)"])
    }

    /// Poses the model with glTF animation `index` at `time` seconds, or the rest pose when `index` is nil.
    public func setAnimation(_ index: Int?, time: Float) async throws {
        try await call("reference.setAnimation(index, time)", ["index": index.map { $0 as Any } ?? NSNull(), "time": Double(time)])
    }

    /// Matrices use the same conventions as `GLTFRenderer` (Metal clip space, 0...1 depth).
    public func setView(viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4) async throws {
        // Remap reversed depth (near 1, far 0) to WebGL's -1...1 (near -1): z' = w - 2z.
        let depthRemap = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, -2, 0], [0, 0, 1, 1]))
        try await call("reference.setView(cameraMatrix, projection)", [
            "cameraMatrix": viewMatrix.inverse.array,
            "projection": (depthRemap * projectionMatrix).array
        ])
    }

    /// In `.matched` mode the reference uses `lighting.environment` (sent once per environment) as its IBL and,
    /// with `showsBackground`, as its background.
    public func setLighting(_ lighting: PBRLighting, mode: LightingMode = .matched, showsBackground: Bool = false) async throws {
        let environmentID = ObjectIdentifier(lighting.environment)
        if environmentID != sentEnvironment {
            // A full-resolution HDR is large to pass through JavaScript; 1024 wide is plenty for comparison.
            let pixels = lighting.environment.equirectangularPixels(maxWidth: 1_024)
            let image: [String: Any] = ["width": pixels.width, "height": pixels.height, "data": pixels.data.base64EncodedString()]
            try await call("reference.setEnvironment(image)", ["image": image])
            sentEnvironment = environmentID
        }
        let lights: [[String: Any]] = lighting.lights.map { light in
            [
                "type": Int(light.type.rawValue),
                "position": light.position.array,
                "direction": light.direction.array,
                "color": light.color.array,
                "intensity": Double(light.intensity),
                "range": Double(light.range),
                "innerConeCos": Double(light.innerConeCos),
                "outerConeCos": Double(light.outerConeCos)
            ]
        }
        try await call("reference.setLighting(settings)", ["settings": [
            "mode": mode.rawValue,
            "exposure": Double(lighting.exposure),
            "toneMapping": Self.threeToneMapping(lighting.toneMapping),
            "environmentRotation": Double(lighting.environmentRotation),
            "environmentIntensity": Double(lighting.environmentIntensity),
            "showsBackground": showsBackground,
            "lights": lights
        ] as [String: Any]])
    }

    /// three.js's operator matching `toneMapping` (the names of THREE's tone mapping constants).
    static func threeToneMapping(_ toneMapping: PBRToneMapping) -> String {
        switch toneMapping {
        case .pbrNeutral: "NeutralToneMapping"
        case .linear: "LinearToneMapping"
        case .acesFilmic: "ACESFilmicToneMapping"
        case .agx: "AgXToneMapping"
        case .reinhard: "ReinhardToneMapping"
        case .none: "NoToneMapping"
        }
    }

    /// Linear RGB, like `MTLClearColor`.
    public func setBackground(_ color: SIMD3<Float>) async throws {
        background = color
        try await call("reference.setBackground(color)", ["color": color.array])
    }

    /// Renders at an exact pixel size, independent of the web view's size. Pass nil to follow the view.
    public func setFixedSize(width: Int, height: Int) async throws {
        fixedSize = (width, height)
        try await call("reference.setFixedSize({width, height})", ["width": width, "height": height])
    }

    public func snapshot() async throws -> CGImage {
        try await waitUntilReady()
        let result = try await webView.callAsyncJavaScript("return reference.snapshot()", arguments: [:], in: nil, contentWorld: .page)
        guard let dataURL = result as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw Error.snapshotFailed
        }
        return image
    }

    private func call(_ body: String, _ arguments: [String: Any]) async throws {
        try await waitUntilReady()
        _ = try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }

    private func waitUntilReady() async throws {
        if isReady { return }
        if let loadFailure { throw loadFailure }
        try await withCheckedThrowingContinuation { readyContinuations.append($0) }
    }

    fileprivate func markReady() {
        // After a reload, restore the page settings that callers set once, before anyone else uses the page.
        Task {
            if let fixedSize {
                _ = try? await webView.callAsyncJavaScript("reference.setFixedSize({width, height})", arguments: ["width": fixedSize.width, "height": fixedSize.height], in: nil, contentWorld: .page)
            }
            if let background {
                _ = try? await webView.callAsyncJavaScript("reference.setBackground(color)", arguments: ["color": background.array], in: nil, contentWorld: .page)
            }
            isReady = true
            readyContinuations.forEach { $0.resume() }
            readyContinuations = []
        }
    }

    fileprivate func contentProcessDidTerminate() {
        FileHandle.standardError.write(Data("GLTFWebReference: web content process terminated\n".utf8))
        terminationCount += 1
        isReady = false
        sentEnvironment = nil
        readyContinuations.forEach { $0.resume(throwing: Error.contentProcessTerminated) }
        readyContinuations = []
        // Load the page explicitly: after a termination the web view may have nothing to reload.
        loadPage()
    }

    private func failIfNotReady() {
        guard !isReady else { return }
        let failure = Error.pageFailedToLoad("three.js did not load within 30 seconds. The first run downloads it from cdn.jsdelivr.net (later runs use the cache), so it needs a network connection once.")
        loadFailure = failure
        readyContinuations.forEach { $0.resume(throwing: failure) }
        readyContinuations = []
    }
}

private final class NavigationObserver: NSObject, WKNavigationDelegate {
    weak var owner: GLTFWebReference?

    init(owner: GLTFWebReference) {
        self.owner = owner
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        MainActor.assumeIsolated {
            owner?.contentProcessDidTerminate()
        }
    }
}

private final class MessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: GLTFWebReference?

    init(owner: GLTFWebReference) {
        self.owner = owner
    }

    func userContentController(_: WKUserContentController, didReceive _: WKScriptMessage) {
        MainActor.assumeIsolated {
            owner?.markReady()
        }
    }
}

/// Serves the bundled page and three.js from `gltfref://app/`, and the current model from `gltfref://model/`.
@MainActor
private final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "gltfref"
    var modelURL: URL?

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        if url.host == "cdn" {
            serveCDNFile(url: url, task: task)
            return
        }
        let fileURL: URL?
        if url.host == "model" {
            fileURL = modelFileURL(for: url)
        } else {
            fileURL = Bundle.module.resourceURL?.appending(path: "Web").appending(path: String(url.path.dropFirst()))
        }
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        respond(task, url: url, data: data, pathExtension: fileURL.pathExtension)
    }

    /// `gltfref://model/<id>/<path>`: the model itself, or a file its .gltf references (buffers, images), resolved
    /// beside the model. Paths that leave the model's directory are refused.
    private func modelFileURL(for url: URL) -> URL? {
        guard let modelURL else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }.dropFirst() // Drop the cache-busting id.
        let relativePath = components.joined(separator: "/")
        if relativePath == modelURL.lastPathComponent {
            return modelURL
        }
        let directory = modelURL.deletingLastPathComponent().standardizedFileURL
        let fileURL = directory.appending(path: relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(directory.path + "/") else {
            return nil
        }
        return fileURL
    }

    /// Serves a three.js file from the disk cache, downloading it from the CDN on the first request.
    private func serveCDNFile(url: URL, task: any WKURLSchemeTask) {
        let path = String(url.path.dropFirst())
        let cacheURL = GLTFWebReference.cacheDirectory.appending(path: path)
        if let data = try? Data(contentsOf: cacheURL) {
            respond(task, url: url, data: data, pathExtension: cacheURL.pathExtension)
            return
        }
        let remoteURL = GLTFWebReference.cdnBaseURL.appending(path: path)
        stoppedTasks.remove(ObjectIdentifier(task))
        Task { @MainActor in
            do {
                let (data, response) = try await URLSession.shared.data(from: remoteURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cacheURL, options: .atomic)
                guard !stoppedTasks.contains(ObjectIdentifier(task)) else { return }
                respond(task, url: url, data: data, pathExtension: cacheURL.pathExtension)
            } catch {
                guard !stoppedTasks.contains(ObjectIdentifier(task)) else { return }
                task.didFailWithError(error)
            }
        }
    }

    /// Tasks WebKit cancelled while a download was in flight; they must not be answered.
    private var stoppedTasks = Set<ObjectIdentifier>()

    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data, pathExtension: String) {
        let mimeType: String
        switch pathExtension.lowercased() {
        case "html": mimeType = "text/html"
        case "js": mimeType = "text/javascript"
        case "gltf": mimeType = "model/gltf+json"
        case "glb": mimeType = "model/gltf-binary"
        default: mimeType = UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*"
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_: WKWebView, stop task: any WKURLSchemeTask) {
        stoppedTasks.insert(ObjectIdentifier(task))
    }
}

private extension simd_float4x4 {
    var array: [Double] {
        [columns.0, columns.1, columns.2, columns.3].flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
    }
}

private extension SIMD3<Float> {
    var array: [Double] { [Double(x), Double(y), Double(z)] }
}
