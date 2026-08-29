namespace DerClou.Gameplay.DevTools
{
    using System;
    using System.Linq;
    using UnityEngine;
    using UnityEngine.InputSystem;

    /// <summary>
    /// Reusable live acceptance view for comparing one animation on many
    /// package characters without modifying the source package assets.
    /// </summary>
    public sealed class CharacterAcceptanceGallery : MonoBehaviour
    {
        public Camera galleryCamera;
        public Animator[] candidates = Array.Empty<Animator>();
        public string[] labels = Array.Empty<string>();
        public Vector3 overviewPosition = new(0f, 7.3f, 30f);
        public Vector3 overviewTarget = new(0f, 7.3f, 0f);
        public float overviewSize = 10.8f;

        private int selectedIndex;
        private bool overview;
        private bool handCloseup;
        private Vector3 orbitTarget;
        private float orbitDistance = 3f;
        private float orbitYaw;
        private float orbitPitch;
        private const float OrbitSensitivity = 0.22f;
        private const float ZoomSensitivity = 0.0015f;

        private void Start()
        {
            // Freeze every candidate at the same authored point in the
            // Flashlight clip. Setting an AnimatorController state's speed to
            // zero before its first evaluation leaves some avatars in bind
            // pose, which made the previous gallery falsely look like an idle
            // comparison. Explicit Play + Update evaluates the retargeted
            // Humanoid pose once, then pauses it for visual inspection.
            foreach (var animator in candidates)
            {
                if (animator == null || animator.runtimeAnimatorController == null) continue;
                animator.speed = 1f;
                animator.Play(0, 0, 0.5f);
                animator.Update(0.001f);
                animator.speed = 0f;
            }

            // Character selection starts with one large, unobstructed model.
            // The overview remains available on demand, but is unsuitable for
            // judging fingers, clothing and skinning quality.
            // The acceptance stand opens on the complete lineup so every
            // candidate is immediately visible in Game view. Selection remains
            // available with arrows and the hand close-up button.
            ShowOverview();
        }

        private void Update()
        {
            var keyboard = Keyboard.current;
            if (keyboard != null)
            {
                if (keyboard.leftArrowKey.wasPressedThisFrame) Previous();
                if (keyboard.rightArrowKey.wasPressedThisFrame) Next();
                if (keyboard.oKey.wasPressedThisFrame) ShowOverview();
                if (keyboard.hKey.wasPressedThisFrame) ToggleHandCloseup();
                if (keyboard.rKey.wasPressedThisFrame && !overview) ShowSelected(resetView: true);
            }

            UpdateOrbitControls();
        }

        private void OnGUI()
        {
            const float height = 42f;
            GUILayout.BeginArea(new Rect(16f, 16f, Mathf.Min(Screen.width - 32f, 900f), 198f), GUI.skin.box);
            GUILayout.Label("CHARACTER ACCEPTANCE — VanillaLoop Flashlight pose");
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Общий вид [O]", GUILayout.Height(height))) ShowOverview();
            if (GUILayout.Button("←", GUILayout.Width(60f), GUILayout.Height(height))) Previous();
            if (GUILayout.Button("→", GUILayout.Width(60f), GUILayout.Height(height))) Next();
            if (GUILayout.Button("Кисть [H]", GUILayout.Height(height))) ToggleHandCloseup();
            GUILayout.EndHorizontal();
            GUILayout.Label(overview ? $"Все кандидаты: {candidates.Length}" : CurrentLabel);
            GUILayout.Label(overview
                ? "Нажмите ← или →, чтобы открыть персонажа крупно"
                : "Вращение: ЛКМ/ПКМ вне панели · Масштаб: колесо · Сброс вида: R");
            GUILayout.EndArea();
        }

        private string CurrentLabel =>
            labels != null && selectedIndex >= 0 && selectedIndex < labels.Length
                ? $"{selectedIndex + 1}/{candidates.Length}: {labels[selectedIndex]}"
                : $"{selectedIndex + 1}/{candidates.Length}";

        public bool SelectByLabelPrefix(string prefix)
        {
            if (string.IsNullOrWhiteSpace(prefix) || labels == null) return false;
            var index = Array.FindIndex(labels, label =>
                label != null && label.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
            if (index < 0) return false;
            selectedIndex = index;
            handCloseup = false;
            ShowSelected(resetView: true);
            return true;
        }

        private void Previous()
        {
            if (candidates.Length == 0) return;
            selectedIndex = (selectedIndex - 1 + candidates.Length) % candidates.Length;
            ShowSelected(resetView: true);
        }

        private void Next()
        {
            if (candidates.Length == 0) return;
            selectedIndex = (selectedIndex + 1) % candidates.Length;
            ShowSelected(resetView: true);
        }

        private void ToggleHandCloseup()
        {
            if (overview)
            {
                overview = false;
                handCloseup = true;
            }
            else
            {
                handCloseup = !handCloseup;
            }
            ShowSelected(resetView: true);
        }

        private void ShowOverview()
        {
            overview = true;
            handCloseup = false;
            SetCandidateVisibility(showAll: true);
            if (galleryCamera == null) return;
            galleryCamera.orthographic = true;
            galleryCamera.orthographicSize = overviewSize;
            galleryCamera.transform.SetPositionAndRotation(
                overviewPosition,
                Quaternion.LookRotation(overviewTarget - overviewPosition, Vector3.up));
        }

        private void ShowSelected(bool resetView)
        {
            if (galleryCamera == null || candidates.Length == 0) return;
            overview = false;
            selectedIndex = Mathf.Clamp(selectedIndex, 0, candidates.Length - 1);
            var animator = candidates[selectedIndex];
            if (animator == null) return;

            SetCandidateVisibility(showAll: false);

            galleryCamera.orthographic = false;
            galleryCamera.fieldOfView = handCloseup ? 28f : 34f;
            galleryCamera.nearClipPlane = 0.01f;
            galleryCamera.allowMSAA = true;
            galleryCamera.allowHDR = true;

            Transform target = null;
            if (handCloseup)
            {
                target = animator.isHuman
                    ? animator.GetBoneTransform(HumanBodyBones.RightHand)
                    : animator.GetComponentsInChildren<Transform>(true)
                        .FirstOrDefault(item => item.name == "hand_r");
            }
            if (target != null)
            {
                orbitTarget = target.position;
                if (resetView) orbitDistance = 0.58f;
            }
            else
            {
                var renderers = animator.GetComponentsInChildren<Renderer>(false);
                if (renderers.Length == 0) return;
                var bounds = renderers[0].bounds;
                for (int i = 1; i < renderers.Length; i++) bounds.Encapsulate(renderers[i].bounds);
                orbitTarget = bounds.center;
                if (resetView) orbitDistance = Mathf.Max(2.5f, bounds.size.y * 1.8f);
            }

            if (resetView)
            {
                orbitYaw = 0f;
                orbitPitch = 0f;
            }
            ApplyOrbitCamera();
        }

        private void UpdateOrbitControls()
        {
            if (overview || galleryCamera == null) return;
            var mouse = Mouse.current;
            if (mouse == null) return;

            var position = mouse.position.ReadValue();
            var overPanel = position.x < 930f && position.y > Screen.height - 220f;
            var dragging = mouse.rightButton.isPressed || (mouse.leftButton.isPressed && !overPanel);
            if (dragging)
            {
                var delta = mouse.delta.ReadValue();
                orbitYaw += delta.x * OrbitSensitivity;
                orbitPitch = Mathf.Clamp(orbitPitch - delta.y * OrbitSensitivity, -75f, 75f);
            }

            var scroll = mouse.scroll.ReadValue().y;
            if (Mathf.Abs(scroll) > 0.01f)
            {
                orbitDistance *= Mathf.Exp(-scroll * ZoomSensitivity);
                orbitDistance = Mathf.Clamp(orbitDistance, handCloseup ? 0.16f : 0.45f, handCloseup ? 2.2f : 8f);
            }

            if (dragging || Mathf.Abs(scroll) > 0.01f) ApplyOrbitCamera();
        }

        private void ApplyOrbitCamera()
        {
            var orbit = Quaternion.Euler(orbitPitch, orbitYaw, 0f);
            galleryCamera.transform.position = orbitTarget + orbit * (Vector3.forward * orbitDistance);
            galleryCamera.transform.rotation = Quaternion.LookRotation(orbitTarget - galleryCamera.transform.position, Vector3.up);
        }

        private void SetCandidateVisibility(bool showAll)
        {
            for (var index = 0; index < candidates.Length; index++)
            {
                var animator = candidates[index];
                if (animator == null) continue;
                var candidateRoot = FindCandidateRoot(animator.transform);
                candidateRoot.gameObject.SetActive(showAll || index == selectedIndex);
            }

            var grid = GameObject.Find("CharacterAcceptanceGrid");
            if (grid == null) return;
            foreach (Transform child in grid.transform)
            {
                if (child.name.StartsWith("Label_", StringComparison.Ordinal))
                    child.gameObject.SetActive(showAll);
            }
        }

        private static Transform FindCandidateRoot(Transform child)
        {
            var current = child;
            while (current.parent != null && current.parent.name != "CharacterAcceptanceGrid")
            {
                current = current.parent;
            }
            return current;
        }
    }
}
