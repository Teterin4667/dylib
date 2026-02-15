#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <map>
#include <string>
#include <thread>
#include <chrono>

// Очень маленькое меню
#define MENU_WIDTH 130
#define BUTTON_HEIGHT 26
#define MENU_PADDING 3

@interface GameHelper : NSObject {
    UIWindow *_overlayWindow;
    UIButton *_menuButton;
    UIView *_menuPanel;
    UILabel *_notificationLabel;
    std::map<std::string, bool> _functions;
    BOOL _menuVisible;
    
    // Для функций
    float _normalBrightness;
    BOOL _autoClickerRunning;
    
    // Для растяжения экрана
    CGFloat _stretchScale;
    BOOL _stretchActive;
    UIPinchGestureRecognizer *_pinchGesture;
}

- (void)toggleMenu;
- (void)hideMenu;
- (void)showNotification:(NSString *)text;
- (void)applyStretch:(CGFloat)scale;
- (void)resetStretch;
- (void)functionTapped:(UITapGestureRecognizer *)tap;
- (void)updateStatuses;
- (void)updateMenuPosition;
- (void)executeFunction:(std::string)func;

@end

@implementation GameHelper

- (instancetype)init {
    self = [super init];
    if (self) {
        _functions["clicker"] = false;
        _functions["fps"] = false;
        _functions["potato"] = false;
        _functions["bright"] = false;
        _functions["night"] = false;
        _functions["stretch"] = false;
        _menuVisible = NO;
        _autoClickerRunning = NO;
        _normalBrightness = [UIScreen mainScreen].brightness;
        _stretchScale = 1.0;
        _stretchActive = NO;
    }
    return self;
}

- (void)createUI {
    // Окно которое НЕ БЛОКИРУЕТ касания игры
    _overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _overlayWindow.windowLevel = UIWindowLevelAlert + 1;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.userInteractionEnabled = YES;
    _overlayWindow.hidden = NO;
    
    // МАЛЕНЬКАЯ КНОПКА 20x20
    _menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _menuButton.frame = CGRectMake(6, 45, 20, 20);
    _menuButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.3];
    _menuButton.layer.cornerRadius = 4;
    _menuButton.layer.borderWidth = 0.3;
    _menuButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
    [_menuButton setTitle:@"⚙️" forState:UIControlStateNormal];
    _menuButton.titleLabel.font = [UIFont systemFontOfSize:10];
    
    [_menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    [_overlayWindow addSubview:_menuButton];
    
    // МЕНЮ
    _menuPanel = [[UIView alloc] initWithFrame:CGRectMake(6, 70, MENU_WIDTH, 0)];
    _menuPanel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    _menuPanel.layer.cornerRadius = 6;
    _menuPanel.clipsToBounds = YES;
    _menuPanel.hidden = YES;
    
    [self buildMenu];
    [_overlayWindow addSubview:_menuPanel];
    
    // НОТИФИКАЦИЯ
    _notificationLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, _overlayWindow.bounds.size.height - 40, _overlayWindow.bounds.size.width - 20, 28)];
    _notificationLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    _notificationLabel.textColor = [UIColor whiteColor];
    _notificationLabel.font = [UIFont systemFontOfSize:11];
    _notificationLabel.textAlignment = NSTextAlignmentCenter;
    _notificationLabel.layer.cornerRadius = 6;
    _notificationLabel.clipsToBounds = YES;
    _notificationLabel.alpha = 0;
    [_overlayWindow addSubview:_notificationLabel];
    
    // ЖЕСТ РАСТЯЖЕНИЯ
    _pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [_overlayWindow addGestureRecognizer:_pinchGesture];
}

- (void)buildMenu {
    NSArray *items = @[@"🖱️ Кликер", @"📊 FPS", @"🥔 Потато", @"☀️ Яркость", @"🌙 Ночь", @"🔍 Растяг"];
    
    CGFloat yOffset = MENU_PADDING;
    
    for (int i = 0; i < items.count; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(MENU_PADDING, yOffset, MENU_WIDTH - MENU_PADDING*2, BUTTON_HEIGHT)];
        row.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.7];
        row.layer.cornerRadius = 4;
        row.tag = i;
        row.userInteractionEnabled = YES;
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(6, 0, 80, BUTTON_HEIGHT)];
        label.text = items[i];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:10];
        [row addSubview:label];
        
        UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(90, 0, 20, BUTTON_HEIGHT)];
        status.tag = 100;
        status.text = @"⚪";
        status.textColor = [UIColor grayColor];
        status.font = [UIFont systemFontOfSize:10];
        [row addSubview:status];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(functionTapped:)];
        [row addGestureRecognizer:tap];
        
        [_menuPanel addSubview:row];
        
        yOffset += BUTTON_HEIGHT + 2;
    }
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(MENU_PADDING, yOffset, MENU_WIDTH - MENU_PADDING*2, BUTTON_HEIGHT);
    closeBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.2 blue:0.2 alpha:0.6];
    closeBtn.layer.cornerRadius = 4;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    [closeBtn addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    
    [_menuPanel addSubview:closeBtn];
    
    // Высота меню
    CGRect frame = _menuPanel.frame;
    frame.size.height = yOffset + BUTTON_HEIGHT + MENU_PADDING;
    _menuPanel.frame = frame;
}

// MARK: - Растяжение экрана
- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (!_functions["stretch"]) return;
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        _stretchScale = gesture.scale;
        [self applyStretch:_stretchScale];
    }
}

