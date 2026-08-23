namespace DerClou.Gameplay.Props
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;
    using DerClou.Gameplay.Simulation;
    using System.Collections.Generic;
    using UnityEngine;

    public class Interactable : MonoBehaviour
    {
        public string InteractableId;
        public InteractionKind[] SupportedInteractions;
        public InteractableComponent RuntimeState;

        public bool Supports(InteractionKind kind)
        {
            foreach (var k in SupportedInteractions) if (k == kind) return true;
            return false;
        }

        public float GetConfigFloat(string key, float defaultValue = 0f)
        {
            if (RuntimeState.config.TryGetValue(key, out var v) && v.type == LevelValue.Type.Float) return v.floatValue;
            return defaultValue;
        }

        public int GetConfigInt(string key, int defaultValue = 0)
        {
            if (RuntimeState.config.TryGetValue(key, out var v) && v.type == LevelValue.Type.Int) return v.intValue;
            return defaultValue;
        }

        public bool GetConfigBool(string key, bool defaultValue = false)
        {
            if (RuntimeState.config.TryGetValue(key, out var v) && v.type == LevelValue.Type.Bool) return v.boolValue;
            return defaultValue;
        }

        public string GetConfigString(string key, string defaultValue = "")
        {
            if (RuntimeState.config.TryGetValue(key, out var v) && v.type == LevelValue.Type.String) return v.stringValue;
            return defaultValue;
        }
    }

    /// <summary>
    /// Renamed from <c>Door</c> in U2 step 2d (`docs/U2_SIMULATION_DESIGN.md`).
    /// The open/close animation that used to run in this class's
    /// <c>Update()</c> now lives in the pure-C#
    /// <c>DerClou.Core.Systems.DoorSystem</c>, ticked from
    /// <see cref="Core.Simulation.SimulationStep"/>. This class only reads
    /// <c>DoorState.openProgress</c> back each frame to slerp the hinge
    /// rotation — it never decides whether the door is open, locked, or
    /// mid-swing.
    /// <para>
    /// <c>openRot</c> depends on hinge side/angle, which weren't known at
    /// <c>Awake()</c> in the old class — <c>LevelBuilder.BuildDoor</c> set
    /// them on public fields immediately *after* <c>AddComponent&lt;Door&gt;()</c>
    /// already ran <c>Awake()</c>, so it silently computed <c>openRot</c>
    /// from the field *initializers'* defaults (hinge = <c>Left</c>, angle =
    /// 90°) rather than the level's actual config — invisible only because
    /// Level01's one door happens to use both defaults. Fixed here by moving
    /// that computation into <see cref="SetHinge"/>, called explicitly once
    /// the real values are known.
    /// </para>
    /// </summary>
    public class DoorView : MonoBehaviour
    {
        public string DoorId;

        private Quaternion closedRot, openRot;

        private void Awake()
        {
            closedRot = transform.localRotation;
        }

        public void SetHinge(DoorHingeSide hingeSide, float openAngleDegrees)
        {
            Vector3 axis = hingeSide == DoorHingeSide.Left ? Vector3.up : Vector3.down;
            openRot = closedRot * Quaternion.AngleAxis(openAngleDegrees, axis);
        }

        private void LateUpdate()
        {
            var state = SimulationService.Current;
            if (state == null || !state.Doors.TryGetValue(DoorId, out var d)) return;
            transform.localRotation = Quaternion.Slerp(closedRot, openRot, d.openProgress);
        }
    }

    /// <summary>
    /// Renamed from <c>SecurityCamera</c> in U2 step 2c
    /// (`docs/U2_SIMULATION_DESIGN.md`). The scan-sweep math that used to
    /// run in this class's <c>Update()</c> now lives in the pure-C#
    /// <c>DerClou.Core.Systems.SecurityCameraSystem</c>, ticked from
    /// <see cref="Core.Simulation.SimulationStep"/>. This class only reads
    /// <c>CameraState.currentYaw</c> back each frame to rotate the
    /// transform/cone — it never decides whether the camera is powered or
    /// where it's currently looking.
    /// </summary>
    public class CameraView : MonoBehaviour
    {
        public string CameraId;
        public Transform ConeTransform;
        public Material ConeMaterial;

        // Editor-gizmo-only cosmetics — not gameplay-authoritative (that's
        // `CameraState.range`/`fieldOfView`). Set once at spawn from the
        // same source data so the gizmo still matches reality; kept
        // separate so `OnDrawGizmosSelected` (which can run in Edit mode,
        // before `SimulationService.Current` exists) never needs state.
        public float GizmoRange = 8f;
        public float GizmoFieldOfView = 90f;

        private void LateUpdate()
        {
            var state = SimulationService.Current;
            if (state == null || !state.Cameras.TryGetValue(CameraId, out var cam)) return;

            transform.rotation = Quaternion.Euler(0, cam.currentYaw, 0);
            if (ConeTransform != null)
            {
                ConeTransform.rotation = transform.rotation;
            }
        }

        private void OnDrawGizmosSelected()
        {
            Gizmos.color = new Color(0, 1, 0, 0.2f);
            Vector3 dir = transform.forward;
            Vector3 left = Quaternion.Euler(0, -GizmoFieldOfView * 0.5f, 0) * dir;
            Vector3 right = Quaternion.Euler(0, GizmoFieldOfView * 0.5f, 0) * dir;
            Gizmos.DrawRay(transform.position, left * GizmoRange);
            Gizmos.DrawRay(transform.position, right * GizmoRange);
        }
    }

    /// <summary>
    /// Renamed from <c>Safe</c> in U2 step 2e (`docs/U2_SIMULATION_DESIGN.md`)
    /// — the last of U2's five migration slices. All the cracking math
    /// (progress accumulation, the proximity check that used to compare two
    /// Transforms in <c>InteractionSystem.Update()</c>) moved to the pure-C#
    /// <c>DerClou.Core.Systems.SafeSystem</c>. This class is now just an id
    /// marker for <c>InteractionSystem</c> to find via
    /// <c>GetComponent&lt;SafeView&gt;()</c> — same as before, a safe has no
    /// visible change on opening, so there is nothing for a per-frame
    /// Update/LateUpdate here to apply.
    /// </summary>
    public class SafeView : MonoBehaviour
    {
        public string SafeId;
    }
}