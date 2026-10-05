import Foundation
import MetalSprocketsGLTF
import SwiftGLTF

/// One row of the Document inspector's outline.
struct DocumentOutlineItem: Identifiable, Hashable {
    /// Unique in the outline: the item's path, e.g. "meshes/3/1".
    var id: String
    var title: String
    var detail: String?
    var systemImage: String
    /// Nil for leaves, so the outline shows no disclosure triangle.
    var children: [Self]?
    /// What the item shows, for the detail view; nil for section headers.
    var reference: DocumentReference?
}

/// An object in a glTF document, by index.
enum DocumentReference: Hashable {
    case scene(Int)
    case node(Int)
    case mesh(Int)
    case primitive(mesh: Int, index: Int)
    case material(Int)
    case texture(Int)
    case image(Int)
    case skin(Int)
    case animation(Int)
    case channel(animation: Int, index: Int)
    case camera(Int)
    case light(Int)
}

/// One of an object's JSON properties, its value as compact JSON (strings unquoted).
struct DocumentProperty: Hashable, Identifiable {
    var name: String
    var value: String
    var id: String { name }
}

/// The contents of a loaded glTF document as an outline: the scenes' node trees, then meshes, materials, textures,
/// images, skins, animations, cameras and lights. Empty sections are left out.
enum DocumentOutline {
    static func items(for asset: GLTFAsset) -> [DocumentOutlineItem] {
        sections(asset.container.document, shownScene: asset.sceneIndex)
    }

    static func sections(_ document: Document, shownScene: Int) -> [DocumentOutlineItem] {
        let lights = document.punctualLights
        func section(_ id: String, _ title: String, _ systemImage: String, _ children: [DocumentOutlineItem]) -> DocumentOutlineItem? {
            children.isEmpty ? nil : DocumentOutlineItem(id: id, title: "\(title) (\(children.count))", systemImage: systemImage, children: children)
        }
        return [
            section("scenes", "Scenes", "square.stack.3d.up", scenes(document, shown: shownScene)),
            section("meshes", "Meshes", "cube", meshes(document)),
            section("materials", "Materials", "paintpalette", materials(document)),
            section("textures", "Textures", "photo", textures(document)),
            section("images", "Images", "photo.on.rectangle", images(document)),
            section("skins", "Skins", "figure.walk", skins(document)),
            section("animations", "Animations", "play.circle", animations(document)),
            section("cameras", "Cameras", "camera", cameras(document)),
            section("lights", "Lights", "lightbulb", lights.enumerated().map { index, light in
                DocumentOutlineItem(id: "lights/\(index)", title: light.name ?? "Light \(index)", detail: lightDetail(light), systemImage: "lightbulb", reference: .light(index))
            }),
        ].compactMap(\.self)
    }

    static func scenes(_ document: Document, shown: Int) -> [DocumentOutlineItem] {
        document.scenes.enumerated().map { index, scene in
            var path = Set<Int>()
            let roots = scene.nodes.map { node(document, $0.index, idPrefix: "scenes/\(index)", path: &path) }
            return DocumentOutlineItem(id: "scenes/\(index)", title: scene.name ?? "Scene \(index)", detail: index == shown ? "shown" : nil, systemImage: "square.stack.3d.up", children: roots.isEmpty ? nil : roots, reference: .scene(index))
        }
    }

    /// A node and its descendants. `path` holds the ancestors, so a cyclic hierarchy stops instead of recursing.
    static func node(_ document: Document, _ index: Int, idPrefix: String, path: inout Set<Int>) -> DocumentOutlineItem {
        let id = "\(idPrefix)/\(index)"
        guard document.nodes.indices.contains(index) else {
            return DocumentOutlineItem(id: id, title: "Node \(index)", detail: "out of range", systemImage: "exclamationmark.triangle")
        }
        guard path.insert(index).inserted else {
            return DocumentOutlineItem(id: id, title: "Node \(index)", detail: "cycle", systemImage: "exclamationmark.triangle")
        }
        defer { path.remove(index) }
        let node = document.nodes[index]
        var parts: [String] = []
        var systemImage = "circle.dashed"
        if let mesh = node.mesh?.index {
            parts.append("mesh \(document.meshes.indices.contains(mesh) ? document.meshes[mesh].name ?? "\(mesh)" : "\(mesh)")")
            systemImage = "cube"
        }
        if let skin = node.skin?.index {
            parts.append("skin \(skin)")
        }
        if node.camera != nil {
            parts.append("camera")
            systemImage = "camera"
        }
        if let light = node.punctualLight(in: document) {
            parts.append("\(light.type.rawValue) light")
            systemImage = "lightbulb"
        }
        if !node.isVisible {
            parts.append("hidden")
        }
        var children: [DocumentOutlineItem] = []
        for child in node.children {
            children.append(Self.node(document, child.index, idPrefix: id, path: &path))
        }
        return DocumentOutlineItem(id: id, title: node.name ?? "Node \(index)", detail: parts.isEmpty ? nil : parts.joined(separator: " · "), systemImage: systemImage, children: children.isEmpty ? nil : children, reference: .node(index))
    }

