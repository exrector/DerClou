namespace DerClou.Gameplay.Camera
{
    using UnityEngine;

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
    /// <item>"Rotation is not offered — decided" and "Panning is not offered
    /// — decided" (top table, <c>docs/UI_AND_CAMERA.md</c> §Camera). The only
    /// player gesture that moves the camera at all is a one-finger drag,
    /// documented as "Peek into the box" — a small, clamped lateral shift,
    /// not a rotate/orbit and not a free pan.</item>
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

        // How far "behind" (−Z) the camera must sit, at its current height
        // and pitch, for its view axis to still hit the ground point it is
        // nominally centered on. At pitch=90 this is 0 (camera sits directly
        // above what it looks at, the old behavior); it grows as the tilt
        // increases.
        private float ZOffsetForTilt =>
            pitchDegrees >= 89.9f ? 0f : height / Mathf.Tan(pitchDegrees * Mathf.Deg2Rad);

        private void Awake()
        {
            transform.rotation = Quaternion.Euler(pitchDegrees, 0, 0);
            homePosition = new Vector3(transform.position.x, height, transform.position.z);
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
            mainCamera.orthographic = true;
            mainCamera.orthographicSize = orthographicSize;
        }

        private void LateUpdate()
        {
            HandleZoom();
            ClampHomeToBounds();
            transform.position = homePosition + new Vector3(peekOffset.x, 0, peekOffset.y);
        }

        private void HandleZoom()
        {
            float scroll = Input.mouseScrollDelta.y;
            if (Mathf.Abs(scroll) > 0.01f)
            {
                orthographicSize = Mathf.Clamp(orthographicSize - scroll * zoomSpeed * Time.deltaTime * 60f, minOrthoSize, maxOrthoSize);
                mainCamera.orthographicSize = orthographicSize;
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

        private void ClampHomeToBounds()
        {
            Vector3 pos = homePosition;
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
            pos.x = minX <= maxX ? Mathf.Clamp(pos.x, minX, maxX) : (minWorldPos.x + maxWorldPos.x) * 0.5f;

            // Clamp the ground point the (possibly tilted) camera is
            // actually looking at, not the camera's own Z position — with a
            // tilt those differ by `ZOffsetForTilt`, and clamping the raw
            // camera Z would silently re-center the look-at point back to
            // the bounds' own center every frame, undoing whatever
            // `FocusOn` set the tilt offset to.
            float zOffset = ZOffsetForTilt;
            float lookAtZ = pos.z + zOffset;
            float minZ = minWorldPos.y + halfH, maxZ = maxWorldPos.y - halfH;
            lookAtZ = minZ <= maxZ ? Mathf.Clamp(lookAtZ, minZ, maxZ) : (minWorldPos.y + maxWorldPos.y) * 0.5f;
            pos.z = lookAtZ - zOffset;

            homePosition = pos;
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
            homePosition = new Vector3(worldPos.x, homePosition.y, worldPos.z - ZOffsetForTilt);
            peekOffset = Vector2.zero;
        }
    }
}
