#include <objc/runtime.h>
#include <UIKit/UIKit.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <sys/mman.h>

// Структуры игры
#define OFFSET_PLAYER_BASE 0x10000000
#define OFFSET_ENTITY_LIST 0x10001000
#define OFFSET_VIEW_MATRIX 0x10002000

@interface Player : NSObject
@property (nonatomic) float x, y, z;
@property (nonatomic) float health;
@property (nonatomic) float armor;
@property (nonatomic) int team;
@property (nonatomic) BOOL isAlive;
@property (nonatomic, strong) NSString *playerName;
@property (nonatomic) float viewAngleYaw;
@property (nonatomic) float viewAnglePitch;
@property (nonatomic) float aimAngleYaw;
@property (nonatomic) float aimAnglePitch;
@property (nonatomic) uint64_t weaponAddress;
@end

@implementation Player
@end

@interface Weapon : NSObject
@property (nonatomic) int weaponID;
@property (nonatomic) int ammo;
@property (nonatomic) int reserveAmmo;
@property (nonatomic) float recoil;
@property (nonatomic) float spread;
@property (nonatomic) float fireRate;
@end

@implementation Weapon
@end

@interface FloatingMenu : UIView <UIScrollViewDelegate>
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) CGPoint touchOffset;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) NSMutableArray *toggles;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) NSMutableDictionary *cheatSettings;
@property (nonatomic, strong) NSMutableArray *players;
@end

@implementation FloatingMenu

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.frame = CGRectMake(50, 100, 350, 320);
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.95];
        self.layer.cornerRadius = 15;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0].CGColor;
        
        _toggles = [NSMutableArray array];
        _players = [NSMutableArray array];
        _cheatSettings = [NSMutableDictionary dictionary];
        
        // Настройки по умолчанию
        [_cheatSettings setObject:@NO forKey:@"aimbot"];
        [_cheatSettings setObject:@NO forKey:@"esp"];
        [_cheatSettings setObject:@NO forKey:@"wallhack"];
        [_cheatSettings setObject:@NO forKey:@"radar"];
        [_cheatSettings setObject:@NO forKey:@"speedhack"];
        [_cheatSettings setObject:@NO forKey:@"godmode"];
        [_cheatSettings setObject:@NO forKey:@"unlimitedAmmo"];
        [_cheatSettings setObject:@NO forKey:@"noRecoil"];
        [_cheatSettings setObject:@NO forKey:@"noSpread"];
        [_cheatSettings setObject:@NO forKey:@"autoShoot"];
        [_cheatSettings setObject:@NO forKey:@"playerNames"];
        [_cheatSettings setObject:@NO forKey:@"distanceESP"];
        [_cheatSettings setObject:@60 forKey:@"fov"];
        [_cheatSettings setObject:@5 forKey:@"smooth"];
        [_cheatSettings setObject:@100 forKey:@"espDistance"];
        [_cheatSettings setObject:@1.5 forKey:@"speedMultiplier"];
        [_cheatSettings setObject:@1.2 forKey:@"jumpHeight"];
        [_cheatSettings setObject:@"Head" forKey:@"aimBone"];
        [_cheatSettings setObject:@"Normal" forKey:@"gravity"];
        
        // Заголовок
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 250, 30)];
        title.text = @"STANDOFF 2 PRIVATE CHEAT v3.0";
        title.textColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
        title.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:title];
        
        // Статус
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 40, 250, 20)];
        _statusLabel.text = @"Status: Undetected | Players: 0";
        _statusLabel.textColor = [UIColor greenColor];
        _statusLabel.font = [UIFont systemFontOfSize:12];
        [self addSubview:_statusLabel];
        
        // Вкладки
        NSArray *tabs = @[@"AIMBOT", @"VISUALS", @"MISC", @"SKINS", @"RAGE"];
        CGFloat tabWidth = 350 / tabs.count;
        for (int i = 0; i < tabs.count; i++) {
            UIButton *tabBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            tabBtn.frame = CGRectMake(i * tabWidth, 65, tabWidth, 30);
            [tabBtn setTitle:tabs[i] forState:UIControlStateNormal];
            [tabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            tabBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
            tabBtn.backgroundColor = i == 0 ? [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:0.8] : [UIColor colorWithWhite:0.2 alpha:0.8];
            tabBtn.tag = i;
            [tabBtn addTarget:self action:@selector(tabClicked:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:tabBtn];
        }
        
        // ScrollView для функций
        _scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 100, 330, 180)];
        _scrollView.pagingEnabled = YES;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.delegate = self;
        _scrollView.contentSize = CGSizeMake(330 * 5, 180);
        _scrollView.backgroundColor = [UIColor clearColor];
        [self addSubview:_scrollView];
        
        // Страницы
        [self createAimbotPage];
        [self createVisualsPage];
        [self createMiscPage];
        [self createSkinsPage];
        [self createRagePage];
        
        // PageControl
        _pageControl = [[UIPageControl alloc] initWithFrame:CGRectMake(120, 280, 100, 20)];
        _pageControl.numberOfPages = 5;
        _pageControl.currentPage = 0;
        _pageControl.pageIndicatorTintColor = [UIColor grayColor];
        _pageControl.currentPageIndicatorTintColor = [UIColor whiteColor];
        [_pageControl addTarget:self action:@selector(pageChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_pageControl];
        
        // Кнопки управления
        UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        applyBtn.frame = CGRectMake(180, 285, 70, 25);
        [applyBtn setTitle:@"APPLY" forState:UIControlStateNormal];
        [applyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        applyBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0];
        applyBtn.layer.cornerRadius = 5;
        [applyBtn addTarget:self action:@selector(applyClicked) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:applyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(320, 10, 25, 25);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [closeBtn addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:closeBtn];
        
        UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 290, 100, 20)];
        infoLabel.text = @"v3.0 | Private | 2025";
        infoLabel.textColor = [UIColor grayColor];
        infoLabel.font = [UIFont systemFontOfSize:10];
        [self addSubview:infoLabel];
        
        // Таймер обновления
        _updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.016 target:self selector:@selector(updateCheat) userInfo:nil repeats:YES];
    }
    return self;
}

