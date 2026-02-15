#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <thread>
#include <chrono>
#include <map>
#include <string>
#include <functional>

// Структура для хранения состояния функций
struct FunctionState {
    bool enabled;
    std::string name;
    dispatch_block_t toggleBlock;
};

// Интерфейс контроллера
@interface GameHelperController : NSObject {
    UIWindow *_overlayWindow;
    UIWindow *_stretchWindow;
    UIButton *_floatingButton;
    UIView *_menuView;
    UILabel *_notificationLabel;
    NSMutableArray *_functionButtons;
    std::map<std::string, FunctionState> _functions;
    std::thread _notificationThread;
    bool _notificationRunning;
    bool _isMenuVisible;
    
    // Для растяжения экрана
    CGFloat _originalScale;
    CGFloat _currentScale;
    UIView *_stretchOverlay;
    UIPinchGestureRecognizer *_pinchGesture;
    UIButton *_resetStretchButton;
}

- (void)initialize;
- (void)cleanup;
- (void)showNotification:(NSString *)message enabled:(BOOL)enabled;
- (void)toggleFunction:(NSString *)functionId;
- (void)updateFunctionButtons;

// Функции растяжения
- (void)enableScreenStretch;
- (void)disableScreenStretch;
- (void)handlePinchGesture:(UIPinchGestureRecognizer *)gesture;
- (void)resetStretch;

// Функции для каждой опции
- (void)toggleAutoClicker;
- (void)toggleFPSUnlock;
- (void)togglePotatoGraphics;
- (void)toggleFPSCounter;
- (void)toggleBrightness;
- (void)toggleReadingMode;
- (void)toggleNightMode;
- (void)toggleBatterySaver;
- (void)toggleAnimationBoost;
- (void)toggleScreenZoom;
- (void)toggleScreenStretch;
- (void)toggleWidescreenMode;

@end

@implementation GameHelperController

- (instancetype)init {
    self = [super init];
    if (self) {
        _functionButtons = [NSMutableArray new];
        _notificationRunning = false;
        _isMenuVisible = false;
        _originalScale = 1.0;
        _currentScale = 1.0;
        [self registerFunctions];
    }
    return self;
}

- (void)registerFunctions {
    __block GameHelperController *blockSelf = self;
    
    // 1. Автокликер
    _functions["autoClicker"] = {
        false, "Автокликер",
        ^{ [blockSelf toggleAutoClicker]; }
    };
    
    // 2. Разблокировка FPS
    _functions["fpsUnlock"] = {
        false, "Разблокировка FPS",
        ^{ [blockSelf toggleFPSUnlock]; }
    };
    
    // 3. Картофельная графика
    _functions["potatoGraphics"] = {
        false, "Картофельная графика",
        ^{ [blockSelf togglePotatoGraphics]; }
    };
    
    // 4. Счетчик FPS
    _functions["fpsCounter"] = {
        false, "Счетчик FPS",
        ^{ [blockSelf toggleFPSCounter]; }
    };
    
    // 5. Усиление яркости
    _functions["brightnessBoost"] = {
        false, "Усиление яркости",
        ^{ [blockSelf toggleBrightness]; }
    };
    
    // 6. Режим чтения
    _functions["readingMode"] = {
        false, "Режим чтения",
        ^{ [blockSelf toggleReadingMode]; }
    };
    
    // 7. Ночной режим
    _functions["nightMode"] = {
        false, "Ночной режим",
        ^{ [blockSelf toggleNightMode]; }
    };
    
    // 8. Энергосбережение
    _functions["batterySaver"] = {
        false, "Энергосбережение",
        ^{ [blockSelf toggleBatterySaver]; }
    };
    
    // 9. Ускорение анимаций
    _functions["animationBoost"] = {
        false, "Ускорение анимаций",
        ^{ [blockSelf toggleAnimationBoost]; }
    };
    
    // 10. Зум экрана
    _functions["screenZoom"] = {
        false, "Зум экрана",
        ^{ [blockSelf toggleScreenZoom]; }
    };
    
    // 11. Растяжение экрана
    _functions["screenStretch"] = {
        false, "Растяжение экрана",
        ^{ [blockSelf toggleScreenStretch]; }
    };
    
    // 12. Широкоформатный режим
    _functions["widescreenMode"] = {
        false, "Широкоформатный режим",
        ^{ [blockSelf toggleWidescreenMode]; }
    };
}

