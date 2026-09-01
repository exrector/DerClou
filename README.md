# Untitled Heist Game — prototype

An original modern heist-planning game that carries forward the design tradition of [The Clue!](https://en.wikipedia.org/wiki/The_Clue!) and [The Sting!](https://en.wikipedia.org/wiki/The_Sting!) for contemporary platforms.

> **Development update:** active production has moved to **Unreal Engine 5**. The earlier implementations are intentionally preserved below and in the repository history rather than being erased.

The project is currently only a **basic playable prototype** and vertical slice. Its first level demonstrates a compact 3D diorama, character movement, patrols, security observation and deterministic plan outcomes. The planned full game contains **180 levels of varying difficulty**; the current build is an early foundation for that larger campaign. The repository also preserves the earlier native Apple and Unity implementations as an engineering record of the project’s evolution.

## Implementations

- `UnrealPort/` — current Unreal Engine prototype and grant demonstration level.
- ~~`UnityPort/` — active Unity implementation~~ — preserved previous playable implementation and deterministic simulation core.
- ~~`DerClouApp/`, `Packages/` — active native Apple implementation~~ — preserved original Swift/RealityKit research implementation.
- `docs/` — design and technical history.

The complete, source-linked migration record is in [`docs/DEVELOPMENT_HISTORY.md`](docs/DEVELOPMENT_HISTORY.md).

## Original project direction (archived)

The repository began as a native Apple-platform **top-down / 2.5D heist-planning puzzle game** built with Swift, SwiftUI and RealityKit, and later moved through a Unity implementation. Its central concept remains unchanged:

**Study the building → build a precise burglary plan → commit → watch the plan execute → learn from failure → improve the plan.**

The game is not intended to be a clone. It carries forward the high-level design grammar of reconnaissance, deterministic patrols, doors, cameras, alarms, tools, loot, timing and multi-character coordination while using original code, levels, characters, art and story.

## Current stage

The Unreal prototype is under active development. The present milestone focuses on proving the first complete visual gameplay loop before production art and content expansion.

This is an independent project with original code, content direction and game design. It is not affiliated with the creators or publishers of the referenced games.

## AI-assisted development

This is also a practical experiment in **AI-assisted solo game development**. Codex is used throughout the project for repository-scale code exploration, architecture work, Unreal/C++ implementation, debugging, refactoring, migration work and technical documentation.

The repository remains public so the project's engineering history can be inspected directly: native Apple/RealityKit experiments, the Unity implementation, the Unreal migration and the ongoing production code all remain visible instead of being reduced to a polished final snapshot.

## License

The **original source code authored for this project** is released under the [MIT License](LICENSE).

Third-party assets are **not** relicensed by this repository. Art, audio, character models, animations, engine content, plugins, trademarks and other third-party material remain subject to their respective owners' licenses and terms unless a file explicitly states otherwise.

## P.S.

A candid development note: Claude Code has frustrated me enough that there are days when I genuinely want to throw the laptop out of an eleventh-floor window. Codex is the tool I actually want to keep building this game with.
