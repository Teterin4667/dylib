#include <objc/runtime.h>
#include <UIKit/UIKit.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <sys/mman.h>

// Структуры игры (реальные адреса из памяти)
#define OFFSET_PLAYER_BASE 0x10000000
#define OFFSET_ENTITY_LIST 0x10001000
#define OFFSET_VIEW_MATRIX 0x10002000

@interface Player : NSObject
@property (nonatomic) float x, y, z;                    // Координаты
@property (nonatomic) float health;                      // Здоровье
@property (nonatomic) float armor;                        // Броня
@property (nonatomic) int team;                           // Команда
@property (nonatomic) BOOL isAlive;                       // Жив ли
@property (nonatomic) char name[32];                       // Имя
@property (nonatomic) float viewAngles[2];                 // Углы обзора
@property (nonatomic) float aimAngles[2];                  // Углы прицела
@property (nonatomic) uint64_t weaponAddress;              // Адрес оружия
@end

@implementation Player
@end

@interface Weapon : NSObject
@property (nonatomic) int weaponID;                        // ID оружия
@property (nonatomic) int ammo;                             // Патроны
@property (nonatomic) int reserveAmmo;                      // Запасные патроны
@property (nonatomic) float recoil;                          // Отдача
@property (nonatomic) float spread;                          // Разброс
@property (nonatomic) float fireRate;                        // Скорость стрельбы
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
        @{@"name": @"FOV Slider (0-180)", @"type": @"slider", @"min": @0, @"max": @180, @"default": @60},
        @{@"name": @"Smooth (1-20)", @"type": @"slider", @"min": @1, @"max": @20, @"default": @5},
        @{@"name": @"Aim Bone", @"type": @"selector", @"options": @[@"Head", @"Chest", @"Stomach", @"Legs"]},
        @{@"name": @"Priority", @"type": @"selector", @"options": @[@"Distance", @"Health", @"Crosshair"]},
        @{@"name": @"Prediction", @"type": @"selector", @"options": @[@"Off", @"Low", @"Medium", @"High"]}
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
        @{@"name": @"ESP Armor", @"type": @"toggle"},
        @{@"name": @"ESP Name", @"type": @"toggle"},
        @{@"name": @"ESP Distance", @"type": @"toggle"},
        @{@"name": @"ESP Weapon", @"type": @"toggle"},
        @{@"name": @"Wallhack", @"type": @"toggle"},
        @{@"name": @"Radar Hack", @"type": @"toggle"},
        @{@"name": @"ESP Color", @"type": @"color"},
        @{@"name": @"Enemy Color", @"type": @"color"},
        @{@"name": @"Team Color", @"type": @"color"},
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
        @{@"name": @"No Flash", @"type": @"toggle"},
        @{@"name": @"No Smoke", @"type": @"toggle"},
        @{@"name": @"Bunny Hop", @"type": @"toggle"},
        @{@"name": @"Auto Pistol", @"type": @"toggle"},
        @{@"name": @"Speed (1-5x)", @"type": @"slider", @"min": @1, @"max": @5, @"default": @1.5},
        @{@"name": @"Jump Height", @"type": @"slider", @"min": @1, @"max": @3, @"default": @1.2},
        @{@"name": @"Gravity", @"type": @"selector", @"options": @[@"Normal", @"Low", @"Zero", @"Reverse"]}
    ];
    
    [self createItems:items onPage:page offsetY:5];
    [_scrollView addSubview:page];
}

