import Foundation
import SwiftGLTF

// KHR_node_visibility: hides a node's mesh and all of its descendants' meshes.
// https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_node_visibility
// SwiftGLTF has no typed version of this extension yet.
public struct KHRNodeVisibility: GLTFExtension {
    public static let extensionName = "KHR_node_visibility"

    public let visible: Bool

    public enum CodingKeys: CodingKey {
        case visible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
    }
}

public extension Node {
    /// False when KHR_node_visibility hides this node (and its descendants).
    var isVisible: Bool {
        (try? extensionValue(KHRNodeVisibility.self))?.visible ?? true
    }
}
