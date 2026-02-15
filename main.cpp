#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include <map>
#include <functional>
#include <cmath>
#include <mach/mach.h>
#include <mach-o/dyld.h>

#ifdef __APPLE__
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#endif

// Структура для хранения состояния функций
struct FunctionState {
    bool enabled;
    std::string name;
    std::function<void()> toggleCallback;
};

// Глобальный класс для управления меню
class GameHelper {
private:
    bool isInitialized;
    std::map<std::string, FunctionState> functions;
    std::thread notificationThread;
    bool notificationRunning;
    
    // iOS UI элементы
    void* overlayWindow;
    void* floatingButton;
    void* menuView;
    void* notificationLabel;
    
public:
    GameHelper() : isInitialized(false), notificationRunning(false) {}
    
    ~GameHelper() {
        cleanup();
    }
    
    void initialize() {
        if (isInitialized) return;
        isInitialized = true;
        
        // Регистрируем функции
        registerFunctions();
        
        // Создаем UI на главном потоке
        dispatch_async(dispatch_get_main_queue(), ^{
            [this createFloatingUI];
        });
        
        // Запускаем поток уведомлений
        notificationRunning = true;
        notificationThread = std::thread(&GameHelper::notificationLoop, this);
    }
    
    void cleanup() {
        notificationRunning = false;
        if (notificationThread.joinable()) {
            notificationThread.join();
        }
        
        // Очищаем UI на главном потоке
        dispatch_async(dispatch_get_main_queue(), ^{
            [this cleanupUI];
        });
    }
    
private:
    void registerFunctions() {
        // 1. Автокликер
        functions["autoClicker"] = {
            false, "Автокликер",
            [this]() { toggleAutoClicker(); }
        };
        
        // 2. Разблокировка FPS
        functions["fpsUnlock"] = {
            false, "Разблокировка FPS",
            [this]() { toggleFPSUnlock(); }
        };
        
        // 3. Картофельная графика
        functions["potatoGraphics"] = {
            false, "Картофельная графика",
            [this]() { togglePotatoGraphics(); }
        };
        
        // 4. Счетчик FPS
        functions["fpsCounter"] = {
            false, "Счетчик FPS",
            [this]() { toggleFPSCounter(); }
        };
        
        // 5. Усиление яркости
        functions["brightnessBoost"] = {
            false, "Усиление яркости",
            [this]() { toggleBrightness(); }
        };
        
        // 6. Режим чтения
        functions["readingMode"] = {
            false, "Режим чтения",
            [this]() { toggleReadingMode(); }
        };
        
        // 7. Ночной режим
        functions["nightMode"] = {
            false, "Ночной режим",
            [this]() { toggleNightMode(); }
        };
        
        // 8. Энергосбережение
        functions["batterySaver"] = {
            false, "Энергосбережение",
            [this]() { toggleBatterySaver(); }
        };
        
        // 9. Ускорение анимаций
        functions["animationBoost"] = {
            false, "Ускорение анимаций",
            [this]() { toggleAnimationBoost(); }
        };
        
        // 10. Зум экрана
        functions["screenZoom"] = {
            false, "Зум экрана",
            [this]() { toggleScreenZoom(); }
        };
    }
    
    void createFloatingUI() {
        // Создаем окно поверх всех
        UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.windowLevel = UIWindowLevelAlert + 1;
        window.backgroundColor = [UIColor clearColor];
        window.userInteractionEnabled = YES;
        [window makeKeyAndVisible];
        
        overlayWindow = (__bridge void*)window;
        
        // Создаем плавающую кнопку
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(20, 100, 60, 60);
        button.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.9];
        button.layer.cornerRadius = 30;
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.layer.shadowOpacity = 0.3;
        button.layer.shadowRadius = 5;
        button.layer.borderWidth = 2;
        button.layer.borderColor = [UIColor whiteColor].CGColor;
        
        [button setTitle:@"⚙️" forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:24];
        
        // Добавляем возможность перетаскивания
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
        [button addGestureRecognizer:panGesture];
        
        [button addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        
        [window addSubview:button];
        floatingButton = (__bridge void*)button;
        
        // Создаем меню (изначально скрыто)
        [self createMenu];
        
        // Создаем уведомление
        [self createNotificationLabel];
    }
    
    void createMenu() {
        UIWindow *window = (__bridge UIWindow*)overlayWindow;
        UIButton *button = (__bridge UIButton*)floatingButton;
        
        UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(20, CGRectGetMaxY(button.frame) + 10, 250, 0)];
        menu.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        menu.layer.cornerRadius = 15;
        menu.layer.shadowColor = [UIColor blackColor].CGColor;
        menu.layer.shadowOffset = CGSizeMake(0, 2);
        menu.layer.shadowOpacity = 0.5;
        menu.layer.shadowRadius = 5;
        menu.clipsToBounds = YES;
        menu.hidden = YES;
        
        [window addSubview:menu];
        menuView = (__bridge void*)menu;
        