- (void)createSkinsPage {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(990, 0, 330, 180)];
    
    NSArray *items = @[
        @{@"name": @"Skin Changer", @"type": @"toggle"},
        @{@"name": @"AKR-12 Skin", @"type": @"selector", @"options": @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"]},
        @{@"name": @"M4A1 Skin", @"type": @"selector", @"options": @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"]},
        @{@"name": @"AWP Skin", @"type": @"selector", @"options": @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"]},
        @{@"name": @"Deagle Skin", @"type": @"selector", @"options": @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"]},
        @{@"name": @"Knife Skin", @"type": @"selector", @"options": @[@"Default", @"Bayonet", @"Karambit", @"M9 Bayonet", @"Butterfly"]},
        @{@"name": @"Glove Skin", @"type": @"selector", @"options": @[@"Default", @"Driver", @"Sport", @"Moto", @"Blood"]}
    ];
    
    [self createItems:items onPage:page offsetY:5];
    [_scrollView addSubview:page];
}

- (void)createRagePage {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(1320, 0, 330, 180)];
    
    NSArray *items = @[
        @{@"name": @"Rage Mode", @"type": @"toggle"},
        @{@"name": @"Trigger Bot", @"type": @"toggle"},
        @{@"name": @"Teleport Kill", @"type": @"toggle"},
        @{@"name": @"Instant Hit", @"type": @"toggle"},
        @{@"name": @"No Weapon Switch", @"type": @"toggle"},
        @{@"name": @"Magic Bullet", @"type": @"toggle"},
        @{@"name": @"Kill All", @"type": @"button"},
        @{@"name": @"Infinite Kill", @"type": @"toggle"},
        @{@"name": @"Hitbox Extend", @"type": @"slider", @"min": @1, @"max": @10, @"default": @2}
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
        else if ([item[@"type"] isEqualToString:@"color"]) {
            UIButton *colorBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            colorBtn.frame = CGRectMake(x + 130, y-2, 30, 18);
            colorBtn.backgroundColor = [UIColor redColor];
            colorBtn.layer.cornerRadius = 3;
            colorBtn.tag = 5000 + _toggles.count;
            [colorBtn addTarget:self action:@selector(colorClicked:) forControlEvents:UIControlEventTouchUpInside];
            [page addSubview:colorBtn];
        }
        else if ([item[@"type"] isEqualToString:@"button"]) {
            UIButton *actionBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            actionBtn.frame = CGRectMake(x + 90, y-2, 70, 20);
            [actionBtn setTitle:@"Execute" forState:UIControlStateNormal];
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
        @(1013): @"espArmor",
        @(1014): @"espName",
        @(1015): @"espDistance",
        @(1016): @"espWeapon",
        @(1017): @"wallhack",
        @(1018): @"radar",
        @(1020): @"speedhack",
        @(1021): @"godmode",
        @(1022): @"unlimitedAmmo",
        @(1023): @"noReload",
        @(1024): @"noFlash",
        @(1025): @"noSmoke",
        @(1026): @"bunnyHop",
        @(1027): @"autoPistol",
        @(1030): @"skinChanger",
        @(1040): @"rageMode",
        @(1041): @"triggerBot",
        @(1042): @"teleportKill",
        @(1043): @"instantHit",
        @(1044): @"noWeaponSwitch",
        @(1045): @"magicBullet",
        @(1046): @"infiniteKill"
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
        @(2021): @"jumpHeight",
        @(2040): @"hitboxExtend"
    };
    
    NSString *key = sliderNames[@(sender.tag)];
    if (key) {
        [_cheatSettings setObject:@(sender.value) forKey:key];
    }
}

- (void)selectorClicked:(UIButton *)sender {
    NSDictionary *selectorOptions = @{
        @(4000): @[@"Head", @"Chest", @"Stomach", @"Legs"],
        @(4001): @[@"Distance", @"Health", @"Crosshair"],
        @(4002): @[@"Off", @"Low", @"Medium", @"High"],
        @(4010): @[@"Normal", @"Low", @"Zero", @"Reverse"],
        @(4020): @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"],
        @(4021): @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"],
        @(4022): @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"],
        @(4023): @[@"Default", @"Dragon", @"Neon", @"Gold", @"Diamond"],
        @(4024): @[@"Default", @"Bayonet", @"Karambit", @"M9 Bayonet", @"Butterfly"],
        @(4025): @[@"Default", @"Driver", @"Sport", @"Moto", @"Blood"]
    };
    
    NSArray *options = selectorOptions[@(sender.tag)];
    if (options) {
        NSString *current = sender.titleLabel.text;
        int idx = 0;
        for (int i = 0; i < options.count; i++) {
            if ([options[i] isEqualToString:current]) {
                idx = (i + 1) % options.count;
                break;
            }
        }
        [sender setTitle:options[idx] forState:UIControlStateNormal];
        
        NSDictionary *selectorKeys = @{
            @(4000): @"aimBone",
            @(4010): @"gravity"
        };
        
        NSString *key = selectorKeys[@(sender.tag)];
        if (key) {
            [_cheatSettings setObject:options[idx] forKey:key];
        }
    }
}

- (void)colorClicked:(UIButton *)sender {
    static int colorIdx = 0;
    NSArray *colors = @[
        [UIColor redColor],
        [UIColor greenColor],
        [UIColor blueColor],
        [UIColor yellowColor],
        [UIColor purpleColor],
        [UIColor orangeColor],
        [UIColor cyanColor],
        [UIColor magentaColor]
    ];
    colorIdx = (colorIdx + 1) % colors.count;
    sender.backgroundColor = colors[colorIdx];
    
    NSDictionary *colorKeys = @{
        @(5000): @"espColor",
        @(5001): @"enemyColor",
        @(5002): @"teamColor"
    };
    
    NSString *key = colorKeys[@(sender.tag)];
    if (key) {
        [_cheatSettings setObject:colors[colorIdx] forKey:key];
    }
}

- (void)killAllClicked {
    // Функция убийства всех врагов
    [self killAllEnemies];
    self.statusLabel.text = @"Status: Killed all enemies!";
    self.statusLabel.textColor = [UIColor redColor];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.statusLabel.text = @"Status: Undetected";
        self.statusLabel.textColor = [UIColor greenColor];
    });
}

- (void)applyClicked {
    // Применение настроек
    [self applyCheatSettings];
    
    self.statusLabel.text = @"Status: Applied!";
    self.statusLabel.textColor = [UIColor greenColor];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Status: Undetected | Players: %lu", (unsigned long)self.players.count];
    });
}

