namespace DerClou.Gameplay.UI
{
    using DerClou.Gameplay.Input;
    using UnityEngine;
    using UnityEngine.InputSystem;

    /// Temporary test surface for the plan/execute/retry loop. The production
    /// Plan Deck remains a later milestone; this makes the current game
    /// immediately usable in Game View and on touch devices.
    public sealed class GreyboxControlHUD : MonoBehaviour
    {
        public GameController controller;
        public InputManager inputManager;
        public TechnicalOverlayView technicalOverlay;

        private GUIStyle titleStyle;
        private GUIStyle bodyStyle;
        private GUIStyle buttonStyle;
        private GUIStyle tabStyle;

        // Sized for the Game View simulating a phone screen, where the
        // previous fixed 330x366 panel visibly covered roughly half the
        // display — collapsed by default so it never blocks the level
        // unless the owner explicitly wants it open.
        private const float PanelWidth = 220f;
        private const float PanelHeight = 250f;
        private const float TabSize = 34f;
        private bool collapsed = true;

        public void Initialize(GameController game, InputManager input, TechnicalOverlayView overlay)
        {
            controller = game;
            inputManager = input;
            technicalOverlay = overlay;
            inputManager.IsPointerOverUI = IsPointerOverControls;
        }

        private void Update()
        {
            if (controller == null) return;
            var keyboard = Keyboard.current;
            if (keyboard == null) return;
            if (keyboard.tKey.wasPressedThisFrame) technicalOverlay?.Toggle();
            if (controller.CurrentPhase == GamePhase.Planning && keyboard.enterKey.wasPressedThisFrame)
                controller.StartExecution();
            else if ((controller.CurrentPhase == GamePhase.Execution || controller.CurrentPhase == GamePhase.Result)
                     && keyboard.escapeKey.wasPressedThisFrame)
                controller.StopExecution();
            else if (controller.CurrentPhase == GamePhase.Result && keyboard.rKey.wasPressedThisFrame)
                controller.RetryExecution();
        }

        private void OnGUI()
        {
            if (controller == null || inputManager == null) return;
            EnsureStyles();

            if (collapsed)
            {
                if (GUI.Button(TabRect(), "☰", tabStyle)) collapsed = false;
                return;
            }

            Rect panel = ControlRect();
            GUI.Box(panel, GUIContent.none);
            if (GUI.Button(new Rect(panel.xMax - 26f, panel.y + 4f, 22f, 22f), "×", tabStyle))
            {
                collapsed = true;
                return;
            }
            GUILayout.BeginArea(new Rect(panel.x + 12f, panel.y + 10f, panel.width - 24f, panel.height - 20f));
            GUILayout.Label(PhaseTitle(), titleStyle);
            GUILayout.Space(4f);

            if (controller.DeveloperSandboxMode)
            {
                GUILayout.Label("Прямое тестирование: выберите любого актёра и тапните по полу — он идёт сразу, без плана.", bodyStyle);
                GUILayout.Label("Слева: один охранник, четыре узла и свободная постановка вора на его пути.", bodyStyle);
                GUILayout.Label("Справа: дверь, мебель и препятствия.", bodyStyle);
                GUILayout.FlexibleSpace();
                if (GUILayout.Button("ТЕСТ: ШУМ (рация)", buttonStyle, GUILayout.Height(28f)))
                    controller.TestEmitSandboxNoise();
                if (GUILayout.Button("ТЕСТ: ВЗЛОМАТЬ СЕЙФ", buttonStyle, GUILayout.Height(28f)))
                    controller.TestCrackSandboxSafe();
                DrawTechnicalOverlayButton();
                GUILayout.Label("Режим планирования в этом уровне отключён.", bodyStyle);
                GUILayout.EndArea();
                return;
            }

            switch (controller.CurrentPhase)
            {
                case GamePhase.Planning:
                    GUILayout.Label("Вор уже выбран. Тапните по полу — точка добавится в план.", bodyStyle);
                    GUILayout.Label($"Действий в плане: {controller.PlannedActionCount}", bodyStyle);
                    GUILayout.FlexibleSpace();
                    GUI.enabled = controller.PlannedActionCount > 0;
                    if (GUILayout.Button("ВЫПОЛНИТЬ ПЛАН", buttonStyle, GUILayout.Height(32f)))
                        controller.StartExecution();
                    GUI.enabled = true;
                    if (GUILayout.Button("ОЧИСТИТЬ ПЛАН", buttonStyle, GUILayout.Height(26f)))
                        controller.ClearPlan();
                    break;

                case GamePhase.Execution:
                    GUILayout.Label($"Время: {controller.missionClock.CurrentTime:0.00} с", bodyStyle);
                    GUILayout.Label("Персонаж выполняет записанный маршрут.", bodyStyle);
                    GUILayout.FlexibleSpace();
                    if (GUILayout.Button("ВЕРНУТЬСЯ К ПЛАНУ", buttonStyle, GUILayout.Height(30f)))
                        controller.StopExecution();
                    break;

                case GamePhase.Result:
                    var failure = controller.CurrentFailure;
                    if (failure.HasValue)
                    {
                        var value = failure.Value;
                        GUILayout.Label($"Провал: {value.reason}\nИсточник: {value.source}\nВремя: {value.time:0.00} с", bodyStyle);
                    }
                    else
                    {
                        GUILayout.Label("Миссия завершена.", bodyStyle);
                    }
                    GUILayout.FlexibleSpace();
                    if (GUILayout.Button("ИЗМЕНИТЬ ПЛАН", buttonStyle, GUILayout.Height(28f)))
                        controller.StopExecution();
                    if (GUILayout.Button("ПОВТОРИТЬ ТОТ ЖЕ ПЛАН", buttonStyle, GUILayout.Height(26f)))
                        controller.RetryExecution();
                    break;
            }

            GUILayout.Space(5f);
            DrawTechnicalOverlayButton();

            GUILayout.EndArea();
        }

