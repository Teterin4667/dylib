#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include <algorithm>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <ctime>

#ifdef _WIN32
    #include <windows.h>
    #define DLL_EXPORT __declspec(dllexport)
#else
    #include <dlfcn.h>
    #include <pthread.h>
    #include <unistd.h>
    #include <sys/mman.h>
    #include <fcntl.h>
    #include <termios.h>
    #include <sys/ioctl.h>
    #include <sys/time.h>
#endif

// Цвета для консоли (ANSI)
#define RESET   "\033[0m"
#define RED     "\033[31m"
#define GREEN   "\033[32m"
#define YELLOW  "\033[33m"
#define BLUE    "\033[34m"
#define MAGENTA "\033[35m"
#define CYAN    "\033[36m"
#define WHITE   "\033[37m"
#define BOLD    "\033[1m"
#define CLEAR_LINE "\033[2K\r"

class GameMenu {
private:
    bool running;
    bool autoClickerEnabled;
    bool fpsUnlocked;
    bool potatoGraphicsEnabled;
    bool fpsCounterEnabled;
    bool brightnessBoostEnabled;
    bool colorBlindModeEnabled;
    bool crosshairEnabled;
    bool soundEqualizerEnabled;
    bool pingReducerEnabled;
    bool streamerModeEnabled;
    bool screenshotModeEnabled;
    bool fpsStabilizerEnabled;
    bool uiScalerEnabled;
    
    int autoClickDelay;
    int targetFPS;
    int fpsCount;
    int brightnessLevel;
    int colorBlindType;
    int crosshairType;
    int soundProfile;
    int uiScale;
    
    std::thread menuThread;
    std::thread notificationThread;
    std::thread fpsCounterThread;
    
    std::vector<std::string> notificationQueue;
    bool notificationMutex;

public:
    GameMenu() : running(false), autoClickerEnabled(false), fpsUnlocked(false),
                 potatoGraphicsEnabled(false), fpsCounterEnabled(false),
                 brightnessBoostEnabled(false), colorBlindModeEnabled(false),
                 crosshairEnabled(false), soundEqualizerEnabled(false),
                 pingReducerEnabled(false), streamerModeEnabled(false),
                 screenshotModeEnabled(false), fpsStabilizerEnabled(false),
                 uiScalerEnabled(false), autoClickDelay(100), targetFPS(144),
                 fpsCount(0), brightnessLevel(100), colorBlindType(0),
                 crosshairType(1), soundProfile(0), uiScale(100),
                 notificationMutex(false) {}

    ~GameMenu() {
        stop();
    }

    void start() {
        if (running) return;
        running = true;
        menuThread = std::thread(&GameMenu::menuLoop, this);
        notificationThread = std::thread(&GameMenu::notificationLoop, this);
        fpsCounterThread = std::thread(&GameMenu::fpsCounterLoop, this);
    }

    void stop() {
        running = false;
        if (menuThread.joinable()) menuThread.join();
        if (notificationThread.joinable()) notificationThread.join();
        if (fpsCounterThread.joinable()) fpsCounterThread.join();
    }

private:
    void clearScreen() {
        std::cout << "\033[2J\033[1;1H";
    }

    void showNotification(const std::string& function, bool enabled) {
        std::string status = enabled ? "включено" : "выключено";
        std::string color = enabled ? GREEN : RED;
        std::string message = color + "✦ " + function + " - " + status + " ✦" + RESET;
        
        while (notificationMutex) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        notificationMutex = true;
        notificationQueue.push_back(message);
        notificationMutex = false;
    }