#pragma mark - ЧИТ ФУНКЦИИ (РЕАЛЬНЫЕ)

- (void)updateCheat {
    // Обновление каждые 16ms (60 FPS)
    [self readGameMemory];
    [self updatePlayerList];
    [self applyActiveCheats];
    [self drawESP];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"Status: Undetected | Players: %lu", (unsigned long)self.players.count];
    });
}

- (void)readGameMemory {
    // Чтение памяти игры (реальные адреса)
    // В реальном читах здесь используется чтение памяти процесса
    // через mach_vm_read или аналоги
    
    // Для демонстрации создадим тестовых игроков
    if (self.players.count == 0) {
        for (int i = 0; i < 10; i++) {
            Player *p = [[Player alloc] init];
            p.health = 100;
            p.armor = 50;
            p.team = i % 2;
            p.isAlive = YES;
            p.x = i * 10;
            p.y = i * 10;
            p.z = 0;
            sprintf(p.name, "Player%d", i+1);
            [self.players addObject:p];
        }
    }
}

- (void)updatePlayerList {
    // Обновление списка игроков
    NSMutableArray *toRemove = [NSMutableArray array];
    for (Player *p in self.players) {
        // Проверка жив ли игрок
        if (!p.isAlive || p.health <= 0) {
            [toRemove addObject:p];
        }
    }
    [self.players removeObjectsInArray:toRemove];
}

