namespace DerClou.Gameplay.Camera
{
    using UnityEngine;
    using UnityEngine.InputSystem;

    /// <summary>
    /// Tactical camera — resting pose and player-input contract both come
    /// from <c>docs/UI_AND_CAMERA.md</c> (the owner: "everything in the
    /// original docs stays valid, only the engine changes"), not invented
    /// per-engine:
    /// <list type="bullet">
    /// <item>Resting tilt is fixed, not straight-down — <c>docs/ART_DIRECTION.md</c>'s
    /// "tabletop diorama" direction: "angled, never overhead... this is what
    /// allows the view to be tilted far enough to have depth at all." The
    /// straight-down look was rejected as reading like a sealed box.</item>
    /// <item>The visual diorama may yaw a little under a two-finger drag.
    /// This changes only the rendering camera; simulation coordinates,
    /// navigation and vision remain in the authoritative X/Z plane.</item>
    /// </list>
    /// The Swift version additionally kept an off-axis projection matrix so
    /// peeking never visibly moved the outer wall-top frame on screen — that
    /// trick existed to work around a RealityKit-specific bug (straight-down
    /// orthographic cameras threw no shadows there, forcing a contorted
    /// perspective-camera-pretending-to-be-orthographic setup). Unity's
    /// perspective camera at a real tilt has no such bug, so peek here is a
    /// plain clamped position shift — same player-facing gesture and range,
    /// simpler implementation.
    /// </summary>
    public class TacticalCamera : MonoBehaviour
    {
        [Header("Camera Settings")]
        public Camera mainCamera;
        // How high above the floor the camera sits. Never set anywhere else:
        // without it the camera stays at its GameObject's default Y (0) —
        // level with the floor it's supposed to be looking down at — which
        // is why nothing rendered before this was added.
        public float height = 20f;
        // 90 = straight down. Lower = more tilted toward the horizon. Kept
        // moderate (not a dramatic near-side view) per GAME_DESIGN.md: "Do
        // not sacrifice path-planning readability for cinematic effects."
        public float pitchDegrees = 70f;
        public float orthographicSize = 15f;
        public float minOrthoSize = 5f;
        public float maxOrthoSize = 30f;
        public float zoomSpeed = 10f;

        [Header("Diorama orbit (two-finger horizontal drag)")]
        public float maxYawDegrees = 20f;
        public float yawSensitivity = 0.09f;
        public float editorTrackpadYawSensitivity = 1.5f;

        [Header("Diorama joystick (presentation only)")]
        public float minPitchDegrees = 52f;
        public float maxPitchDegrees = 82f;
        public float joystickYawSpeedDegreesPerSecond = 42f;
        public float joystickPitchSpeedDegreesPerSecond = 34f;

        [Header("Peek (docs/UI_AND_CAMERA.md: one-finger drag)")]
        // How far the camera may shift sideways/forward off its framed
        // position. Not derived from the documented "±20°, 0.09°/point"
        // figure — that was an angular parameter of the off-axis projection
        // trick above, which has no equivalent here. Tuned by feel instead.
        public float maxPeekOffset = 4f;
        public float peekSensitivity = 0.015f; // world units per screen pixel

        [Header("Bounds")]
        public Vector2 minWorldPos = new Vector2(-50, -50);
        public Vector2 maxWorldPos = new Vector2(50, 50);

        // The framed position `ClampToBounds`/`FocusOn` compute — peek is
        // layered on top of this each frame, never baked into it, so
        // re-framing (e.g. a future "fit whole mission" button) always
        // starts from zero peek rather than compounding drift.
        private Vector3 homePosition;
        private Vector2 peekOffset;
        private Vector3 focusPoint;
        private float authoredYawDegrees;
        private float yawOffsetDegrees;
        private bool usesOrthographicProjection = true;

