# Proximity Archipelago

Стратегия о колонии муравьёв. Три запроса требуют ресурсы со склада; выполнение добавляет время и редкую награду. Отказ стоит ресурсов и не даёт награды. Пять закрытых запросов развивают колонию. Стартовый таймер — 3 минуты, население — 5 муравьёв. [Правила эксперимента](docs/TASK_EXPERIMENT.md).

## Запуск и редактирование

Откройте `project.godot` в Godot 4.7.2 и нажмите F5. После обновления завершите прежний запущенный экземпляр игры.

**Дизайнеру:** Project → Tools → «Открыть инструменты уровня». Вкладка **«Уровень»** содержит кнопки карты, каталога цен, начальных ресурсов, заданий и проверки. Нажмите **«1. Открыть карту и рисовать»**: откроется сохранённый уровень и палитра TileMap. Рисуйте кистью, сохраняйте Ctrl+S. Запуск не перерисовывает карту. [Пошаговая инструкция](docs/DESIGNER_WORKFLOW.md).

Карта по умолчанию 50×50. Можно рисовать дальше: границы мира и камеры следуют нарисованным клеткам. Вода не создаёт навигационных узлов; поле расстояний охватывает связанный остров. [Устройство навигации и ограничения](docs/ISLAND_NAVIGATION.md).

## Управление

| Действие | Управление |
| --- | --- |
| Камера | Зажатая ЛКМ, СКМ или WASD |
| Пауза и стройка | Пробел, B или «Пауза / стройка» |
| Рисование плана | Инструмент в палитре и ЛКМ |
| Применение плана | ▶, Пробел, Esc или B |
| Отмена в плане | ПКМ снимает последнее добавление на клетке; Ctrl+Z отменяет мазок; X отменяет план |
| Снос | Инструмент «Снос» в палитре |
| Камера в стройке | «Перемещение» и ЛКМ либо СКМ/WASD |
| Масштаб карты | Колесо, включая стройку; в обычной игре также − / + |
| Навигационные числа | N: вход в клетку в мс, приоритеты в секундах, выключено |
| Начало расчёта | ЛКМ по клетке в режиме приоритетов |
| Данные предприятия | Наведите курсор в режиме чисел |
| Меню, настройки, рестарт | Esc или «…» |
| Масштаб интерфейса | Настройки: 50%, 75%, 100%; исходно 75% |

Строительство по ПКМ удалено. Вне стройки ПКМ ничего не строит. Пища в HUD показана как `всего(свободно)`; стройка и задания не расходуют зарезервированные порции. Снос дома требует подтверждения и уничтожает его жителей. Проверка плана защищает безопасный путь к пище.

Предприятия выбираются по `время пути + 0.5 × (работают + идут)`. Запас продукции не участвует. Красные числа обозначают работу, синие — дома, зелёные — пищу, серые — обычные клетки. На предприятии отображается итоговая оценка с текущей нагрузкой. Боковая карточка показывает `2+1/4` и расчёт. [Подробности назначения](docs/WORK_ASSIGNMENT.md).

Дом стоит **10 дерева + 20 камня**. Цены и правила меняются в каталоге; сохранённые изменения подхватываются во время партии. Правило роста ×1.2 можно подключить в Price Rules. [Конфиги, новые ресурсы и рецепты](docs/DESIGNER_WORKFLOW.md).

## Проверки

```sh
bash tools/check.sh
bash tools/check_editor_ui.sh
bash tools/check_ui.sh
bash tools/check_planning_ui.sh
bash tools/check_construction_ui.sh
bash tools/check_designer_ui.sh
bash tools/check_tasks_ui.sh
```

Проверки выполняются в отдельных копиях проекта. GUI требует X11, OpenGL и ffmpeg. Снимки, видео и отчёты сохраняются **вне репозитория**, по умолчанию в `/tmp/colony-validation`. Другой путь задаётся `COLONY_OUTPUT_ROOT=/absolute/path`. Папка `evidence` удалена; прежние записи доступны в истории Git.

`World.diagnostics_enabled` включает журнал колонии. [Диагностика Windows WASAPI](docs/WINDOWS_AUDIO.md); [разбор удалённого кода](docs/ISLAND_NAVIGATION.md#очистка).

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

