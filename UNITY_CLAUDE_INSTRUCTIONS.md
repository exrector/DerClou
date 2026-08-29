# DerClou — подключение Claude к Unity и обязательный рабочий цикл

Эта инструкция предназначена для Claude Code, который продолжает разработку
Unity-версии DerClou на этом Mac. Она описывает фактическую локальную
конфигурацию. Не заменять её универсальными советами из старых Unity-гайдов.

## 1. Точные проект и редактор

- Корень репозитория: `/Users/exrector/Documents/PROJECTS/DerClou`
- Активный Unity-проект: `/Users/exrector/Documents/PROJECTS/DerClou/UnityPort`
- Редактор: `/Applications/Unity/Hub/Editor/6000.5.9f1/Unity.app`
- Основная тестовая сцена: `Assets/DerClou/Scenes/DeveloperSandbox.unity`
- Активная production-реализация: Unity/C#.
- Swift/RealityKit-код — frozen reference; не редактировать его как основной
  проект и не удалять.

Сначала прочитать полностью:

1. `UNITY_CLAUDE_INSTRUCTIONS.md`
2. `docs/00_UNITY_PORT_MASTER_PLAN.md`
3. `docs/ADR_UNITY_FIRST_FOUNDATION.md`
4. `docs/ADR_2D_SIMULATION_3D_DIORAMA.md`
5. `docs/DEVELOPER_SANDBOX.md`
6. `CLAUDE.md`

Перед изменениями выполнить:

```sh
cd /Users/exrector/Documents/PROJECTS/DerClou
git status --short
cat UnityPort/ProjectSettings/ProjectVersion.txt
pgrep -fl '/Unity.app/Contents/MacOS/Unity'
```

Грязное рабочее дерево ожидаемо: не стирать и не откатывать чужие изменения.

## 2. Фактическое MCP-подключение Claude

Claude Code уже имеет user-scoped сервер `unity-mcp`:

```text
command: /Users/exrector/.unity/relay/relay_mac_arm64.app/Contents/MacOS/relay_mac_arm64
args: --mcp
scope: user
```

Проверка:

```sh
claude mcp get unity-mcp
claude mcp list
```

Нормальный результат: `unity-mcp ... Connected`.

Если запись отсутствует или повреждена, а relay существует, восстановить:

```sh
claude mcp remove unity-mcp -s user
claude mcp add -s user unity-mcp -- \
  /Users/exrector/.unity/relay/relay_mac_arm64.app/Contents/MacOS/relay_mac_arm64 --mcp
```

Не переустанавливать Unity, AI Navigation или relay только потому, что одно
MCP-действие не ответило. Сначала проверить процесс Unity, проект и состояние
relay. Имена MCP-инструментов могут получать технический hash/prefix; выбирать
их по смысловому имени `Unity_*`, не записывать hash в код или документацию.

## 3. Если Unity не запущен

Запускать строго закреплённую версию и строго `UnityPort`:

```sh
open -a '/Applications/Unity/Hub/Editor/6000.5.9f1/Unity.app' --args \
  -projectPath '/Users/exrector/Documents/PROJECTS/DerClou/UnityPort'
```

Дождаться завершения импорта/компиляции. Через Unity MCP проверить:

1. `Unity_GetProjectRoot`/`Unity_ManageEditor.GetProjectRoot` — путь должен
   заканчиваться на `/DerClou/UnityPort`.
2. `Unity_ManageEditor.GetState` — `IsCompiling=false`, `IsUpdating=false`.
3. `Unity_ManageScene.GetActive` — активна `DeveloperSandbox` либо явно
   требуемая текущей задачей сцена.
4. `Unity_ReadConsole` — нет красных ошибок.

Если активна не та сцена, загрузить через MCP:

```text
Unity_ManageScene.Load
Path: Assets/DerClou/Scenes/DeveloperSandbox.unity
```

## 4. Обязательный Unity Standard Gate

Перед каждой функцией или исправлением проверить в таком порядке:

1. built-in Unity API/component;
2. уже установленный released official Unity package;
3. официальную документацию именно для Unity 6000.5.9f1/совместимой версии
   пакета;
4. thin adapter к детерминированному Core;
5. собственный алгоритм — только для уникальной механики DerClou или после
   документированного пробела Unity.

Установленный baseline находится в `UnityPort/Packages/manifest.json`:

- URP 17.5;
- Input System 1.20 и uGUI;
- AI Navigation 2.0.14;
- Cinemachine 3.1.7;
- Animation Rigging 1.4.1;
- Behavior 1.0.16;
- ProBuilder 6.1.2;
- Splines 2.9.0;
- Timeline 1.8.13;
- Memory Profiler и Profile Analyzer.

Не добавлять новый пакет, пока существующий baseline или built-in API решает
задачу. Не предлагать платные плагины как основу проекта.

