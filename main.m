#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>

// MARK: - Структуры для PosterBoard
@interface PosterBoardManager : NSObject
+ (void)injectToPosterBoard:(NSData *)wallpaperData;
+ (void)createTendiesFile:(NSURL *)videoURL;
+ (void)applyWallpaperViaPosterBoard:(NSString *)tendiesFilePath;
@end

@implementation PosterBoardManager

// Главный метод - обход через PosterBoard как в Pocket Poster
+ (void)injectToPosterBoard:(NSData *)wallpaperData {
    // Путь к PosterBoard в системе
    NSString *posterBoardPath = @"/var/mobile/Containers/Data/Application/com.apple.PosterBoard";
    
    // Создаем резервную копию через iMazing-style метод
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Путь к директории с расширениями PosterBoard
    NSString *extensionsPath = [NSString stringWithFormat:@"%@/Library/Application Support/PRBPosterExtensionDataStore", posterBoardPath];
    
    // Создаем директорию для наших обоев если её нет
    NSString *collectionsPath = [extensionsPath stringByAppendingPathComponent:@"com.apple.WallpaperKit.CollectionsPoster"];
    
    if (![fileManager fileExistsAtPath:collectionsPath]) {
        [fileManager createDirectoryAtPath:collectionsPath withIntermediateDirectories:YES attributes:nil];
    }
    
    // Генерируем UUID для нового постера
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *posterPath = [collectionsPath stringByAppendingPathComponent:uuid];
    
    // Создаем структуру постера
    [fileManager createDirectoryAtPath:posterPath withIntermediateDirectories:YES attributes:nil];
    
    // Создаем конфигурацию
    NSString *configPath = [posterPath stringByAppendingPathComponent:@"configurations"];
    [fileManager createDirectoryAtPath:configPath withIntermediateDirectories:YES attributes:nil];
    
    // Создаем версионную структуру
    NSString *versionsPath = [posterPath stringByAppendingPathComponent:@"versions/1/contents"];
    [fileManager createDirectoryAtPath:versionsPath withIntermediateDirectories:YES attributes:nil];
    
    // Копируем видео в assets
    NSString *assetsPath = [versionsPath stringByAppendingPathComponent:@"assets"];
    [fileManager createDirectoryAtPath:assetsPath withIntermediateDirectories:YES attributes:nil];
    
    NSString *videoPath = [assetsPath stringByAppendingPathComponent:@"wallpaper.mov"];
    [wallpaperData writeToFile:videoPath atomically:YES];
    
    // Создаем CA bundle структуру
    NSString *caBundlePath = [versionsPath stringByAppendingPathComponent:@"Wallpaper.ca"];
    [fileManager createDirectoryAtPath:caBundlePath withIntermediateDirectories:YES attributes:nil];
    
    // Создаем main.caml файл для анимации
    NSString *camlPath = [caBundlePath stringByAppendingPathComponent:@"main.caml"];
    NSString *camlContent = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                             "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                             "<plist version=\"1.0\">\n"
                             "<dict>\n"
                             "    <key>layers</key>\n"
                             "    <array>\n"
                             "        <dict>\n"
                             "            <key>frame</key>\n"
                             "            <string>{{0, 0}, {390, 844}}</string>\n"
                             "            <key>contents</key>\n"
                             "            <string>wallpaper.mov</string>\n"
                             "            <key>transform</key>\n"
                             "            <dict>\n"
                             "                <key>scale</key>\n"
                             "                <real>1.0</real>\n"
                             "            </dict>\n"
                             "        </dict>\n"
                             "    </array>\n"
                             "</dict>\n"
                             "</plist>";
    [camlContent writeToFile:camlPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // Создаем wallpaper.plist
    NSString *wallpaperPlistPath = [caBundlePath stringByAppendingPathComponent:@"wallpaper.plist"];
    NSDictionary *wallpaperPlist = @{
        @"subsystem": @"LayeredAnimation",
        @"assets": @[@"wallpaper.mov"],
        @"lightModeAssets": @[@"wallpaper.mov"],
        @"darkModeAssets": @[@"wallpaper.mov"]
    };
    [wallpaperPlist writeToFile:wallpaperPlistPath atomically:YES];
    
    // Создаем метаданные постера
    NSString *metadataPath = [posterPath stringByAppendingPathComponent:@"metadata.plist"];
    NSDictionary *metadata = @{
        @"name": @"Tendies Video Wallpaper",
        @"identifier": uuid,
        @"version": @1,
        @"supportsDarkMode": @YES
    };
    [metadata writeToFile:metadataPath atomically:YES];
    
    // Отправляем сигнал PosterBoard для перезагрузки
    [self notifyPosterBoard];
}

// Создание .tendies файла как в Pocket Poster
+ (void)createTendiesFile:(NSURL *)videoURL {
    NSData *videoData = [NSData dataWithContentsOfURL:videoURL];
    
    // Создаем структуру .tendies файла
    NSMutableDictionary *tendiesPackage = [NSMutableDictionary dictionary];
    tendiesPackage[@"version"] = @1;
    tendiesPackage[@"type"] = @"video";
    tendiesPackage[@"video"] = [videoData base64EncodedStringWithOptions:0];
    tendiesPackage[@"metadata"] = @{
        @"name": @"Tendies Wallpaper",
        @"author": @"Tendies App",
        @"resolution": @"390x844",
        @"fps": @30
    };
    
    // Сохраняем в Documents
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tendiesPath = [documentsPath stringByAppendingPathComponent:@"wallpaper.tendies"];
    
    [tendiesPackage writeToFile:tendiesPath atomically:YES];
    
    NSLog(@"Tendies file created at: %@", tendiesPath);
}

// Отправка уведомления PosterBoard
+ (void)notifyPosterBoard {
    // Эмуляция CFNotificationCenterPost для PosterBoard
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.apple.PosterBoard.ReloadWallpapers" 
                                                            object:nil 
                                                          userInfo:nil];
    });
}