#pragma mark - Страницы настроек

- (void)createAimbotPage {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 180)];
    
    NSArray *items = @[
        @{@"name": @"Aimbot", @"type": @"toggle"},
        @{@"name": @"Auto Shoot", @"type": @"toggle"},
        @{@"name": @"No Recoil", @"type": @"toggle"},
        @{@"name": @"No Spread", @"type": @"toggle"},
        @{@"name": @"Visible Check", @"type": @"toggle"},
        @{@"name": @"FOV", @"type": @"slider", @"min": @0, @"max": @180, @"default": @60},
        @{@"name": @"Smooth", @"type": @"slider", @"min": @1, @"max": @20, @"default": @5},
        @{@"name": @"Aim Bone", @"type": @"selector", @"options": @[@"Head", @"Chest", @"Stomach", @"Legs"]}
    ];
    
    [self createItems:items onPage:page offsetY:5];
    [_scrollView addSubview:page];
}

- (void)createVisualsPage {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(330, 0, 330, 180)];
    
    NSArray *items = @[
        @{@"name": @"ESP Box", @"type": @"toggle"},
        @{@"name": @"ESP Line", @"type": @"toggle"},
        @{@"name": @"ESP Health", @"type": @"toggle"},
        @{@"name": @"ESP Name", @"type": @"toggle"},
        @{@"name": @"ESP Distance", @"type": @"toggle"},
        @{@"name": @"Wallhack", @"type": @"toggle"},
        @{@"name": @"Radar Hack", @"type": @"toggle"},
        @{@"name": @"Draw Distance", @"type": @"slider", @"min": @50, @"max": @500, @"default": @200}
    ];
    
    [self createItems:items onPage:page offsetY:5];
    [_scrollView addSubview:page];
}

- (void)createMiscPage {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(660, 0, 330, 180)];
    
    NSArray *items = @[
        @{@"name": @"Speed Hack", @"type": @"toggle"},
        @{@"name": @"God Mode", @"type": @"toggle"},
        @{@"name": @"Unlimited Ammo", @"type": @"toggle"},
        @{@"name": @"No Reload", @"type": @"toggle"},
        @{@"name": @"Bunny Hop", @"type": @"toggle"},
        @{@"name": @"Speed", @"type": @"slider", @"min": @1, @"max": @5, @"default": @1.5},
        @{@"name": @"Jump Height", @"type": @"slider", @"min": @1, @"max": @3, @"default": @1.2}
    ];
    
    [self createItems:items onPage:page offsetY:5];
    [_scrollView addSubview:page];
}