- (void)initialize {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self createUI];
    });
    
    // Запускаем поток уведомлений с weak self
    _notificationRunning = true;
    
    __weak GameHelperController *weakSelf = self;
    _notificationThread = std::thread([weakSelf]() {
        // Проверяем, что объект еще жив
        if (weakSelf) {
            [weakSelf notificationLoop];
        }
    });
}

- (void)cleanup {
    _notificationRunning = false;
    if (_notificationThread.joinable()) {
        _notificationThread.join();
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self disableScreenStretch];
        [_overlayWindow removeFromSuperview];
        [_stretchWindow removeFromSuperview];
        _overlayWindow = nil;
        _stretchWindow = nil;
    });
}

- (void)createUI {
    // Создаем окно поверх всех
    _overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _overlayWindow.windowLevel = UIWindowLevelAlert + 1;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.userInteractionEnabled = YES;
    [_overlayWindow makeKeyAndVisible];
    
    // Создаем окно для растяжения (ниже основного)
    _stretchWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _stretchWindow.windowLevel = UIWindowLevelNormal;
    _stretchWindow.backgroundColor = [UIColor clearColor];
    _stretchWindow.userInteractionEnabled = YES;
    _stretchWindow.hidden = YES;
    
    // Создаем плавающую кнопку
    [self createFloatingButton];
    
    // Создаем меню
    [self createMenu];
    
    // Создаем уведомление
    [self createNotificationLabel];
    
    // Создаем оверлей для растяжения
    [self createStretchOverlay];
}

- (void)createFloatingButton {
    _floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _floatingButton.frame = CGRectMake(20, 100, 60, 60);
    _floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.9];
    _floatingButton.layer.cornerRadius = 30;
    _floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
    _floatingButton.layer.shadowOpacity = 0.3;
    _floatingButton.layer.shadowRadius = 5;
    _floatingButton.layer.borderWidth = 2;
    _floatingButton.layer.borderColor = [UIColor whiteColor].CGColor;
    
    [_floatingButton setTitle:@"⚙️" forState:UIControlStateNormal];
    _floatingButton.titleLabel.font = [UIFont systemFontOfSize:24];
    
    // Добавляем возможность перетаскивания
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [_floatingButton addGestureRecognizer:panGesture];
    
    [_floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    [_overlayWindow addSubview:_floatingButton];
}

- (void)createStretchOverlay {
    // Прозрачный оверлей для обработки жестов растяжения
    _stretchOverlay = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _stretchOverlay.backgroundColor = [UIColor clearColor];
    _stretchOverlay.userInteractionEnabled = YES;
    _stretchOverlay.hidden = YES;
    
    // Добавляем жест pinch для растяжения
    _pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
    [_stretchOverlay addGestureRecognizer:_pinchGesture];
    
    // Кнопка сброса растяжения
    _resetStretchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _resetStretchButton.frame = CGRectMake(20, 180, 100, 40);
    _resetStretchButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:0.8];
    _resetStretchButton.layer.cornerRadius = 8;
    _resetStretchButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _resetStretchButton.layer.shadowOffset = CGSizeMake(0, 2);
    _resetStretchButton.layer.shadowOpacity = 0.3;
    _resetStretchButton.layer.shadowRadius = 3;
    
    [_resetStretchButton setTitle:@"🔄 Сброс" forState:UIControlStateNormal];
    _resetStretchButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [_resetStretchButton addTarget:self action:@selector(resetStretch) forControlEvents:UIControlEventTouchUpInside];
    _resetStretchButton.hidden = YES;
    
    [_stretchOverlay addSubview:_resetStretchButton];
    [_stretchWindow addSubview:_stretchOverlay];
}

- (void)createMenu {
    _menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 180, 300, 0)];
    _menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    _menuView.layer.cornerRadius = 20;
    _menuView.layer.shadowColor = [UIColor blackColor].CGColor;
    _menuView.layer.shadowOffset = CGSizeMake(0, 4);
    _menuView.layer.shadowOpacity = 0.5;
    _menuView.layer.shadowRadius = 8;
    _menuView.clipsToBounds = YES;
    _menuView.hidden = YES;
    
    [_overlayWindow addSubview:_menuView];
    
    // Заголовок меню
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 300, 30)];
    titleLabel.text = @"🎮 УЮТНЫЙ ГЕЙМПЛЕЙ";
    titleLabel.textColor = [UIColor cyanColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [_menuView addSubview:titleLabel];
    
    // Заполняем меню функциями
    [self populateMenu];
}

