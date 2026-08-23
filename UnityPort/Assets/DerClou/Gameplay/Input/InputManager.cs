namespace DerClou.Gameplay.Input
{
    using DerClou.Core.Data;
    using DerClou.Gameplay.Actors;
    using DerClou.Gameplay.Camera;
    using DerClou.Gameplay.Props;
    using UnityEngine;
    using System.Collections.Generic;

    public enum InputMode { Planning, Execution, Inspecting }

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
        private Vector2 pointerDownPos;
        private Vector2 lastPointerPos;

        public InputMode CurrentMode => currentMode;
        public ActorView SelectedActor => selectedActor;
        public event System.Action<ActorView> OnActorSelected;
        public event System.Action<Interactable> OnInteractableHovered;
        public event System.Action<Interactable> OnInteractableClicked;
        public event System.Action<Vector3> OnFloorClicked;

        private void Update()
        {
            if (currentMode != InputMode.Planning) return;

            HandleHover();
            HandlePointer();
        }

        private void HandlePointer()
        {
            if (Input.GetMouseButtonDown(0))
            {
                pointerDown = true;
                isDragging = false;
                pointerDownPos = Input.mousePosition;
                lastPointerPos = pointerDownPos;
                return;
            }

            if (!pointerDown) return;

            if (Input.GetMouseButton(0))
            {
                Vector2 current = Input.mousePosition;
                if (!isDragging && (current - pointerDownPos).magnitude > dragThresholdPixels)
                    isDragging = true;

                if (isDragging)
                    tacticalCamera.ApplyPeek(current - lastPointerPos);

                lastPointerPos = current;
                return;
            }

            if (Input.GetMouseButtonUp(0))
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
        private void HandleClick()
        {
            Ray ray = tacticalCamera.mainCamera.ScreenPointToRay(pointerDownPos);
            // Visible in the Console the instant a tap is recognized —
            // without this, "nothing happened" and "the click never reached
            // Unity's Input system" (e.g. because the Game view didn't have
            // focus) look identical from outside the Editor.
            Debug.Log($"[InputManager] tap at {pointerDownPos}");

            if (Physics.Raycast(ray, out var hit, 1000f, actorMask))
            {
                var actor = hit.collider.GetComponentInParent<ActorView>();
                // Only the thief is player-controlled — guards are AI-only,
                // clicking one should not silently redirect input to it.
                if (actor != null && actor.Role == ActorRole.Thief) { SelectActor(actor); return; }
            }

            if (Physics.Raycast(ray, out hit, 1000f, interactableMask))
            {
                var interactable = hit.collider.GetComponent<Interactable>();
                if (interactable != null) { OnInteractableClicked?.Invoke(interactable); return; }
            }

            if (Physics.Raycast(ray, out hit, 1000f, floorMask))
            {
                OnFloorClicked?.Invoke(hit.point);
                return;
            }

            Debug.Log("[InputManager] tap hit nothing on any mask");
        }

        private void HandleHover()
        {
            Ray ray = tacticalCamera.mainCamera.ScreenPointToRay(Input.mousePosition);
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
    }
}