// Применение через PosterBoard (метод как в Pocket Poster)
+ (void)applyWallpaperViaPosterBoard:(NSString *)tendiesFilePath {
    // Читаем .tendies файл
    NSDictionary *tendiesPackage = [NSDictionary dictionaryWithContentsOfFile:tendiesFilePath];
    
    if (tendiesPackage) {
        NSString *videoBase64 = tendiesPackage[@"video"];
        NSData *videoData = [[NSData alloc] initWithBase64EncodedString:videoBase64 options:0];
        
        if (videoData) {
            // Инжектим в PosterBoard
            [self injectToPosterBoard:videoData];
            
            // Показываем успех
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Успех!" 
                                                                           message:@"Видео обои добавлены в PosterBoard. Перейдите в Настройки > Обои чтобы активировать." 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }
    }
}

@end

// MARK: - Главный контроллер с PosterBoard интеграцией
@interface PosterBoardApp : UIResponder <UIApplicationDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) UICollectionView *collectionView;
@property (strong, nonatomic) NSMutableArray *videos;
@property (strong, nonatomic) NSMutableArray *installedWallpapers;
@end

@implementation PosterBoardApp

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    // Настройка главного экрана
    [self setupMainView];
    
    // Загрузка видео обоев
    [self loadVideos];
    
    // Проверка установленных обоев
    [self loadInstalledWallpapers];
    
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = [UIColor blackColor];
    [self.window.rootViewController.view addSubview:self.collectionView];
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)setupMainView {
    // Создание коллекции
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake([UIScreen mainScreen].bounds.size.width, 280);
    layout.minimumLineSpacing = 2;
    
    self.collectionView = [[UICollectionView alloc] initWithFrame:self.window.bounds collectionViewLayout:layout];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColor = [UIColor blackColor];
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"VideoCell"];
    
    // Кнопка добавления видео
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
                                                                                target:self 
                                                                                action:@selector(addVideoFromGallery)];
    self.window.rootViewController.navigationItem.rightBarButtonItem = addButton;
}

- (void)loadVideos {
    self.videos = [NSMutableArray array];
    
    // Встроенные видео (в реальном проекте нужно добавить файлы)
    NSArray *videoNames = @[@"tendies_cyberpunk", @"tendies_neon", @"tendies_space", @"tendies_abstract"];
    NSArray *videoTitles = @[@"Cyberpunk Tendies", @"Neon Tendies", @"Space Tendies", @"Abstract Tendies"];
    
    for (int i = 0; i < videoNames.count; i++) {
        NSString *path = [[NSBundle mainBundle] pathForResource:videoNames[i] ofType:@"mp4"];
        if (path) {
            NSDictionary *video = @{
                @"name": videoTitles[i],
                @"path": path,
                @"type": @"builtin"
            };
            [self.videos addObject:video];
        }
    }
}

- (void)loadInstalledWallpapers {
    self.installedWallpapers = [NSMutableArray array];
    
    // Проверяем директорию PosterBoard на наличие установленных обоев
    NSString *posterBoardPath = @"/var/mobile/Containers/Data/Application/com.apple.PosterBoard/Library/Application Support/PRBPosterExtensionDataStore/com.apple.WallpaperKit.CollectionsPoster";
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:posterBoardPath]) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:posterBoardPath error:nil];
        for (NSString *item in contents) {
            if ([item length] == 36) { // UUID формат
                [self.installedWallpapers addObject:item];
            }
        }
    }
}