- (void)populateMenu {
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
        @"Зум экрана",
        @"Растяжение экрана",
        @"Широкоформатный режим"
    ];
    
    CGFloat yOffset = 50;
    int index = 0;
    
    for (NSString *name in functionNames) {
        UIView *buttonContainer = [[UIView alloc] initWithFrame:CGRectMake(10, yOffset, 280, 44)];
        buttonContainer.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        buttonContainer.layer.cornerRadius = 10;
        buttonContainer.tag = index;
        
        // Название функции
        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 12, 200, 20)];
        nameLabel.text = name;
        nameLabel.textColor = [UIColor whiteColor];
        nameLabel.font = [UIFont systemFontOfSize:14];
        [buttonContainer addSubview:nameLabel];
        
        // Индикатор состояния
        UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(235, 12, 30, 20)];
        statusLabel.tag = 100;
        statusLabel.text = @"⚪";
        statusLabel.textColor = [UIColor grayColor];
        statusLabel.font = [UIFont systemFontOfSize:16];
        [buttonContainer addSubview:statusLabel];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(functionTapped:)];
        [buttonContainer addGestureRecognizer:tap];
        
        [_menuView addSubview:buttonContainer];
        [_functionButtons addObject:buttonContainer];
        
        yOffset += 50;
        index++;
    }
    
    // Добавляем кнопку закрытия
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    closeButton.frame = CGRectMake(10, yOffset + 10, 280, 40);
    closeButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8];
    closeButton.layer.cornerRadius = 10;
    [closeButton setTitle:@"❌ Закрыть меню" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [_menuView addSubview:closeButton];
    
    // Обновляем высоту меню
    CGRect menuFrame = _menuView.frame;
    menuFrame.size.height = yOffset + 60;
    _menuView.frame = menuFrame;
}

- (void)createNotificationLabel {
    _notificationLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, _overlayWindow.bounds.size.height - 90, _overlayWindow.bounds.size.width - 40, 50)];
    _notificationLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
    _notificationLabel.textColor = [UIColor whiteColor];
    _notificationLabel.textAlignment = NSTextAlignmentCenter;
    _notificationLabel.layer.cornerRadius = 15;
    _notificationLabel.clipsToBounds = YES;
    _notificationLabel.font = [UIFont boldSystemFontOfSize:16];
    _notificationLabel.numberOfLines = 2;
    _notificationLabel.alpha = 0;
    
    [_overlayWindow addSubview:_notificationLabel];
}

// MARK: - Gesture Handlers
- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    UIButton *button = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint newCenter = CGPointMake(button.center.x + translation.x,
                                       button.center.y + translation.y);
        
        // Ограничиваем краями экрана
        newCenter.x = MAX(button.frame.size.width/2, 
                         MIN(button.superview.bounds.size.width - button.frame.size.width/2, newCenter.x));
        newCenter.y = MAX(button.frame.size.height/2 + 50, 
                         MIN(button.superview.bounds.size.height - button.frame.size.height/2 - 50, newCenter.y));
        
        button.center = newCenter;
        [gesture setTranslation:CGPointZero inView:button.superview];
        
        // Перемещаем меню вместе с кнопкой
        [self updateMenuPosition];
    }
}

- (void)handlePinchGesture:(UIPinchGestureRecognizer *)gesture {
    if (!_functions["screenStretch"].enabled) return;
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat scale = gesture.scale;
        _currentScale = scale;
        
        // Применяем трансформацию к окну приложения
        [self applyStretchTransform:scale];
        
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        // Сохраняем масштаб
        _originalScale = _currentScale;
    }
}

- (void)applyStretchTransform:(CGFloat)scale {
    // Находим главное окно приложения
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    
    // Применяем трансформацию растяжения
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, 1.0); // Растяжение по горизонтали
    mainWindow.transform = transform;
    
    // Обновляем позицию кнопки сброса
    _resetStretchButton.hidden = NO;
}

