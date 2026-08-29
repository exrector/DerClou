# Development history

DerClou is one continuous game-design and engineering project. The repository intentionally preserves each implementation stage so the evolution of the prototype can be inspected rather than reconstructed from screenshots or claims.

## 1. Native Apple prototype — Swift, SwiftUI and RealityKit

**Period:** 16–23 August 2026  
**Source:** [`DerClouApp/`](../DerClouApp), [`Packages/`](../Packages), [`DerClouTests/`](../DerClouTests)

The first implementation established the heist-planning concept, the 2D deterministic simulation under a 3D diorama, tap navigation, tactical camera experiments, reusable interaction components, guard patrols, security vision and the early character pipeline.

This stage is represented by dozens of incremental commits, including the initial architecture, deterministic A* navigation, mission clock, camera interaction, generic interaction framework, animation synchronisation and the character-system audit.

## 2. Unity prototype

**Period:** 23–29 August 2026  
**Source:** [`UnityPort/`](../UnityPort)

The Unity port turned the research prototype into a playable vertical slice and separated deterministic game state from visual presentation. It contains the plan → execute → retry loop, pure C# simulation state, patrol and camera timing, door and safe state, navigation and vision work, developer sandbox tooling and automated tests.

The Unity stage remains buildable source history, not a binary export. Large downloaded marketplace packages, generated caches and discarded animation experiments are excluded from the public repository.

## 3. Unreal Engine prototype — current

**Period:** from 29 August 2026  
**Source:** [`UnrealPort/`](../UnrealPort)

Active development has moved to Unreal Engine 5. The current milestone is a grant demonstration built around the first compact heist level: a 3D diorama, autonomous guard patrol, rotating security camera, visible observation lighting and two deterministic demonstration outcomes.

All subsequent Unreal development is committed directly inside this repository. The external working copy used during the initial import is not a second source of truth.

## Repository evidence

- A single Git history records the project from its initial design documents through all three implementations.
- Source, tests, project settings and technical documentation are retained for the Apple and Unity stages.
- The Unreal project lives in `UnrealPort/` and is the current working project.
- Generated editor state, caches and third-party marketplace payloads are excluded so the public repository contains reviewable project work rather than local machine noise.

The implementation changed; the core game remained the same:

**Study the building → build a precise burglary plan → commit → watch the plan execute → learn from failure → improve the plan.**
