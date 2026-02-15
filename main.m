#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <MobileCoreServices/MobileCoreServices.h>

// MARK: - Менеджер для работы с UDID PosterBoard
@interface UDIDManager : NSObject
+ (NSString *)getSavedUDID;
+ (void)saveUDID:(NSString *)udid;
+ (NSString *)promptForUDID;
+ (NSString *)detectPosterBoardUDID;
@end

@implementation UDIDManager

// Сохранение UDID в UserDefaults
+ (void)saveUDID:(NSString *)udid {
    [[NSUserDefaults standardUserDefaults] setObject:udid forKey:@"PosterBoardUDID"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Получение сохраненного UDID
+ (NSString *)getSavedUDID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"PosterBoardUDID"];
}

// Автоматическое определение UDID PosterBoard
+ (NSString *)detectPosterBoardUDID {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appsPath = @"/var/mobile/Containers/Data/Application";
    
    if ([fm fileExistsAtPath:appsPath]) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:appsPath error:nil];
        for (NSString *item in contents) {
            // Проверяем формат UUID
            if ([item length] == 36 && [item containsString:@"-"]) {
                NSString *appPath = [appsPath stringByAppendingPathComponent:item];
                NSString *metadataPath = [appPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
                
                if ([fm fileExistsAtPath:metadataPath]) {
                    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
                    NSString *identifier = metadata[@"MCMMetadataIdentifier"];
                    
                    if ([identifier isEqualToString:@"com.apple.PosterBoard"]) {
                        return item;
                    }
                }
            }
        }
    }
    return nil;
}

// Создание UI для ввода UDID
+ (NSString *)promptForUDID {
    NSString *saved = [self getSavedUDID];
    NSString *detected = [self detectPosterBoardUDID];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSString *result = saved ?: detected ?: @"";
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [PosterBoardManager getCurrentViewController];
        
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"Настройка PosterBoard" 
            message:[NSString stringWithFormat:@"Введите UDID PosterBoard\n\n%@\n\nКак найти:\n1. Установите Nugget\n2. Подключите iPhone\n3. Нажмите 'Read UDID'\n4. Скопируйте UDID приложения PosterBoard", 
                     detected ? [NSString stringWithFormat:@"Найден UDID: %@", detected] : @"UDID не найден"]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
            textField.text = saved;
            textField.keyboardType = UIKeyboardTypeDefault;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *udid = alert.textFields.firstObject.text;
            if (udid.length > 0) {
                [self saveUDID:udid];
                result = udid;
            }
            dispatch_semaphore_signal(semaphore);
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            dispatch_semaphore_signal(semaphore);
        }]];
        
        [topVC presentViewController:alert animated:YES completion:nil];
    });
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return result;
}

@end

// MARK: - Структуры для PosterBoard (iOS 16+)
@interface PosterBoardManager : NSObject
+ (void)injectToPosterBoard:(NSData *)wallpaperData withName:(NSString *)name;
+ (void)resetAppleCollections;
+ (void)createWallpaperInAppleCollections:(NSData *)wallpaperData withName:(NSString *)name;
+ (UIViewController *)getCurrentViewController;
+ (NSString *)getPosterBoardPath;
@end

@implementation PosterBoardManager

// Получение актуального пути PosterBoard для iOS 16+ с использованием UDID
+ (NSString *)getPosterBoardPath {
    NSString *udid = [UDIDManager getSavedUDID];
    
    if (!udid || udid.length == 0) {
        udid = [UDIDManager promptForUDID];
    }
    
    if (udid && udid.length > 0) {
        return [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@", udid];
    }
    
    // Fallback пути если UDID не получен
    NSArray *paths = @[
        @"/var/mobile/Containers/Data/Application/com.apple.PosterBoard",
        @"/private/var/mobile/Containers/Data/Application/com.apple.PosterBoard",
        @"/var/mobile/Containers/Data/Application/68B3F8B9-5E5A-4F5C-B5E5-8E5F5D5E5A5B"
    ];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
    }
    
    // Если ничего не найдено, используем сохраненный UDID с путем
    if (udid) {
        return [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@", udid];
    }
    
    return paths[0];
}

// Создание директории с обработкой ошибок
+ (BOOL)createDirectoryIfNeeded:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    
    if (![fileManager fileExistsAtPath:path]) {
        BOOL success = [fileManager createDirectoryAtPath:path 
                               withIntermediateDirectories:YES 
                                                attributes:nil 
                                                     error:&error];
        if (!success) {
            NSLog(@"Failed to create directory: %@", error);
            return NO;
        }
    }
    return YES;
}