    static func meshes(_ document: Document) -> [DocumentOutlineItem] {
        document.meshes.enumerated().map { meshIndex, mesh in
            let primitives = mesh.primitives.enumerated().map { index, primitive in
                var parts = ["\(primitive.mode)".lowercased()]
                if let material = primitive.material?.index {
                    parts.append(document.materials.indices.contains(material) ? document.materials[material].name ?? "material \(material)" : "material \(material)")
                }
                parts.append(primitive.attributes.keys.map(\.rawValue).sorted().joined(separator: ", "))
                if !primitive.targets.isEmpty {
                    parts.append("\(primitive.targets.count) morph targets")
                }
                if let extensions = primitive.extensions?.values.keys, !extensions.isEmpty {
                    parts.append(extensions.sorted().joined(separator: ", "))
                }
                return DocumentOutlineItem(id: "meshes/\(meshIndex)/\(index)", title: "Primitive \(index)", detail: parts.joined(separator: " · "), systemImage: "triangle", reference: .primitive(mesh: meshIndex, index: index))
            }
            return DocumentOutlineItem(id: "meshes/\(meshIndex)", title: mesh.name ?? "Mesh \(meshIndex)", detail: "\(mesh.primitives.count) primitive\(mesh.primitives.count == 1 ? "" : "s")", systemImage: "cube", children: primitives.isEmpty ? nil : primitives, reference: .mesh(meshIndex))
        }
    }

    static func materials(_ document: Document) -> [DocumentOutlineItem] {
        document.materials.enumerated().map { index, material in
            var parts = ["\(material.alphaMode ?? .OPAQUE)".lowercased()]
            if material.doubleSided == true {
                parts.append("double-sided")
            }
            let extensions = (material.extensions?.values.keys).map { $0.sorted() } ?? []
            let children = extensions.map { DocumentOutlineItem(id: "materials/\(index)/\($0)", title: $0, systemImage: "puzzlepiece.extension", reference: .material(index)) }
            return DocumentOutlineItem(id: "materials/\(index)", title: material.name ?? "Material \(index)", detail: parts.joined(separator: " · "), systemImage: "paintpalette", children: children.isEmpty ? nil : children, reference: .material(index))
        }
    }

    static func textures(_ document: Document) -> [DocumentOutlineItem] {
        document.textures.enumerated().map { index, texture in
            var parts: [String] = []
            if let image = texture.source?.index {
                parts.append(document.images.indices.contains(image) ? document.images[image].name ?? "image \(image)" : "image \(image)")
            }
            if let extensions = texture.extensions?.values.keys, !extensions.isEmpty {
                parts.append(extensions.sorted().joined(separator: ", "))
            }
            if let sampler = texture.sampler?.index {
                parts.append("sampler \(sampler)")
            }
            return DocumentOutlineItem(id: "textures/\(index)", title: texture.name ?? "Texture \(index)", detail: parts.isEmpty ? nil : parts.joined(separator: " · "), systemImage: "photo", reference: .texture(index))
        }
    }

    static func images(_ document: Document) -> [DocumentOutlineItem] {
        document.images.enumerated().map { index, image in
            var parts: [String] = []
            if let mimeType = image.mimeType {
                parts.append(mimeType)
            }
            if image.bufferView != nil {
                parts.append("embedded")
            } else if let uri = image.uri {
                let text = "\(uri)"
                parts.append(text.hasPrefix("data:") ? "data URI" : text.removingPercentEncoding ?? text)
            }
            return DocumentOutlineItem(id: "images/\(index)", title: image.name ?? "Image \(index)", detail: parts.isEmpty ? nil : parts.joined(separator: " · "), systemImage: "photo.on.rectangle", reference: .image(index))
        }
    }

