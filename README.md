# Proximity Archipelago

Небольшая стратегия о колонии муравьёв. За **3 минуты** накопите по **100 древесины, камня и пищи**. Стартовый муравейник содержит **5 муравьёв**. Начальный склад: 60 древесины, 40 камня, 20 пищи. Дороги ускоряют движение и помогают выполнить цель; ожидание без строительства приводит к поражению.

## Запуск

Откройте `project.godot` в **Godot 4.7.2** и нажмите F5. Для чистого запуска из терминала:

```sh
godot --headless --editor --quit
godot --path .
```

После обновления кода завершите прежний запущенный экземпляр игры и запустите F5 заново.

## Управление

| Действие | Управление |
| --- | --- |
| Перемещение камеры | Зажатая ЛКМ, средняя кнопка или WASD |
| Меню выбранной клетки | ПКМ |
| Закрытие меню строительства | Любой повторный ПКМ, ЛКМ снаружи или Esc |
| Масштаб | Колесо или кнопки − / +; при открытом меню колесо не масштабирует карту |
| Пауза / возврат | Esc |
| Настройки | Главное меню, кнопка «…» в HUD или меню паузы |

Снос требует подтверждения. Снос муравейника уничтожает его жителей. Последнюю столовую нельзя снести, пока в мире есть муравьи. Нельзя изменить рельеф так, чтобы живые муравьи потеряли безопасный путь к еде.

В HUD пища отображается как `всего(свободно)`: разница зарезервирована под следующие приёмы пищи. Стройка не может потратить эти порции.

## Границы кода

- `_shell/` — переходы экранов, стек меню, причины паузы, сохранение настроек.
- `screens/match.gd` — связь оболочки, ввода, HUD и одной игровой сессии.
- `game/wolrd.gd` — сборка локальных сервисов мира и явный запуск. Имя сохранено для совместимости существующих сцен.
- `game/entities/` — реестр зданий, население, дома и рабочие места. `ColonyPopulation` владеет созданием и удалением жителей.
- `game/planning/` — бюджет голода, выбор полного рабочего рейса и исполнение движения.
- `game/navigation/` — снимок сетки, A*, Dijkstra с кучей и ограниченные кэши полей расстояний.
- `game/building/` — определения построек и проверяемые команды размещения/сноса.
- `game/resources/` — склад с резервированием пищи и пакетными уведомлениями.
- `game/ui/`, `overlays/` — пиксельная тема, HUD и представление причин ошибок.
- `game/art/` — единый каталог сменяемых текстур.

Доменные правила не вызывают Router и не меняют глобальную паузу. Два мира не разделяют население, склад или реестр. Подробности и статус исходных 30 замечаний: [отчёт изменений](docs/CHANGE_REPORT.md). [Первичный аудит](ARCHITECTURE_AUDIT.md) описывает исходную ревизию.

## Графика и интерфейс

Игровые PNG имеют размер **16×16**. Замена через `game/art/colony_art.tres` поддерживает 32×32 и 64×64 при прежнем размере игровой клетки. [Инструкция и происхождение ассетов](game/art/README.md).

Интерфейс использует предоставленный BoldPixels, серые полупрозрачные девятисегментные рамки и квадратные состояния кнопок. Pixuf также импортирован для будущих вариантов темы. Базовый viewport — 640×360; масштабирование целое, aspect `keep`, фильтр nearest, обе привязки 2D к пикселям включены. Размер 640×360 выбран для читаемого BoldPixels 16 px.

## Проверки

```sh
./tools/check.sh
./tools/check_ui.sh
```

`check.sh` выполняет чистый импорт и регрессии в отдельной временной копии. Ошибки скриптов, провалы и утечки возвращают ненулевой код. `GODOT_BIN` позволяет выбрать исполняемый файл Godot. CI повторяет эти проверки на Godot 4.7.2.

`check_ui.sh` требует доступный X11, OpenGL и ffmpeg. Он использует отдельную копию и отдельные пользовательские настройки. Реальные события GUI проверяют меню, настройки, стройку, снос, управление камерой, паузу, победу, поражение и выход. Скриншоты, видео и JSON сохраняются в `evidence/after/`. Full HD проверяется отдельным viewport с итоговым масштабом 3×; переключение нативного полноэкранного режима проверяется отдельно.

Диагностика мира по умолчанию выключена. Включайте `World.diagnostics_enabled` только при необходимости.

## Примечания оболочки

1. `get_tree().create_timer(t)` defaults to `process_always = true`. It keeps firing while paused. If you use it in gameplay code, pass false explicitly:
```gdscript
await get_tree().create_timer(0.3, false).timeout
```

2. `get_tree().create_tween()` ignores pause. Always use `node.create_tween()`, because the tween inherits the node's process mode

3. Autoloads inherit pausability from root. If your future `AudioManager` fades music with a tween, set `process_mode = PROCESS_MODE_ALWAYS` in its `_ready()`

4. `await` in `_ready()` works but makes `_ready` `async`. `Router.goto` awaits the fade, so `Boot._ready` returns before the first screen is visible

5. Payload must be set before `add_child`. If you move the `_current.payload = payload` line after `add_child`, `_ready()` in the screen won't see it

6. Hidden menus still receive input unless you guard for it. That's why `MenuBase._unhandled_input` starts with `if not visible: return`

7. `process_mode` is set in the Inspector, not the script, for the shell layers. If you set it in code, make sure it runs before anything can pause - `_enter_tree()` is safe, `_ready()` is too late for the very first frame in edge cases