// СБРОС КОЛЛЕКЦИЙ APPLE
+ (void)resetAppleCollections {
    NSString *posterBoardPath = [self getPosterBoardPath];
    NSString *collectionsPath = [NSString stringWithFormat:@"%@/Library/Application Support/PRBPosterExtensionDataStore/com.apple.WallpaperKit.CollectionsPoster", posterBoardPath];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:collectionsPath]) {
        // Создаем бэкап если его нет
        NSString *backupPath = [NSString stringWithFormat:@"%@.bak", collectionsPath];
        if (![fm fileExistsAtPath:backupPath]) {
            [fm copyItemAtPath:collectionsPath toPath:backupPath error:nil];
        }
        
        // Удаляем все пользовательские коллекции кроме системных
        NSArray *contents = [fm contentsOfDirectoryAtPath:collectionsPath error:nil];
        for (NSString *item in contents) {
            NSString *fullPath = [collectionsPath stringByAppendingPathComponent:item];
            
            // Сохраняем только Apple коллекции
            if (![item hasPrefix:@"com.apple."]) {
                [fm removeItemAtPath:fullPath error:nil];
            }
        }
        
        // Отправляем сигнал PosterBoard на перезагрузку
        [self notifyPosterBoardReload];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Коллекции сброшены" 
                                                                           message:@"Коллекции Apple восстановлены" 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[self getCurrentViewController] presentViewController:alert animated:YES completion:nil];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Ошибка" 
                                                                           message:@"Коллекции не найдены. Проверьте UDID PosterBoard" 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [UDIDManager promptForUDID];
            }]];
            [[self getCurrentViewController] presentViewController:alert animated:YES completion:nil];
        });
    }
}

// СОЗДАНИЕ ОБОЕВ В КОЛЛЕКЦИЯХ APPLE
+ (void)createWallpaperInAppleCollections:(NSData *)wallpaperData withName:(NSString *)name {
    NSString *posterBoardPath = [self getPosterBoardPath];
    NSString *appleCollectionsPath = [NSString stringWithFormat:@"%@/Library/Application Support/PRBPosterExtensionDataStore/com.apple.WallpaperKit.CollectionsPoster", posterBoardPath];
    
    // Проверяем существует ли путь
    if (![[NSFileManager defaultManager] fileExistsAtPath:appleCollectionsPath]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Ошибка" 
                                                                           message:@"Путь PosterBoard не найден. Проверьте UDID" 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ввести UDID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [UDIDManager promptForUDID];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
            [[self getCurrentViewController] presentViewController:alert animated:YES completion:nil];
        });
        return;
    }
    
    // Создаем структуру как у Apple коллекций
    NSString *collectionId = [NSString stringWithFormat:@"com.apple.wallpaper.tendies.%@", [[NSUUID UUID] UUIDString]];
    NSString *collectionPath = [appleCollectionsPath stringByAppendingPathComponent:collectionId];
    
    if (![self createDirectoryIfNeeded:collectionPath]) {
        return;
    }
    
    // Создаем метаданные коллекции (как у Apple)
    NSDictionary *collectionMetadata = @{
        @"version": @1,
        @"displayName": name,
        @"identifier": collectionId,
        @"type": @"com.apple.wallpaper.collection.video",
        @"subtype": @"dynamic",
        @"supportedDevices": @[@"iPhone", @"iPad"],
        @"creationDate": [NSDate date],
        @"lastModifiedDate": [NSDate date],
        @"isAppleCollection": @YES,
        @"wallpaperOptions": @{
            @"supportsDarkMode": @YES,
            @"supportsParallax": @YES,
            @"supportsPerspective": @YES
        }
    };
    
    NSString *metadataPath = [collectionPath stringByAppendingPathComponent:@"metadata.plist"];
    [collectionMetadata writeToFile:metadataPath atomically:YES];
    
    // Создаем конфигурацию
    NSString *configsPath = [collectionPath stringByAppendingPathComponent:@"configurations"];
    [self createDirectoryIfNeeded:configsPath];
    
    // Создаем версию
    NSString *versionsPath = [collectionPath stringByAppendingPathComponent:@"versions"];
    [self createDirectoryIfNeeded:versionsPath];
    
    NSString *versionPath = [versionsPath stringByAppendingPathComponent:@"1"];
    [self createDirectoryIfNeeded:versionPath];
    
    NSString *contentsPath = [versionPath stringByAppendingPathComponent:@"contents"];
    [self createDirectoryIfNeeded:contentsPath];
    
    // Assets
    NSString *assetsPath = [contentsPath stringByAppendingPathComponent:@"assets"];
    [self createDirectoryIfNeeded:assetsPath];
    
    NSString *videoPath = [assetsPath stringByAppendingPathComponent:@"wallpaper.mov"];
    [wallpaperData writeToFile:videoPath atomically:YES];
    
    // Создаем превью из видео
    [self createPreviewFromVideo:videoPath atPath:assetsPath];
    
    // CA Bundle как у Apple
    NSString *caBundlePath = [contentsPath stringByAppendingPathComponent:@"Wallpaper.ca"];
    [self createDirectoryIfNeeded:caBundlePath];
    
    // Создаем main.caml с правильной структурой для iOS 16+
    [self createCAMLFileAtPath:caBundlePath withName:name];
    
    // Создаем wallpaper.plist
    [self createWallpaperPlistAtPath:caBundlePath withIdentifier:collectionId name:name];
    
    // Обновляем индекс
    [self updatePosterBoardIndex];
    
    // Уведомляем систему
    [self notifyPosterBoardReload];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ Успешно!" 
                                                                       message:[NSString stringWithFormat:@"Обои \"%@\" добавлены в коллекции Apple.\n\nПерейдите в Настройки > Обои чтобы выбрать их.", name]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Открыть настройки" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=Wallpaper"] 
                                               options:@{} 
                                     completionHandler:nil];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        [[self getCurrentViewController] presentViewController:alert animated:YES completion:nil];
    });
}