    static func skins(_ document: Document) -> [DocumentOutlineItem] {
        document.skins.enumerated().map { index, skin in
            DocumentOutlineItem(id: "skins/\(index)", title: skin.name ?? "Skin \(index)", detail: "\(skin.joints.count) joints", systemImage: "figure.walk", reference: .skin(index))
        }
    }

    static func animations(_ document: Document) -> [DocumentOutlineItem] {
        document.animations.enumerated().map { animationIndex, animation in
            let channels = animation.channels.enumerated().map { index, channel in
                let target = channel.target.node.map { node in
                    document.nodes.indices.contains(node.index) ? document.nodes[node.index].name ?? "node \(node.index)" : "node \(node.index)"
                } ?? "pointer"
                var detail = target
                if animation.samplers.indices.contains(channel.sampler) {
                    detail += " · \(animation.samplers[channel.sampler].interpolation.rawValue.lowercased())"
                }
                return DocumentOutlineItem(id: "animations/\(animationIndex)/\(index)", title: channel.target.path.rawValue, detail: detail, systemImage: "arrow.triangle.2.circlepath", reference: .channel(animation: animationIndex, index: index))
            }
            return DocumentOutlineItem(id: "animations/\(animationIndex)", title: animation.name ?? "Animation \(animationIndex)", detail: "\(animation.channels.count) channels", systemImage: "play.circle", children: channels.isEmpty ? nil : channels, reference: .animation(animationIndex))
        }
    }

    static func cameras(_ document: Document) -> [DocumentOutlineItem] {
        document.cameras.enumerated().map { index, camera in
            let detail: String
            if let perspective = camera.perspective {
                detail = "perspective · \(Int((perspective.yfov * 180 / .pi).rounded()))° vertical"
            } else if camera.orthographic != nil {
                detail = "orthographic"
            } else {
                detail = "no projection"
            }
            return DocumentOutlineItem(id: "cameras/\(index)", title: camera.name ?? "Camera \(index)", detail: detail, systemImage: "camera", reference: .camera(index))
        }
    }

    /// The referenced object's JSON properties, sorted by name, after its index; empty when it does not exist.
    static func properties(of reference: DocumentReference, in document: Document) -> [DocumentProperty] {
        func element<T>(_ array: [T], _ index: Int) -> T? {
            array.indices.contains(index) ? array[index] : nil
        }
        let index: String
        let object: (any Encodable)?
        switch reference {
        case .scene(let i): index = "\(i)"; object = element(document.scenes, i)
        case .node(let i): index = "\(i)"; object = element(document.nodes, i)
        case .mesh(let i): index = "\(i)"; object = element(document.meshes, i)
        case let .primitive(mesh, i): index = "\(mesh).\(i)"; object = element(document.meshes, mesh).flatMap { element($0.primitives, i) }
        case .material(let i): index = "\(i)"; object = element(document.materials, i)
        case .texture(let i): index = "\(i)"; object = element(document.textures, i)
        case .image(let i): index = "\(i)"; object = element(document.images, i)
        case .skin(let i): index = "\(i)"; object = element(document.skins, i)
        case .animation(let i): index = "\(i)"; object = element(document.animations, i)
        case let .channel(animation, i): index = "\(animation).\(i)"; object = element(document.animations, animation).flatMap { element($0.channels, i) }
        case .camera(let i): index = "\(i)"; object = element(document.cameras, i)
        case .light(let i): index = "\(i)"; object = element(document.punctualLights, i)
        }
        guard let object, let data = try? JSONEncoder().encode(object), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let properties = json.keys.sorted().map { DocumentProperty(name: $0, value: jsonText(json[$0] as Any)) }
        return [DocumentProperty(name: "index", value: index)] + properties
    }

    private static func jsonText(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "\(value)"
        }
        // Wrapped in an array so scalars serialize too; strip the wrapper.
        return String(text.dropFirst().dropLast())
    }

    static func lightDetail(_ light: Light) -> String {
        var parts = ["\(light.type.rawValue)", "intensity \(light.intensity.formatted(.number.precision(.significantDigits(1 ... 4))))"]
        if light.color != [1, 1, 1] {
            parts.append("color \(light.color.x.formatted(.number.precision(.fractionLength(2)))), \(light.color.y.formatted(.number.precision(.fractionLength(2)))), \(light.color.z.formatted(.number.precision(.fractionLength(2))))")
        }
        return parts.joined(separator: " · ")
    }
}