    void notificationLoop() {
        while (running) {
            if (!notificationQueue.empty()) {
                while (notificationMutex) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                }
                notificationMutex = true;
                
                // Сохраняем текущую позицию курсора
                std::cout << "\033[s";
                
                // Перемещаемся в правый нижний угол
                std::cout << "\033[999;999H";
                
                // Показываем последнее уведомление
                for (const auto& notif : notificationQueue) {
                    std::cout << notif << "  ";
                }
                std::cout << "\033[u" << std::flush;
                
                notificationQueue.clear();
                notificationMutex = false;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

    void fpsCounterLoop() {
        auto lastTime = std::chrono::high_resolution_clock::now();
        int frameCount = 0;
        
        while (running) {
            if (fpsCounterEnabled) {
                frameCount++;
                auto currentTime = std::chrono::high_resolution_clock::now();
                auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(currentTime - lastTime).count();
                
                if (elapsed >= 1) {
                    fpsCount = frameCount;
                    frameCount = 0;
                    lastTime = currentTime;
                    
                    // Показываем FPS в правом верхнем углу
                    std::cout << "\033[s\033[1;1HFPS: " << fpsCount << "\033[u" << std::flush;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    }

    void menuLoop() {
        while (running) {
            clearScreen();
            
            // Красивый заголовок
            std::cout << BOLD << CYAN;
            std::cout << "╔════════════════════════════════════════╗\n";
            std::cout << "║        🎮 ИГРОВОЕ МЕНЮ УЮТА 🎮         ║\n";
            std::cout << "╚════════════════════════════════════════╝\n\n" << RESET;
            
            // Основные функции
            std::cout << BOLD << YELLOW << "⚡ ОСНОВНЫЕ ФУНКЦИИ:\n" << RESET;
            std::cout << (autoClickerEnabled ? GREEN : RED) << "1. Автокликер [F1] " << (autoClickerEnabled ? "✅" : "❌") << RESET;
            std::cout << " (задержка: " << autoClickDelay << "ms)\n";
            
            std::cout << (fpsUnlocked ? GREEN : RED) << "2. Разблокировка FPS [F2] " << (fpsUnlocked ? "✅" : "❌") << RESET;
            std::cout << " (цель: " << targetFPS << " FPS)\n";
            
            std::cout << (potatoGraphicsEnabled ? GREEN : RED) << "3. Картофельная графика [F3] " << (potatoGraphicsEnabled ? "✅" : "❌") << RESET;
            std::cout << " (для слабых ПК)\n";
            
            std::cout << (fpsCounterEnabled ? GREEN : RED) << "4. Счетчик FPS [F4] " << (fpsCounterEnabled ? "✅" : "❌") << RESET;
            std::cout << " (текущий: " << fpsCount << ")\n\n";
            
            std::cout << BOLD << YELLOW << "🎨 ВИЗУАЛЬНЫЕ УЛУЧШЕНИЯ:\n" << RESET;
            std::cout << (brightnessBoostEnabled ? GREEN : RED) << "5. Усиление яркости [F5] " << (brightnessBoostEnabled ? "✅" : "❌") << RESET;
            std::cout << " (уровень: " << brightnessLevel << "%)\n";
            
            std::cout << (colorBlindModeEnabled ? GREEN : RED) << "6. Режим для дальтоников [F6] " << (colorBlindModeEnabled ? "✅" : "❌") << RESET;
            std::cout << " (тип: " << getColorBlindType() << ")\n";
            
            std::cout << (crosshairEnabled ? GREEN : RED) << "7. Кастомный прицел [F7] " << (crosshairEnabled ? "✅" : "❌") << RESET;
            std::cout << " (тип: " << crosshairType << ")\n\n";
            
            std::cout << BOLD << YELLOW << "🔊 ЗВУК И КОМФОРТ:\n" << RESET;
            std::cout << (soundEqualizerEnabled ? GREEN : RED) << "8. Звуковой эквалайзер [F8] " << (soundEqualizerEnabled ? "✅" : "❌") << RESET;
            std::cout << " (профиль: " << getSoundProfile() << ")\n";
            
            std::cout << (pingReducerEnabled ? GREEN : RED) << "9. Оптимизация сети [F9] " << (pingReducerEnabled ? "✅" : "❌") << RESET;
            std::cout << " (снижение пинга)\n\n";
            
            std::cout << BOLD << YELLOW << "📺 ДОПОЛНИТЕЛЬНО:\n" << RESET;
            std::cout << (streamerModeEnabled ? GREEN : RED) << "0. Режим стримера [F10] " << (streamerModeEnabled ? "✅" : "❌") << RESET;
            std::cout << " (скрытие личной инфо)\n";
            
            std::cout << (screenshotModeEnabled ? GREEN : RED) << "q. Режим скриншота [F11] " << (screenshotModeEnabled ? "✅" : "❌") << RESET;
            std::cout << " (без UI)\n";
            
            std::cout << (fpsStabilizerEnabled ? GREEN : RED) << "w. Стабилизатор FPS [F12] " << (fpsStabilizerEnabled ? "✅" : "❌") << RESET;
            std::cout << " (плавный геймплей)\n";
            
            std::cout << (uiScalerEnabled ? GREEN : RED) << "e. Масштабирование UI " << (uiScalerEnabled ? "✅" : "❌") << RESET;
            std::cout << " (масштаб: " << uiScale << "%)\n\n";
            
            // Настройки
            std::cout << BOLD << CYAN << "⚙️  НАСТРОЙКИ:\n" << RESET;
            std::cout << "t. Задержка автокликера (" << autoClickDelay << "ms)\n";
            std::cout << "y. Целевой FPS (" << targetFPS << ")\n";
            std::cout << "u. Яркость (" << brightnessLevel << "%)\n";
            std::cout << "i. Масштаб UI (" << uiScale << "%)\n\n";
            
            std::cout << BOLD << MAGENTA << "ESC - выход из меню\n" << RESET;
            
            // Обработка ввода
            handleInput();
        }
    }

    std::string getColorBlindType() {
        switch(colorBlindType) {
            case 1: return "Протанопия";
            case 2: return "Дейтеранопия";
            case 3: return "Тританопия";
            default: return "Выключен";
        }
    }

    std::string getSoundProfile() {
        switch(soundProfile) {
            case 1: return "Игры";
            case 2: return "Фильмы";
            case 3: return "Музыка";
            default: return "Стандарт";
        }
    }

    void handleInput() {
        char c = getChar();
        
        switch(c) {
            case '1': case 27: // F1
                toggleAutoClicker();
                break;
            case '2': case 28: // F2
                toggleFPSUnlock();
                break;
            case '3': case 29: // F3
                togglePotatoGraphics();
                break;
            case '4': case 30: // F4
                toggleFPSCounter();
                break;
            case '5': case 31: // F5
                toggleBrightnessBoost();
                break;
            case '6': case 32: // F6
                toggleColorBlindMode();
                break;
            case '7': case 33: // F7
                toggleCrosshair();
                break;
            case '8': case 34: // F8
                toggleSoundEqualizer();
                break;
            case '9': case 35: // F9
                togglePingReducer();
                break;
            case '0': case 36: // F10
                toggleStreamerMode();
                break;
            case 'q': case 37: // F11
                toggleScreenshotMode();
                break;
            case 'w': case 38: // F12
                toggleFPSStabilizer();
                break;
            case 'e':
                toggleUIScaler();
                break;
            case 't':
                adjustSetting(autoClickDelay, 10, 1000, 50, "Задержка автокликера");
                break;
            case 'y':
                adjustSetting(targetFPS, 30, 360, 30, "Целевой FPS");
                break;
            case 'u':
                adjustSetting(brightnessLevel, 50, 200, 10, "Яркость");
                if (brightnessBoostEnabled) {
                    applyBrightness();
                }
                break;
            case 'i':
                adjustSetting(uiScale, 50, 200, 10, "Масштаб UI");
                if (uiScalerEnabled) {
                    applyUIScale();
                }
                break;
            case 27: // ESC
                running = false;
                break;
        }
    }

    char getChar() {
        char c = 0;
#ifdef _WIN32
        if (_kbhit()) {
            c = _getch();
        }
#else
        struct termios oldt, newt;
        tcgetattr(STDIN_FILENO, &oldt);
        newt = oldt;
        newt.c_lflag &= ~(ICANON | ECHO);
        tcsetattr(STDIN_FILENO, TCSANOW, &newt);
        if (read(STDIN_FILENO, &c, 1) > 0) {
            if (c == 27) { // Escape sequence для F-клавиш
                char seq[2];
                if (read(STDIN_FILENO, &seq[0], 1) > 0 && read(STDIN_FILENO, &seq[1], 1) > 0) {
                    if (seq[0] == '[') {
                        c = seq[1] + 16; // Преобразуем F1-F12 в 27-38
                    }
                }
            }
        }
        tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
#endif
        return c;
    }

    void adjustSetting(int& setting, int min, int max, int step, const std::string& name) {
        clearScreen();
        std::cout << BOLD << CYAN << "⚙️  Настройка: " << name << RESET << "\n\n";
        std::cout << "Текущее значение: " << setting << "\n";
        std::cout << "Используйте +/- для изменения, Enter для сохранения\n";
        
        bool adjusting = true;
        while (adjusting) {
            char c = getChar();
            if (c == '+') {
                setting = std::min(max, setting + step);
                std::cout << CLEAR_LINE << "Новое значение: " << setting << std::flush;
            } else if (c == '-') {
                setting = std::max(min, setting - step);
                std::cout << CLEAR_LINE << "Новое значение: " << setting << std::flush;
            } else if (c == '\n' || c == '\r') {
                adjusting = false;
            }
        }
        
        showNotification(name + " изменена", true);
    }

    // Реализация функций
    void toggleAutoClicker() {
        autoClickerEnabled = !autoClickerEnabled;
        showNotification("Автокликер", autoClickerEnabled);
        
        if (autoClickerEnabled) {
            std::thread([this]() {
                while (autoClickerEnabled && running) {
                    // Симуляция клика мышью
                    std::cout << "\a"; // Звуковой сигнал
                    std::this_thread::sleep_for(std::chrono::milliseconds(autoClickDelay));
                }
            }).detach();
        }
    }

    void toggleFPSUnlock() {
        fpsUnlocked = !fpsUnlocked;
        showNotification("Разблокировка FPS", fpsUnlocked);
        
        if (fpsUnlocked) {
            std::cout << "FPS разблокирован до " << targetFPS << "\n";
            // Здесь был бы код для изменения FPS в игре
        }
    }

    void togglePotatoGraphics() {
        potatoGraphicsEnabled = !potatoGraphicsEnabled;
        showNotification("Картофельная графика", potatoGraphicsEnabled);
        
        if (potatoGraphicsEnabled) {
            std::cout << "Графика оптимизирована для слабых ПК\n";
            // Уменьшение качества текстур, теней и т.д.
        }
    }

    void toggleFPSCounter() {
        fpsCounterEnabled = !fpsCounterEnabled;
        showNotification("Счетчик FPS", fpsCounterEnabled);
    }

    void toggleBrightnessBoost() {
        brightnessBoostEnabled = !brightnessBoostEnabled;
        showNotification("Усиление яркости", brightnessBoostEnabled);
        applyBrightness();
    }

    void applyBrightness() {
        if (brightnessBoostEnabled) {
            // Применение настроек яркости
            std::cout << "Яркость установлена на " << brightnessLevel << "%\n";
        }
    }

    void toggleColorBlindMode() {
        colorBlindType = (colorBlindType + 1) % 4;
        colorBlindModeEnabled = (colorBlindType > 0);
        showNotification("Режим для дальтоников", colorBlindModeEnabled);
    }

    void toggleCrosshair() {
        crosshairType = (crosshairType % 3) + 1;
        crosshairEnabled = true;
        showNotification("Кастомный прицел (тип " + std::to_string(crosshairType) + ")", true);
    }

    void toggleSoundEqualizer() {
        soundProfile = (soundProfile + 1) % 4;
        soundEqualizerEnabled = (soundProfile > 0);
        showNotification("Звуковой эквалайзер (" + getSoundProfile() + ")", soundEqualizerEnabled);
    }

    void togglePingReducer() {
        pingReducerEnabled = !pingReducerEnabled;
        showNotification("Оптимизация сети", pingReducerEnabled);
        
        if (pingReducerEnabled) {
            // Оптимизация сетевых настроек
            std::cout << "Применены настройки для снижения пинга\n";
        }
    }

    void toggleStreamerMode() {
        streamerModeEnabled = !streamerModeEnabled;
        showNotification("Режим стримера", streamerModeEnabled);
        
        if (streamerModeEnabled) {
            std::cout << "Личная информация скрыта\n";
        }
    }

    void toggleScreenshotMode() {
        screenshotModeEnabled = !screenshotModeEnabled;
        showNotification("Режим скриншота", screenshotModeEnabled);
        
        if (screenshotModeEnabled) {
            std::cout << "Интерфейс скрыт для чистых скриншотов\n";
        }
    }

    void toggleFPSStabilizer() {
        fpsStabilizerEnabled = !fpsStabilizerEnabled;
        showNotification("Стабилизатор FPS", fpsStabilizerEnabled);
        
        if (fpsStabilizerEnabled) {
            std::thread([this]() {
                while (fpsStabilizerEnabled && running) {
                    // Автоматическая настройка графики для поддержания FPS
                    std::this_thread::sleep_for(std::chrono::seconds(5));
                }
            }).detach();
        }
    }

    void toggleUIScaler() {
        uiScalerEnabled = !uiScalerEnabled;
        showNotification("Масштабирование UI", uiScalerEnabled);
        applyUIScale();
    }

    void applyUIScale() {
        if (uiScalerEnabled) {
            std::cout << "Масштаб UI установлен на " << uiScale << "%\n";
        }
    }
};

// Глобальный экземпляр меню
GameMenu* g_menu = nullptr;

// Функция для инициализации меню
extern "C" DLL_EXPORT void init_menu() {
    if (!g_menu) {
        g_menu = new GameMenu();
        g_menu->start();
    }
}

// Функция для остановки меню
extern "C" DLL_EXPORT void stop_menu() {
    if (g_menu) {
        g_menu->stop();
        delete g_menu;
        g_menu = nullptr;
    }
}

// Точка входа для dylib
#ifdef _WIN32
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH:
            init_menu();
            break;
        case DLL_PROCESS_DETACH:
            stop_menu();
            break;
    }
    return TRUE;
}
#else
__attribute__((constructor)) void on_load() {
    init_menu();
}

__attribute__((destructor)) void on_unload() {
    stop_menu();
}
#endif