// Создание CAML файла
+ (void)createCAMLFileAtPath:(NSString *)caBundlePath withName:(NSString *)name {
    NSString *camlPath = [caBundlePath stringByAppendingPathComponent:@"main.caml"];
    
    // Получаем размер экрана
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    NSString *camlContent = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        "<plist version=\"1.0\">\n"
        "<dict>\n"
        "    <key>rootLayer</key>\n"
        "    <dict>\n"
        "        <key>type</key>\n"
        "        <string>AVPlayerLayer</string>\n"
        "        <key>frame</key>\n"
        "        <string>{{0, 0}, {%f, %f}}</string>\n"
        "        <key>videoName</key>\n"
        "        <string>wallpaper.mov</string>\n"
        "        <key>videoGravity</key>\n"
        "        <string>AVLayerVideoGravityResizeAspectFill</string>\n"
        "        <key>shouldLoop</key>\n"
        "        <true/>\n"
        "        <key>muted</key>\n"
        "        <false/>\n"
        "    </dict>\n"
        "    <key>options</key>\n"
        "    <dict>\n"
        "        <key>stillImageMode</key>\n"
        "        <false/>\n"
        "        <key>parallaxEnabled</key>\n"
        "        <true/>\n"
        "        <key>perspectiveZoom</key>\n"
        "        <real>1.0</real>\n"
        "    </dict>\n"
        "</dict>\n"
        "</plist>", screenWidth, screenHeight];
    
    [camlContent writeToFile:camlPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// Создание wallpaper.plist
+ (void)createWallpaperPlistAtPath:(NSString *)caBundlePath withIdentifier:(NSString *)identifier name:(NSString *)name {
    NSString *wallpaperPlistPath = [caBundlePath stringByAppendingPathComponent:@"wallpaper.plist"];
    NSDictionary *wallpaperPlist = @{
        @"CFBundleIdentifier": identifier,
        @"CFBundleName": name,
        @"CFBundleVersion": @1,
        @"subsystem": @"LayeredAnimation",
        @"assets": @[@"wallpaper.mov"],
        @"lightModeAssets": @[@"wallpaper.mov"],
        @"darkModeAssets": @[@"wallpaper.mov"],
        @"previewImage": @"wallpaper_preview.jpg"
    };
    [wallpaperPlist writeToFile:wallpaperPlistPath atomically:YES];
}

// Создание превью из видео (исправленная версия без deprecated методов)
+ (void)createPreviewFromVideo:(NSString *)videoPath atPath:(NSString *)assetsPath {
    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    CMTime time = CMTimeMake(1, 30);
    
    // Используем асинхронный метод вместо deprecated
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:time]] 
                                     completionHandler:^(CMTime requestedTime, 
                                                         CGImageRef image, 
                                                         CMTime actualTime, 
                                                         AVAssetImageGeneratorResult result, 
                                                         NSError *error) {
        if (result == AVAssetImageGeneratorSucceeded && image) {
            UIImage *uiImage = [UIImage imageWithCGImage:image];
            NSData *imageData = UIImageJPEGRepresentation(uiImage, 0.8);
            NSString *previewPath = [assetsPath stringByAppendingPathComponent:@"wallpaper_preview.jpg"];
            [imageData writeToFile:previewPath atomically:YES];
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

// Обновление индекса PosterBoard
+ (void)updatePosterBoardIndex {
    NSString *posterBoardPath = [self getPosterBoardPath];
    NSString *indexPath = [NSString stringWithFormat:@"%@/Library/Application Support/PRBPosterExtensionDataStore/index.plist", posterBoardPath];
    
    NSMutableDictionary *index = [NSMutableDictionary dictionaryWithContentsOfFile:indexPath];
    if (!index) {
        index = [NSMutableDictionary dictionary];
    }
    
    index[@"lastUpdate"] = [NSDate date];
    index[@"version"] = @2;
    [index writeToFile:indexPath atomically:YES];
}

// Уведомление PosterBoard о перезагрузке
+ (void)notifyPosterBoardReload {
    // Для iOS 16+
    dispatch_async(dispatch_get_main_queue(), ^{
        // Отправляем системное уведомление
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
                                            (CFStringRef)@"com.apple.PosterBoard.ReloadWallpapers", 
                                            NULL, 
                                            NULL, 
                                            YES);
        
        // Также отправляем локальное уведомление
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.apple.PosterBoard.ReloadWallpapers" 
                                                            object:nil 
                                                          userInfo:nil];
    });
}

