# Доступ к редактору Unreal для агентов

В проекте **два независимых моста** в живой редактор. Оба работают только пока
редактор запущен. Оба слушают только петлевой интерфейс.

---

## Мост 1 — реестр инструментов Epic (был изначально)

- **Адрес:** `http://localhost:8000/mcp`
- **Протокол:** JSON-RPC, MCP. Авторизация не нужна.
- **Плагины:** `ModelContextProtocol`, `ToolsetRegistry`, `AllToolsets`,
  `MCPClientToolset` — были в проекте с самого начала.

### Как обратиться

```python
import json, urllib.request
URL = "http://localhost:8000/mcp"

def post(payload, sid=None, want_header=False):
    h = {"Content-Type": "application/json",
         "Accept": "application/json, text/event-stream"}
    if sid:
        h["Mcp-Session-Id"] = sid
    r = urllib.request.urlopen(
        urllib.request.Request(URL, json.dumps(payload).encode(), h), timeout=600)
    return (r.headers.get("Mcp-Session-Id"), r.read().decode()) if want_header            else r.read().decode()

sid, _ = post({"jsonrpc": "2.0", "id": 1, "method": "initialize",
               "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "agent", "version": "1"}}},
              want_header=True)
post({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)

def call(toolset, tool, args):
    d = json.loads(post({"jsonrpc": "2.0", "id": 99, "method": "tools/call",
        "params": {"name": "call_tool", "arguments":
            {"toolset_name": toolset, "tool_name": tool, "arguments": args}}}, sid))
    if d["result"].get("isError"):
        return ("ERR", d["result"]["content"][0]["text"])
    v = json.loads(d["result"]["content"][0]["text"]).get("returnValue")
    return json.loads(v) if isinstance(v, str) and v.startswith(("{", "[")) else v
```

### Основные наборы

| Набор | Для чего |
|---|---|
| `editor_toolset.toolsets.scene.SceneTools` | `find_actors`, `add_to_scene_from_class`, `remove_from_scene` |
| `editor_toolset.toolsets.actor.ActorTools` | `get_label`, `set_label`, `get_actor_transform`, `add_component`, `get_components` |
| `editor_toolset.toolsets.object.ObjectTools` | `get_properties`, `set_properties` — чтение и запись любых свойств |
| `editor_toolset.toolsets.asset.AssetTools` | `duplicate`, `move`, `delete`, `save_assets`, `exists` |
| `editor_toolset.toolsets.skeletal_mesh.SkeletalMeshTools` | `get_bone_names`, `get_socket_names`, `get_socket_transform`, `add_socket` |
| `DerClueEditor.DerClueStateTreeToolset` | **`AddMeshToSocket`**, **`AttachToSocket`** — наш собственный набор |

### Обязательные аргументы, которые легко забыть

`find_actors` требует **все четыре**: `actor_type`, `name`, `tag`,
`collision_channels`. Без любого — ошибка.

---

## Мост 2 — Funplay MCP (добавлен 2026-09-03)

- **Адрес:** `http://127.0.0.1:8765/`
- **Токен проекта:** `e0256005f3d28f9a634ecdc7825adbdcfc479507d0e382360ec27a007eb2c24c`
- **Заголовок:** `Authorization: Bearer <токен>`
- **Плагин:** `Plugins/FunplayMCP` — чистый Python, **компилировать нечего**
- **Настройки:** `Saved/FunplayMCP/funplay_mcp_settings.json`
  (профиль `full` = 97 инструментов, сервер стартует сам вместе с редактором)
- **Источник:** https://github.com/FunplayAI/funplay-unreal-mcp (MIT)

### Как обратиться

```python
import json, urllib.request
TOKEN = "e0256005f3d28f9a634ecdc7825adbdcfc479507d0e382360ec27a007eb2c24c"
URL = "http://127.0.0.1:8765/"

def rpc(method, params=None):
    body = json.dumps({"jsonrpc": "2.0", "id": 1,
                       "method": method, "params": params or {}}).encode()
    req = urllib.request.Request(URL, body, {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": "Bearer " + TOKEN})
    raw = urllib.request.urlopen(req, timeout=300).read().decode()
    for line in raw.splitlines():          # ответ приходит как SSE
        if line.startswith("data: "):
            raw = line[6:]
            break
    return json.loads(raw)

def call(tool, args=None):
    r = rpc("tools/call", {"name": tool, "arguments": args or {}})
    return r["result"]["content"][0]["text"]

print(call("execute_python", {"code": "result = unreal.SystemLibrary.get_engine_version()"}))
```

### Чем он ценен — закрывает дыры первого моста

| Что не мог мост 1 | Чем решается |
|---|---|
| Поставить `bUpdateAnimationInEditor` | `component.set_update_animation_in_editor(True)` |
| Сохранить уровень | `unreal.EditorLevelLibrary.save_current_level()`, `save_all_dirty_levels()` |
| Прочитать трансформы костей — углы приходилось подбирать вслепую | весь `unreal` API через `execute_python` |
| Управлять камерой окна просмотра | есть штатные инструменты |
| Увидеть результат без захвата экрана пользователя | `take_screenshot` — картинка приходит прямо в ответ |

### Чего в нём нет

Правки **графов** Blueprint. Если понадобится перепроводить узлы (например
переопределения в `ABP_Guard`), нужен третий мост — `ue-mcp`
(https://github.com/db-lyon/ue-mcp), но он требует плагина на C++ и его
компиляции при первом запуске редактора.

---

## Грабли, проверенные на практике

1. **`add_component_by_class` в Python этого движка НЕТ.** Компоненты
   добавлять через мост 1: `ActorTools.add_component`, затем
   `DerClueStateTreeToolset.AttachToSocket`.

2. **`get_actor_transform` после привязки к сокету врёт** — отдаёт
   обнулённый относительный трансформ, а не мировой. Пробник, привязанный к
   кости, вернёт `(0,0,0)`. Мировые трансформы читать через `execute_python`.

3. **Свойство `ParentAssetOverrides` (переопределения анимации в дочернем
   AnimBP) через мост 1 не читается и не пишется.** Оно хранит **прямые ссылки
   на объекты**: если удалить и пересоздать ассет по тому же пути, ссылка
   обнуляется молча, и AnimBP проваливается к родительским анимациям.

4. **Изменения в уровне не сохраняются сами.** Дважды теряли работу при
   перезагрузке уровня. Сохранять сразу: `save_current_level()`.

5. **`set_properties` не меняет размер массива и его элементы за один вызов** —
   ошибка `ArrayAdd: elements changed alongside the size change`. Делать в два
   прохода: сначала подмена значений, потом добавление по одному.
