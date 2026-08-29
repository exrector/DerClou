namespace DerClou.Gameplay.Lighting
{
    using DerClou.Core.Data;
    using DerClou.Gameplay.Simulation;
    using UnityEngine;
    using UnityEngine.Rendering;

    /// One Unity-native 3D light implementation shared by wall cameras and
    /// handheld guard flashlights. The same source state supplies position,
    /// yaw, range and angle; Unity's Spot Light supplies the floor footprint,
    /// surface illumination and realtime shadows. No procedural cone mesh is
    /// created.
    public sealed class WorldSpotlightView : MonoBehaviour
    {
        public int SourceId { get; private set; }
        public Transform VisualOrigin { get; private set; }
        public Light SpotLight => spotLight;

        [Range(0.5f, 1f)] public float cameraAimDistanceRatio = 0.92f;
        [Range(0.10f, 0.6f)] public float flashlightAimDistanceRatio = 0.22f;
        public float cameraIntensity = 14f;
        public float flashlightIntensity = 11f;
        public Color cameraColor = new Color(1f, 0.10f, 0.06f);
        public Color flashlightColor = new Color(1f, 0.78f, 0.24f);

        private Light spotLight;

        public void Initialize(int sourceId, Transform visualOrigin)
        {
            SourceId = sourceId;
            VisualOrigin = visualOrigin != null ? visualOrigin : transform;
            EnsureLight();
            Synchronize();
        }

        private void LateUpdate() => Synchronize();

        private void EnsureLight()
        {
            if (spotLight != null) return;
            var lightObject = new GameObject("RealtimeSpotLight");
            lightObject.transform.SetParent(VisualOrigin, false);
            spotLight = lightObject.AddComponent<Light>();
            spotLight.type = LightType.Spot;
            spotLight.lightmapBakeType = LightmapBakeType.Realtime;
            spotLight.renderMode = LightRenderMode.ForcePixel;
            spotLight.shadows = LightShadows.Soft;
            spotLight.shadowStrength = 0.92f;
            // Thin door leaves are only ~12 cm deep in the sandbox. Large
            // default normal bias detached their shadow from the geometry
            // and made a closed door look transparent to the flashlight.
            spotLight.shadowBias = 0.005f;
            spotLight.shadowNormalBias = 0.02f;
            spotLight.shadowNearPlane = 0.03f;
            spotLight.bounceIntensity = 0f;
            spotLight.cullingMask = ~0;
        }

        private void Synchronize()
        {
            var state = SimulationService.Current;
            if (state == null || !state.VisionSources.TryGetValue(SourceId, out var source))
            {
                if (spotLight != null) spotLight.enabled = false;
                return;
            }
            EnsureLight();

            bool powered = source.isEnabled;
            Vector3 planarPosition;
            if (source.kind == VisionSourceKind.GuardActor)
            {
                if (!state.Actors.TryGetValue(source.actorId, out var actor))
                {
                    spotLight.enabled = false;
                    return;
                }
                planarPosition = new Vector3(actor.Position.x, 0f, actor.Position.z);
            }
            else
            {
                planarPosition = new Vector3(source.fixedPosition.x, 0f, source.fixedPosition.z);
                if (source.kind == VisionSourceKind.SecurityCamera
                    && state.Cameras.TryGetValue(source.sourceLabel, out var camera))
                    powered &= camera.powered;
            }

            spotLight.enabled = powered;
            if (!powered) return;

            Vector3 origin = VisualOrigin != null
                ? VisualOrigin.position
                : planarPosition + Vector3.up * source.eyeHeight;
            float yawRadians = source.currentFacingYaw * Mathf.Deg2Rad;
            Vector3 forward = new Vector3(Mathf.Sin(yawRadians), 0f, Mathf.Cos(yawRadians));
            bool cameraSource = source.kind == VisionSourceKind.SecurityCamera;
            float aimRatio = cameraSource ? cameraAimDistanceRatio : flashlightAimDistanceRatio;
            float landingDistance = Mathf.Max(0.75f, source.config.range * aimRatio);
            Vector3 target = planarPosition + forward * landingDistance + Vector3.up * 0.03f;
            Quaternion beamRotation = Quaternion.LookRotation(target - origin, Vector3.up);

            // The housing/flashlight and the emitted light are one entity:
            // both point at the same physical target on the floor.
            VisualOrigin.SetPositionAndRotation(origin, beamRotation);
            spotLight.transform.localPosition = Vector3.zero;
            spotLight.transform.localRotation = Quaternion.identity;
            spotLight.range = Mathf.Sqrt(source.config.range * source.config.range
                + source.eyeHeight * source.eyeHeight) + 0.5f;
            spotLight.spotAngle = Mathf.Clamp(source.config.fieldOfViewDegrees, 1f, 179f);
            spotLight.innerSpotAngle = spotLight.spotAngle * 0.68f;
            spotLight.color = cameraSource ? cameraColor : flashlightColor;
            spotLight.intensity = cameraSource ? cameraIntensity : flashlightIntensity;
        }
    }
}
