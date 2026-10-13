# Тестовая сборка simulation-05

Версия 0.2.6-test.5, Android versionCode 14. Ветка test/simulation-05.

Сокращён перебор морских маршрутов. Перед поиском проверяются экипаж и запасы; попытки распределены между циклами. Автосохранение читает холодные участки без вытеснения кеша и освобождает симуляцию после подготовки снимка.

[Все файлы](https://github.com/resassance/little-worlds/tree/test/simulation-05/test-builds).

- [Android Preview APK](https://github.com/resassance/little-worlds/raw/refs/heads/test/simulation-05/test-builds/little-worlds-android-preview.apk)
- [Windows](https://github.com/resassance/little-worlds/raw/refs/heads/test/simulation-05/test-builds/little-worlds-windows-test.zip)
- [Linux](https://github.com/resassance/little-worlds/raw/refs/heads/test/simulation-05/test-builds/little-worlds-linux-test.zip)
- [Web](https://github.com/resassance/little-worlds/raw/refs/heads/test/simulation-05/test-builds/little-worlds-web-test.zip)
- [Исходники](https://github.com/resassance/little-worlds/raw/refs/heads/test/simulation-05/test-builds/little-worlds-godot-test.zip)

APK обновляет предыдущую версию «Маленькие миры · тест» и сохраняет её миры. Основная игра установлена отдельно.

## Что проверить

1. Откройте мир, в котором останавливались жители. Оставьте ×1 или ×5 на несколько минут с включённым автосохранением. Наблюдайте за месяцами и людьми, включая время после сохранения.
2. Проверьте корабли, знакомство островов и новые экспедиции. Поиск берегов теперь идёт постепенно.
3. Нарисуйте сушу и воду возле поселения, затем отпустите кисть. Развитие должно продолжиться после применения правок.
4. Сохраните и загрузите мир, сверните приложение и вернитесь. Проверьте население, здания и путешественников.

Если загрузка по ссылке не начинается, откройте папку сборки, выберите файл и нажмите Download raw file. Для Web распакуйте весь архив и запустите start-windows.exe или start-linux.

[Разбор остановок](docs/SIMULATION_05.md) · [План жилья и городов](docs/SETTLEMENT_EVOLUTION.md).
