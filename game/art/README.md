# Замена графики

Текущие восемь игровых PNG имеют размер **16×16**. Они находятся в `game/assets/tiles/` и `game/assets/sprites/`.

## Быстрая замена

1. Замените нужный PNG, сохранив путь. Godot автоматически переимпортирует ресурс.
2. Либо откройте `game/art/colony_art.tres` в Inspector и назначьте новые текстуры.
3. Для отдельной темы создайте копию этого ресурса и назначьте её в поле `World.art`.

Логика не зависит от имён файлов нового набора. Меню, HUD и здания используют каталог. Показатели ресурсов и проходимость хранятся отдельно.

## Переход на 32×32 или 64×64

Картинки могут иметь другое квадратное разрешение. Каталог автоматически собирает временный атлас с максимальным разрешением тайлов. Меньшие тайлы увеличиваются nearest-neighbor при загрузке. Файлы при этом не изменяются.

Клетка игрового мира всегда занимает 16 мировых единиц. Размер клетки TileSet берётся из разрешения атласа; масштаб TileMap компенсирует это значение. Спрайты зданий также масштабируются к клетке. Координаты, footprint, маршруты и стоимость движения не меняются.

Поэтому замена 16×16 на 32×32 **не заставляет 32-пиксельную картинку залезать в соседнюю клетку**. Она сохраняет более подробную графику при том же игровом размере. Проверка `_test_art_resolution` подменяет одну текстуру на 32×32 и проверяет клетку, население и преобразования координат.

Для увеличения здания до нескольких игровых клеток меняйте `SceneBuildOption.occupied_cells` и точки входа `entry_offsets`. Разрешение рисунка само по себе не меняет площадь здания.

## Происхождение текущего набора

Использован встроенный инструмент imagegen. Созданы два исходных атласа. Четверти каждого механически уменьшены до 16×16 с BOX-фильтром и сохранены отдельными PNG. Исходные большие изображения не импортируются игрой. Анимация муравья и белые уголки рисуются кодом и не требуют замены текстур.

### Запрос для материалов

```text
Generate a production game terrain texture atlas for a top-down pixel-art ant colony strategy game. Exactly square 1024x1024 image, exactly a 2 by 2 grid with four equally sized square 512x512 tiles, no gutters, no borders, no labels, no lettering. TOP LEFT: rich forest-floor mossy grass, tiny pale grass blades, clover flecks and soil speckles, dark olive and sage green, seamless texture. TOP RIGHT: warm earthen soil, tiny pebbles, roots and grain, chestnut brown and ochre, seamless texture. BOTTOM LEFT: compacted dirt footpath surface with small worn cobbles and subtle irregular stones, sandy tan, seamless texture. BOTTOM RIGHT: calm deep teal pond water, short rhythmic pale ripples, subtle darker depths, seamless texture. All four tiles must be flat perfectly overhead material swatches with NO perspective and NO objects. Pixel-art aesthetic: each tile consists of exactly 32 by 32 large logical square pixels, enlarged crisply to 512px, restricted tasteful earthy palette, hand-crafted indie strategy game quality, readable shapes and varied material texture rather than solid fill. Consistent subdued daylight. Tile edges must continue naturally and seamlessly on repetition. No shading across entire tiles, no gradients, no anti-aliasing, no background outside these four fully opaque material tiles.
```

### Запрос для зданий и ресурсов

```text
Use case: stylized-concept. Asset type: transparent game sprite atlas. Create a square 2x2 sprite sheet for a top-down pixel-art ant colony strategy game, four equally sized cells with NO grid lines or captions. Each subject centered with generous transparent padding and no pixels crossing cell boundaries. TOP LEFT: rounded anthill nest of warm earthen soil with one dark tunnel opening, tiny grass tufts, pebble highlights and small root details; an actual ant nest, no human houses. TOP RIGHT: a low berry bush with dark sage and moss green leaves and a handful of warm red berries, readable overhead silhouette. BOTTOM LEFT: fallen short timber branch and small wood chips, rich honey and chestnut browns, readable overhead silhouette. BOTTOM RIGHT: cluster of pale blue-gray flint stones and small rock chips, readable overhead silhouette. All four objects drawn from perfectly overhead, charming crafted indie strategy-game sprites with crisp square pixel clusters, restricted cohesive earthy palette, warm upper-left light, subtle compact ground contact shadows. Treat each cell as a low-resolution 32x32 sprite enlarged with crisp nearest-neighbor pixels. No gradients, no anti-aliasing, no letters, no background material, no frames. Transparent background around each isolated object. Each object fills about 70 percent of its cell.
```

