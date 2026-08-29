namespace DerClou.Gameplay.UI
{
    using DerClou.Gameplay.Camera;
    using UnityEngine;
    using UnityEngine.EventSystems;
    using UnityEngine.InputSystem;
    using UnityEngine.InputSystem.OnScreen;
    using UnityEngine.InputSystem.UI;
    using UnityEngine.UI;

    /// <summary>
    /// Bottom-right diorama-look control built from Unity's official
    /// Input System <see cref="OnScreenStick"/>. It is presentation-only:
    /// the produced vector rotates/tilts <see cref="TacticalCamera"/> and
    /// never enters the deterministic mission state.
    /// </summary>
    public sealed class CameraJoystickHUD : MonoBehaviour
    {
        private const float BaseDiameter = 176f;
        private const float KnobDiameter = 72f;
        private const float EdgeMargin = 22f;

        private TacticalCamera tacticalCamera;
        private RectTransform baseRect;
        private InputAction lookAction;
        private Sprite circleSprite;

        public void Initialize(TacticalCamera cameraRig)
        {
            tacticalCamera = cameraRig;
            BuildStandardUnityUI();
            lookAction = new InputAction("DioramaLook", InputActionType.Value, "<Gamepad>/rightStick");
            lookAction.Enable();
        }

        private void Update()
        {
            if (tacticalCamera == null || lookAction == null) return;
            Vector2 value = Vector2.ClampMagnitude(lookAction.ReadValue<Vector2>(), 1f);
            tacticalCamera.ApplyDioramaJoystick(value, Time.unscaledDeltaTime);
            PositionInsideSafeArea();
        }

        public bool IsPointerOverJoystick(Vector2 screenPoint)
        {
            if (baseRect == null) return false;
            return RectTransformUtility.RectangleContainsScreenPoint(baseRect, screenPoint, null);
        }

        private void BuildStandardUnityUI()
        {
            EnsureEventSystem();

            var canvasObject = new GameObject("DioramaCameraControls", typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            canvasObject.transform.SetParent(transform, false);
            var canvas = canvasObject.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 100;
            var scaler = canvasObject.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1170f, 2532f);
            scaler.matchWidthOrHeight = 0.5f;

            circleSprite = CreateCircleSprite();
            var baseObject = new GameObject("CameraJoystickBase", typeof(RectTransform), typeof(Image));
            baseObject.transform.SetParent(canvasObject.transform, false);
            baseRect = baseObject.GetComponent<RectTransform>();
            baseRect.anchorMin = baseRect.anchorMax = new Vector2(1f, 0f);
            baseRect.pivot = new Vector2(0.5f, 0.5f);
            baseRect.sizeDelta = Vector2.one * BaseDiameter;
            var baseImage = baseObject.GetComponent<Image>();
            baseImage.sprite = circleSprite;
            baseImage.color = new Color(0.04f, 0.06f, 0.08f, 0.58f);
            baseImage.raycastTarget = false;

            // The transparent hit disc is deliberately larger than the
            // visible knob. OnScreenStick moves this RectTransform and sends
            // the resulting Vector2 to a virtual right stick.
            var stickObject = new GameObject("CameraJoystickStick", typeof(RectTransform), typeof(Image), typeof(OnScreenStick));
            stickObject.transform.SetParent(baseObject.transform, false);
            var stickRect = stickObject.GetComponent<RectTransform>();
            stickRect.anchorMin = stickRect.anchorMax = stickRect.pivot = new Vector2(0.5f, 0.5f);
            stickRect.sizeDelta = Vector2.one * 136f;
            var hitImage = stickObject.GetComponent<Image>();
            hitImage.sprite = circleSprite;
            hitImage.color = new Color(1f, 1f, 1f, 0.01f);
            hitImage.raycastTarget = true;
            var onScreenStick = stickObject.GetComponent<OnScreenStick>();
            onScreenStick.controlPath = "<Gamepad>/rightStick";
            onScreenStick.movementRange = 54f;
            stickObject.AddComponent<CameraJoystickCenterTap>().Initialize(tacticalCamera);

            var knobObject = new GameObject("Knob", typeof(RectTransform), typeof(Image));
            knobObject.transform.SetParent(stickObject.transform, false);
            var knobRect = knobObject.GetComponent<RectTransform>();
            knobRect.anchorMin = knobRect.anchorMax = knobRect.pivot = new Vector2(0.5f, 0.5f);
            knobRect.sizeDelta = Vector2.one * KnobDiameter;
            var knobImage = knobObject.GetComponent<Image>();
            knobImage.sprite = circleSprite;
            knobImage.color = new Color(0.86f, 0.91f, 0.96f, 0.94f);
            knobImage.raycastTarget = false;

            // The neutral knob is also the one-shot home button. A tap
            // returns to top view; a drag remains standard OnScreenStick.
            CreateGlyphBar(knobObject.transform, new Vector2(26f, 4f));
            CreateGlyphBar(knobObject.transform, new Vector2(4f, 26f));

            PositionInsideSafeArea();
        }

        private static void EnsureEventSystem()
        {
            if (EventSystem.current != null) return;
            // InputSystemUIInputModule assigns Unity's default UI actions in
            // OnEnable. Do not fall back to StandaloneInputModule: that would
            // keep the deprecated legacy Input Manager alive just for UI.
            var eventSystem = new GameObject("EventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));
            DontDestroyOnLoad(eventSystem);
        }

        private void PositionInsideSafeArea()
        {
            if (baseRect == null) return;
            Rect safe = Screen.safeArea;
            float rightInset = Screen.width - safe.xMax;
            baseRect.anchoredPosition = new Vector2(
                -(rightInset + EdgeMargin + BaseDiameter * 0.5f),
                safe.yMin + EdgeMargin + BaseDiameter * 0.5f);
        }

        private static Sprite CreateCircleSprite()
        {
            const int size = 64;
            var texture = new Texture2D(size, size, TextureFormat.RGBA32, false)
            {
                name = "RuntimeJoystickCircle",
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp,
                hideFlags = HideFlags.HideAndDontSave
            };
            var pixels = new Color32[size * size];
            float radius = size * 0.5f - 1f;
            Vector2 center = Vector2.one * (size - 1) * 0.5f;
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float edge = radius - Vector2.Distance(new Vector2(x, y), center);
                byte alpha = (byte)Mathf.RoundToInt(255f * Mathf.Clamp01(edge + 1f));
                pixels[y * size + x] = new Color32(255, 255, 255, alpha);
            }
            texture.SetPixels32(pixels);
            texture.Apply(false, true);
            return Sprite.Create(texture, new Rect(0, 0, size, size), Vector2.one * 0.5f, size);
        }

        private static void CreateGlyphBar(Transform parent, Vector2 size)
        {
            var bar = new GameObject("TopViewGlyph", typeof(RectTransform), typeof(Image));
            bar.transform.SetParent(parent, false);
            var rect = bar.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = rect.pivot = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = size;
            var image = bar.GetComponent<Image>();
            image.color = new Color(0.08f, 0.12f, 0.16f, 0.78f);
            image.raycastTarget = false;
        }

        private void OnDestroy()
        {
            lookAction?.Dispose();
            if (circleSprite != null)
            {
                Texture texture = circleSprite.texture;
                Destroy(circleSprite);
                if (texture != null) Destroy(texture);
            }
        }
    }

    public sealed class CameraJoystickCenterTap : MonoBehaviour, IPointerDownHandler, IDragHandler, IPointerUpHandler
    {
        private const float TapTravelThreshold = 12f;
        private TacticalCamera tacticalCamera;
        private Vector2 pointerDownPosition;
        private float maxTravel;

        public void Initialize(TacticalCamera cameraRig) => tacticalCamera = cameraRig;

        public void OnPointerDown(PointerEventData eventData)
        {
            pointerDownPosition = eventData.position;
            maxTravel = 0f;
        }

        public void OnDrag(PointerEventData eventData)
        {
            maxTravel = Mathf.Max(maxTravel, Vector2.Distance(pointerDownPosition, eventData.position));
        }

        public void OnPointerUp(PointerEventData eventData)
        {
            maxTravel = Mathf.Max(maxTravel, Vector2.Distance(pointerDownPosition, eventData.position));
            if (maxTravel <= TapTravelThreshold) tacticalCamera?.ResetToTopView();
        }
    }

}