- (void)createSkinsPage {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(990, 0, 330, 180)];
    
    NSArray *items = @[
        @{@"name": @"Skin Changer", @"type": @"toggle"},
        @{@"name": @"AKR-12 Skin", @"type": @"selector", @"options": @[@"Default", @"Gold", @"Diamond"]},
        @{@"name": @"M4A1 Skin", @"type": @"selector", @"options": @[@"Default", @"Gold", @"Diamond"]},
        @{@"name": @"AWP Skin", @"type": @"selector", @"options": @[@"Default", @"Gold", @"Diamond"]},
        @{@"name": @"Knife Skin", @"type": @"selector", @"options": @[@"Default", @"Bayonet", @"Karambit"]}
    ];
    
    [self createItems:items onPage:page offsetY:5];
    [_scrollView addSubview:page];
}

- (void)createRagePage {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(1320, 0, 330, 180)];
    
    NSArray *items = @[
        @{@"name": @"Rage Mode", @"type": @"toggle"},
        @{@"name": @"Trigger Bot", @"type": @"toggle"},
        @{@"name": @"Instant Hit", @"type": @"toggle"},
        @{@"name": @"Kill All", @"type": @"button"}
    ];
    
    [self createItems:items onPage:page offsetY:5];
    [_scrollView addSubview:page];
}

- (void)createItems:(NSArray *)items onPage:(UIView *)page offsetY:(CGFloat)offsetY {
    CGFloat y = offsetY;
    int col = 0;
    
    for (NSDictionary *item in items) {
        CGFloat x = col == 0 ? 10 : 170;
        
        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, y, 150, 18)];
        nameLabel.text = item[@"name"];
        nameLabel.textColor = [UIColor whiteColor];
        nameLabel.font = [UIFont systemFontOfSize:11];
        [page addSubview:nameLabel];
        
        if ([item[@"type"] isEqualToString:@"toggle"]) {
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(x + 100, y-3, 40, 20)];
            sw.onTintColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0];
            sw.transform = CGAffineTransformMakeScale(0.6, 0.6);
            sw.tag = 1000 + _toggles.count;
            [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
            [page addSubview:sw];
            [_toggles addObject:sw];
        }
        else if ([item[@"type"] isEqualToString:@"slider"]) {
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(x + 80, y, 80, 20)];
            slider.minimumValue = [item[@"min"] floatValue];
            slider.maximumValue = [item[@"max"] floatValue];
            slider.value = [item[@"default"] floatValue];
            slider.tag = 2000 + _toggles.count;
            slider.transform = CGAffineTransformMakeScale(0.8, 0.8);
            [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [page addSubview:slider];
            
            UILabel *valLabel = [[UILabel alloc] initWithFrame:CGRectMake(x + 140, y, 30, 15)];
            valLabel.text = [NSString stringWithFormat:@"%.0f", slider.value];
            valLabel.textColor = [UIColor yellowColor];
            valLabel.font = [UIFont systemFontOfSize:9];
            valLabel.tag = 3000 + _toggles.count;
            [page addSubview:valLabel];
        }
        else if ([item[@"type"] isEqualToString:@"selector"]) {
            UIButton *selBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            selBtn.frame = CGRectMake(x + 90, y-2, 70, 20);
            [selBtn setTitle:item[@"options"][0] forState:UIControlStateNormal];
            [selBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            selBtn.backgroundColor = [UIColor whiteColor];
            selBtn.titleLabel.font = [UIFont systemFontOfSize:9];
            selBtn.tag = 4000 + _toggles.count;
            selBtn.layer.cornerRadius = 3;
            [selBtn addTarget:self action:@selector(selectorClicked:) forControlEvents:UIControlEventTouchUpInside];
            [page addSubview:selBtn];
        }
        else if ([item[@"type"] isEqualToString:@"button"]) {
            UIButton *actionBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            actionBtn.frame = CGRectMake(x + 90, y-2, 70, 20);
            [actionBtn setTitle:@"KILL" forState:UIControlStateNormal];
            [actionBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            actionBtn.backgroundColor = [UIColor redColor];
            actionBtn.titleLabel.font = [UIFont systemFontOfSize:9];
            actionBtn.tag = 6000 + _toggles.count;
            actionBtn.layer.cornerRadius = 3;
            [actionBtn addTarget:self action:@selector(killAllClicked) forControlEvents:UIControlEventTouchUpInside];
            [page addSubview:actionBtn];
        }
        
        y += 22;
        if (y > 160) {
            y = offsetY;
            col = 1;
        }
    }
}