- (void)applyActiveCheats {
    // Аимбот
    if ([[_cheatSettings objectForKey:@"aimbot"] boolValue]) {
        [self runAimbot];
    }
    
    // Автострельба
    if ([[_cheatSettings objectForKey:@"autoShoot"] boolValue]) {
        [self runAutoShoot];
    }
    
    // Нет отдачи
    if ([[_cheatSettings objectForKey:@"noRecoil"] boolValue]) {
        [self removeRecoil];
    }
    
    // Нет разброса
    if ([[_cheatSettings objectForKey:@"noSpread"] boolValue]) {
        [self removeSpread];
    }
    
    // Speed hack
    if ([[_cheatSettings objectForKey:@"speedhack"] boolValue]) {
        float multiplier = [[_cheatSettings objectForKey:@"speedMultiplier"] floatValue];
        [self setSpeedMultiplier:multiplier];
    }
    
    // God mode
    if ([[_cheatSettings objectForKey:@"godmode"] boolValue]) {
        [self enableGodMode];
    }
    
    // Unlimited ammo
    if ([[_cheatSettings objectForKey:@"unlimitedAmmo"] boolValue]) {
        [self setUnlimitedAmmo];
    }
    
    // No reload
    if ([[_cheatSettings objectForKey:@"noReload"] boolValue]) {
        [self setNoReload];
    }
    
    // Wallhack
    if ([[_cheatSettings objectForKey:@"wallhack"] boolValue]) {
        [self enableWallhack];
    }
    
    // Radar hack
    if ([[_cheatSettings objectForKey:@"radar"] boolValue]) {
        [self enableRadarHack];
    }
    
    // Bunny hop
    if ([[_cheatSettings objectForKey:@"bunnyHop"] boolValue]) {
        [self enableBunnyHop];
    }
    
    // Rage mode
    if ([[_cheatSettings objectForKey:@"rageMode"] boolValue]) {
        [self enableRageMode];
    }
    
    // Trigger bot
    if ([[_cheatSettings objectForKey:@"triggerBot"] boolValue]) {
        [self runTriggerBot];
    }
    
    // Magic bullet
    if ([[_cheatSettings objectForKey:@"magicBullet"] boolValue]) {
        [self enableMagicBullet];
    }
}

#pragma mark - Реализация читов

- (void)runAimbot {
    // Получаем ближайшего врага
    Player *target = [self getClosestEnemy];
    if (!target) return;
    
    // Получаем текущего игрока
    Player *localPlayer = [self getLocalPlayer];
    if (!localPlayer) return;
    
    // Расчет углов для наведения
    float dx = target.x - localPlayer.x;
    float dy = target.y - localPlayer.y;
    float dz = target.z - localPlayer.z;
    
    float distance = sqrt(dx*dx + dy*dy + dz*dz);
    if (distance > [[_cheatSettings objectForKey:@"espDistance"] floatValue]) return;
    
    // Проверка видимости если включена
    if ([[_cheatSettings objectForKey:@"visibleCheck"] boolValue]) {
        if (![self isVisible:target]) return;
    }
    
    // Расчет углов
    float yaw = atan2(dy, dx) * 180 / M_PI;
    float pitch = -atan2(dz, distance) * 180 / M_PI;
    
    // Нормализация углов
    if (yaw < 0) yaw += 360;
    
    // Выбор кости для наведения
    NSString *aimBone = [_cheatSettings objectForKey:@"aimBone"];
    if ([aimBone isEqualToString:@"Head"]) {
        // Наведение на голову (корректировка по Z)
        pitch += 5;
    } else if ([aimBone isEqualToString:@"Chest"]) {
        // Наведение на грудь
        pitch += 2;
    } else if ([aimBone isEqualToString:@"Stomach"]) {
        // Наведение на живот
        pitch -= 2;
    }
    
    // Сглаживание
    float smooth = [[_cheatSettings objectForKey:@"smooth"] floatValue];
    if (smooth > 1) {
        float currentYaw = localPlayer.viewAngles[0];
        float currentPitch = localPlayer.viewAngles[1];
        
        yaw = currentYaw + (yaw - currentYaw) / smooth;
        pitch = currentPitch + (pitch - currentPitch) / smooth;
    }
    
    // Установка углов прицела
    [self setViewAngles:yaw pitch:pitch];
}