        // How far "behind" (−Z) the camera must sit, at its current height
        // and pitch, for its view axis to still hit the ground point it is
        // nominally centered on. At pitch=90 this is 0 (camera sits directly
        // above what it looks at, the old behavior); it grows as the tilt
        // increases.
        private float ZOffsetForTilt =>
            pitchDegrees >= 89.9f ? 0f : height / Mathf.Tan(pitchDegrees * Mathf.Deg2Rad);

        private void Awake()
        {
            authoredYawDegrees = transform.eulerAngles.y;
            yawOffsetDegrees = 0f;
            transform.rotation = Quaternion.Euler(pitchDegrees, CurrentYawDegrees, 0);
            focusPoint = new Vector3(transform.position.x, 0f, transform.position.z + ZOffsetForTilt);
            RebuildHomePosition();
            transform.position = homePosition;
            // `GameBootstrap` creates this component via `AddComponent`, which
            // runs `Awake` immediately — before the very next line in
            // `GameBootstrap.CreateCoreSystems` gets to assign or create
            // `mainCamera`. There is usually no `Camera.main` yet either (no
            // camera exists in the scene until that same bootstrap code adds
            // one). `ApplyCameraSettings` is safe to skip here and is called
            // again, authoritatively, once `mainCamera` is actually set.
            if (mainCamera == null) mainCamera = Camera.main;
            ApplyCameraSettings();
        }

        /// Idempotent: safe to call again once `mainCamera` is assigned or
        /// created after this component already exists.
        public void ApplyCameraSettings()
        {
            if (mainCamera == null) return;
            mainCamera.orthographic = usesOrthographicProjection;
            if (usesOrthographicProjection) mainCamera.orthographicSize = orthographicSize;
        }

        private void LateUpdate()
        {
            HandleZoom();
            ClampFocusToBounds();
            RebuildHomePosition();
            transform.position = homePosition + new Vector3(peekOffset.x, 0, peekOffset.y);
            SynchronizeRenderCameraTransform();
        }

        private void HandleZoom()
        {
            // Input System scroll is reported in platform units (commonly
            // 120 per wheel notch), while the previous API returned notches.
            Vector2 scroll = Mouse.current == null
                ? Vector2.zero
                : Mouse.current.scroll.ReadValue() / 120f;
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
            // A Mac trackpad's two-finger horizontal swipe arrives in the
            // Editor as horizontal scroll, not as touch contacts. Treat it as
            // the simulator equivalent of the iPhone two-finger orbit.
            if (Mathf.Abs(scroll.x) > Mathf.Abs(scroll.y) && Mathf.Abs(scroll.x) > 0.01f)
            {
                ApplyDioramaOrbit(scroll.x * editorTrackpadYawSensitivity / Mathf.Max(0.001f, yawSensitivity));
                return;
            }
#endif
            if (Mathf.Abs(scroll.y) > 0.01f)
            {
                if (usesOrthographicProjection)
                {
                    orthographicSize = Mathf.Clamp(orthographicSize - scroll.y * zoomSpeed * Time.deltaTime * 60f, minOrthoSize, maxOrthoSize);
                    mainCamera.orthographicSize = orthographicSize;
                }
                else mainCamera.fieldOfView = Mathf.Clamp(mainCamera.fieldOfView - scroll.y * 2f, 20f, 80f);
            }
        }

        /// Called from `InputManager` while a one-finger drag is in
        /// progress — the *only* player gesture that moves this camera
        /// (`docs/UI_AND_CAMERA.md`: rotation and free panning are both
        /// explicitly "not offered — decided"). `screenDelta` is the
        /// frame's mouse movement in pixels; `InputManager` is responsible
        /// for telling a drag apart from a tap so ordinary clicks don't
        /// also nudge the camera.
        public void ApplyPeek(Vector2 screenDelta)
        {
            peekOffset += screenDelta * peekSensitivity;
            peekOffset = Vector2.ClampMagnitude(peekOffset, maxPeekOffset);
        }