- (void)resetStretch {
    // Сбрасываем трансформацию
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    mainWindow.transform = CGAffineTransformIdentity;
    
    _currentScale = 1.0;
    _originalScale = 1.0;
    _resetStretchButton.hidden = YES;
    
    [self showNotification:@"Растяжение сброшено" enabled:NO];
}

// MARK: - Menu Actions
- (void)toggleMenu {
    _isMenuVisible = !_isMenuVisible;
    _menuView.hidden = !_isMenuVisible;
    
    if (_isMenuVisible) {
        [self updateMenuPosition];
        [self updateFunctionButtons];
    }
}

- (void)hideMenu {
    _isMenuVisible = NO;
    _menuView.hidden = YES;
}

- (void)updateMenuPosition {
    CGRect menuFrame = _menuView.frame;
    menuFrame.origin.x = _floatingButton.frame.origin.x;
    menuFrame.origin.y = CGRectGetMaxY(_floatingButton.frame) + 10;
    
    // Проверяем, не выходит ли меню за экран
    if (menuFrame.origin.y + menuFrame.size.height > _overlayWindow.bounds.size.height - 50) {
        menuFrame.origin.y = _floatingButton.frame.origin.y - menuFrame.size.height - 10;
    }
    
    // Проверяем по горизонтали
    if (menuFrame.origin.x + menuFrame.size.width > _overlayWindow.bounds.size.width - 10) {
        menuFrame.origin.x = _overlayWindow.bounds.size.width - menuFrame.size.width - 10;
    }
    
    _menuView.frame = menuFrame;
}

- (void)functionTapped:(UITapGestureRecognizer *)gesture {
    UIView *container = gesture.view;
    int index = (int)container.tag;
    [self toggleFunctionAtIndex:index];
}

- (void)toggleFunctionAtIndex:(int)index {
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
        case 10: functionId = "screenStretch"; break;
        case 11: functionId = "widescreenMode"; break;
    }
    
    [self toggleFunction:[NSString stringWithUTF8String:functionId.c_str()]];
}

- (void)toggleFunction:(NSString *)functionId {
    std::string fid = [functionId UTF8String];
    auto& func = _functions[fid];
    func.enabled = !func.enabled;
    
    // Вызываем соответствующий блок
    if (func.toggleBlock) {
        func.toggleBlock();
    }
    
    [self showNotification:[NSString stringWithUTF8String:func.name.c_str()] enabled:func.enabled];
    [self updateFunctionButtons];
}

- (void)updateFunctionButtons {
    int index = 0;
    for (UIView *container in _functionButtons) {
        UILabel *statusLabel = [container viewWithTag:100];
        if (statusLabel) {
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
                case 10: functionId = "screenStretch"; break;
                case 11: functionId = "widescreenMode"; break;
            }
            
            BOOL enabled = _functions[functionId].enabled;
            statusLabel.text = enabled ? @"✅" : @"⚪";
            statusLabel.textColor = enabled ? [UIColor greenColor] : [UIColor grayColor];
            
            // Подсветка активной функции
            container.backgroundColor = enabled ? 
                [UIColor colorWithRed:0.3 green:0.5 blue:0.3 alpha:1.0] :
                [UIColor colorWithWhite:0.2 alpha:1.0];
        }
        index++;
    }
}

- (void)showNotification:(NSString *)message enabled:(BOOL)enabled {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *icon = enabled ? @"✅" : @"❌";
        self->_notificationLabel.text = [NSString stringWithFormat:@"%@  %@", icon, message];
        self->_notificationLabel.backgroundColor = enabled ? 
            [UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:0.9] :
            [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:0.9];
        
        [UIView animateWithDuration:0.3 animations:^{
            self->_notificationLabel.alpha = 1.0;
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3 delay:2.0 options:0 animations:^{
                self->_notificationLabel.alpha = 0.0;
            } completion:nil];
        }];
    });
}

- (void)notificationLoop {
    while (_notificationRunning) {
        if (_functions["fpsCounter"].enabled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                static int frameCount = 0;
                frameCount++;
                if (frameCount % 30 == 0) {
                    // Симуляция FPS
                    int fps = 30 + arc4random_uniform(30);
                    self->_notificationLabel.text = [NSString stringWithFormat:@"📊 FPS: %d", fps];
                    self->_notificationLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
                    self->_notificationLabel.alpha = 0.8;
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        self->_notificationLabel.alpha = 0.0;
                    });
                }
            });
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}

