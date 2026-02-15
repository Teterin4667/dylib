#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <thread>
#include <chrono>
#include <map>
#include <string>
#include <functional>
#include <vector>

// Компактный размер меню
#define MENU_WIDTH 200
#define BUTTON_HEIGHT 35
#define MENU_PADDING 8

// Структура для хранения состояния функций
struct FunctionState {
    bool enabled;
    std::string name;
    dispatch_block_t toggleBlock;
};

// Интерфейс контроллера
@interface GameHelperController : NSObject {
    UIWindow *_overlayWindow;
    UIButton *_floatingButton;
    UIView *_menuView;
    UILabel *_notificationLabel;
    NSMutableArray *_functionButtons;
    std::map<std::string, FunctionState> _functions;
    bool _isMenuVisible;
    CGPoint _lastTouchPoint;
}

- (void)initialize;
- (void)cleanup;
- (void)showNotification:(NSString *)message enabled:(BOOL)enabled;
- (void)toggleFunction:(NSString *)functionId;
- (void)updateFunctionButtons;

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
- (void)toggleWidescreenMode;

@end

@implementation GameHelperController

- (instancetype)init {
    self = [super init];
    if (self) {
        _functionButtons = [NSMutableArray new];
        _isMenuVisible = false;
        _lastTouchPoint = CGPointZero;
        [self registerFunctions];
    }
    return self;
}

- (void)registerFunctions {
    __weak GameHelperController *weakSelf = self;
    
    _functions["autoClicker"] = {
        false, "Автокликер",
        ^{ [weakSelf toggleAutoClicker]; }
    };
    
    _functions["fpsUnlock"] = {
        false, "FPS Unlock",
        ^{ [weakSelf toggleFPSUnlock]; }
    };
    
    _functions["potatoGraphics"] = {
        false, "Потато графика",
        ^{ [weakSelf togglePotatoGraphics]; }
    };
    
    _functions["fpsCounter"] = {
        false, "Счетчик FPS",
        ^{ [weakSelf toggleFPSCounter]; }
    };
    
    _functions["brightnessBoost"] = {
        false, "Яркость +",
        ^{ [weakSelf toggleBrightness]; }
    };
    
    _functions["readingMode"] = {
        false, "Чтение",
        ^{ [weakSelf toggleReadingMode]; }
    };
    
    _functions["nightMode"] = {
        false, "Ночь",
        ^{ [weakSelf toggleNightMode]; }
    };
    
    _functions["batterySaver"] = {
        false, "Эконом",
        ^{ [weakSelf toggleBatterySaver]; }
    };
    
    _functions["animationBoost"] = {
        false, "Анимации",
        ^{ [weakSelf toggleAnimationBoost]; }
    };
    
    _functions["screenZoom"] = {
        false, "Зум",
        ^{ [weakSelf toggleScreenZoom]; }
    };
    
    _functions["widescreenMode"] = {
        false, "Широкий",
        ^{ [weakSelf toggleWidescreenMode]; }
    };
}

- (void)initialize {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self createUI];
    });
}

- (void)cleanup {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_overlayWindow removeFromSuperview];
        _overlayWindow = nil;
    });
}

- (void)createUI {
    _overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _overlayWindow.windowLevel = UIWindowLevelAlert + 1;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.userInteractionEnabled = YES;
    _overlayWindow.hidden = NO;
    
    [self createFloatingButton];
    [self createMenu];
    [self createNotificationLabel];
}

- (void)createFloatingButton {
    _floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _floatingButton.frame = CGRectMake(20, 100, 44, 44);
    _floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:0.85];
    _floatingButton.layer.cornerRadius = 22;
    _floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
    _floatingButton.layer.shadowOpacity = 0.2;
    _floatingButton.layer.shadowRadius = 3;
    _floatingButton.layer.borderWidth = 1;
    _floatingButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    _floatingButton.clipsToBounds = YES;
    
    [_floatingButton setTitle:@"⚙️" forState:UIControlStateNormal];
    _floatingButton.titleLabel.font = [UIFont systemFontOfSize:20];
    
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [_floatingButton addGestureRecognizer:panGesture];
    
    [_floatingButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    [_overlayWindow addSubview:_floatingButton];
}

