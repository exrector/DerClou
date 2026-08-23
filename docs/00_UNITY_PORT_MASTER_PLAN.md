# UNITY PORT MASTER PLAN — PRIORITY 0

> **ПЕРВЫЙ ПРИОРИТЕТ ПРОЕКТА. READ THIS FIRST.**
>
> Этот документ сохраняет план перехода Swift → Unity дословно. До завершения описанных ниже этапов он имеет приоритет над более старыми roadmap/onboarding-документами в части текущей реализации и порядка работ. Старый Swift/RealityKit-код не удаляется: он остаётся frozen reference implementation.

## Ход выполнения (обновляется по мере работы)

- [x] **U0** — repository source of truth (`CLAUDE.md`/`AGENTS.md`/master plan). 2026-08-23.
- [x] **U1** — Built-In → URP (`com.unity.render-pipelines.universal@17.5.0`, единственная версия под 6000.5.9f1; `Assets/Settings/DerClou_URP.asset` + `DerClou_Renderer.asset`; `Shader.Find("Standard")` → `"Universal Render Pipeline/Lit"` в `GameBootstrap.cs`/`LevelBuilder.cs` — других материалов в проекте не было, конвертировать было нечего). Проверено вживую: 0 ошибок консоли, playable-цепочка (select/move/door) не сломана. 2026-08-23.
- [x] Этап 12 (камера) — закрыт отдельно, orthographic-камера остаётся, см. раздел ниже.
- [ ] **U2** — deterministic simulation (дизайн: `docs/U2_SIMULATION_DESIGN.md`).
  - [x] 2a — Actor movement (`MissionState`/`ActorState`, `ActorMovementSystem`, `SimulationStep`, `SimulationService`, `ActorEntity`→`ActorView`). 2026-08-23.
  - [x] 2b — Guard patrol (`GuardState`, pure-C# `Core.Systems.GuardPatrolSystem`, `GuardPatrolSystem`→`GuardView`, `ActorMovementSystem.RequestPath` shared by player+guard, `NavigationService` removed in favor of `MissionState.Grid`). 2026-08-23.
  - [x] 2c — Security camera (`CameraState`, pure-C# `SecurityCameraSystem`, `SecurityCamera`→`CameraView`, `InteractionSystem.PerformPanel` flips `MissionState.Cameras` directly). 2026-08-23.
  - [x] 2d — Door (`DoorState`, pure-C# `DoorSystem`, `Door`→`DoorView`; fixed a real latent `Awake()`-ordering bug computing the hinge rotation from unconfigured defaults along the way). 2026-08-23.
  - [ ] 2e — Safe
- [ ] **U3** — real planning loop.
- [ ] **U4** — deterministic guard vision, первая настоящая `plan → execute → fail/succeed → edit → retry` миссия.

---

Порт идёт лучше, чем тебе сейчас кажется, но **Unity-версия пока портировала технический слой игры, а не её главную механику: `plan → execute → fail → edit → retry` фактически ещё отсутствует.** При этом я нашёл несколько конкретных вещей, которые сейчас надо исправить до дальнейшего наращивания проекта.

Я посмотрел последний push `f17bcc0`. В нём уже есть хороший фундамент: чистый C# core, собственный grid+A*, `LevelBlueprint`, `PropCatalog`, `MissionClock`, актёры, патрули, input/raycast и реально проходимая цепочка `дверь → панель → камера → сейф → loot → extraction`. Это не пустой перенос — технический vertical slice действительно существует. fileciteturn68file0L4-L4

Но есть важная разница между «можно кликать и пройти уровень» и «работает наша игра».

### Что уже перенесено, а чего нет

| Система | Unity сейчас | Относительно Swift |
|---|---|---|
| Data-driven LevelBlueprint | ✅ | практически есть |
| PropCatalog | ✅ | есть |
| Custom grid + A* | ✅ | базовый вариант есть |
| Tap / raycast / selection | ✅ | есть |
| Перемещение персонажа | ✅ | визуально работает |
| Guard patrol | ✅ базовый | сильно проще Swift |
| Door | ✅ live | не встроена в план |
| Security panel → camera | ✅ live | не встроено в timeline |
| Safe → loot → extraction | ✅ live | работает |
| MissionClock | ✅ каркас | есть |
| `PlanAction / ActorPlan / MissionPlan` | ✅ модели данных | есть |
| Настоящее plan recording | ❌ | нет |
| Commit / execution | ❌ | нет |
| Reset → deterministic replay | ❌ | нет |
| Edit/retry | ❌ | нет |
| Failure reason + timestamp | ❌ | нет |
| Guard vision / detection | ❌ | Swift значительно впереди |
| Camera detection | ❌ | камера только визуально вращается |
| Multi-actor synchronization | ❌ | нет |
| Actor encounter/collision planning | ❌ | Swift намного впереди |
| Automatic door traversal | ❌ | Swift впереди |
| Character action state machine | ⚠️ очень базово | Swift намного впереди |
| Реальные humanoid assets | ❌ в репозитории нет | Swift имел реальные модели |
| Plan Deck / HUD | ❌ | нет |
| Tests | ⚠️ практически нет | Swift: большой regression suite |
| Lighting / production graphics | ❌ | ещё не начиналось нормально |

Ключевой нюанс: **сущность плана в C# у тебя уже есть.** `PlanAction`, `ActorPlan`, `MissionPlan`, типы `MoveTo`, `Wait`, `OpenDoor`, `Hack`, `CrackSafe`, `TakeLoot`, `Extract` и т. д. уже созданы. fileciteturn84file0L2-L2

Не существует именно **рабочего планировщика**.

Сейчас в `GameController.OnFloorClicked()` происходит неправильное для финальной механики действие:

```text id="jvcch6"
тап
↓
персонаж сразу идёт
+
MoveTo записывается в MissionPlan
```

А `TickExecution()` и фактический `StartExecution()` всё ещё TODO. fileciteturn79file0L2-L2

То есть сейчас `MissionPlan` фактически работает как журнал того, что игрок уже сделал, а должен быть инструкцией о том, **что персонаж сделает потом**.

Это и есть главный следующий рубеж.

---

## Но сначала я нашёл три инфраструктурные проблемы

### 1. CLAUDE.md и AGENTS.md сейчас прямо противоречат реальности

Это серьёзно.

Текущий `CLAUDE.md` продолжает говорить:

> Swift + SwiftUI + RealityKit + Reality Composer Pro  
> Do not migrate to Unity

и подробно инструктирует Claude заниматься RealityKit. fileciteturn91file0L2-L2

`AGENTS.md` делает то же самое Codex: Swift, RealityKit, Xcode, Apple runtime stack и запрет миграции в Unity. fileciteturn92file0L2-L2

При этом последний commit уже говорит, что:

> `UnityPort/` — active development target going forward.

fileciteturn68file0L4-L4

**Это надо исправить первым коммитом.** Иначе ты буквально даёшь агентам взаимоисключающие инструкции.

Swift-проект надо обозначить:

```text id="9usr4w"
FROZEN REFERENCE IMPLEMENTATION
```

а:

```text id="jjzg6w"
UnityPort/
```

как:

```text id="bjgqbz"
ACTIVE PRODUCTION TARGET
Unity 6.5.9f1
C#
```

---

### 2. Unity у тебя уже правильной версии — 6.5.9f1

Это я специально проверил по самому проекту:

```text id="qeapzo"
m_EditorVersion: 6000.5.9f1
```

fileciteturn86file0L2-L2

То есть **версию Unity сейчас не трогаем вообще.**

---

### 3. Но проект сейчас НЕ URP

Вот это неожиданно и важно.

В `Packages/manifest.json` **нет Universal Render Pipeline**. fileciteturn87file0L2-L2

А в `GraphicsSettings.asset`:

```text id="17d7oz"
m_CustomRenderPipeline: {fileID: 0}
```

То есть UnityPort сейчас сидит на Built-In Render Pipeline. fileciteturn88file0L2-L2

И `GameBootstrap` действительно создаёт материалы через:

```csharp id="ntl1qe"
Shader.Find("Standard")
```

то есть Built-In shader. fileciteturn89file0L2-L2

Это надо исправить **сейчас**, пока проект маленький.

Официальный Unity Render Pipeline Converter предназначен именно для Built-In → URP и умеет создать URP Asset/Renderer и конвертировать материалы. Unity предупреждает, что преобразование необратимо, поэтому сначала checkpoint/commit. ([docs.unity3d.com](https://docs.unity3d.com/cn/6000.0/Manual/urp/features/rp-converter.html?utm_source=chatgpt.com))

---

# Конкретный план Unity-порта

Я бы теперь не пытался тупо переносить Swift feature-for-feature. В Swift вы уже слишком далеко ушли в сложную навигацию, ещё не доказав главную механику. Собственный `PRODUCTION_PLAN.md` уже правильно говорит: следующий design gate — **plan → commit → failure → correction → retry**, а не очередной routing algorithm. fileciteturn78file0L2-L2

Поэтому порядок такой.

## Этап 0. Сделать репозиторий правдивым

Сначала один housekeeping commit.

1. `CLAUDE.md`: Unity 6.5.9f1 становится active production target.
2. `AGENTS.md`: то же для Codex.
3. Swift/RealityKit обозначить как frozen reference implementation.
4. `UnityPort/README.md` исправить — сейчас он ошибочно называет себя «complete Unity port», рекомендует Unity 2022.3 и местами всё ещё говорит про NavMeshAgent, хотя код уже перешёл на grid+A*. fileciteturn70file0L2-L2
5. Создать `docs/UNITY_PORT_STATUS.md` с таблицей `Swift → Unity`.

Это важно не для красоты документации. **Агенты должны получать одно актуальное описание проекта.**

---

## Этап 1. Built-In → URP

Сделать checkpoint.

Затем в Unity:

`Window → Rendering → Render Pipeline Converter`

выбрать:

`Built-in Render Pipeline to URP`

и выполнить минимум:

```text id="ua28yb"
Rendering Settings
Material Upgrade
```

Unity сама создаёт URP Asset и Renderer Asset. Это официальный путь. ([docs.unity3d.com](https://docs.unity3d.com/cn/6000.0/Manual/urp/features/rp-converter.html?utm_source=chatgpt.com))

После этого:

```text id="4j59yj"
Shader.Find("Standard")
```

больше не использовать. Для создаваемых runtime-материалов использовать URP/Lit либо реальные Material assets.

Критерий готовности:

```text id="bnda76"
SampleScene запускается
0 красных Console errors
весь текущий уровень виден
door/panel/safe/loot/extraction всё ещё работают
GraphicsSettings содержит URP asset
```

После этого рендер-пайплайн больше не трогаем.

---

# Этап 2. Сделать C# simulation единственным источником истины

Вот это фундамент.

Сейчас `ActorEntity` самостоятельно двигает GameObject через:

```csharp id="7cjvtf"
Time.deltaTime
```

fileciteturn81file0L2-L2

Дверь анимируется через `Time.deltaTime`, security camera вычисляет scan phase через `Time.deltaTime`, safe cracking тоже накопливает `Time.deltaTime`. fileciteturn93file0L2-L2

Поэтому **нынешняя Unity-версия ещё не является реально детерминированной**, несмотря на наличие `MissionClock`.

Нужно сделать:

```text id="gkv12h"
DerClou.Core
    MissionState
    ActorState
    GuardState
    DoorState
    SecurityCameraState
    SafeState
    MissionSnapshot
    FailureEvent

    SimulationEngine
        Tick(fixedDt)
        StateAt(time)
```

Главное правило:

```text id="21s4lg"
Core simulation decides WHAT happened.

Unity decides HOW it looks.
```

Например:

```text id="ed8e3z"
Simulation:
guard1 position at 12.4 = (8.2, 5.0)
guard1 facing = 137°
door1 open = 0.62

Unity:
transform.position = that position
Animator = Walk
door mesh rotation = 55.8°
```

Но Unity Transform больше не определяет game state.

Критерий:

Одна и та же миссия, запущенная с render:

```text id="70g4we"
30 FPS
60 FPS
120 FPS
```

даёт одинаковые события и времена.

---

# Этап 3. Настоящий PLAN

Вот здесь Unity впервые превращается именно в твою игру.

Уже существующие:

```text id="qovfjh"
PlanAction
ActorPlan
MissionPlan
```

не выбрасывать. Они нормальная основа. fileciteturn84file0L2-L2

Добавить примерно:

```text id="6gntgl"
PlanBuilder
PlanCompiler
PlanExecutor
MissionInitialSnapshot
ExecutionTrace
FailureEvent
```

### Что меняется при тапе

Сейчас:

```text id="1g6h0s"
tap → actor moves
```

Должно быть:

```text id="r3pfpb"
tap
↓
PathFinder
↓
calculate path distance
↓
duration = distance / walkSpeed
↓
append MoveTo to ActorPlan
↓
actor DOES NOT MOVE
```

Можно показывать линию будущего маршрута.

Следующий тап:

```text id="jr2wge"
MoveTo
then
OpenDoor
then
MoveTo
then
Hack
```

Каждое действие имеет:

```text id="r3hmlq"
startTime
duration
endTime
```

---

# Этап 4. Shared timeline

У каждого персонажа собственная дорожка:

```text id="5j2x66"
THIEF
0 ─ Move ─ Open ─ Move ─ CrackSafe ─ Take

TECH
0 ───── Wait ─ Move ─ Hack ────────────

GUARDS / CAMERAS
живут на той же общей временной оси
```

Это принцип оригинальной игры и уже зафиксирован в проектной документации.

Добавить явный:

```text id="t825o9"
ActorPlanCursor
```

То есть если действия thief занимают:

```text id="7u3qzr"
Move 4.2
OpenDoor 1.0
Move 3.5
```

следующее действие автоматически стартует на:

```text id="78skkt"
8.7 s
```

А `WAIT` просто увеличивает cursor.

---

# Этап 5. EXECUTE

Только после нажатия Execute:

```text id="eizsxn"
1. сохранить immutable MissionPlan
2. восстановить MissionInitialSnapshot
3. missionClock = 0
4. phase = Execution
5. запустить SimulationEngine
6. Unity presentation следует за simulation state
```

Во время execution игрок уже не задаёт свободные движения.

Если тот же plan запустить десять раз:

```text id="76oqz6"
run 1 = run 2 = ... = run 10
```

---

# Этап 6. Failure → Retry

Вместо обычного:

```text id="itr06g"
Game Over
```

симуляция должна возвращать:

```text id="194vch"
FailureEvent
{
    time: 12.43
    actor: thief1
    source: guard1
    reason: Seen
    position: ...
}
```

UI:

```text id="c8g24j"
FAILED
Seen by Guard 1
00:12.43
```

После этого:

```text id="ctvcqa"
Back to Plan
```

План **не удаляется**.

Игрок меняет:

```text id="gd4kdk"
WAIT 0.8 s
```

или маршрут и снова Execute.

Вот здесь наконец появляется сама игра.

---

# Этап 7. Vision

После рабочего replay.

Перенести из Swift не весь код, а контракт:

```text id="tmwjxd"
range
FOV angle
facing
line of sight
```

В pure C#.

Не использовать `Physics.Raycast` как источник истины.

Можно использовать его для visual/debug verification, но detection должен считаться из той же 2D geometry, что и simulation.

Security camera тоже должна быть функцией mission time:

```text id="poiyhn"
yaw = ScanYaw(time, arc, period, phase)
```

а не:

```csharp id="lens7v"
scanPhase += Time.deltaTime
```

как сейчас. fileciteturn93file0L2-L2

И нарисованный cone должен использовать **эти же числа**.

---

# Этап 8. Door traversal

После vision.

Здесь уже можно забрать хорошую механику Swift:

```text id="r4dh4f"
route intersects closed door
↓
approach door
↓
OpenDoor / Unlock / Lockpick
↓
door changes state
↓
continue original destination
```

Не заставлять игрока тапать:

```text id="4k2e2h"
до двери
на дверь
за дверь
```

если смысл команды был:

> иди туда.

Swift это уже умел; в Unity стоит повторить **поведение**, а не переносить реализацию один-в-один. fileciteturn76file0L2-L2

---

# Этап 9. Multi-actor synchronization

Только теперь второй playable actor.

Очень важно:

не использовать Unity local avoidance как gameplay authority.

У тебя уже есть правильный custom pathfinder.

Далее:

```text id="f25u56"
trajectory A
trajectory B
↓
predict overlap in time/space
↓
deterministic resolution
```

На первом этапе достаточно:

```text id="hrujcq"
actor radius
route commit order
stable tie breaker
wait/detour
```

Не надо сразу переносить всю чудовищно сложную систему encounter planning из Swift.

---

# Этап 10. Минимальный Plan Deck

Не сразу красивый.

Я бы здесь выбрал Unity UI Toolkit, потому что структура и стили могут жить в текстовых `UXML` + `USS`, что удобно агентам; Unity сама рекомендует UXML для описания UI-структуры. ([docs.unity3d.com](https://docs.unity3d.com/kr/6000.0/Manual/ui-systems/introduction-ui-toolkit.html?utm_source=chatgpt.com))

Минимум:

```text id="dx78rh"
00:12.4        EXECUTE

THIEF
[ MOVE ][ WAIT ][ OPEN ][ MOVE ]

TECH
[ WAIT ][ MOVE ][ HACK ]

|────────────●────────────|
```

Нужно уметь:

```text id="lzitbd"
выбрать actor
увидеть actions
удалить action
вставить Wait
scrub time
Execute
Reset
Back to Plan
```

Не заниматься пока красивыми иконками.

---

# Этап 11. Персонажи

Только когда основной цикл уже работает.

Сначала **один** настоящий Mixamo humanoid.

Не пять.

```text id="yjvqqy"
Thief
Idle
Walk
```

Проверить:

```text id="m7656p"
Humanoid avatar
Animator
Idle ↔ Walk
нормальный scale
ноги не скользят
тень есть
20–30 минут без деградации
```

После этого Guard.

После этого уже:

```text id="be3eji"
Base Layer = locomotion
Upper Body Layer = flashlight / interaction
Avatar Mask = upper body
```

Текущий `ActorEntity` уже содержит заготовку под такой layer, хотя assets в `UnityPort` ещё фактически отсутствуют. fileciteturn81file0L2-L2

---

# Этап 12. Камера — РЕШЕНО, 2026-08-23, не открывать заново

**Статус: закрыто.** Рекомендация ниже про переход на perspective camera **устарела и отменена** — оставлена только для истории решения, не как инструкция агенту. Не тратить время на повторный пересмотр этого этапа.

Что произошло: рекомендация строилась на предположении, что orthographic-камера не даёт теней — это верно для RealityKit (см. `docs/UI_AND_CAMERA.md`, отдельный, годами задокументированный баг именно этого движка) и **оказалось неверно для Unity**. Клод проверил вживую (рендер-скриншоты в Unity-сессии 2026-08-23): `TacticalCamera` в Built-in RP, orthographic, с наклоном — тени рендерятся нормально. Причина, из-за которой Swift-версию пришлось уводить в перспективную камеру-обманку, здесь просто отсутствует.

**Решение владельца (2026-08-23):** оставить текущую orthographic diorama-камеру как есть. Не переносить старые RealityKit-компромиссы (off-axis projection, perspective-под-orthographic) в Unity без причины, которая здесь реально существует.

**Критерий готовности камеры** (заменяет всё, что написано ниже в свёрнутом блоке): камера считается рабочей, если даёт (1) читаемую диораму, (2) peek-жест (уже сделан — `docs/UI_AND_CAMERA.md`: rotation/panning прямо "not offered, decided"), (3) нормальные тени. Все три уже выполнены. Камера не должна становиться отдельным исследовательским проектом — не трогать дальше без явного запроса владельца.

<details>
<summary>Исходная рекомендация этого этапа (устарела, оставлена для истории решения)</summary>

Я **не переносил бы сейчас ту 12-часовую custom off-axis камеру из RealityKit.**

В Unity сейчас `TacticalCamera` всё ещё orthographic + tilt + pan/edge-pan.

Для production baseline я бы сделал проще:

```text
Perspective Camera
fixed tabletop/diorama angle
carefully framed level
optional pinch zoom
no edge-pan on iPhone
```

То есть тот визуальный подход, к которому мы в итоге пришли после сравнения с нормальной диорамой.

Когда игра уже выглядит хорошо — можно решить, нужен ли какой-то особый camera effect вообще.

</details>

---

# Этап 13. Убрать ощущение коробки

У Xcode-документации уже есть правильная идея: здание должно **стоять где-то**, а не быть всей вселенной.

То есть вокруг:

```text id="soxlfp"
grass
pavement
path
shrubs
trees
exterior props
```

fileciteturn90file0L2-L2

И foreground wall fade/cutaway.

Это даст гораздо больший визуальный выигрыш, чем очередная хитрая projection matrix.

---

# Этап 14. LightingLab → настоящий уровень

После URP.

Отдельная сцена:

```text id="9cnnb7"
floor
wall
cube
character
Directional Light
shadows
ambient / sky
```

Получить хороший стабильный результат.

Только потом переносить те же настройки на Level 1.

Не отлаживать освещение одновременно с персонажем, камерой, pathfinding и UI.

---

# Этап 15. iPhone parity gate

Когда всё выше работает:

Development Build → Xcode → реальный iPhone.

Тест минимум 30 минут:

```text id="p6owfm"
3 guards
1 thief
1 scanning camera
shadows
animations
Plan Deck
repeated execution/retry
```

Проверяем:

```text id="0l3yk9"
FPS
CPU
GPU
memory
allocations
thermal behaviour
animation stability
input latency
```

---

## Что я специально НЕ стал бы сейчас переносить из Swift

Чтобы опять не потратить неделю не туда:

```text id="4d7cah"
❌ сложный polygon corridor/funnel backend
❌ весь encounter-planning machinery
❌ все 184 старых теста одним махом
❌ custom off-axis projection
❌ сложный procedural skeleton system
❌ все пять персонажей
❌ полный security dependency graph
❌ polished UI
```

Сначала:

```text id="dgm0tp"
ONE THIEF
ONE GUARD
ONE VISION CONE
ONE PLAN
EXECUTE
FAIL
FIX
RETRY
```

Если **это** начинает ощущаться как интересная головоломка — всё остальное уже имеет смысл.

И это, кстати, буквально совпадает с наиболее разумной частью собственного `PRODUCTION_PLAN.md`: там уже написано, что текущий главный риск — выстроить девять систем, прежде чем проверить, приятно ли вообще игроку исправлять план после ошибки. fileciteturn78file0L2-L2

### Что я бы дал Клоду прямо сейчас

Не «продолжай портировать игру».

А следующий строго последовательный пакет:

```text id="9uzc5u"
MILESTONE U0
Fix repository source-of-truth:
- UnityPort is active production target.
- Unity 6000.5.9f1.
- Swift/RealityKit is frozen reference only.
- update CLAUDE.md, AGENTS.md and UnityPort/README.md.
- do not delete Swift implementation.

MILESTONE U1
Checkpoint current working UnityPort, then convert Built-In Render Pipeline to URP using Unity's official Render Pipeline Converter.
Verify the existing playable live loop still works with zero Console errors.

MILESTONE U2
Make DerClou.Core the sole gameplay authority.
No actor movement, guard timing, camera scan, door state, safe cracking or mission outcome may depend on Time.deltaTime or a GameObject Transform.
Unity objects become presentation of pure-C# simulation state.

MILESTONE U3
Implement the real planning loop:
Planning tap creates PlanAction but does not move the actor.
Compile paths and durations.
Execute restores initial snapshot and plays immutable MissionPlan.
Failure returns time/source/reason.
Retry preserves the plan.
Same plan must produce identical result.

MILESTONE U4
Add one deterministic guard + pure-C# vision + visible matching cone.
Then make the first greybox mission genuinely playable as:
plan → execute → seen/fail or succeed → edit → retry.
```

**До завершения U4 я бы запретил агенту заниматься новыми персонажами, красивыми материалами, дополнительными уровнями и сложной камерой.**

После U4 Unity-версия впервые будет не просто технически догонять Xcode, а **реально станет прототипом той игры, которую ты задумал**.