#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// MARK: - Менеджер для работы с UDID PosterBoard
@interface UDIDManager : NSObject
+ (NSString *)getSavedUDID;
+ (void)saveUDID:(NSString *)udid;
+ (void)promptForUDID;
+ (NSString *)detectPosterBoardUDID;
+ (UIViewController *)getCurrentViewController;
@end

@implementation UDIDManager

+ (void)saveUDID:(NSString *)udid {
    [[NSUserDefaults standardUserDefaults] setObject:udid forKey:@"PosterBoardUDID"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)getSavedUDID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"PosterBoardUDID"];
}

+ (NSString *)detectPosterBoardUDID {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appsPath = @"/var/mobile/Containers/Data/Application";
    
    if ([fm fileExistsAtPath:appsPath]) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:appsPath error:nil];
        for (NSString *item in contents) {
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

+ (void)promptForUDID {
    NSString *saved = [self getSavedUDID];
    NSString *detected = [self detectPosterBoardUDID];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self getCurrentViewController];
        
        UIAlertController *alert = [UIAlertController 
            alertControllerWithTitle:@"UDID PosterBoard" 
            message:[NSString stringWithFormat:@"Введите UDID PosterBoard\n\n%@\n\nКак найти:\n1. Установите Nugget\n2. Подключите iPhone\n3. Нажмите 'Read UDID'\n4. Скопируйте UDID приложения PosterBoard", 
                     detected ? [NSString stringWithFormat:@"Найден: %@", detected] : @"Автоопределение не найдено"]
            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
            textField.text = saved ?: detected;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Сохранить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *udid = alert.textFields.firstObject.text;
            if (udid.length > 0) {
                [self saveUDID:udid];
                
                UIAlertController *success = [UIAlertController alertControllerWithTitle:@"Сохранено" 
                                                                                 message:@"UDID сохранен" 
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                [success addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [topVC presentViewController:success animated:YES completion:nil];
            }
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
        
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

+ (UIViewController *)getCurrentViewController {
    UIWindowScene *scene = (UIWindowScene *)[UIApplication sharedApplication].connectedScenes.allObjects.firstObject;
    UIWindow *window = scene.windows.firstObject;
    UIViewController *rootVC = window.rootViewController;
    
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

@end

// MARK: - PosterBoard Manager
@interface PosterBoardManager : NSObject
+ (void)injectToPosterBoard:(NSData *)wallpaperData withName:(NSString *)name;
+ (void)resetAppleCollections;
+ (NSString *)getPosterBoardPath;
@end

@implementation PosterBoardManager

+ (NSString *)getPosterBoardPath {
    NSString *udid = [UDIDManager getSavedUDID];
    if (udid && udid.length > 0) {
        return [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@", udid];
    }
    return nil;
}

+ (BOOL)createDirectoryIfNeeded:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    if (![fm fileExistsAtPath:path]) {
        if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"Failed to create directory: %@", error);
            return NO;
        }
    }
    return YES;
}

+ (void)resetAppleCollections {
    NSString *posterPath = [self getPosterBoardPath];
    if (!posterPath) {
        [self showAlert:@"Ошибка" message:@"Сначала введите UDID PosterBoard"];
        return;
    }
    
    NSString *collectionsPath = [NSString stringWithFormat:@"%@/Library/Application Support/PRBPosterExtensionDataStore/com.apple.WallpaperKit.CollectionsPoster", posterPath];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:collectionsPath]) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:collectionsPath error:nil];
        for (NSString *item in contents) {
            if (![item hasPrefix:@"com.apple."]) {
                NSString *fullPath = [collectionsPath stringByAppendingPathComponent:item];
                [fm removeItemAtPath:fullPath error:nil];
            }
        }
        
        [self notifyPosterBoardReload];
        [self showAlert:@"Готово" message:@"Коллекции Apple восстановлены"];
    }
}