## 5. Архитектурная граница, которую нельзя нарушать

- `DerClou.Core` владеет временем, состоянием, маршрутами, обнаружением,
  приоритетами, планом, retry и результатом миссии.
- Unity владеет NavMesh-запросом, рендерингом, Transform-представлением,
  Animator, Light, материалами, камерой и UI.
- Вся механика рассчитывается в X/Z. Y существует для 3D-диорамы и света.
- `NavMeshAgent` не двигает персонажа и не является gameplay authority.
- `NavMeshPath` можно запросить один раз и скопировать в immutable
  `WorldPoint[]`; Execute/Retry не перестраивает его каждый кадр.
- Spot Light визуален. Точное попадание вора определяется одним 2D
  `VisionSolver`; технический слой `[T]` показывает его реальные границы.
- Лучи, raycast, изменения света и декоративные действия не останавливают
  движение и не инвалидируют чужие маршруты глобально.

## 6. Как безопасно редактировать и проверять

До изменения:

1. прочитать затрагиваемые файлы и существующие тесты;
2. проверить `git status`/`git diff`;
3. не перезаписывать сцену, prefab или пользовательские изменения целиком;
4. для текстовых файлов делать минимальный patch;
5. для Unity assets/scene hierarchy предпочитать Unity MCP.

После изменения C#:

1. очистить Console;
2. выполнить `Assets/Refresh` через `Unity_ManageMenuItem`;
3. дождаться `IsCompiling=false`;
4. прочитать Console с типом `All`, а не только последнюю общую ошибку;
5. при ошибке `All compiler errors have to be fixed` найти настоящий
   `error CS...` выше в Console;
6. запустить EditMode-тесты штатной автоматизированной командой Unity MCP:
   `Unity_ManageMenuItem.Execute` → `Tools/DerClou/Run EditMode Tests`;
   итог читать в Editor.log как `[DerClou Tests] passed=N failed=0`;
7. затем запустить Play Mode и проверить целостное поведение в Game View.

Компиляция и unit-тесты не заменяют живую проверку. Для оконной проверки:

- сначала сфокусировать Game через menu item `Window/General/Game %2`;
- затем делать скриншот/ввод;
- не объявлять UI сломанным, пока не проверен фокус активного окна;
- не закрывать плавающее окно Test Runner красной кнопкой: на текущем macOS
  это может закрыть весь Unity Editor; возвращаться к Game через menu item;
- редакторский `Gizmos/NavMesh` не считать частью игры; игровой технический
  слой включается только кнопкой `[T]`.

## 7. Минимальная живая матрица после навигационных изменений

Проверить в `DeveloperSandbox`:

1. вор получает прямые последовательные назначения без остановки между ними;
2. вор и охранник никогда не проходят друг сквозь друга;
3. неподвижный актёр обходится одной плавной траекторией без коротких
   перепланирований;
4. занятый узел патруля обходится, а недоступный — пропускается;
5. после внешнего вызова охранник возвращается к ближайшему достижимому
   свободному узлу исходного маршрута;
6. закрытая дверь блокирует NavGrid, VisionSolver и Unity Spot Light shadow;
7. камера получает дальность из геометрии своей комнаты;
8. изменение на другом конце карты не пересчитывает маршрут охранника;
9. Console не содержит красных ошибок;
10. deterministic tests и live parity проходят.

## 8. Текущая точка продолжения

Завершено:

- U0–U4;
- developer sandbox и технический слой;
- первый U5-срез: runtime `NavMeshSurface`, стандартный `NavMeshPath`, копия
  результата в immutable `WorldPoint[]`;
- live parity: все четыре звена маршрута охранника достижимы;
- возврат после alert к ближайшему достижимому свободному узлу;
- закрытая дверь входит в точный occlusion и отбрасывает realtime-тень;
- дальность камеры выводится из комнаты.

Завершено дополнительно:

- U5.2: Core-интерфейс spatial corridor, Unity NavMesh adapter, frozen route
  в `PlanAction`, grid fallback/parity oracle;
- U6 Core: межкомнатный маршрут компилируется в `approach → align → open →
  traverse → optional close → resume`; Execute не вызывает новый path query;
- дверь централизованно обновляет NavGrid, VisionOccluders и revision портала;
- постоянная команда `Tools/DerClou/Run EditMode Tests` (53/53 на 2026-08-24).

Продолжать с завершения **U6 Unity presentation/live sandbox**, затем U7
stimuli/guard goal stack, U8 temporal reservations и U9 semantic motion — в
порядке master plan.

## 9. Формат завершения рабочего цикла

Перед передачей следующему агенту записать:

- что фактически изменено;
- что проверено в EditMode;
- что проверено в живом Game View;
- точные ошибки/блокеры, если остались;
- текущий следующий пункт master plan;
- Unity оставить открытым на `DeveloperSandbox`/Game View, если владелец не
  просил иначе.
