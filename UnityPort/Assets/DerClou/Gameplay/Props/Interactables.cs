namespace DerClou.Gameplay.Props
{
    using DerClou.Core.Data;
    using DerClou.Core.Simulation;
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

    public class Door : MonoBehaviour
    {
        public string DoorId;
        public DoorHingeSide HingeSide;
        public float OpenAngle = 90f;
        public float OpenDuration = 1f;
        public float CloseDuration = 1f;
        public bool IsOpen { get; private set; }
        public bool IsLocked { get; set; }
        public int LockDifficulty = 1;

        private Quaternion closedRot, openRot;
        private float currentProgress;
        private bool isAnimating;
        private float animSpeed;

        private void Awake()
        {
            closedRot = transform.localRotation;
            Vector3 axis = HingeSide == DoorHingeSide.Left ? Vector3.up : Vector3.down;
            openRot = closedRot * Quaternion.AngleAxis(OpenAngle, axis);
        }

        public void SetLocked(bool locked) => IsLocked = locked;

        public void Open()
        {
            if (IsOpen || isAnimating) return;
            IsOpen = true;
            isAnimating = true;
            animSpeed = 1f / OpenDuration;
            currentProgress = 0f;
        }

        public void Close()
        {
            if (!IsOpen || isAnimating) return;
            IsOpen = false;
            isAnimating = true;
            animSpeed = 1f / CloseDuration;
            currentProgress = 1f;
        }

        public void Toggle() { if (IsOpen) Close(); else Open(); }

        private void Update()
        {
            if (!isAnimating) return;
            currentProgress = Mathf.MoveTowards(currentProgress, IsOpen ? 1f : 0f, animSpeed * Time.deltaTime);
            transform.localRotation = Quaternion.Slerp(closedRot, openRot, currentProgress);
            if (Mathf.Approximately(currentProgress, IsOpen ? 1f : 0f)) isAnimating = false;
        }
    }

    public class SecurityCamera : MonoBehaviour
    {
        public string CameraId;
        public float Range = 8f;
        public float FieldOfView = 90f;
        public float ScanArc = 90f;
        public float ScanPeriod = 8f;
        public float MountHeight = 2.4f;
        public bool Powered = true;

        public Transform ConeTransform;
        public Material ConeMaterial;

        private float scanPhase;

        private void Update()
        {
            if (!Powered) return;
            scanPhase += Time.deltaTime / ScanPeriod;
            float yaw = Mathf.Sin(scanPhase * Mathf.PI * 2f) * ScanArc * 0.5f;
            transform.rotation = Quaternion.Euler(0, yaw, 0);

            if (ConeTransform != null)
            {
                ConeTransform.rotation = transform.rotation;
            }
        }

        private void OnDrawGizmosSelected()
        {
            if (!Powered) return;
            Gizmos.color = new Color(0, 1, 0, 0.2f);
            Vector3 dir = transform.forward;
            Vector3 left = Quaternion.Euler(0, -FieldOfView * 0.5f, 0) * dir;
            Vector3 right = Quaternion.Euler(0, FieldOfView * 0.5f, 0) * dir;
            Gizmos.DrawRay(transform.position, left * Range);
            Gizmos.DrawRay(transform.position, right * Range);
        }
    }

    public class Safe : MonoBehaviour
    {
        public string SafeId;
        public bool IsLocked = true;
        public int Difficulty = 3;
        public float CrackDuration = 20f;
        public List<string> ContainedLootIds = new();
        public bool IsOpen { get; private set; }
        public float CrackProgress { get; private set; }

        public void StartCracking(float dt)
        {
            if (!IsLocked || IsOpen) return;
            CrackProgress = Mathf.Min(1f, CrackProgress + dt / CrackDuration);
            if (CrackProgress >= 1f) Unlock();
        }

        public void Unlock()
        {
            IsLocked = false;
            IsOpen = true;
            // Spawn loot
        }
    }
}