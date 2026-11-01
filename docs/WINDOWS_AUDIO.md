# Диагностика Windows WASAPI

Ошибка `WASAPI: Initialize failed with error 0xffffffff88890008` соответствует неподдерживаемому формату аудиопотока (`AUDCLNT_E_UNSUPPORTED_FORMAT`). [Контракт Microsoft IAudioClient::Initialize](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-initialize).

Это отказ звукового устройства/аудиодрайвера при инициализации Godot. Лог не сообщает выбранное устройство, его формат и версию движка. Проверка на Linux с Dummy-драйвером не подтверждает исправление Windows WASAPI. Проект не переключается на Dummy принудительно: это скрыло бы проблему ценой отключения звука.

На компьютере с ошибкой:

1. Выберите в настройках Windows доступное рабочее устройство вывода. Проверьте воспроизведение звука вне Godot.
2. Проверьте доступные форматы устройства. Для диагностики попробуйте обычный стерео PCM-формат без пространственного звука и дополнительных эффектов.
3. Сравните частоту устройства с Godot `Audio > Driver > Mix Rate`. Если формат меняется, полностью перезапустите редактор и игру. Не меняйте частоту WAV-клика: это отдельное свойство аудиофайла.
4. Если отказ остаётся, сохраните запуск с `--verbose`, точную версию Godot, имя устройства и его формат. Эти данные нужны для проверки конкретного Windows-драйвера.

[Настройка mix_rate в Godot](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-audio-driver-mix-rate), [реализация WASAPI](https://github.com/godotengine/godot/blob/master/drivers/wasapi/audio_driver_wasapi.cpp).

Предупреждения GDScript из присланного снимка исправлены отдельно: локальные `top` и `fill` переименованы, намеренно неиспользуемый параметр темы обозначен `_border`. Они не являются причиной отказа WASAPI.

## GetBufferSize во время игры

Сообщение `thread_func: WASAPI: GetBufferSize error` спустя несколько минут относится к работающему аудиопотоку. Это другая точка отказа, чем прежний Initialize с HRESULT 0xffffffff88890008. Переносить диагноз неподдерживаемого формата на новый лог нельзя.

[Microsoft GetBufferSize](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-getbuffersize) допускает несколько причин отказа: неинициализированный поток, недоступное устройство, потерянные ресурсы или остановленную аудиослужбу. Конкретный HRESULT в присланной строке отсутствует. [Драйвер Godot](https://github.com/godotengine/godot/blob/master/drivers/wasapi/audio_driver_wasapi.cpp) пишет эту строку внутри аудиопотока; навигация и число островов не вызывают этот API из GDScript.

Для воспроизведения на Windows нужны полный verbose-лог, версия движка и сведения об устройстве. Отметьте, совпал ли сбой с отключением USB/Bluetooth, сменой устройства или выходом из сна. Эти события — проверяемые гипотезы, не установленная причина. Исправление Windows-драйвера на Linux не подтверждено; звук не отключается скрытым переключением на Dummy.