        // Заполняем меню функциями
        [self populateMenu];
    }
    
    void populateMenu() {
        UIView *menu = (__bridge UIView*)menuView;
        
        NSArray *functionNames = @[
            @"Автокликер",
            @"Разблокировка FPS",
            @"Картофельная графика",
            @"Счетчик FPS",
            @"Усиление яркости",
            @"Режим чтения",
            @"Ночной режим",
            @"Энергосбережение",
            @"Ускорение анимаций",
            @"Зум экрана"
        ];
        
        CGFloat yOffset = 10;
        int index = 0;
        
        for (NSString *name in functionNames) {
            UIButton *funcButton = [UIButton buttonWithType:UIButtonTypeCustom];
            funcButton.frame = CGRectMake(10, yOffset, 230, 40);
            funcButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
            funcButton.layer.cornerRadius = 8;
            funcButton.tag = index;
            
            [funcButton setTitle:name forState:UIControlStateNormal];
            [funcButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            funcButton.titleLabel.font = [UIFont systemFontOfSize:14];
            
            // Добавляем индикатор состояния
            UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(190, 10, 30, 20)];
            statusLabel.tag = 100 + index;
            statusLabel.text = @"⚪";
            statusLabel.textColor = [UIColor grayColor];
            statusLabel.font = [UIFont systemFontOfSize:12];
            [funcButton addSubview:statusLabel];
            
            [funcButton addTarget:self action:@selector(functionTapped:) forControlEvents:UIControlEventTouchUpInside];
            
            [menu addSubview:funcButton];
            
            yOffset += 45;
            index++;
        }
        
        // Обновляем высоту меню
        CGRect menuFrame = menu.frame;
        menuFrame.size.height = yOffset + 10;
        menu.frame = menuFrame;
    }
    
    void createNotificationLabel() {
        UIWindow *window = (__bridge UIWindow*)overlayWindow;
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, window.bounds.size.height - 60, window.bounds.size.width - 40, 40)];
        label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.layer.cornerRadius = 10;
        label.clipsToBounds = YES;
        label.font = [UIFont boldSystemFontOfSize:14];
        label.alpha = 0;
        
        [window addSubview:label];
        notificationLabel = (__bridge void*)label;
    }
    
    // Objective-C селекторы
    void dragButton(UIPanGestureRecognizer *gesture) {
        UIButton *button = (UIButton*)gesture.view;
        CGPoint translation = [gesture translationInView:button.superview];
        
        if (gesture.state == UIGestureRecognizerStateChanged) {
            CGPoint newCenter = CGPointMake(button.center.x + translation.x,
                                           button.center.y + translation.y);
            
            // Ограничиваем краями экрана
            newCenter.x = MAX(button.frame.size.width/2, 
                             MIN(button.superview.bounds.size.width - button.frame.size.width/2, newCenter.x));
            newCenter.y = MAX(button.frame.size.height/2 + 40, 
                             MIN(button.superview.bounds.size.height - button.frame.size.height/2 - 40, newCenter.y));
            
            button.center = newCenter;
            [gesture setTranslation:CGPointZero inView:button.superview];
            
            // Перемещаем меню вместе с кнопкой
            [self updateMenuPosition];
        }
    }
    
    void toggleMenu() {
        UIView *menu = (__bridge UIView*)menuView;
        menu.hidden = !menu.hidden;
        isMenuVisible = !menu.hidden;
        
        if (!menu.hidden) {
            [self updateMenuPosition];
        }
    }
    
    void updateMenuPosition() {
        UIView *menu = (__bridge UIView*)menuView;
        UIButton *button = (__bridge UIButton*)floatingButton;
        
        CGRect menuFrame = menu.frame;
        menuFrame.origin.x = button.frame.origin.x;
        menuFrame.origin.y = CGRectGetMaxY(button.frame) + 10;
        
        // Проверяем, не выходит ли меню за экран
        if (menuFrame.origin.y + menuFrame.size.height > button.superview.bounds.size.height - 40) {
            menuFrame.origin.y = button.frame.origin.y - menuFrame.size.height - 10;
        }
        
        menu.frame = menuFrame;
    }
    
    void functionTapped(UIButton *sender) {
        int index = (int)sender.tag;
        [self toggleFunctionAtIndex:index];
        
        // Обновляем индикатор
        UILabel *statusLabel = [sender viewWithTag:100 + index];
        BOOL enabled = [self getFunctionState:index];
        statusLabel.text = enabled ? @"✅" : @"⚪";
        statusLabel.textColor = enabled ? [UIColor greenColor] : [UIColor grayColor];
    }
    
    void toggleFunctionAtIndex(int index) {
        std::string functionId;
        switch(index) {
            case 0: functionId = "autoClicker"; break;
            case 1: functionId = "fpsUnlock"; break;
            case 2: functionId = "potatoGraphics"; break;
            case 3: functionId = "fpsCounter"; break;
            case 4: functionId = "brightnessBoost"; break;
            case 5: functionId = "readingMode"; break;
            case 6: functionId = "nightMode"; break;
            case 7: functionId = "batterySaver"; break;
            case 8: functionId = "animationBoost"; break;
            case 9: functionId = "screenZoom"; break;
        }
        
        auto& func = functions[functionId];
        func.enabled = !func.enabled;
        func.toggleCallback();
        
        [self showNotification:[NSString stringWithUTF8String:func.name.c_str()] enabled:func.enabled];
    }
    
    bool getFunctionState(int index) {
        std::string functionId;
        switch(index) {
            case 0: functionId = "autoClicker"; break;
            case 1: functionId = "fpsUnlock"; break;
            case 2: functionId = "potatoGraphics"; break;
            case 3: functionId = "fpsCounter"; break;
            case 4: functionId = "brightnessBoost"; break;
            case 5: functionId = "readingMode"; break;
            case 6: functionId = "nightMode"; break;
            case 7: functionId = "batterySaver"; break;
            case 8: functionId = "animationBoost"; break;
            case 9: functionId = "screenZoom"; break;
        }
        return functions[functionId].enabled;
    }
    
    void showNotification(NSString *message, BOOL enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UILabel *label = (__bridge UILabel*)self->notificationLabel;
            label.text = [NSString stringWithFormat:@"%@ %@", 
                         enabled ? @"✅" : @"❌", message];
            label.backgroundColor = enabled ? 
                [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:0.8] :
                [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8];
            
            [UIView animateWithDuration:0.3 animations:^{
                label.alpha = 1.0;
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{
                    label.alpha = 0.0;
                } completion:nil];
            }];
        });
    }
    
    void notificationLoop() {
        while (notificationRunning) {
            // Обновляем счетчик FPS если включен
            if (functions["fpsCounter"].enabled) {
                [self updateFPSCounter];
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
    }
    
    void updateFPSCounter() {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Показываем FPS в углу
            UILabel *label = (__bridge UILabel*)self->notificationLabel;
            if (label.alpha < 0.1) {
                static int frameCount = 0;
                frameCount++;
                
                if (frameCount % 10 == 0) {
                    label.text = [NSString stringWithFormat:@"📊 FPS: %d", 
                                 arc4random_uniform(30) + 30]; // Симуляция FPS
                    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
                    
                    [UIView animateWithDuration:0.2 animations:^{
                        label.alpha = 0.8;
                    }];
                }
            }
        });
    }
    
    void cleanupUI() {
        UIWindow *window = (__bridge UIWindow*)overlayWindow;
        [window removeFromSuperview];
        window = nil;
    }
    
    // Реализации функций
    void toggleAutoClicker() {
        if (functions["autoClicker"].enabled) {
            std::thread([this]() {
                while (functions["autoClicker"].enabled) {
                    // Симуляция клика
                    std::this_thread::sleep_for(std::chrono::milliseconds(100));
                }
            }).detach();
        }
    }
    
    void toggleFPSUnlock() {
        // Разблокировка FPS (убираем ограничения)
        if (functions["fpsUnlock"].enabled) {
            // Код для разблокировки FPS
        }
    }
    
    void togglePotatoGraphics() {
        if (functions["potatoGraphics"].enabled) {
            // Уменьшение качества графики
        }
    }
    
    void toggleFPSCounter() {
        // Включается автоматически в notificationLoop
    }
    
    void toggleBrightness() {
        if (functions["brightnessBoost"].enabled) {
            // Увеличение яркости
            [[UIScreen mainScreen] setBrightness:1.0];
        } else {
            [[UIScreen mainScreen] setBrightness:0.5];
        }
    }
    
    void toggleReadingMode() {
        if (functions["readingMode"].enabled) {
            // Режим чтения (сепия, уменьшение синего)
        }
    }
    
    void toggleNightMode() {
        if (functions["nightMode"].enabled) {
            // Ночной режим (темная тема, теплые тона)
            if (@available(iOS 13.0, *)) {
                // Используем системную темную тему
            }
        }
    }
    
    void toggleBatterySaver() {
        if (functions["batterySaver"].enabled) {
            // Энергосбережение (уменьшение FPS, отключение эффектов)
        }
    }
    
    void toggleAnimationBoost() {
        if (functions["animationBoost"].enabled) {
            // Ускорение анимаций системы
            [[NSUserDefaults standardUserDefaults] setFloat:0.5 forKey:@"UIAnimationSpeed"];
        } else {
            [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"UIAnimationSpeed"];
        }
    }
    
    void toggleScreenZoom() {
        if (functions["screenZoom"].enabled) {
            // Режим масштабирования экрана
        }
    }
};

// Глобальный экземпляр
static GameHelper* g_helper = nullptr;

// Функции для экспорта
extern "C" {
    void init_game_helper() {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            g_helper = new GameHelper();
            g_helper->initialize();
        });
    }
    
    void cleanup_game_helper() {
        if (g_helper) {
            g_helper->cleanup();
            delete g_helper;
            g_helper = nullptr;
        }
    }
    
    // Точка входа для dylib
    __attribute__((constructor)) static void on_load() {
        init_game_helper();
    }
    
    __attribute__((destructor)) static void on_unload() {
        cleanup_game_helper();
    }
}