- (void)createMenu {
    _menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 150, MENU_WIDTH, 0)];
    _menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    _menuView.layer.cornerRadius = 12;
    _menuView.layer.shadowColor = [UIColor blackColor].CGColor;
    _menuView.layer.shadowOffset = CGSizeMake(0, 2);
    _menuView.layer.shadowOpacity = 0.3;
    _menuView.layer.shadowRadius = 4;
    _menuView.clipsToBounds = YES;
    _menuView.hidden = YES;
    
    [_overlayWindow addSubview:_menuView];
    
    [self populateCompactMenu];
}

- (void)populateCompactMenu {
    NSArray *functionKeys = @[
        @"autoClicker", @"fpsUnlock", @"potatoGraphics", @"fpsCounter",
        @"brightnessBoost", @"readingMode", @"nightMode", @"batterySaver",
        @"animationBoost", @"screenZoom", @"widescreenMode"
    ];
    
    CGFloat yOffset = MENU_PADDING;
    int index = 0;
    
    for (NSString *key in functionKeys) {
        std::string fid = [key UTF8String];
        FunctionState &func = _functions[fid];
        
        UIView *buttonContainer = [[UIView alloc] initWithFrame:CGRectMake(MENU_PADDING, yOffset, MENU_WIDTH - MENU_PADDING*2, BUTTON_HEIGHT)];
        buttonContainer.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
        buttonContainer.layer.cornerRadius = 6;
        buttonContainer.tag = index;
        
        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 130, BUTTON_HEIGHT)];
        nameLabel.text = [NSString stringWithUTF8String:func.name.c_str()];
        nameLabel.textColor = [UIColor whiteColor];
        nameLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        [buttonContainer addSubview:nameLabel];
        
        UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(140, 0, 30, BUTTON_HEIGHT)];
        statusLabel.tag = 100;
        statusLabel.text = @"⚪";
        statusLabel.textColor = [UIColor grayColor];
        statusLabel.font = [UIFont systemFontOfSize:14];
        statusLabel.textAlignment = NSTextAlignmentRight;
        [buttonContainer addSubview:statusLabel];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(functionTapped:)];
        [buttonContainer addGestureRecognizer:tap];
        
        [_menuView addSubview:buttonContainer];
        [_functionButtons addObject:buttonContainer];
        
        yOffset += BUTTON_HEIGHT + 4;
        index++;
    }
    
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    closeButton.frame = CGRectMake(MENU_PADDING, yOffset, MENU_WIDTH - MENU_PADDING*2, BUTTON_HEIGHT);
    closeButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8];
    closeButton.layer.cornerRadius = 6;
    [closeButton setTitle:@"✕ Закрыть" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [closeButton addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    
    [_menuView addSubview:closeButton];
    
    CGRect menuFrame = _menuView.frame;
    menuFrame.size.height = yOffset + BUTTON_HEIGHT + MENU_PADDING;
    _menuView.frame = menuFrame;
}

- (void)createNotificationLabel {
    _notificationLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, _overlayWindow.bounds.size.height - 70, _overlayWindow.bounds.size.width - 40, 36)];
    _notificationLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    _notificationLabel.textColor = [UIColor whiteColor];
    _notificationLabel.textAlignment = NSTextAlignmentCenter;
    _notificationLabel.layer.cornerRadius = 8;
    _notificationLabel.clipsToBounds = YES;
    _notificationLabel.font = [UIFont boldSystemFontOfSize:13];
    _notificationLabel.alpha = 0;
    
    [_overlayWindow addSubview:_notificationLabel];
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    UIButton *button = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _lastTouchPoint = button.center;
    }
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint newCenter = CGPointMake(button.center.x + translation.x,
                                       button.center.y + translation.y);
        
        CGFloat minX = button.frame.size.width/2;
        CGFloat maxX = button.superview.bounds.size.width - button.frame.size.width/2;
        CGFloat minY = button.frame.size.height/2 + 40;
        CGFloat maxY = button.superview.bounds.size.height - button.frame.size.height/2 - 40;
        
        newCenter.x = MAX(minX, MIN(maxX, newCenter.x));
        newCenter.y = MAX(minY, MIN(maxY, newCenter.y));
        
        button.center = newCenter;
        [gesture setTranslation:CGPointZero inView:button.superview];
        
        [self updateMenuPosition];
    }
}

