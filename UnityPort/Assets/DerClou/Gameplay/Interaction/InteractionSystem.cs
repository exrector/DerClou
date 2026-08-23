namespace DerClou.Gameplay.Interaction
{
    using DerClou.Core.Data;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Props;
    using DerClou.Gameplay.Simulation;
    using UnityEngine;
    using System.Collections.Generic;

    /// <summary>
    /// Resolves a clicked <see cref="Interactable"/> into an actual effect —
    /// walking the selected actor into range first if it isn't close enough,
    /// then running the one behavior each prop exists for (door, security
    /// panel, safe, loot, extraction). This is the minimum real version of
    /// the "tap world objects to interact" rule in the project CLAUDE.md and
    /// of the security-dependency grammar it describes (switch gates camera,
    /// safe gates loot, loot gates extraction) — not the general dependency
    /// graph engine that grammar eventually calls for, which is out of scope
    /// for a level whose whole point right now is being clickable.
    /// </summary>
    public class InteractionSystem : MonoBehaviour
    {
        public const float InteractRange = 1.6f;

        private ActorView pendingActor;
        private Interactable pendingTarget;

        private ActorView crackingActor;
        private Safe crackingSafe;

        private readonly Dictionary<string, Safe> safesById = new();

        public bool HasLoot { get; private set; }
        public bool MissionComplete { get; private set; }
        public event System.Action OnMissionComplete;

        /// Scans the just-built level for the devices interactions need to
        /// look up by id. Called once after `LevelBuilder.Build` — the
        /// builder itself stays unaware this system exists. Cameras aren't
        /// looked up this way any more (U2 step 2c) — `MissionState.Cameras`
        /// is itself the registry, keyed by the same id.
        public void DiscoverRegistries()
        {
            safesById.Clear();
            foreach (var safe in FindObjectsOfType<Safe>()) safesById[safe.SafeId] = safe;
        }

        public void RequestInteract(ActorView actor, Interactable target)
        {
            if (actor == null || target == null || MissionComplete) return;

            if (PlanarDistance(actor.transform.position, target.transform.position) > InteractRange)
            {
                actor.SetDestination(target.transform.position);
                pendingActor = actor;
                pendingTarget = target;
                return;
            }

            pendingActor = null;
            pendingTarget = null;
            Perform(actor, target);
        }

        private void Update()
        {
            if (pendingActor != null && pendingTarget != null
                && PlanarDistance(pendingActor.transform.position, pendingTarget.transform.position) <= InteractRange)
            {
                var actor = pendingActor;
                var target = pendingTarget;
                pendingActor = null;
                pendingTarget = null;
                Perform(actor, target);
            }

            if (crackingSafe != null)
            {
                if (PlanarDistance(crackingActor.transform.position, crackingSafe.transform.position) > InteractRange)
                {
                    Debug.Log($"{crackingSafe.SafeId}: взлом прерван — слишком далеко.");
                    crackingSafe = null;
                    crackingActor = null;
                }
                else
                {
                    crackingSafe.StartCracking(Time.deltaTime);
                    if (crackingSafe.IsOpen)
                    {
                        Debug.Log($"{crackingSafe.SafeId}: взломан.");
                        crackingSafe = null;
                        crackingActor = null;
                    }
                }
            }
        }

        private void Perform(ActorView actor, Interactable target)
        {
            var door = target.GetComponent<Door>();
            if (door != null) { PerformDoor(door); return; }

            var safe = target.GetComponent<Safe>();
            if (safe != null) { PerformSafe(actor, safe); return; }

            if (target.Supports(InteractionKind.ToggleSwitch) || target.Supports(InteractionKind.Hack))
            {
                PerformPanel(target);
                return;
            }

            if (target.Supports(InteractionKind.TakeLoot))
            {
                PerformLoot(target);
                return;
            }

            if (target.Supports(InteractionKind.Extract))
            {
                PerformExtract();
                return;
            }

            Debug.Log($"{target.InteractableId}: нет реализованного действия.");
        }

        private void PerformDoor(Door door)
        {
            if (door.IsLocked) { Debug.Log($"{door.DoorId}: заперто."); return; }
            door.Toggle();
            Debug.Log($"{door.DoorId}: {(door.IsOpen ? "открыта" : "закрыта")}.");
        }

        private void PerformPanel(Interactable panel)
        {
            string controlledId = panel.GetConfigString("controlsCameraId", "");
            var state = SimulationService.Current;
            if (string.IsNullOrEmpty(controlledId) || state == null || !state.Cameras.TryGetValue(controlledId, out var cam))
            {
                Debug.Log($"{panel.InteractableId}: не подключена ни к одному устройству.");
                return;
            }
            cam.powered = !cam.powered;
            state.Cameras[controlledId] = cam;
            Debug.Log($"{panel.InteractableId}: камера '{controlledId}' теперь {(cam.powered ? "включена" : "выключена")}.");
        }

        private void PerformSafe(ActorView actor, Safe safe)
        {
            if (safe.IsOpen) { Debug.Log($"{safe.SafeId}: уже открыт."); return; }
            crackingActor = actor;
            crackingSafe = safe;
            Debug.Log($"{safe.SafeId}: взлом начат (~{safe.CrackDuration:0}с, не отходи).");
        }

        private void PerformLoot(Interactable loot)
        {
            string requiredSafeId = loot.GetConfigString("requiresSafeId", "");
            if (!string.IsNullOrEmpty(requiredSafeId)
                && safesById.TryGetValue(requiredSafeId, out var safe) && !safe.IsOpen)
            {
                Debug.Log($"{loot.InteractableId}: сначала вскрой '{requiredSafeId}'.");
                return;
            }

            HasLoot = true;
            loot.gameObject.SetActive(false);
            Debug.Log($"{loot.InteractableId}: забрано.");
        }

        private void PerformExtract()
        {
            if (!HasLoot)
            {
                Debug.Log("Эвакуация: сначала возьми добычу.");
                return;
            }

            MissionComplete = true;
            Debug.Log("=== МИССИЯ ВЫПОЛНЕНА: добыча вынесена ===");
            OnMissionComplete?.Invoke();
        }

        private static float PlanarDistance(Vector3 a, Vector3 b) =>
            Vector2.Distance(new Vector2(a.x, a.z), new Vector2(b.x, b.z));
    }
}