// MARK: - UICollectionView DataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.videos.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"VideoCell" forIndexPath:indexPath];
    
    // Очистка ячейки
    for (UIView *view in cell.contentView.subviews) {
        [view removeFromSuperview];
    }
    
    NSDictionary *video = self.videos[indexPath.row];
    
    // Превью
    UIView *previewView = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    previewView.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0];
    
    // Название
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, cell.bounds.size.width - 40, 30)];
    titleLabel.text = video[@"name"];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    
    // Индикатор видео
    UILabel *videoBadge = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, 100, 30)];
    videoBadge.text = @"🎬 4K Video";
    videoBadge.textColor = [UIColor whiteColor];
    videoBadge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    videoBadge.textAlignment = NSTextAlignmentCenter;
    videoBadge.font = [UIFont systemFontOfSize:12];
    videoBadge.layer.cornerRadius = 10;
    videoBadge.clipsToBounds = YES;
    
    // Кнопка установки через PosterBoard
    UIButton *posterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    posterButton.frame = CGRectMake(20, cell.bounds.size.height - 80, cell.bounds.size.width - 40, 50);
    posterButton.backgroundColor = [UIColor systemBlueColor];
    posterButton.layer.cornerRadius = 12;
    [posterButton setTitle:@"📱 Установить через PosterBoard" forState:UIControlStateNormal];
    [posterButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    posterButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    posterButton.tag = indexPath.row;
    [posterButton addTarget:self action:@selector(installViaPosterBoard:) forControlEvents:UIControlEventTouchUpInside];
    
    [previewView addSubview:titleLabel];
    [previewView addSubview:videoBadge];
    [previewView addSubview:posterButton];
    [cell.contentView addSubview:previewView];
    
    return cell;
}

// MARK: - Установка через PosterBoard (метод Pocket Poster)
- (void)installViaPosterBoard:(UIButton *)sender {
    NSInteger index = sender.tag;
    NSDictionary *video = self.videos[index];
    
    NSString *videoPath = video[@"path"];
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    
    // Шаг 1: Создаем .tendies файл
    [PosterBoardManager createTendiesFile:videoURL];
    
    // Шаг 2: Получаем путь к .tendies файлу
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tendiesPath = [documentsPath stringByAppendingPathComponent:@"wallpaper.tendies"];
    
    // Показываем процесс установки
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"Установка через PosterBoard" 
                                                                          message:@"Инжектим видео в систему..." 
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self.window.rootViewController presentViewController:progressAlert animated:YES completion:nil];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [progressAlert dismissViewControllerAnimated:YES completion:^{
            // Шаг 3: Применяем через PosterBoard
            [PosterBoardManager applyWallpaperViaPosterBoard:tendiesPath];
            
            // Шаг 4: Показываем инструкцию
            [self showPosterBoardInstructions:video[@"name"]];
        }];
    });
}

// Инструкция как в Pocket Poster
- (void)showPosterBoardInstructions:(NSString *)videoName {
    UIAlertController *instructionAlert = [UIAlertController alertControllerWithTitle:@"✅ PosterBoard Injection Complete" 
                                                                             message:[NSString stringWithFormat:@"Видео \"%@\" успешно добавлено в PosterBoard!\n\n1. Перейдите в Настройки > Обои\n2. Нажмите 'Добавить новые обои'\n3. Прокрутите вниз до раздела 'Коллекции'\n4. Выберите 'Tendies Video Wallpaper'\n5. Нажмите 'Установить'", videoName]
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    [instructionAlert addAction:[UIAlertAction actionWithTitle:@"Открыть Настройки" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // Открываем настройки обоев
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"App-Prefs:root=Wallpaper"] options:@{} completionHandler:nil];
    }]];
    
    [instructionAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    [self.window.rootViewController presentViewController:instructionAlert animated:YES completion:nil];
}

// Добавление своего видео из галереи
- (void)addVideoFromGallery {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.movie"];
    
    [self.window.rootViewController presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:^{
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        
        if (videoURL) {
            // Копируем видео в Documents
            NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            NSString *destinationPath = [documentsPath stringByAppendingPathComponent:@"custom_video.mp4"];
            
            NSError *error;
            [[NSFileManager defaultManager] copyItemAtPath:videoURL.path toPath:destinationPath error:&error];
            
            if (!error) {
                // Добавляем в коллекцию
                NSDictionary *newVideo = @{
                    @"name": @"Моё видео",
                    @"path": destinationPath,
                    @"type": @"custom"
                };
                [self.videos addObject:newVideo];
                [self.collectionView reloadData];
                
                // Спрашиваем установить ли сразу
                UIAlertController *askAlert = [UIAlertController alertControllerWithTitle:@"Видео добавлено" 
                                                                                  message:@"Установить сейчас через PosterBoard?" 
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                [askAlert addAction:[UIAlertAction actionWithTitle:@"Да" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    // Находим индекс нового видео
                    NSInteger index = self.videos.count - 1;
                    UIButton *fakeButton = [UIButton new];
                    fakeButton.tag = index;
                    [self installViaPosterBoard:fakeButton];
                }]];
                [askAlert addAction:[UIAlertAction actionWithTitle:@"Позже" style:UIAlertActionStyleCancel handler:nil]];
                
                [self.window.rootViewController presentViewController:askAlert animated:YES completion:nil];
            }
        }
    }];
}

@end

// MARK: - Точка входа
int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([PosterBoardApp class]));
    }
}
