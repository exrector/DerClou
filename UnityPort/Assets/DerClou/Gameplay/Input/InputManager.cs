namespace DerClou.Gameplay.Input
{
    using DerClou.Core.Data;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Camera;
    using DerClou.Gameplay.Props;
    using UnityEngine;
    using UnityEngine.InputSystem;
    using UnityEngine.InputSystem.EnhancedTouch;
    using System.Collections.Generic;
    using Touch = UnityEngine.InputSystem.EnhancedTouch.Touch;

    public enum InputMode { Planning, Execution, Inspecting }
    public enum TapResult { None, ActorSelected, Interactable, Floor }

    public class InputManager : MonoBehaviour
    {
        [Header("References")]
        public TacticalCamera tacticalCamera;
        public LayerMask floorMask;
        public LayerMask interactableMask;
        public LayerMask actorMask;

        [Header("Selection")]
        public Material selectionOutlineMaterial;
        public Color selectionColor = Color.cyan;
        public bool allowAnyActorSelection;

        [Header("Tap vs. drag")]
        // Beyond this many pixels of movement, a mouse-down is a drag (camera
        // peek — docs/UI_AND_CAMERA.md's one-finger-drag gesture) rather than
        // a tap (select/move/interact). Without this split, `HandleClick`
        // used to fire on the down-frame regardless of what happened after,
        // so peeking the camera would also issue a move/interact command at
        // wherever the drag started.
        public float dragThresholdPixels = 12f;

        private InputMode currentMode = InputMode.Planning;
        private ActorView selectedActor;
        private ActorView hoveredActor;
        private Interactable hoveredInteractable;
        private Dictionary<ActorView, Material[]> originalMaterials = new();

        private bool pointerDown;
        private bool isDragging;
        private bool isOrbitDragging;
        private Vector2 pointerDownPos;
        private Vector2 lastPointerPos;
        private bool ownsEnhancedTouch;

        public InputMode CurrentMode => currentMode;
        public ActorView SelectedActor => selectedActor;
        public event System.Action<ActorView> OnActorSelected;
        public event System.Action<Interactable> OnInteractableHovered;
        public event System.Action<Interactable> OnInteractableClicked;
        public event System.Action<Vector3> OnFloorClicked;
        public System.Func<Vector2, bool> IsPointerOverUI;

        private void OnEnable()
        {
            if (EnhancedTouchSupport.enabled) return;
            EnhancedTouchSupport.Enable();
            ownsEnhancedTouch = true;
        }

        private void OnDisable()
        {
            if (!ownsEnhancedTouch) return;
            EnhancedTouchSupport.Disable();
            ownsEnhancedTouch = false;
        }

        private void Update()
        {
            // Diorama viewpoint is presentation and remains available while
            // a deterministic plan is running; it never enters MissionState.
            if (HandleTwoFingerDiorama()) return;
            if (currentMode != InputMode.Planning) return;

            HandleHover();
            HandlePointer();
        }

        private bool HandleTwoFingerDiorama()
        {
            var touches = Touch.activeTouches;
            if (touches.Count < 2) return false;
            // Two fingers belong exclusively to the presentation camera.
            // Cancel any pending tap so an orbit can never issue a gameplay
            // command through Unity's mouse-emulation path.
            pointerDown = false;
            isDragging = false;
            var first = touches[0];
            var second = touches[1];
            float horizontalDelta = (first.delta.x + second.delta.x) * 0.5f;
            tacticalCamera.ApplyDioramaOrbit(horizontalDelta);
            return true;
        }

        private void HandlePointer()
        {
            var touches = Touch.activeTouches;
            if (touches.Count == 1)
            {
                var touch = touches[0];
                HandlePrimaryPointer(
                    touch.phase == UnityEngine.InputSystem.TouchPhase.Began,
                    touch.phase == UnityEngine.InputSystem.TouchPhase.Moved
                        || touch.phase == UnityEngine.InputSystem.TouchPhase.Stationary,
                    touch.phase == UnityEngine.InputSystem.TouchPhase.Ended
                        || touch.phase == UnityEngine.InputSystem.TouchPhase.Canceled,
                    touch.screenPosition);
                return;
            }

            var mouse = Mouse.current;
            if (mouse == null) return;
            Vector2 mousePosition = mouse.position.ReadValue();
#if UNITY_EDITOR || UNITY_STANDALONE_OSX
            // Editor/simulator fallback when Unity does not expose trackpad
            // fingers as touches: Option+left-drag or right-drag.
            var keyboard = Keyboard.current;
            bool altPressed = keyboard != null && (keyboard.leftAltKey.isPressed || keyboard.rightAltKey.isPressed);
            bool orbitPressed = mouse.rightButton.isPressed
                || (mouse.leftButton.isPressed && altPressed);
            if (orbitPressed)
            {
                Vector2 current = mousePosition;
                if (!isOrbitDragging)
                {
                    isOrbitDragging = true;
                    pointerDown = false;
                    isDragging = false;
                    lastPointerPos = current;
                    return;
                }
                tacticalCamera.ApplyDioramaOrbit(current.x - lastPointerPos.x);
                lastPointerPos = current;
                return;
            }
            isOrbitDragging = false;
#endif
            HandlePrimaryPointer(
                mouse.leftButton.wasPressedThisFrame,
                mouse.leftButton.isPressed,
                mouse.leftButton.wasReleasedThisFrame,
                mousePosition);
        }

        private void HandlePrimaryPointer(bool pressed, bool held, bool released, Vector2 position)
        {
            if (pressed)
            {
                if (IsPointerOverUI != null && IsPointerOverUI(position))
                {
                    pointerDown = false;
                    isDragging = false;
                    return;
                }
                pointerDown = true;
                isDragging = false;
                pointerDownPos = position;
                lastPointerPos = pointerDownPos;
                return;
            }

            if (!pointerDown) return;

            if (held)
            {
                Vector2 current = position;
                if (!isDragging && (current - pointerDownPos).magnitude > dragThresholdPixels)
                    isDragging = true;

                if (isDragging)
                    tacticalCamera.ApplyPeek(current - lastPointerPos);

                lastPointerPos = current;
                return;
            }

            if (released)
            {
                if (!isDragging) HandleClick();
                pointerDown = false;
                isDragging = false;
            }
        }

        /// One raycast pass per tap, dispatched to exactly one target
        /// (actor > interactable > floor) — this replaced three separate
        /// handlers that each re-raycast and act independently on the same
        /// `GetMouseButtonDown(0)` frame: a floor click fired both the
        /// selection path's `OnFloorClicked` AND a direct `SetDestination`
        /// call, and clicking a door/panel/safe/loot prop (all on
        /// `interactableMask`, none of which have an `ActorView` parent)
        /// called `SelectActor(null)`, which threw inside `HighlightActor`
        /// the moment anything was already selected.
        private void HandleClick() => ProcessTap(pointerDownPos);

        /// Screen-space tap entry point shared by live pointer input and
        /// automated Play Mode verification. It performs the same single
        /// priority-ordered raycast pass in both cases.
        public TapResult ProcessTap(Vector2 screenPosition)
        {
            Ray ray = tacticalCamera.mainCamera.ScreenPointToRay(screenPosition);
            // Visible in the Console the instant a tap is recognized —
            // without this, "nothing happened" and "the click never reached
            // Unity's Input system" (e.g. because the Game view didn't have
            // focus) look identical from outside the Editor.
            Debug.Log($"[InputManager] tap at {screenPosition}");

            if (Physics.Raycast(ray, out var hit, 1000f, actorMask))
            {
                var actor = hit.collider.GetComponentInParent<ActorView>();
                // Only the thief is player-controlled — guards are AI-only,
                // clicking one should not silently redirect input to it.
                if (actor != null && (allowAnyActorSelection || actor.Role == ActorRole.Thief))
                {
                    SelectActor(actor);
                    return TapResult.ActorSelected;
                }
            }

            if (Physics.Raycast(ray, out hit, 1000f, interactableMask))
            {
                var interactable = hit.collider.GetComponent<Interactable>();
                if (interactable != null)
                {
                    OnInteractableClicked?.Invoke(interactable);
                    return TapResult.Interactable;
                }
            }

            if (Physics.Raycast(ray, out hit, 1000f, floorMask))
            {
                OnFloorClicked?.Invoke(hit.point);
                return TapResult.Floor;
            }

            Debug.Log("[InputManager] tap hit nothing on any mask");
            return TapResult.None;
        }

        private void HandleHover()
        {
            var mouse = Mouse.current;
            if (mouse == null) return;
            Ray ray = tacticalCamera.mainCamera.ScreenPointToRay(mouse.position.ReadValue());
            if (Physics.Raycast(ray, out var hit, 1000f, actorMask))
            {
                var actor = hit.collider.GetComponentInParent<ActorView>();
                if (actor != null && actor != hoveredActor)
                {
                    hoveredActor = actor;
                    // Highlight hover
                }
            }
            else if (hoveredActor != null)
            {
                hoveredActor = null;
            }

            if (Physics.Raycast(ray, out hit, 1000f, interactableMask))
            {
                var interactable = hit.collider.GetComponent<Interactable>();
                if (interactable != null && interactable != hoveredInteractable)
                {
                    hoveredInteractable = interactable;
                    OnInteractableHovered?.Invoke(interactable);
                }
            }
            else if (hoveredInteractable != null)
            {
                hoveredInteractable = null;
            }
        }

        public void SelectActor(ActorView actor)
        {
            if (actor == null) return;
            if (selectedActor == actor) return;

            ClearSelection();
            selectedActor = actor;
            HighlightActor(selectedActor, true);
            OnActorSelected?.Invoke(actor);
        }

        public void ClearSelection()
        {
            if (selectedActor != null) HighlightActor(selectedActor, false);
            selectedActor = null;
        }

        private void HighlightActor(ActorView actor, bool on)
        {
            var renderers = actor.GetComponentsInChildren<Renderer>();
            if (on)
            {
                var mats = new List<Material>();
                foreach (var r in renderers) mats.AddRange(r.materials);
                originalMaterials[actor] = mats.ToArray();

                foreach (var r in renderers)
                {
                    var newMats = new Material[r.materials.Length];
                    for (int i = 0; i < newMats.Length; i++)
                    {
                        newMats[i] = new Material(selectionOutlineMaterial);
                        newMats[i].color = selectionColor;
                    }
                    r.materials = newMats;
                }
            }
            else if (originalMaterials.TryGetValue(actor, out var orig))
            {
                var renderers2 = actor.GetComponentsInChildren<Renderer>();
                int idx = 0;
                foreach (var r in renderers2)
                {
                    var mats = new Material[r.materials.Length];
                    for (int i = 0; i < mats.Length; i++)
                        mats[i] = orig[idx++];
                    r.materials = mats;
                }
                originalMaterials.Remove(actor);
            }
        }

        public void SetMode(InputMode mode) => currentMode = mode;

        public bool SelectDefaultPlayerActor()
        {
            var actors = FindObjectsByType<ActorView>(FindObjectsSortMode.None);
            foreach (var actor in actors)
            {
                if (actor.Role != ActorRole.Thief) continue;
                SelectActor(actor);
                return true;
            }
            return false;
        }
    }
}