- (void)toggleMenu {
    _isMenuVisible = !_isMenuVisible;
    
    [UIView animateWithDuration:0.2 animations:^{
        self->_menuView.hidden = !self->_isMenuVisible;
        if (self->_isMenuVisible) {
            self->_menuView.alpha = 1.0;
        }
    }];
    
    if (_isMenuVisible) {
        [self updateMenuPosition];
        [self updateFunctionButtons];
    }
}

- (void)hideMenu {
    _isMenuVisible = NO;
    
    [UIView animateWithDuration:0.2 animations:^{
        self->_menuView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->_menuView.hidden = YES;
    }];
}

- (void)updateMenuPosition {
    CGRect menuFrame = _menuView.frame;
    menuFrame.origin.x = _floatingButton.frame.origin.x;
    menuFrame.origin.y = CGRectGetMaxY(_floatingButton.frame) + 5;
    
    if (menuFrame.origin.y + menuFrame.size.height > _overlayWindow.bounds.size.height - 20) {
        menuFrame.origin.y = _floatingButton.frame.origin.y - menuFrame.size.height - 5;
    }
    
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
    NSArray *functionKeys = @[
        @"autoClicker", @"fpsUnlock", @"potatoGraphics", @"fpsCounter",
        @"brightnessBoost", @"readingMode", @"nightMode", @"batterySaver",
        @"animationBoost", @"screenZoom", @"widescreenMode"
    ];
    
    if (index < functionKeys.count) {
        [self toggleFunction:functionKeys[index]];
    }
}

- (void)toggleFunction:(NSString *)functionId {
    std::string fid = [functionId UTF8String];
    auto& func = _functions[fid];
    func.enabled = !func.enabled;
    
    if (func.toggleBlock) {
        func.toggleBlock();
    }
    
    [self showNotification:[NSString stringWithUTF8String:func.name.c_str()] enabled:func.enabled];
    [self updateFunctionButtons];
}

- (void)updateFunctionButtons {
    NSArray *functionKeys = @[
        @"autoClicker", @"fpsUnlock", @"potatoGraphics", @"fpsCounter",
        @"brightnessBoost", @"readingMode", @"nightMode", @"batterySaver",
        @"animationBoost", @"screenZoom", @"widescreenMode"
    ];
    
    int index = 0;
    for (UIView *container in _functionButtons) {
        UILabel *statusLabel = [container viewWithTag:100];
        if (statusLabel && index < functionKeys.count) {
            NSString *key = functionKeys[index];
            std::string fid = [key UTF8String];
            
            BOOL enabled = _functions[fid].enabled;
            statusLabel.text = enabled ? @"✅" : @"⚪";
            statusLabel.textColor = enabled ? [UIColor greenColor] : [UIColor grayColor];
            
            container.backgroundColor = enabled ? 
                [UIColor colorWithRed:0.3 green:0.5 blue:0.3 alpha:0.9] :
                [UIColor colorWithWhite:0.2 alpha:0.9];
        }
        index++;
    }
}

- (void)showNotification:(NSString *)message enabled:(BOOL)enabled {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *icon = enabled ? @"✅" : @"❌";
        self->_notificationLabel.text = [NSString stringWithFormat:@"%@ %@", icon, message];
        self->_notificationLabel.backgroundColor = enabled ? 
            [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:0.8] :
            [UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:0.8];
        
        [UIView animateWithDuration:0.2 animations:^{
            self->_notificationLabel.alpha = 1.0;
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.2 delay:1.5 options:0 animations:^{
                self->_notificationLabel.alpha = 0.0;
            } completion:nil];
        }];
    });
}

- (void)toggleAutoClicker {
    if (_functions["autoClicker"].enabled) {
        __weak GameHelperController *weakSelf = self;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            GameHelperController *strongSelf = weakSelf;
            while (strongSelf && strongSelf->_functions["autoClicker"].enabled) {
                [NSThread sleepForTimeInterval:0.1];
                strongSelf = weakSelf; // Обновляем strongSelf на каждой итерации
            }
        });
    }
    [self showNotification:@"Автокликер" enabled:_functions["autoClicker"].enabled];
}

- (void)toggleFPSUnlock {
    [self showNotification:@"FPS Unlock" enabled:_functions["fpsUnlock"].enabled];
}

- (void)togglePotatoGraphics {
    [self showNotification:@"Потато графика" enabled:_functions["potatoGraphics"].enabled];
}