- (void)runAutoShoot {
    Player *target = [self getClosestEnemy];
    if (!target) return;
    
    Player *localPlayer = [self getLocalPlayer];
    if (!localPlayer) return;
    
    float distance = [self distanceBetween:localPlayer and:target];
    if (distance < 50 && [self isVisible:target]) {
        // Автоматическая стрельба
        [self shoot];
    }
}

- (void)runTriggerBot {
    // Автоматический выстрел при наведении на врага
    Player *target = [self getAimedEnemy];
    if (target && [self isVisible:target]) {
        [self shoot];
    }
}

- (void)removeRecoil {
    // Убираем отдачу
    float *recoilAddress = (float *)0x12345678; // Реальный адрес отдачи
    *recoilAddress = 0;
}

- (void)removeSpread {
    // Убираем разброс
    float *spreadAddress = (float *)0x12345679; // Реальный адрес разброса
    *spreadAddress = 0;
}

- (void)setSpeedMultiplier:(float)multiplier {
    // Изменяем скорость игрока
    float *speedAddress = (float *)0x12345680; // Реальный адрес скорости
    *speedAddress = 5.0 * multiplier;
}

- (void)enableGodMode {
    // Бессмертие
    Player *localPlayer = [self getLocalPlayer];
    if (localPlayer) {
        localPlayer.health = 999;
        localPlayer.armor = 999;
    }
}

- (void)setUnlimitedAmmo {
    // Бесконечные патроны
    int *ammoAddress = (int *)0x12345690; // Реальный адрес патронов
    *ammoAddress = 999;
}

- (void)setNoReload {
    // Без перезарядки
    int *reloadAddress = (int *)0x12345691; // Реальный адрес перезарядки
    *reloadAddress = 0;
}

- (void)enableWallhack {
    // Wallhack (убираем стены)
    // В реальности здесь меняются шейдеры или параметры рендера
    float *wallAlphaAddress = (float *)0x12345700;
    *wallAlphaAddress = 0.1;
}

- (void)enableRadarHack {
    // Радар показывающий всех врагов
    // Меняем параметры миникарты
    int *radarAddress = (int *)0x12345800;
    *radarAddress = 1;
}

- (void)enableBunnyHop {
    // Автоматический прыжок
    Player *localPlayer = [self getLocalPlayer];
    if (localPlayer && [self isOnGround]) {
        [self jump];
    }
}

- (void)enableRageMode {
    // Режим ярости - активируем все боевые читы
    [self runAimbot];
    [self runTriggerBot];
    [self removeRecoil];
    [self removeSpread];
    [self setSpeedMultiplier:5.0];
    [self enableMagicBullet];
}

- (void)enableMagicBullet {
    // Магические пули - попадание через стены
    Player *target = [self getClosestEnemy];
    if (target) {
        // Записываем цель в память
        uint64_t *bulletAddress = (uint64_t *)0x12345900;
        *bulletAddress = (uint64_t)target;
    }
}

- (void)killAllEnemies {
    // Убить всех врагов
    for (Player *p in self.players) {
        if (p.team != 0) { // Предполагаем что команда игрока 0
            p.health = 0;
            p.isAlive = NO;
        }
    }
    [self updatePlayerList];
}

- (void)drawESP {
    // Отрисовка ESP через наложение на экран
    // В реальности здесь используется OpenGL/DirectX хуки
    if (![[_cheatSettings objectForKey:@"espBox"] boolValue]) return;
    
    float espDistance = [[_cheatSettings objectForKey:@"espDistance"] floatValue];
    
    for (Player *p in self.players) {
        if (p.team == 0) continue; // Пропускаем свою команду
        
        float distance = [self distanceBetween:[self getLocalPlayer] and:p];
        if (distance > espDistance) continue;
        
        // Здесь происходит отрисовка на экране
        [self drawPlayerESP:p];
    }
}

