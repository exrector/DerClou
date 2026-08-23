import RealityKit

/// Looks up a character's baked clips by name instead of by list position.
///
/// Before this existed, every place that needed a character's animation —
/// `LevelSceneBuilder`'s load-time freeze pose, `WalkAnimationSync`'s
/// start/stop — read `model.availableAnimations.first`: whichever clip
/// happened to be first in the exported usdz, unnamed and unchecked. That
/// was silently correct only while every character carried exactly one clip.
/// The source pipeline now deliberately exports a semantic clip library, so
/// `.first` would make the chosen action depend on USD ordering. RealityKit's
/// own answer
/// to this, `AnimationLibraryComponent`, has been available since iOS 18.0
/// (confirmed directly against this project's installed SDK — see
/// RealityFoundation.swiftinterface — matching the iOS 18 deployment floor
/// CLAUDE.md sets, well below the iOS 27 the newer AnimationGraphComponent
/// needs): a per-entity `[String: AnimationResource]` keyed however the
/// USD SkelAnimation prim was named at export. `ArtSource/Tools/
/// apply_animation.py` names every extracted action by its gameplay semantic,
/// so the key is already there in every exported usdz — this reads it by name
/// instead of by position.
@MainActor
public enum CharacterAnimationLibrary {
    /// Blender appends `.001` when an action name already exists, and USD
    /// exports that suffix as `_001`. Those are pipeline details, not part of
    /// the gameplay-facing animation contract.
    public static func canonicalName(_ name: String) -> String {
        guard name.count > 4 else { return name }
        let suffix = name.suffix(4)
        guard let separator = suffix.first,
              separator == "." || separator == "_",
              suffix.dropFirst().allSatisfy(\.isNumber) else {
            return name
        }
        return String(name.dropLast(4))
    }

    /// Builds an `AnimationLibraryComponent` for `model` itself, keyed by
    /// each of its clips' own names (falling back to a stable index string
    /// for the rare unnamed clip rather than dropping it). Call once, right
    /// after loading a character's model — `animation(named:on:)` reads
    /// what this attaches.
    public static func attach(
        to model: Entity,
        semanticAliases: [String: String] = [:],
        supplementalClips: [String: AnimationResource] = [:]
    ) {
        // USD exporters disagree about where availableAnimations is surfaced:
        // some publish it on the loaded root, while glTF-derived USD commonly
        // publishes it on a nested SkelRoot. Keep that structural detail out of
        // gameplay by reading the clip from its actual playback owner.
        guard let owner = animationOwners(in: model).first else { return }
        let clips = owner.availableAnimations
        var library = AnimationLibraryComponent()
        for (index, clip) in clips.enumerated() {
            let exportedName = clip.name ?? "clip\(index)"
            library.animations[exportedName] = clip

            let contractName = canonicalName(exportedName)
            if library.animations[contractName] == nil {
                library.animations[contractName] = clip
            }
        }

        // Some RealityKit/Exporter combinations expose a USD animation
        // under a framework-generated name. Keep that convention behind
        // an explicit adapter instead of allowing `.first` order to become
        // gameplay behavior again.
        for (contractName, sourceName) in semanticAliases {
            if let source = clips.first(where: { $0.name == sourceName }) {
                library.animations[contractName] = source
            }
        }
        for (contractName, resource) in supplementalClips {
            library.animations[contractName] = resource
        }
        // Keep the semantic catalogue on the stable visual root. RealityKit
        // treats an imported SkelRoot as an internal bind-point entity and may
        // reject user components on it ("Failed to set override status for
        // bind point component member"). Playback still targets `owner`; only
        // the catalogue lives here, independent of exporter hierarchy.
        model.components.set(library)
    }

    /// First animation exported anywhere in an isolated single-semantic
    /// carrier. Carrier identity, not ordering among actions, supplies the
    /// semantic name.
    public static func firstAvailableAnimation(in root: Entity) -> AnimationResource? {
        animationOwners(in: root).first?.availableAnimations.first
    }

    /// The clip named `name` on one of `container`'s direct children —
    /// mirroring how a loaded character is actually shaped: `attach(to:)`
    /// is called with the loaded usdz's own root entity, which is added as
    /// a child of the actor's outer container entity, so a lookup starting
    /// from that container has to check its children rather than itself.
    /// Nil if `attach(to:)` was never called for this actor, or if no clip
    /// by that name exists.
    public static func animation(named name: String, on container: Entity) -> AnimationResource? {
        bindings(named: name, on: container).first?.resource
    }

    /// The visual children that actually own a named animation. Systems play
    /// only on these entities, never on unrelated children such as selection
    /// rings or vision-cone overlays.
    public static func bindings(
        named name: String,
        on container: Entity
    ) -> [(entity: Entity, resource: AnimationResource)] {
        descendants(including: container).compactMap { entity in
            guard let resource = entity.components[AnimationLibraryComponent.self]?.animations[name] else {
                return nil
            }
            let playbackEntity = animationOwners(in: entity).first ?? entity
            return (playbackEntity, resource)
        }
    }

    static func animationOwners(in root: Entity) -> [Entity] {
        descendants(including: root).filter { !$0.availableAnimations.isEmpty }
    }

    private static func descendants(including root: Entity) -> [Entity] {
        var result = [root]
        for child in root.children {
            result.append(contentsOf: descendants(including: child))
        }
        return result
    }
}