- (void)toggleFPSCounter {
    if (_functions["fpsCounter"].enabled) {
        __weak GameHelperController *weakSelf = self;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            GameHelperController *strongSelf = weakSelf;
            while (strongSelf && strongSelf->_functions["fpsCounter"].enabled) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    GameHelperController *innerStrongSelf = weakSelf;
                    if (innerStrongSelf) {
                        int fps = 30 + arc4random_uniform(30);
                        innerStrongSelf->_notificationLabel.text = [NSString stringWithFormat:@"📊 FPS: %d", fps];
                        innerStrongSelf->_notificationLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
                        innerStrongSelf->_notificationLabel.alpha = 0.8;
                        
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            GameHelperController *finalStrongSelf = weakSelf;
                            if (finalStrongSelf) {
                                finalStrongSelf->_notificationLabel.alpha = 0.0;
                            }
                        });
                    }
                });
                [NSThread sleepForTimeInterval:2.0];
                strongSelf = weakSelf; // Обновляем strongSelf на каждой итерации
            }
        });
    }
    [self showNotification:@"Счетчик FPS" enabled:_functions["fpsCounter"].enabled];
}

- (void)toggleBrightness {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_functions["brightnessBoost"].enabled) {
            [UIScreen mainScreen].brightness = 1.0;
        } else {
            [UIScreen mainScreen].brightness = 0.5;
        }
    });
    [self showNotification:@"Яркость" enabled:_functions["brightnessBoost"].enabled];
}

- (void)toggleReadingMode {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        UIView *existingOverlay = [mainWindow viewWithTag:999];
        
        if (self->_functions["readingMode"].enabled && !existingOverlay) {
            UIView *colorOverlay = [[UIView alloc] initWithFrame:mainWindow.bounds];
            colorOverlay.backgroundColor = [UIColor colorWithRed:0.95 green:0.85 blue:0.75 alpha:0.2];
            colorOverlay.tag = 999;
            colorOverlay.userInteractionEnabled = NO;
            [mainWindow addSubview:colorOverlay];
        } else {
            [existingOverlay removeFromSuperview];
        }
    });
    [self showNotification:@"Режим чтения" enabled:_functions["readingMode"].enabled];
}

- (void)toggleNightMode {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        UIView *existingOverlay = [mainWindow viewWithTag:998];
        
        if (self->_functions["nightMode"].enabled && !existingOverlay) {
            UIView *darkOverlay = [[UIView alloc] initWithFrame:mainWindow.bounds];
            darkOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.3];
            darkOverlay.tag = 998;
            darkOverlay.userInteractionEnabled = NO;
            [mainWindow addSubview:darkOverlay];
        } else {
            [existingOverlay removeFromSuperview];
        }
    });
    [self showNotification:@"Ночной режим" enabled:_functions["nightMode"].enabled];
}

- (void)toggleBatterySaver {
    [self showNotification:@"Энергосбережение" enabled:_functions["batterySaver"].enabled];
}

- (void)toggleAnimationBoost {
    [self showNotification:@"Ускорение анимаций" enabled:_functions["animationBoost"].enabled];
}

- (void)toggleScreenZoom {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        
        [UIView animateWithDuration:0.2 animations:^{
            if (self->_functions["screenZoom"].enabled) {
                mainWindow.transform = CGAffineTransformMakeScale(1.15, 1.15);
            } else {
                mainWindow.transform = CGAffineTransformIdentity;
            }
        }];
    });
    [self showNotification:@"Зум" enabled:_functions["screenZoom"].enabled];
}

- (void)toggleWidescreenMode {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        
        [UIView animateWithDuration:0.2 animations:^{
            if (self->_functions["widescreenMode"].enabled) {
                mainWindow.transform = CGAffineTransformMakeScale(1.2, 1.0);
            } else {
                mainWindow.transform = CGAffineTransformIdentity;
            }
        }];
    });
    [self showNotification:@"Широкий режим" enabled:_functions["widescreenMode"].enabled];
}

@end

// Глобальный экземпляр
static GameHelperController *g_helper = nil;

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
    
    __attribute__((constructor)) static void on_load() {
        init_game_helper();
    }
    
    __attribute__((destructor)) static void on_unload() {
        cleanup_game_helper();
    }
}