        private void DrawTechnicalOverlayButton()
        {
            if (technicalOverlay == null) return;
            string state = technicalOverlay.IsVisible ? "ВКЛ" : "ВЫКЛ";
            if (GUILayout.Button($"ТЕХНИЧЕСКИЙ СЛОЙ: {state}  [T]", buttonStyle, GUILayout.Height(28f)))
                technicalOverlay.Toggle();
        }

        public bool IsPointerOverControls(Vector2 screenPoint)
        {
            var guiPoint = new Vector2(screenPoint.x, Screen.height - screenPoint.y);
            return collapsed ? TabRect().Contains(guiPoint) : ControlRect().Contains(guiPoint);
        }

        private static Rect ControlRect()
        {
            Rect safe = Screen.safeArea;
            float safeTop = Screen.height - safe.yMax;
            float width = Mathf.Min(PanelWidth, safe.width - 24f);
            return new Rect(safe.x + 12f, safeTop + 12f, width, PanelHeight);
        }

        // A small always-visible tab in the same corner the full panel
        // would open from — collapsed by default so it never sits over the
        // level, expandable with one tap when the owner actually wants it.
        private static Rect TabRect()
        {
            Rect safe = Screen.safeArea;
            float safeTop = Screen.height - safe.yMax;
            return new Rect(safe.x + 12f, safeTop + 12f, TabSize, TabSize);
        }

        private string PhaseTitle() => controller.CurrentPhase switch
        {
            GamePhase.Planning => "ПЛАНИРОВАНИЕ",
            GamePhase.Execution => "ВЫПОЛНЕНИЕ",
            GamePhase.Result => controller.CurrentFailure.HasValue ? "ПЛАН НЕ СРАБОТАЛ" : "УСПЕХ",
            _ => controller.CurrentPhase.ToString().ToUpperInvariant()
        };

        private void EnsureStyles()
        {
            if (titleStyle != null) return;
            titleStyle = new GUIStyle(GUI.skin.label)
            {
                fontSize = 15,
                fontStyle = FontStyle.Bold,
                normal = { textColor = Color.white }
            };
            bodyStyle = new GUIStyle(GUI.skin.label)
            {
                fontSize = 11,
                wordWrap = true,
                normal = { textColor = Color.white }
            };
            buttonStyle = new GUIStyle(GUI.skin.button)
            {
                fontSize = 11,
                fontStyle = FontStyle.Bold
            };
            tabStyle = new GUIStyle(GUI.skin.button)
            {
                fontSize = 16,
                fontStyle = FontStyle.Bold,
                alignment = TextAnchor.MiddleCenter
            };
        }

        private void OnDestroy()
        {
            if (inputManager != null && inputManager.IsPointerOverUI == IsPointerOverControls)
                inputManager.IsPointerOverUI = null;
        }
    }
}
