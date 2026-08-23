namespace DerClou.Gameplay.Camera
{
    using UnityEngine;

    /// <summary>
    /// Orthographic tactical camera with pan/zoom.
    /// <para>
    /// Not a pure top-down camera: <c>docs/ART_DIRECTION.md</c>'s settled
    /// "tabletop diorama" look explicitly calls for a tilted view ("this is
    /// what allows the view to be tilted far enough to have depth at all"),
    /// with the straight-down look rejected as reading like a sealed box.
    /// <paramref name="pitchDegrees"/> is the tilt: 90 is the old
    /// straight-down look, lower values tip the view forward so wall faces,
    /// shadows and character silhouettes are actually visible.
    /// </para>
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
        public float panSpeed = 20f;
        public float edgePanMargin = 50f;
        public float edgePanSpeed = 25f;

        [Header("Bounds")]
        public Vector2 minWorldPos = new Vector2(-50, -50);
        public Vector2 maxWorldPos = new Vector2(50, 50);

        private Vector3 dragOrigin;
        private bool isDragging;

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
            transform.position = new Vector3(transform.position.x, height, transform.position.z);
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
            HandlePan();
            ClampToBounds();
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

        private void HandlePan()
        {
            // Middle mouse or two-finger drag
            if (Input.GetMouseButtonDown(2) || (Input.touchCount == 2))
            {
                dragOrigin = mainCamera.ScreenToWorldPoint(Input.mousePosition);
                isDragging = true;
            }
            if (Input.GetMouseButtonUp(2) || Input.touchCount != 2)
                isDragging = false;

            if (isDragging)
            {
                Vector3 diff = dragOrigin - mainCamera.ScreenToWorldPoint(Input.mousePosition);
                transform.position += new Vector3(diff.x, 0, diff.z);
            }

            // Edge pan
            Vector2 mousePos = Input.mousePosition;
            Vector3 pan = Vector3.zero;
            if (mousePos.x < edgePanMargin) pan.x -= 1;
            if (mousePos.x > Screen.width - edgePanMargin) pan.x += 1;
            if (mousePos.y < edgePanMargin) pan.z -= 1;
            if (mousePos.y > Screen.height - edgePanMargin) pan.z += 1;

            if (pan != Vector3.zero)
                transform.position += pan.normalized * edgePanSpeed * Time.deltaTime;
        }

        private void ClampToBounds()
        {
            Vector3 pos = transform.position;
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

            transform.position = pos;
        }

        public void SetBounds(Vector2 min, Vector2 max) { minWorldPos = min; maxWorldPos = max; }

        /// Frames the camera on `worldPos` (a ground point), accounting for
        /// the tilt so the look-at point — not the camera's own position —
        /// lands on `worldPos`.
        public void FocusOn(Vector3 worldPos, float size = -1f)
        {
            if (size > 0) { orthographicSize = size; mainCamera.orthographicSize = size; }
            transform.position = new Vector3(worldPos.x, transform.position.y, worldPos.z - ZOffsetForTilt);
        }
    }
}