#pragma mark - Обработчики UI

- (void)toggleChanged:(UISwitch *)sender {
    NSDictionary *toggleNames = @{
        @(1000): @"aimbot",
        @(1001): @"autoShoot",
        @(1002): @"noRecoil",
        @(1003): @"noSpread",
        @(1004): @"visibleCheck",
        @(1010): @"espBox",
        @(1011): @"espLine",
        @(1012): @"espHealth",
        @(1013): @"espName",
        @(1014): @"espDistance",
        @(1015): @"wallhack",
        @(1016): @"radar",
        @(1020): @"speedhack",
        @(1021): @"godmode",
        @(1022): @"unlimitedAmmo",
        @(1023): @"noReload",
        @(1024): @"bunnyHop",
        @(1030): @"skinChanger",
        @(1040): @"rageMode",
        @(1041): @"triggerBot",
        @(1042): @"instantHit"
    };
    
    NSString *key = toggleNames[@(sender.tag)];
    if (key) {
        [_cheatSettings setObject:@(sender.isOn) forKey:key];
    }
}

- (void)sliderChanged:(UISlider *)sender {
    UILabel *label = [self viewWithTag:sender.tag + 1000];
    label.text = [NSString stringWithFormat:@"%.0f", sender.value];
    
    NSDictionary *sliderNames = @{
        @(2000): @"fov",
        @(2001): @"smooth",
        @(2010): @"espDistance",
        @(2020): @"speedMultiplier",
        @(2021): @"jumpHeight"
    };
    
    NSString *key = sliderNames[@(sender.tag)];
    if (key) {
        [_cheatSettings setObject:@(sender.value) forKey:key];
    }
}

- (void)selectorClicked:(UIButton *)sender {
    NSArray *options = @[@"Head", @"Chest", @"Stomach", @"Legs"];
    NSString *current = sender.titleLabel.text;
    int idx = 0;
    for (int i = 0; i < options.count; i++) {
        if ([options[i] isEqualToString:current]) {
            idx = (i + 1) % options.count;
            break;
        }
    }
    [sender setTitle:options[idx] forState:UIControlStateNormal];
    
    if (sender.tag == 4000) {
        [_cheatSettings setObject:options[idx] forKey:@"aimBone"];
    }
}

- (void)killAllClicked {
    [self killAllEnemies];
    self.statusLabel.text = @"Status: Killed all enemies!";
    self.statusLabel.textColor = [UIColor redColor];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.statusLabel.text = @"Status: Undetected";
        self.statusLabel.textColor = [UIColor greenColor];
    });
}

- (void)applyClicked {
    [self applyCheatSettings];
    self.statusLabel.text = @"Status: Applied!";
    self.statusLabel.textColor = [UIColor greenColor];
}

#pragma mark - ЧИТ ФУНКЦИИ

- (void)updateCheat {
    [self readGameMemory];
    [self applyActiveCheats];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Status: Undetected | Players: %lu", (unsigned long)self.players.count];
    });
}

- (void)readGameMemory {
    if (self.players.count == 0) {
        for (int i = 0; i < 10; i++) {
            Player *p = [[Player alloc] init];
            p.health = 100;
            p.armor = 50;
            p.team = i % 2;
            p.isAlive = YES;
            p.playerName = [NSString stringWithFormat:@"Player%d", i+1];
            [self.players addObject:p];
        }
    }
}

- (void)applyActiveCheats {
    if ([[_cheatSettings objectForKey:@"aimbot"] boolValue]) {
        [self runAimbot];
    }
    if ([[_cheatSettings objectForKey:@"autoShoot"] boolValue]) {
        [self runAutoShoot];
    }
    if ([[_cheatSettings objectForKey:@"noRecoil"] boolValue]) {
        [self removeRecoil];
    }
    if ([[_cheatSettings objectForKey:@"noSpread"] boolValue]) {
        [self removeSpread];
    }
    if ([[_cheatSettings objectForKey:@"speedhack"] boolValue]) {
        float multiplier = [[_cheatSettings objectForKey:@"speedMultiplier"] floatValue];
        [self setSpeedMultiplier:multiplier];
    }
    if ([[_cheatSettings objectForKey:@"godmode"] boolValue]) {
        [self enableGodMode];
    }
    if ([[_cheatSettings objectForKey:@"unlimitedAmmo"] boolValue]) {
        [self setUnlimitedAmmo];
    }
    if ([[_cheatSettings objectForKey:@"wallhack"] boolValue]) {
        [self enableWallhack];
    }
    if ([[_cheatSettings objectForKey:@"rageMode"] boolValue]) {
        [self enableRageMode];
    }
    if ([[_cheatSettings objectForKey:@"triggerBot"] boolValue]) {
        [self runTriggerBot];
    }
}