+ (void)injectToPosterBoard:(NSData *)wallpaperData withName:(NSString *)name {
    NSString *posterPath = [self getPosterBoardPath];
    if (!posterPath) {
        [self showAlert:@"Ошибка" message:@"Сначала введите UDID PosterBoard"];
        return;
    }
    
    NSString *collectionsPath = [NSString stringWithFormat:@"%@/Library/Application Support/PRBPosterExtensionDataStore/com.apple.WallpaperKit.CollectionsPoster", posterPath];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:collectionsPath]) {
        [self showAlert:@"Ошибка" message:@"PosterBoard не найден по указанному UDID"];
        return;
    }
    
    NSString *collectionId = [NSString stringWithFormat:@"com.apple.wallpaper.tendies.%@", [[NSUUID UUID] UUIDString]];
    NSString *collectionPath = [collectionsPath stringByAppendingPathComponent:collectionId];
    
    if (![self createDirectoryIfNeeded:collectionPath]) return;
    
    // Создаем структуру
    NSDictionary *metadata = @{
        @"version": @1,
        @"displayName": name,
        @"identifier": collectionId,
        @"type": @"com.apple.wallpaper.collection.video",
        @"creationDate": [NSDate date]
    };
    [metadata writeToFile:[collectionPath stringByAppendingPathComponent:@"metadata.plist"] atomically:YES];
    
    // Создаем версионную структуру
    NSString *contentsPath = [NSString stringWithFormat:@"%@/versions/1/contents", collectionPath];
    [self createDirectoryIfNeeded:contentsPath];
    
    // Assets
    NSString *assetsPath = [contentsPath stringByAppendingPathComponent:@"assets"];
    [self createDirectoryIfNeeded:assetsPath];
    
    NSString *videoPath = [assetsPath stringByAppendingPathComponent:@"wallpaper.mov"];
    [wallpaperData writeToFile:videoPath atomically:YES];
    
    // CA Bundle
    NSString *caBundlePath = [contentsPath stringByAppendingPathComponent:@"Wallpaper.ca"];
    [self createDirectoryIfNeeded:caBundlePath];
    
    // Создаем превью
    [self createPreviewFromVideo:videoPath atPath:assetsPath];
    
    [self notifyPosterBoardReload];
    [self showAlertWithAction:name];
}

+ (void)createPreviewFromVideo:(NSString *)videoPath atPath:(NSString *)assetsPath {
    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    
    CMTime time = CMTimeMake(1, 30);
    CGImageRef imageRef = [gen copyCGImageAtTime:time actualTime:nil error:nil];
    
    if (imageRef) {
        UIImage *image = [UIImage imageWithCGImage:imageRef];
        NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
        [imageData writeToFile:[assetsPath stringByAppendingPathComponent:@"wallpaper_preview.jpg"] atomically:YES];
        CGImageRelease(imageRef);
    }
}

+ (void)notifyPosterBoardReload {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), 
                                        CFSTR("com.apple.PosterBoard.ReloadWallpapers"), 
                                        NULL, NULL, YES);
}

+ (void)showAlert:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[UDIDManager getCurrentViewController] presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)showAlertWithAction:(NSString *)name {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ Успешно!" 
                                                                       message:[NSString stringWithFormat:@"Обои \"%@\" добавлены", name]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Открыть настройки" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=Wallpaper"] 
                                               options:@{} completionHandler:nil];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        [[UDIDManager getCurrentViewController] presentViewController:alert animated:YES completion:nil];
    });
}

@end

// MARK: - Главный контроллер
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@interface MainViewController : UIViewController <UICollectionViewDelegate, UICollectionViewDataSource, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) UICollectionView *collectionView;
@property (strong, nonatomic) NSMutableArray *videos;
@property (strong, nonatomic) UIView *menuView;
@property (assign, nonatomic) BOOL isMenuOpen;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[MainViewController new]];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"Tendies Wallpapers";
    self.isMenuOpen = NO;
    
    // Настройка навигации
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"☰" style:UIBarButtonItemStylePlain target:self action:@selector(toggleMenu)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"+" style:UIBarButtonItemStylePlain target:self action:@selector(addVideo)];
    
    // Настройка коллекции
    [self setupCollectionView];
    [self setupMenu];
    [self loadVideos];
    
    // Проверка UDID
    if (![UDIDManager getSavedUDID]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UDIDManager promptForUDID];
        });
    }
}

- (void)setupCollectionView {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    CGFloat width = self.view.bounds.size.width - 20;
    layout.itemSize = CGSizeMake(width, 200);
    layout.minimumLineSpacing = 10;
    
    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColor = [UIColor clearColor];
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"Cell"];
    [self.view addSubview:self.collectionView];
}