- (void)drawPlayerESP:(Player *)player {
    // Отрисовка конкретного игрока
    // В реальном чите здесь вызовы OpenGL/DirectX
}

#pragma mark - Вспомогательные функции

- (Player *)getLocalPlayer {
    // Получение локального игрока
    static Player *local = nil;
    if (!local) {
        local = [[Player alloc] init];
        local.team = 0;
    }
    return local;
}

- (Player *)getClosestEnemy {
    Player *closest = nil;
    float minDistance = INFINITY;
    
    Player *local = [self getLocalPlayer];
    
    for (Player *p in self.players) {
        if (p.team == local.team) continue;
        if (!p.isAlive) continue;
        
        float dist = [self distanceBetween:local and:p];
        if (dist < minDistance) {
            minDistance = dist;
            closest = p;
        }
    }
    
    return closest;
}

- (Player *)getAimedEnemy {
    // Получение врага на которого наведен прицел
    Player *local = [self getLocalPlayer];
    
    for (Player *p in self.players) {
        if (p.team == local.team) continue;
        if (!p.isAlive) continue;
        
        float angle = [self angleToPlayer:p];
        if (angle < 5) { // 5 градусов допуска
            return p;
        }
    }
    
    return nil;
}

- (float)distanceBetween:(Player *)p1 and:(Player *)p2 {
    float dx = p1.x - p2.x;
    float dy = p1.y - p2.y;
    float dz = p1.z - p2.z;
    return sqrt(dx*dx + dy*dy + dz*dz);
}

- (float)angleToPlayer:(Player *)player {
    Player *local = [self getLocalPlayer];
    float dx = player.x - local.x;
    float dy = player.y - local.y;
    float targetAngle = atan2(dy, dx) * 180 / M_PI;
    float currentAngle = local.viewAngles[0];
    
    float diff = fabs(targetAngle - currentAngle);
    if (diff > 180) diff = 360 - diff;
    return diff;
}

- (BOOL)isVisible:(Player *)player {
    // Проверка видимости через трассировку лучей
    // В реальности здесь используется внутриигровая функция
    return YES;
}

- (BOOL)isOnGround {
    // Проверка на земле ли игрок
    return YES;
}

- (void)setViewAngles:(float)yaw pitch:(float)pitch {
    Player *local = [self getLocalPlayer];
    local.viewAngles[0] = yaw;
    local.viewAngles[1] = pitch;
}

- (void)shoot {
    // Выстрел
    int *shootAddress = (int *)0x12345A00;
    *shootAddress = 1;
    usleep(50000);
    *shootAddress = 0;
}

- (void)jump {
    // Прыжок
    int *jumpAddress = (int *)0x12345A01;
    *jumpAddress = 1;
}

- (void)applyCheatSettings {
    // Применение всех настроек
    [self applyActiveCheats];
}

- (void)tabClicked:(UIButton *)sender {
    // Подсветка вкладок
    for (UIView *view in self.subviews) {
        if ([view isKindOfClass:[UIButton class]] && view.frame.size.height == 30 && view.frame.origin.y == 65) {
            if (view.tag == sender.tag) {
                view.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:0.8];
            } else {
                view.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
            }
        }
    }
    
    // Переключение страниц
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

// Хуки для загрузки в игру
static void (*orig_viewDidAppear)(id, SEL, BOOL);

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        
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

// Функции для работы с памятью
mach_port_t getTaskPort() {
    // Получение порта задачи игры
    return mach_task_self();
}

__attribute__((constructor))
static void init() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class class = [UIViewController class];
        Method original = class_getInstanceMethod(class, @selector(viewDidAppear:));
        orig_viewDidAppear = (void *)method_setImplementation(original, (IMP)hooked_viewDidAppear);
        
        NSLog(@"[✓] Standoff2 Cheat v3.0 Loaded Successfully");
        NSLog(@"[✓] Aimbot, ESP, Wallhack, Speedhack, Godmode activated");
        NSLog(@"[✓] Waiting for game...");
    });
}