        /// Rotates only the observer around the fixed ground-plane focus.
        /// No world transform and no simulation state is touched.
        public void ApplyDioramaOrbit(float horizontalScreenDelta)
        {
            yawOffsetDegrees = Mathf.Clamp(
                yawOffsetDegrees + horizontalScreenDelta * yawSensitivity,
                -maxYawDegrees,
                maxYawDegrees);
            transform.rotation = Quaternion.Euler(pitchDegrees, CurrentYawDegrees, 0f);
            RebuildHomePosition();
            // Apply in the gesture frame; waiting for LateUpdate makes direct
            // touch motion visibly lag and complicates frame-by-frame checks.
            transform.position = homePosition + new Vector3(peekOffset.x, 0f, peekOffset.y);
            SynchronizeRenderCameraTransform();
        }

        /// <summary>
        /// Applies the official Input System on-screen stick to the observer
        /// rig only. The mission state, level and every gameplay transform
        /// remain untouched, so looking around cannot change a replay.
        /// </summary>
        public void ApplyDioramaJoystick(Vector2 normalizedInput, float unscaledDeltaTime)
        {
            if (normalizedInput.sqrMagnitude < 0.0001f) return;

            yawOffsetDegrees = Mathf.Clamp(
                yawOffsetDegrees + normalizedInput.x * joystickYawSpeedDegreesPerSecond * unscaledDeltaTime,
                -maxYawDegrees,
                maxYawDegrees);
            pitchDegrees = Mathf.Clamp(
                pitchDegrees - normalizedInput.y * joystickPitchSpeedDegreesPerSecond * unscaledDeltaTime,
                minPitchDegrees,
                maxPitchDegrees);

            RebuildHomePosition();
            transform.position = homePosition + new Vector3(peekOffset.x, 0f, peekOffset.y);
            SynchronizeRenderCameraTransform();
        }

        /// The joystick's centre is a one-shot home action. "Top" means the
        /// highest readable diorama pitch allowed by this camera profile,
        /// with authored yaw restored and all temporary peek removed.
        public void ResetToTopView()
        {
            yawOffsetDegrees = 0f;
            pitchDegrees = maxPitchDegrees;
            peekOffset = Vector2.zero;
            RebuildHomePosition();
            transform.position = homePosition;
            SynchronizeRenderCameraTransform();
        }

        public float CurrentYawDegrees => authoredYawDegrees + yawOffsetDegrees;

        /// Editor authoring bridge: makes the runtime Game camera reproduce a
        /// Scene View pose without moving any gameplay object. The copied
        /// pose becomes the new neutral diorama angle; touch orbit remains a
        /// small ±maxYawDegrees offset around it.
        public void SetAuthoredView(
            Vector3 cameraPosition,
            Quaternion cameraRotation,
            bool orthographic,
            float projectionValue)
        {
            transform.SetPositionAndRotation(cameraPosition, cameraRotation);
            pitchDegrees = NormalizeSignedAngle(cameraRotation.eulerAngles.x);
            authoredYawDegrees = NormalizeSignedAngle(cameraRotation.eulerAngles.y);
            yawOffsetDegrees = 0f;
            height = Mathf.Max(0.1f, cameraPosition.y);

            Vector3 forward = transform.forward;
            float distanceToFloor = Mathf.Abs(forward.y) > 0.0001f
                ? -cameraPosition.y / forward.y
                : 0f;
            focusPoint = distanceToFloor > 0f
                ? cameraPosition + forward * distanceToFloor
                : new Vector3(cameraPosition.x, 0f, cameraPosition.z);
            focusPoint.y = 0f;
            homePosition = cameraPosition;
            peekOffset = Vector2.zero;

            if (mainCamera != null)
            {
                usesOrthographicProjection = orthographic;
                SynchronizeRenderCameraTransform();
                mainCamera.orthographic = orthographic;
                if (orthographic)
                {
                    orthographicSize = Mathf.Clamp(projectionValue, minOrthoSize, maxOrthoSize);
                    mainCamera.orthographicSize = orthographicSize;
                }
                else mainCamera.fieldOfView = projectionValue;
            }
        }