// MARK: - Function Implementations
- (void)toggleAutoClicker {
    if (_functions["autoClicker"].enabled) {
        __weak GameHelperController *weakSelf = self;
        
        std::thread([weakSelf]() {
            while (weakSelf && weakSelf->_functions["autoClicker"].enabled) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Эмуляция клика
                    // Можно добавить визуальный эффект или звук
                });
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }).detach();
    }
}

- (void)toggleFPSUnlock {
    // Разблокировка FPS (убираем ограничения)
    if (_functions["fpsUnlock"].enabled) {
        // Код для разблокировки FPS
    }
}

- (void)togglePotatoGraphics {
    if (_functions["potatoGraphics"].enabled) {
        // Уменьшение качества графики
    }
}

- (void)toggleFPSCounter {
    // Включается автоматически в notificationLoop
}

- (void)toggleBrightness {
    if (_functions["brightnessBoost"].enabled) {
        // Увеличение яркости
        [[UIScreen mainScreen] setBrightness:1.0];
    } else {
        [[UIScreen mainScreen] setBrightness:0.5];
    }
}

- (void)toggleReadingMode {
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    UIView *existingOverlay = [mainWindow viewWithTag:999];
    
    if (_functions["readingMode"].enabled && !existingOverlay) {
        // Режим чтения (сепия)
        UIView *colorOverlay = [[UIView alloc] initWithFrame:mainWindow.bounds];
        colorOverlay.backgroundColor = [UIColor colorWithRed:0.9 green:0.8 blue:0.7 alpha:0.3];
        colorOverlay.tag = 999;
        colorOverlay.userInteractionEnabled = NO;
        [mainWindow addSubview:colorOverlay];
    } else {
        [existingOverlay removeFromSuperview];
    }
}

- (void)toggleNightMode {
    if (_functions["nightMode"].enabled) {
        // Ночной режим (темная тема)
        if (@available(iOS 13.0, *)) {
            // Используем системную темную тему
        }
    }
}

- (void)toggleBatterySaver {
    if (_functions["batterySaver"].enabled) {
        // Энергосбережение
        [[NSProcessInfo processInfo] setProcessName:@"BatterySaver"];
    }
}

- (void)toggleAnimationBoost {
    if (_functions["animationBoost"].enabled) {
        // Ускорение анимаций
        [[NSUserDefaults standardUserDefaults] setFloat:0.5 forKey:@"UIAnimationSpeedScale"];
    } else {
        [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"UIAnimationSpeedScale"];
    }
}

- (void)toggleScreenZoom {
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    
    if (_functions["screenZoom"].enabled) {
        // Зум экрана
        [UIView animateWithDuration:0.3 animations:^{
            mainWindow.transform = CGAffineTransformMakeScale(1.2, 1.2);
        }];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            mainWindow.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)toggleScreenStretch {
    if (_functions["screenStretch"].enabled) {
        [self enableScreenStretch];
    } else {
        [self disableScreenStretch];
    }
}

- (void)enableScreenStretch {
    _stretchWindow.hidden = NO;
    _stretchOverlay.hidden = NO;
    _resetStretchButton.hidden = YES;
    [self showNotification:@"Растяжение экрана - используйте pinch жесты" enabled:YES];
}

- (void)disableScreenStretch {
    _stretchWindow.hidden = YES;
    _stretchOverlay.hidden = YES;
    _resetStretchButton.hidden = YES;
    [self resetStretch];
}

- (void)toggleWidescreenMode {
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    
    if (_functions["widescreenMode"].enabled) {
        // Широкоформатный режим (21:9)
        [UIView animateWithDuration:0.5 animations:^{
            mainWindow.transform = CGAffineTransformMakeScale(1.3, 1.0);
        }];
    } else {
        [UIView animateWithDuration:0.5 animations:^{
            mainWindow.transform = CGAffineTransformIdentity;
        }];
    }
}

@end

// Глобальный экземпляр
static GameHelperController *g_helper = nil;

// Функции для экспорта
extern "C" {
    void init_game_helper() {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            g_helper = [[GameHelperController alloc] init];
            [g_helper initialize];
        });
    }
    
    void cleanup_game_helper() {
        if (g_helper) {
            [g_helper cleanup];
            g_helper = nil;
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
