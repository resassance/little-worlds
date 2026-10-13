# Тестовая сборка performance-04

Версия 0.2.6-test.4, Android versionCode 13. Ветка test/performance-04; релиз не опубликован.

[Все файлы](https://github.com/resassance/little-worlds/tree/test/performance-04/test-builds).

- [Android Preview APK](https://github.com/resassance/little-worlds/raw/refs/heads/test/performance-04/test-builds/little-worlds-android-preview.apk)
- [Windows](https://github.com/resassance/little-worlds/raw/refs/heads/test/performance-04/test-builds/little-worlds-windows-test.zip)
- [Linux](https://github.com/resassance/little-worlds/raw/refs/heads/test/performance-04/test-builds/little-worlds-linux-test.zip)
- [Web](https://github.com/resassance/little-worlds/raw/refs/heads/test/performance-04/test-builds/little-worlds-web-test.zip)
- [Исходники](https://github.com/resassance/little-worlds/raw/refs/heads/test/performance-04/test-builds/little-worlds-godot-test.zip)

Если ссылка не скачивается, откройте папку сборки, выберите файл и нажмите Download raw file.

APK обновляет приложение «Маленькие миры · тест» из weather-02 и atlas-03, сохраняя его миры. Пакет org.littleworlds.sandbox.preview. Основная игра использует отдельный пакет и свои сохранения; прежний ключ её подписи недоступен в восстановленном окружении.

## Что проверить

1. На ×1 и ×5 ведите кистью 15–30 секунд: прямая, круги, зигзаги, возврат по земле. Сравните радиусы 2, 8, 16 и 64. Земля должна появляться во время движения, подробности — достраиваться.
2. Несколько раз нарисуйте землю, лес, горы, затем воду по тому же месту. Убедитесь, что форма и порядок сохраняются, после отпускания не остаётся длинного догоняния.
3. Повторите огонь, дождь и биомы. Проверьте камеру, паузу, скорость и меню во время незавершённых правок.
4. Проверьте обычное наблюдение, плотное поселение, жителей вдалеке, корабли, природные события и карточки людей. В больших мирах сравните реальное течение месяцев на ×1 и ×5.
5. Удалите землю возле построек и жителей. Они должны правильно реагировать на потерю суши. Нарисуйте отдельный остров вдали от них: соседние задачи сохраняются.
6. Несколько раз сохраните, загрузите и смените мир; сверните и верните приложение. Проведите длительную сессию на телефоне и сравните начало с состоянием после нагрева.

При непрерывном рисовании новый шаг развития временно ждёт редактирование. После отпускания или остановки движения мир продолжает работу; меню и камера остаются доступны. Это поведение защищает согласованность данных мира.

Для Web распакуйте архив целиком и запустите start-windows.exe или start-linux.

[Замеры и ограничения](docs/PERFORMANCE_04.md) · [Общий план оптимизации](docs/OPTIMIZATION_PLAN.md).