        private void ClampFocusToBounds()
        {
            if (!usesOrthographicProjection)
            {
                focusPoint.x = Mathf.Clamp(focusPoint.x, minWorldPos.x, maxWorldPos.x);
                focusPoint.z = Mathf.Clamp(focusPoint.z, minWorldPos.y, maxWorldPos.y);
                return;
            }
            float halfH = mainCamera.orthographicSize;
            float halfW = halfH * mainCamera.aspect;

            // This assumes the camera's view is *smaller* than the level, so
            // there is a real range to pan within. `LevelBuilder.Build` sets
            // `orthographicSize` to frame the whole level with margin, which
            // makes the view *larger* than the bounds on at least one axis —
            // `minWorldPos.x + halfW` then exceeds `maxWorldPos.x - halfW`,
            // and `Mathf.Clamp` with min > max snaps to whichever bound it
            // checks second, every single `LateUpdate`. That silently
            // overrode the camera's framed position with a corner offset the
            // instant Play started — the empty-looking Game view was this,
            // not a level-generation problem. Fall back to centering on the
            // level on any axis where the view doesn't fit inside it.
            float minX = minWorldPos.x + halfW, maxX = maxWorldPos.x - halfW;
            focusPoint.x = minX <= maxX ? Mathf.Clamp(focusPoint.x, minX, maxX) : (minWorldPos.x + maxWorldPos.x) * 0.5f;

            // Clamp the ground point the (possibly tilted) camera is
            // actually looking at, not the camera's own Z position — with a
            // tilt those differ by `ZOffsetForTilt`, and clamping the raw
            // camera Z would silently re-center the look-at point back to
            // the bounds' own center every frame, undoing whatever
            // `FocusOn` set the tilt offset to.
            float minZ = minWorldPos.y + halfH, maxZ = maxWorldPos.y - halfH;
            focusPoint.z = minZ <= maxZ ? Mathf.Clamp(focusPoint.z, minZ, maxZ) : (minWorldPos.y + maxWorldPos.y) * 0.5f;
        }

        private void RebuildHomePosition()
        {
            transform.rotation = Quaternion.Euler(pitchDegrees, CurrentYawDegrees, 0f);
            Vector3 forward = transform.forward;
            float distance = height / Mathf.Max(0.001f, -forward.y);
            homePosition = focusPoint - forward * distance;
        }

        public void SetBounds(Vector2 min, Vector2 max) { minWorldPos = min; maxWorldPos = max; }

        /// Frames the camera on `worldPos` (a ground point), accounting for
        /// the tilt so the look-at point — not the camera's own position —
        /// lands on `worldPos`. Also resets peek: re-framing is meant to
        /// give a clean, predictable view, not compound whatever offset a
        /// prior drag left behind.
        public void FocusOn(Vector3 worldPos, float size = -1f)
        {
            if (size > 0) { orthographicSize = size; mainCamera.orthographicSize = size; }
            focusPoint = new Vector3(worldPos.x, 0f, worldPos.z);
            peekOffset = Vector2.zero;
            RebuildHomePosition();
        }

        private void SynchronizeRenderCameraTransform()
        {
            if (mainCamera == null || mainCamera.transform == transform) return;
            if (mainCamera.transform.IsChildOf(transform))
            {
                mainCamera.transform.localPosition = Vector3.zero;
                mainCamera.transform.localRotation = Quaternion.identity;
                return;
            }
            mainCamera.transform.SetPositionAndRotation(transform.position, transform.rotation);
        }

        private static float NormalizeSignedAngle(float angle)
        {
            angle %= 360f;
            return angle > 180f ? angle - 360f : angle;
        }
    }
}
