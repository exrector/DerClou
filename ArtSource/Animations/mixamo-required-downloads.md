# DerClou — точный список анимаций Mixamo

Снимок каталога: 2026-08-22. Полный авторизованный каталог Motion содержит
2446 уникальных клипов. UUID приведён, чтобы различать одноимённые результаты.

## Настройки экспорта для каждого клипа

- Character: один и тот же утверждённый мужской риг DerClou.
- Format: FBX Binary.
- Skin: Without Skin.
- Frames per Second: 30.
- Keyframe Reduction: None.
- In Place: включать для циклов Walk/Run/Sneak; для стартов, остановок,
  поворотов и взаимодействий сохранить исходный root motion для анализа,
  затем удалить перенос/поворот root в импортном пайплайне DerClou.

## P0 — скачать сейчас: базовый контракт движения

| Семантика | Точное имя в Mixamo | Описание, которое должно совпасть | UUID |
|---|---|---|---|
| StopWalking | Stop Walking | Walking To Standing Idle | `c9c8d966-b96c-11e4-a802-0aaa78deedf9` |
| ShortStepForward | Short Step Forward | Short Boxing Step Forward | `c9cb50af-b96c-11e4-a802-0aaa78deedf9` |
| ShortStepBackward | Step Backward | Short Boxing Step Backward | `c9cadb92-b96c-11e4-a802-0aaa78deedf9` |
| SideStep | Side Step | Side Step | `c9c7ff20-b96c-11e4-a802-0aaa78deedf9` |
| TurnLeft90 | Unarmed Turn Left 90 | Turning 90 Degrees Left | `c9ceef5f-b96c-11e4-a802-0aaa78deedf9` |
| TurnRight90 | Unarmed Turn Right 90 | Turning 90 Degrees Right | `c9cef01d-b96c-11e4-a802-0aaa78deedf9` |
| TurnLeft45 | Left Turn 45 | 45 Degree Left Turn From Idle | `c9c94322-b96c-11e4-a802-0aaa78deedf9` |
| TurnAround | Quick 180 Turn | Quick Right 180 Turn | `c9c8c959-b96c-11e4-a802-0aaa78deedf9` |
| WalkTurn180 | Walking Turn 180 | Turning 180 Degrees While Walking | `c9c9c73f-b96c-11e4-a802-0aaa78deedf9` |
| WalkArcLeft | Walking Left Turn | Turning Left While Walking | `c9ccc3a9-b96c-11e4-a802-0aaa78deedf9` |
| WalkArcRight | Walk Forward Arc Right | Walking Forward Right Arc In A Sad Disposition | `c9ccdbe3-b96c-11e4-a802-0aaa78deedf9` |

`WalkArcRight` — только кандидат для проверки ног: верх тела имеет sad-style.
Если стиль заметен после lower-body extraction, клип отклонить. Плавная произвольная
траектория всё равно строится steering-системой; эти клипы нужны для контакта стоп,
а не для задания геометрии маршрута.

Уже имеются локально и повторно скачивать не нужно: `Unarmed Idle`, чистый
`Start Walking` с описанием `Walking From Standing` (UUID
`c9c8b661-b96c-11e4-a802-0aaa78deedf9`), `Standard Walk` (UUID
`c9ccc2e9-b96c-11e4-a802-0aaa78deedf9`).

## P1 — скачать для вора и тревоги

| Назначение | Точное имя | Описание | UUID |
|---|---|---|---|
| Sneak loop | Sneak Walk | Male Ninja Sneak Walk | `c9cd223d-b96c-11e4-a802-0aaa78deedf9` |
| Crouch walk | Crouch Walk Forward | Walking Forward While Crouched | `b9fbd249-a554-423c-aa37-baa98223c4dc` |
| Crouch turn left | Crouch Turn Left 90 | Turning 90 Degrees Left | `59638101-83cb-4f5b-9ecc-5f3184b1669c` |
| Crouch turn right | Crouch Turn Right 90 | Turning 90 Degrees Right | `f73f73aa-7b67-43ca-ad1b-f58e6f909e95` |
| Chase run | Running | Running Forward Quickly | `c9c97eca-b96c-11e4-a802-0aaa78deedf9` |
| Run stop | Run To Stop | Fast Stop From Full Run | `c9c9a5a7-b96c-11e4-a802-0aaa78deedf9` |
| Run reversal | Running To Turn | Fast Run To 180 Degree Turn | `c9c8d7db-b96c-11e4-a802-0aaa78deedf9` |

## P1 — двери, мебель, устройства и реакция охранника

| Назначение | Точное имя | Описание | UUID |
|---|---|---|---|
| Door inward | Opening Door Inwards | Male Walking And Opening A Door Inwards | `c9ca099c-b96c-11e4-a802-0aaa78deedf9` |
| Door outward | Open Door Outwards | Open Door Outwards While Walking | `c9ca4de1-b96c-11e4-a802-0aaa78deedf9` |
| Try locked door | Opening | Attempting To Open A Door | `c9c84f3e-b96c-11e4-a802-0aaa78deedf9` |
| Cabinet open | Opening | Opening Cabinet Door | `c9c6d49e-b96c-11e4-a802-0aaa78deedf9` |
| Cabinet close | Closing | Closing Cabinet Door | `c9c6d55d-b96c-11e4-a802-0aaa78deedf9` |
| Search low | Looking Through Files Low | Male Looking Through A File Cabinet Low | `c9ca04b6-b96c-11e4-a802-0aaa78deedf9` |
| Search high | Searching Files High | Searching The Top Drawer Of A File Cabinet | `c9ca0631-b96c-11e4-a802-0aaa78deedf9` |
| Inspect low | Kneeling Inspecting | Kneeling And Inspecting Element With Hands | `c9c8cded-b96c-11e4-a802-0aaa78deedf9` |
| Pick up / examine | Lifting | Pick Up Object And Examine | `c9c6fe3b-b96c-11e4-a802-0aaa78deedf9` |
| Guard scan | Unarmed Idle Looking Ver. 1 | Looking Around | `c9ceeaca-b96c-11e4-a802-0aaa78deedf9` |
| Guard hears/sees event | Reacting | Being Surprised And Looking Right | `c9c8214a-b96c-11e4-a802-0aaa78deedf9` |
| Capture candidate | Restrain | Block And Restraining A Larger Person | `c9c8aace-b96c-11e4-a802-0aaa78deedf9` |

Уже имеются локально: `Opening Door Inwards`, `Button Pushing`, `Pulling Lever`,
`Looking`. Дубликаты с `(1)` повторно не использовать.

## В Mixamo нет подходящего точного клипа

Не скачивать случайную замену только из-за похожего названия:

- `CloseDoor` для обычной межкомнатной двери;
- `UnlockDoor` ключом;
- `Lockpick`;
- `CrackSafe` / вращение диска сейфа;
- `Hack` стоя у панели;
- болгарка, дрель и другие шумные инструменты;
- полноценная парная анимация захвата, согласованная для двух конкретных ригов.

Эти действия требуют отдельного авторского/Fab-клипа или редактирования в Blender.
Для `CloseDoor` нельзя молча проигрывать `OpenDoor` задом наперёд: это допустимо
только после проверки контакта руки, стороны петель и траектории корпуса.

## Правило приёмки

Каждый FBX проходит автоматическую очистку: импортируется только Action/armature,
меш и материалы источника не копируются. Затем проверяются совместимость рига,
контакт стоп, длительность, loop seam, root displacement/root yaw и отсутствие
оружия/реквизита в позе. Имя файла назначается по семантике DerClou, а не по
неоднозначному имени Mixamo.