// Главный метод инжекта
+ (void)injectToPosterBoard:(NSData *)wallpaperData withName:(NSString *)name {
    [self createWallpaperInAppleCollections:wallpaperData withName:name];
}

// Получение текущего контроллера (исправленная версия без deprecated)
+ (UIViewController *)getCurrentViewController {
    UIWindow *window = nil;
    
    if (@available(iOS 15.0, *)) {
        window = [UIApplication sharedApplication].connectedScenes
            .allObjects.firstObject ? [((UIWindowScene *)[UIApplication sharedApplication].connectedScenes.allObjects.firstObject) windows].firstObject : nil;
    } else if (@available(iOS 13.0, *)) {
        window = [UIApplication sharedApplication].windows.firstObject;
    } else {
        window = [UIApplication sharedApplication].keyWindow;
    }
    
    UIViewController *rootVC = window.rootViewController;
    
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    return rootVC;
}

@end

// MARK: - Главный контроллер
@interface TendiesWallpaperApp : UIResponder <UIApplicationDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UICollectionView *collectionView;
@property (strong, nonatomic) NSMutableArray *videos;
@property (strong, nonatomic) UIView *menuView;
@property (assign, nonatomic) BOOL isMenuOpen;
@end

@implementation TendiesWallpaperApp

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    [self setupMainView];
    [self loadVideos];
    
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor blackColor];
    
    // Настройка навигации
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:rootVC];
    navController.navigationBar.barStyle = UIBarStyleBlack;
    navController.navigationBar.tintColor = [UIColor whiteColor];
    
    UIBarButtonItem *menuButton = [[UIBarButtonItem alloc] initWithTitle:@"☰" 
                                                                    style:UIBarButtonItemStylePlain 
                                                                   target:self 
                                                                   action:@selector(toggleMenu)];
    rootVC.navigationItem.leftBarButtonItem = menuButton;
    
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithTitle:@"+" 
                                                                   style:UIBarButtonItemStylePlain 
                                                                  target:self 
                                                                  action:@selector(addVideoFromGallery)];
    rootVC.navigationItem.rightBarButtonItem = addButton;
    
    rootVC.title = @"Tendies Wallpapers";
    
    [rootVC.view addSubview:self.collectionView];
    
    [self setupMenuInView:rootVC.view];
    
    // Проверяем UDID при запуске
    if (![UDIDManager getSavedUDID]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UDIDManager promptForUDID];
        });
    }
    
    self.window.rootViewController = navController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)setupMainView {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake([UIScreen mainScreen].bounds.size.width, 280);
    layout.minimumLineSpacing = 2;
    
    self.collectionView = [[UICollectionView alloc] initWithFrame:[UIScreen mainScreen].bounds collectionViewLayout:layout];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColor = [UIColor blackColor];
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"VideoCell"];
}

