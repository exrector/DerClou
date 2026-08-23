namespace DerClou.Gameplay.Interaction
{
    using DerClou.Core.Data;
    using DerClou.Core.Systems;
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

        // Tracked only for the player-facing log line when cracking stops —
        // the actual progress/interrupt logic lives in `SafeSystem`, driven
        // from `SimulationStep`, not from this MonoBehaviour's `Update()`.
        private string crackingSafeId;

        public bool HasLoot { get; private set; }
        public bool MissionComplete { get; private set; }
        public event System.Action OnMissionComplete;

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

            // `SafeSystem.Tick` (from `SimulationStep`, not here) does the
            // actual progress/interrupt-on-distance work now — this just
            // watches for the state transition to log it for the player.
            if (crackingSafeId != null)
            {
                var state = SimulationService.Current;
                if (state == null || !state.Safes.TryGetValue(crackingSafeId, out var s))
                {
                    crackingSafeId = null;
                }
                else if (!s.isBeingCracked)
                {
                    Debug.Log(s.isOpen ? $"{crackingSafeId}: взломан." : $"{crackingSafeId}: взлом прерван — слишком далеко.");
                    crackingSafeId = null;
                }
            }
        }

        private void Perform(ActorView actor, Interactable target)
        {
            var door = target.GetComponent<DoorView>();
            if (door != null) { PerformDoor(door); return; }

            var safe = target.GetComponent<SafeView>();
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

        private void PerformDoor(DoorView door)
        {
            var state = SimulationService.Current;
            if (state == null || !state.Doors.TryGetValue(door.DoorId, out var d)) return;

            if (d.isLocked) { Debug.Log($"{door.DoorId}: заперто."); return; }
            DoorSystem.SetOpen(state, door.DoorId, !d.isOpen);
            Debug.Log($"{door.DoorId}: {(!d.isOpen ? "открыта" : "закрыта")}.");
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

        private void PerformSafe(ActorView actor, SafeView safe)
        {
            var state = SimulationService.Current;
            if (state == null || !state.Safes.TryGetValue(safe.SafeId, out var s)) return;

            if (s.isOpen) { Debug.Log($"{safe.SafeId}: уже открыт."); return; }
            SafeSystem.StartCracking(state, safe.SafeId, actor.ActorId);
            crackingSafeId = safe.SafeId;
            Debug.Log($"{safe.SafeId}: взлом начат (~{s.crackDurationSeconds:0}с, не отходи).");
        }

        private void PerformLoot(Interactable loot)
        {
            string requiredSafeId = loot.GetConfigString("requiresSafeId", "");
            var state = SimulationService.Current;
            if (!string.IsNullOrEmpty(requiredSafeId) && state != null
                && state.Safes.TryGetValue(requiredSafeId, out var safe) && !safe.isOpen)
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