- (void)applyStretch:(CGFloat)scale {
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    if (mainWindow) {
        [UIView animateWithDuration:0.1 animations:^{
            mainWindow.transform = CGAffineTransformMakeScale(scale, 1.0);
        }];
    }
}

- (void)resetStretch {
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    if (mainWindow) {
        [UIView animateWithDuration:0.2 animations:^{
            mainWindow.transform = CGAffineTransformIdentity;
        }];
    }
    _stretchScale = 1.0;
}

// MARK: - Управление меню
- (void)toggleMenu {
    _menuVisible = !_menuVisible;
    _menuPanel.hidden = !_menuVisible;
    
    if (_menuVisible) {
        [self updateMenuPosition];
        [self updateStatuses];
    }
}

- (void)hideMenu {
    _menuVisible = NO;
    _menuPanel.hidden = YES;
}

- (void)updateMenuPosition {
    CGRect frame = _menuPanel.frame;
    frame.origin.x = _menuButton.frame.origin.x;
    frame.origin.y = CGRectGetMaxY(_menuButton.frame) + 2;
    
    if (frame.origin.y + frame.size.height > _overlayWindow.bounds.size.height - 20) {
        frame.origin.y = _menuButton.frame.origin.y - frame.size.height - 2;
    }
    
    if (frame.origin.x + frame.size.width > _overlayWindow.bounds.size.width - 5) {
        frame.origin.x = _overlayWindow.bounds.size.width - frame.size.width - 5;
    }
    
    _menuPanel.frame = frame;
}

- (void)functionTapped:(UITapGestureRecognizer *)tap {
    UIView *row = tap.view;
    int index = (int)row.tag;
    
    NSArray *keys = @[@"clicker", @"fps", @"potato", @"bright", @"night", @"stretch"];
    NSArray *names = @[@"Автокликер", @"FPS Unlock", @"Потато режим", @"Яркость+", @"Ночной режим", @"Растяжение"];
    
    if (index < keys.count) {
        NSString *key = keys[index];
        std::string k = [key UTF8String];
        
        _functions[k] = !_functions[k];
        
        [self executeFunction:k];
        
        [self showNotification:[NSString stringWithFormat:@"%@ %@", names[index], _functions[k] ? @"✅" : @"❌"]];
        
        UILabel *status = [row viewWithTag:100];
        if (status) {
            status.text = _functions[k] ? @"✅" : @"⚪";
            status.textColor = _functions[k] ? [UIColor greenColor] : [UIColor grayColor];
        }
        
        if (k == "stretch" && !_functions[k]) {
            [self resetStretch];
        }
    }
}

- (void)updateStatuses {
    NSArray *keys = @[@"clicker", @"fps", @"potato", @"bright", @"night", @"stretch"];
    
    for (int i = 0; i < _menuPanel.subviews.count - 1; i++) {
        UIView *row = _menuPanel.subviews[i];
        UILabel *status = [row viewWithTag:100];
        if (status && i < keys.count) {
            std::string k = [keys[i] UTF8String];
            status.text = _functions[k] ? @"✅" : @"⚪";
            status.textColor = _functions[k] ? [UIColor greenColor] : [UIColor grayColor];
        }
    }
}

// MARK: - Функции игры
- (void)executeFunction:(std::string)func {
    if (func == "clicker") {
        if (_functions["clicker"]) {
            __weak GameHelper *weakSelf = self;
            _autoClickerRunning = YES;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                GameHelper *strongSelf = weakSelf;
                while (strongSelf && strongSelf->_functions["clicker"]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // Здесь код для автокликера
                    });
                    [NSThread sleepForTimeInterval:0.05];
                    strongSelf = weakSelf;
                }
                if (strongSelf) {
                    strongSelf->_autoClickerRunning = NO;
                }
            });
        }
    }
    else if (func == "fps") {
        if (_functions["fps"]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"FPSUnlock"];
        }
    }
    else if (func == "potato") {
        if (_functions["potato"]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"LowQualityMode"];
        }
    }
    else if (func == "bright") {
        if (_functions["bright"]) {
            [UIScreen mainScreen].brightness = 1.0;
        } else {
            [UIScreen mainScreen].brightness = _normalBrightness;
        }
    }
    else if (func == "night") {
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        UIView *existingOverlay = [mainWindow viewWithTag:777];
        
        if (_functions["night"] && !existingOverlay) {
            UIView *overlay = [[UIView alloc] initWithFrame:mainWindow.bounds];
            overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.3];
            overlay.tag = 777;
            overlay.userInteractionEnabled = NO;
            [mainWindow addSubview:overlay];
        } else if (!_functions["night"] && existingOverlay) {
            [existingOverlay removeFromSuperview];
        }
    }
    else if (func == "stretch") {
        if (_functions["stretch"]) {
            [self showNotification:@"🔍 Используйте щипок для растяжения"];
        }
    }
}

// MARK: - Уведомления
- (void)showNotification:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_notificationLabel.text = text;
        self->_notificationLabel.alpha = 1.0;
        
        [UIView animateWithDuration:0.2 delay:1.2 options:0 animations:^{
            self->_notificationLabel.alpha = 0.0;
        } completion:nil];
    });
}

@end

// Глобальный экземпляр
static GameHelper *g_helper = nil;

extern "C" {
    void init_game_helper() {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            g_helper = [[GameHelper alloc] init];
            [g_helper createUI];
        });
    }
    
    void cleanup_game_helper() {
        g_helper = nil;
    }
    
    __attribute__((constructor)) static void on_load() {
        init_game_helper();
    }
    
    __attribute__((destructor)) static void on_unload() {
        cleanup_game_helper();
    }
}
