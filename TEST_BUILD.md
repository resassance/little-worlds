# Тестовая сборка economy-save-08

Версия 0.2.6-test.8, Android versionCode 17.

Сохранение освобождает симуляцию до чтения холодных участков и сериализации сведений о мире. Версии файлов снимка сохраняются при последующем рисовании и смене мира. Строительные грузы учитываются общим индексом поселения, поиск партнёров заранее исключает неподходящих кандидатов. Размер карты и правила развития сохранены.

[Все файлы](https://github.com/resassance/little-worlds/tree/test/economy-save-08/test-builds).

- [Android Preview APK](https://github.com/resassance/little-worlds/raw/refs/heads/test/economy-save-08/test-builds/little-worlds-android-preview.apk)
- [Windows](https://github.com/resassance/little-worlds/raw/refs/heads/test/economy-save-08/test-builds/little-worlds-windows-test.zip)
- [Linux](https://github.com/resassance/little-worlds/raw/refs/heads/test/economy-save-08/test-builds/little-worlds-linux-test.zip)
- [Web](https://github.com/resassance/little-worlds/raw/refs/heads/test/economy-save-08/test-builds/little-worlds-web-test.zip)
- [Исходники](https://github.com/resassance/little-worlds/raw/refs/heads/test/economy-save-08/test-builds/little-worlds-godot-test.zip)

APK обновляет прежнюю «Маленькие миры · тест» с сохранением её миров.

## Что посмотреть

1. Загрузите прежний мир и наблюдайте за развитием на ×1 и ×5. Поселения продолжают строиться, семьи — образовываться.
2. Создайте несколько далёких островов, вернитесь к поселению и запустите сохранение. После получения снимка мир продолжает жить, пока идёт запись.
3. Нарисуйте землю или лес после начала сохранения. Последующая загрузка возвращает мир на момент снимка; более поздние действия входят в следующее сохранение.
4. Повторите непрерывную кисть возле домов и вдалеке, сохраните ещё раз и загрузите мир.

[Изменения оптимизации](docs/ECONOMY_SAVE_08.md) · [Следующий контент: руины и история мира](docs/CONTENT_NEXT.md).

Если скачивание не начинается, откройте папку сборки, выберите файл и нажмите Download raw file. Для Web распакуйте весь архив и запустите start-windows.exe или start-linux.
