import MetalSprocketsGLTF
import Testing

// Animation channels through the public API only (no @testable), as a scene graph loader would read them.
@Suite(.requiresMetal4)
struct AnimationChannelAPITests {
    @Test func readsChannelsWithoutTestableImport() throws {
        let asset = try GLTFAsset(url: makeMorphTriangleFile())
        let clip = try #require(asset.animations.first)
        let channel = try #require(clip.channels.first)
        #expect(channel.target == .node(0, .weights))
        #expect(channel.times == [0, 1])
        #expect(channel.values == [0, 1])
        #expect(channel.componentsPerValue == 1)
        #expect(channel.interpolation == .linear)
        #expect(channel.sample(at: 0.25) == [0.25])
        #expect(channel.sample(at: 5) == [1])
    }
}