- (void)setupMenu {
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(-280, 0, 280, self.view.bounds.size.height)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    self.menuView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.menuView.layer.shadowOffset = CGSizeMake(2, 0);
    self.menuView.layer.shadowOpacity = 0.5;
    
    NSArray *items = @[@"🔄 Сбросить коллекции", @"📱 Ввести UDID", @"⭐ Избранное", @"ℹ️ О программе"];
    for (int i = 0; i < items.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(20, 100 + i * 60, 240, 40);
        [btn setTitle:items[i] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        btn.tag = i;
        [btn addTarget:self action:@selector(menuAction:) forControlEvents:UIControlEventTouchUpInside];
        [self.menuView addSubview:btn];
    }
    
    [self.view addSubview:self.menuView];
}

- (void)toggleMenu {
    self.isMenuOpen = !self.isMenuOpen;
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self.menuView.frame;
        frame.origin.x = self.isMenuOpen ? 0 : -280;
        self.menuView.frame = frame;
    }];
}

- (void)menuAction:(UIButton *)sender {
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
            [self showAbout];
            break;
    }
}

- (void)loadVideos {
    self.videos = [NSMutableArray array];
    NSArray *names = @[@"Cyberpunk Neon", @"Tendies Dance", @"Space Trip", @"Ocean Waves", @"Abstract"];
    for (NSString *name in names) {
        [self.videos addObject:@{@"name": name}];
    }
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.videos.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:ip];
    
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    UIView *bg = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    bg.backgroundColor = [UIColor colorWithRed:arc4random_uniform(255)/255.0 
                                         green:arc4random_uniform(255)/255.0 
                                          blue:arc4random_uniform(255)/255.0 alpha:1];
    bg.layer.cornerRadius = 12;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, bg.bounds.size.width-30, 30)];
    title.text = self.videos[ip.row][@"name"];
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:20];
    
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(15, 55, 60, 25)];
    badge.text = @"🎬 4K";
    badge.textColor = [UIColor whiteColor];
    badge.backgroundColor = [UIColor colorWithRed:0 green:0.5 blue:1 alpha:0.8];
    badge.textAlignment = NSTextAlignmentCenter;
    badge.font = [UIFont boldSystemFontOfSize:12];
    badge.layer.cornerRadius = 8;
    badge.clipsToBounds = YES;
    
    NSString *udidStatus = [UDIDManager getSavedUDID] ? @"✅" : @"⚠️";
    UILabel *udidLabel = [[UILabel alloc] initWithFrame:CGRectMake(bg.bounds.size.width-70, 15, 50, 25)];
    udidLabel.text = udidStatus;
    udidLabel.textAlignment = NSTextAlignmentCenter;
    udidLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    udidLabel.layer.cornerRadius = 8;
    udidLabel.clipsToBounds = YES;
    
    UIButton *installBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    installBtn.frame = CGRectMake(15, bg.bounds.size.height-60, bg.bounds.size.width-30, 45);
    installBtn.backgroundColor = [UIColor systemBlueColor];
    installBtn.layer.cornerRadius = 10;
    [installBtn setTitle:@"Установить" forState:UIControlStateNormal];
    [installBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    installBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    installBtn.tag = ip.row;
    [installBtn addTarget:self action:@selector(installWallpaper:) forControlEvents:UIControlEventTouchUpInside];
    
    [bg addSubview:title];
    [bg addSubview:badge];
    [bg addSubview:udidLabel];
    [bg addSubview:installBtn];
    [cell.contentView addSubview:bg];
    
    return cell;
}

- (void)installWallpaper:(UIButton *)sender {
    if (![UDIDManager getSavedUDID]) {
        [UDIDManager promptForUDID];
        return;
    }
    
    NSData *dummyData = [@"TENDIES_VIDEO_DATA" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *name = self.videos[sender.tag][@"name"];
    [PosterBoardManager injectToPosterBoard:dummyData withName:name];
}

- (void)addVideo {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        if (videoURL) {
            NSData *data = [NSData dataWithContentsOfURL:videoURL];
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Название" message:@"Введите название" preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:nil];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Установить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *name = alert.textFields.firstObject.text ?: @"Мои обои";
                [PosterBoardManager injectToPosterBoard:data withName:name];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)showFavorites {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Избранное" message:@"Здесь будут избранные обои" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAbout {
    NSString *udid = [UDIDManager getSavedUDID] ?: @"не задан";
    NSString *msg = [NSString stringWithFormat:@"Tendies Wallpapers v1.0\n\nUDID: %@\n\nТолько iOS 16+\nВидео обои в коллекциях Apple", udid];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"О программе" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// MARK: - Точка входа
int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