- (void)setupMenuInView:(UIView *)parentView {
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(-300, 0, 300, parentView.bounds.size.height)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.menuView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.menuView.layer.shadowOffset = CGSizeMake(2, 0);
    self.menuView.layer.shadowOpacity = 0.5;
    
    NSArray *menuItems = @[
        @{@"title": @"🔄 Сбросить коллекции Apple", @"action": @"resetCollections"},
        @{@"title": @"📱 Ввести UDID PosterBoard", @"action": @"enterUDID"},
        @{@"title": @"⭐ Избранное", @"action": @"favorites"},
        @{@"title": @"⚙️ Настройки", @"action": @"settings"},
        @{@"title": @"ℹ️ О программе", @"action": @"about"}
    ];
    
    for (int i = 0; i < menuItems.count; i++) {
        NSDictionary *item = menuItems[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(20, 100 + i * 60, 260, 40);
        [button setTitle:item[@"title"] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.tag = i;
        [button addTarget:self action:@selector(menuItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.menuView addSubview:button];
    }
    
    [parentView addSubview:self.menuView];
}

- (void)toggleMenu {
    self.isMenuOpen = !self.isMenuOpen;
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self.menuView.frame;
        frame.origin.x = self.isMenuOpen ? 0 : -300;
        self.menuView.frame = frame;
    }];
}

- (void)menuItemTapped:(UIButton *)sender {
    [self toggleMenu];
    
    switch (sender.tag) {
        case 0:
            [PosterBoardManager resetAppleCollections];
            break;
        case 1:
            [UDIDManager promptForUDID];
            break;
        case 2:
            [self showFavorites];
            break;
        case 3:
            [self showSettings];
            break;
        case 4:
            [self showAbout];
            break;
    }
}

- (void)loadVideos {
    self.videos = [NSMutableArray array];
    
    NSArray *videoNames = @[@"Cyberpunk Neon", @"Tendies Dance", @"Space Trip", @"Ocean Waves", @"Abstract Flow"];
    NSArray *videoFiles = @[@"cyberpunk", @"tendies", @"space", @"ocean", @"abstract"];
    
    for (int i = 0; i < videoNames.count; i++) {
        NSDictionary *video = @{
            @"name": videoNames[i],
            @"file": videoFiles[i],
            @"type": @"mp4"
        };
        [self.videos addObject:video];
    }
}

// MARK: - UICollectionView
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.videos.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"VideoCell" forIndexPath:indexPath];
    
    for (UIView *view in cell.contentView.subviews) {
        [view removeFromSuperview];
    }
    
    NSDictionary *video = self.videos[indexPath.row];
    
    UIView *previewView = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    previewView.backgroundColor = [UIColor colorWithRed:arc4random_uniform(255)/255.0 
                                                   green:arc4random_uniform(255)/255.0 
                                                    blue:arc4random_uniform(255)/255.0 alpha:1.0];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, cell.bounds.size.width - 40, 40)];
    titleLabel.text = video[@"name"];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.shadowColor = [UIColor blackColor];
    titleLabel.shadowOffset = CGSizeMake(1, 1);
    
    UILabel *badgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, 80, 30)];
    badgeLabel.text = @"🎬 4K";
    badgeLabel.textColor = [UIColor whiteColor];
    badgeLabel.backgroundColor = [UIColor colorWithRed:0 green:0.5 blue:1 alpha:0.8];
    badgeLabel.textAlignment = NSTextAlignmentCenter;
    badgeLabel.font = [UIFont boldSystemFontOfSize:14];
    badgeLabel.layer.cornerRadius = 10;
    badgeLabel.clipsToBounds = YES;
    
    // Информация о UDID
    NSString *udidInfo = [UDIDManager getSavedUDID] ? @"✅ UDID OK" : @"⚠️ Нужен UDID";
    UILabel *udidLabel = [[UILabel alloc] initWithFrame:CGRectMake(cell.bounds.size.width - 120, 20, 100, 30)];
    udidLabel.text = udidInfo;
    udidLabel.textColor = [UIColor whiteColor];
    udidLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    udidLabel.textAlignment = NSTextAlignmentCenter;
    udidLabel.font = [UIFont systemFontOfSize:12];
    udidLabel.layer.cornerRadius = 10;
    udidLabel.clipsToBounds = YES;
    
    // Кнопка установки в коллекции Apple
    UIButton *installButton = [UIButton buttonWithType:UIButtonTypeCustom];
    installButton.frame = CGRectMake(20, cell.bounds.size.height - 100, cell.bounds.size.width - 40, 50);
    installButton.backgroundColor = [UIColor systemBlueColor];
    installButton.layer.cornerRadius = 12;
    [installButton setTitle:@"📱 Добавить в коллекции Apple" forState:UIControlStateNormal];
    [installButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    installButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    installButton.tag = indexPath.row;
    [installButton addTarget:self action:@selector(installToAppleCollections:) forControlEvents:UIControlEventTouchUpInside];
    
    [previewView addSubview:titleLabel];
    [previewView addSubview:badgeLabel];
    [previewView addSubview:udidLabel];
    [previewView addSubview:installButton];
    [cell.contentView addSubview:previewView];
    
    return cell;
}