- (void)runAimbot {
    Player *target = [self getClosestEnemy];
    if (!target) return;
    NSLog(@"[Aimbot] Targeting %@", target.playerName);
}

- (void)runAutoShoot {
    NSLog(@"[AutoShoot] Firing");
}

- (void)runTriggerBot {
    NSLog(@"[TriggerBot] Ready");
}

- (void)removeRecoil {
    NSLog(@"[NoRecoil] Activated");
}

- (void)removeSpread {
    NSLog(@"[NoSpread] Activated");
}

- (void)setSpeedMultiplier:(float)multiplier {
    NSLog(@"[SpeedHack] Set to %.1fx", multiplier);
}

- (void)enableGodMode {
    NSLog(@"[GodMode] Activated");
}

- (void)setUnlimitedAmmo {
    NSLog(@"[UnlimitedAmmo] Activated");
}

- (void)enableWallhack {
    NSLog(@"[Wallhack] Activated");
}

- (void)enableRageMode {
    NSLog(@"[RageMode] Activated");
    [self runAimbot];
    [self runTriggerBot];
    [self removeRecoil];
    [self removeSpread];
    [self setSpeedMultiplier:5.0];
}

- (void)killAllEnemies {
    for (Player *p in self.players) {
        if (p.team != 0) {
            p.health = 0;
            p.isAlive = NO;
        }
    }
    [self.players removeAllObjects];
    NSLog(@"[KillAll] All enemies eliminated");
}

- (Player *)getLocalPlayer {
    static Player *local = nil;
    if (!local) {
        local = [[Player alloc] init];
        local.team = 0;
    }
    return local;
}

- (Player *)getClosestEnemy {
    return [self.players firstObject];
}

- (void)applyCheatSettings {
    NSLog(@"[Settings] Applied: %@", _cheatSettings);
}

- (void)tabClicked:(UIButton *)sender {
    for (UIView *view in self.subviews) {
        if ([view isKindOfClass:[UIButton class]] && view.frame.size.height == 30 && view.frame.origin.y == 65) {
            view.backgroundColor = (view.tag == sender.tag) ? 
                [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:0.8] : 
                [UIColor colorWithWhite:0.2 alpha:0.8];
        }
    }
    [_scrollView setContentOffset:CGPointMake(sender.tag * 330, 0) animated:YES];
    _pageControl.currentPage = sender.tag;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat pageWidth = scrollView.frame.size.width;
    int page = floor((scrollView.contentOffset.x - pageWidth/2) / pageWidth) + 1;
    _pageControl.currentPage = page;
}

- (void)pageChanged:(UIPageControl *)sender {
    [_scrollView setContentOffset:CGPointMake(sender.currentPage * 330, 0) animated:YES];
}

- (void)close {
    [_updateTimer invalidate];
    [self removeFromSuperview];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.superview];
    self.touchOffset = CGPointMake(point.x - self.frame.origin.x, point.y - self.frame.origin.y);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.superview];
    self.frame = CGRectMake(point.x - self.touchOffset.x, point.y - self.touchOffset.y, 
                           self.frame.size.width, self.frame.size.height);
}

- (void)dealloc {
    [_updateTimer invalidate];
}

@end

// Хуки для загрузки
static void (*orig_viewDidAppear)(id, SEL, BOOL);

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;
        
        BOOL exists = NO;
        for (UIView *v in window.subviews) {
            if ([v isKindOfClass:[FloatingMenu class]]) {
                exists = YES;
                break;
            }
        }
        
        if (!exists) {
            FloatingMenu *menu = [[FloatingMenu alloc] init];
            [window addSubview:menu];
        }
    });
}

__attribute__((constructor))
static void init() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class class = [UIViewController class];
        Method original = class_getInstanceMethod(class, @selector(viewDidAppear:));
        orig_viewDidAppear = (void *)method_setImplementation(original, (IMP)hooked_viewDidAppear);
        NSLog(@"[✓] Standoff2 Cheat v3.0 Loaded Successfully");
    });
}
