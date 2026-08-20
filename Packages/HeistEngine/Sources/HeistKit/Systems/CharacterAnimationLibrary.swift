import RealityKit

/// Looks up a character's baked clips by name instead of by list position.
///
/// Before this existed, every place that needed a character's animation —
/// `LevelSceneBuilder`'s load-time freeze pose, `WalkAnimationSync`'s
/// start/stop — read `model.availableAnimations.first`: whichever clip
/// happened to be first in the exported usdz, unnamed and unchecked. That
/// was silently correct only because every character has ever carried
/// exactly one clip. The moment a second one exists (an Idle clip is the
/// obvious next one — see docs/CHARACTER_ASSET_PIPELINE.md's animation
/// strategy section) `.first` becomes a coin flip. RealityKit's own answer
/// to this, `AnimationLibraryComponent`, has been available since iOS 18.0
/// (confirmed directly against this project's installed SDK — see
/// RealityFoundation.swiftinterface — matching the iOS 18 deployment floor
/// CLAUDE.md sets, well below the iOS 27 the newer AnimationGraphComponent
/// needs): a per-entity `[String: AnimationResource]` keyed however the
/// USD SkelAnimation prim was named at export. `ArtSource/Tools/
/// apply_animation.py` already names every action it applies (its
/// `action_name` argument, currently always "Walk"), so the key is already
/// there in every exported usdz — this just starts reading it by name
/// instead of by position.
@MainActor
public enum CharacterAnimationLibrary {
    /// Builds an `AnimationLibraryComponent` for `model` itself, keyed by
    /// each of its clips' own names (falling back to a stable index string
    /// for the rare unnamed clip rather than dropping it). Call once, right
    /// after loading a character's model — `animation(named:on:)` reads
    /// what this attaches.
    public static func attach(to model: Entity) {
        let clips = model.availableAnimations
        guard !clips.isEmpty else { return }
        var library = AnimationLibraryComponent()
        for (index, clip) in clips.enumerated() {
            library.animations[clip.name ?? "clip\(index)"] = clip
        }
        model.components.set(library)
    }

    /// The clip named `name` on one of `container`'s direct children —
    /// mirroring how a loaded character is actually shaped: `attach(to:)`
    /// is called with the loaded usdz's own root entity, which is added as
    /// a child of the actor's outer container entity, so a lookup starting
    /// from that container has to check its children rather than itself.
    /// Nil if `attach(to:)` was never called for this actor, or if no clip
    /// by that name exists.
    public static func animation(named name: String, on container: Entity) -> AnimationResource? {
        for child in container.children {
            if let resource = child.components[AnimationLibraryComponent.self]?.animations[name] {
                return resource
            }
        }
        return nil
    }
}