// Установка в коллекции Apple
- (void)installToAppleCollections:(UIButton *)sender {
    if (![UDIDManager getSavedUDID]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Требуется UDID" 
                                                                       message:@"Сначала введите UDID PosterBoard в меню" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Ввести UDID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [UDIDManager promptForUDID];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
        [[PosterBoardManager getCurrentViewController] presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSInteger index = sender.tag;
    NSDictionary *video = self.videos[index];
    
    // В реальном проекте здесь нужно загрузить видео из bundle
    // Для демо создаем тестовые данные
    NSData *fakeVideoData = [@"FAKE_VIDEO_DATA" dataUsingEncoding:NSUTF8StringEncoding];
    
    [PosterBoardManager injectToPosterBoard:fakeVideoData withName:video[@"name"]];
}

// Добавление своего видео
- (void)addVideoFromGallery {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    
    [[PosterBoardManager getCurrentViewController] presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        
        if (videoURL) {
            NSData *videoData = [NSData dataWithContentsOfURL:videoURL];
            
            UIAlertController *nameAlert = [UIAlertController alertControllerWithTitle:@"Название обоев" 
                                                                               message:@"Введите название" 
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            
            [nameAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"Мои видео обои";
            }];
            
            [nameAlert addAction:[UIAlertAction actionWithTitle:@"Установить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *name = nameAlert.textFields.firstObject.text;
                if (name.length == 0) name = @"Мои видео обои";
                
                [PosterBoardManager injectToPosterBoard:videoData withName:name];
            }]];
            
            [nameAlert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
            
            [[PosterBoardManager getCurrentViewController] presentViewController:nameAlert animated:YES completion:nil];
        }
    }];
}

- (void)showFavorites {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Избранное" 
                                                                   message:@"Здесь будут избранные обои" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[PosterBoardManager getCurrentViewController] presentViewController:alert animated:YES completion:nil];
}

- (void)showSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Настройки" 
                                                                   message:[NSString stringWithFormat:@"Текущий UDID: %@\n\nДля изменения нажмите 'Ввести UDID' в меню", 
                                                                            [UDIDManager getSavedUDID] ?: @"не задан"] 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[PosterBoardManager getCurrentViewController] presentViewController:alert animated:YES completion:nil];
}

- (void)showAbout {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tendies Wallpapers" 
                                                                   message:@"Версия 2.0\n\n✅ Поддержка iOS 16+\n✅ Видео обои в коллекциях Apple\n✅ Ввод UDID через Nugget\n✅ Сброс коллекций Apple\n\nКак получить UDID:\n1. Установите Nugget\n2. Подключите iPhone\n3. Нажмите 'Read UDID'\n4. Найдите PosterBoard UDID" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[PosterBoardManager getCurrentViewController] presentViewController:alert animated:YES completion:nil];
}

@end

// MARK: - Точка входа
int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([TendiesWallpaperApp class]));
    }
}
