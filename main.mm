name: Build iOS Dylib

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup iOS SDK
      run: |
        xcodebuild -version
        xcrun --sdk iphoneos --show-sdk-path
        
    - name: Build Dylib for iOS
      run: |
        # Компиляция для iOS arm64
        clang++ -std=c++11 -dynamiclib \
          -arch arm64 \
          -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
          -miphoneos-version-min=12.0 \
          -framework Foundation \
          -framework UIKit \
          -framework CoreGraphics \
          -o game_helper.dylib \
          main.mm \
          -Wall -O2 \
          -fobjc-arc \
          -current_version 1.0 \
          -compatibility_version 1.0
          
        # Проверка архитектуры
        lipo -info game_helper.dylib
        
    - name: Create Release Package
      run: |
        mkdir -p release
        cp game_helper.dylib release/
        
        # Создание README
        cat > release/README.md << 'EOF'
        # 🎮 Game Helper для iOS (Компактная версия)

        ## Компактное меню:
        - Маленькая кнопка 44x44
        - Узкое меню 200px
        - Не перекрывает игру
        - Можно перетаскивать

        ## Функции:
        - ✅ Автокликер
        - ✅ Разблокировка FPS
        - ✅ Потато графика
        - ✅ Счетчик FPS
        - ✅ Усиление яркости
        - ✅ Режим чтения
        - ✅ Ночной режим
        - ✅ Энергосбережение
        - ✅ Ускорение анимаций
        - ✅ Зум экрана
        - ✅ Широкий режим

        ## Установка:
        ```objc
        void *handle = dlopen("game_helper.dylib", RTLD_LAZY);
        ```

        ## Совместимость:
        - iOS 12.0+
        - arm64
        - ARC
        EOF
        
    - name: Upload Artifact
      uses: actions/upload-artifact@v4
      with:
        name: game-helper-ios
        path: release/
        retention-days: 90
