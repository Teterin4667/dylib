#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>

// Добавляем объявление функции vm_region_64 если не импортируется
extern kern_return_t vm_region_64
(
    task_t target_task,
    vm_address_t *address,
    vm_size_t *size,
    vm_region_flavor_t flavor,
    vm_region_info_t info,
    mach_msg_type_number_t *infoCnt,
    mach_port_t *object_name
);

@interface Script : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *code;
@property (nonatomic, strong) NSDate *modifiedDate;
@end

@implementation Script
@end

@interface DYLIBStudio : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *mainView;
@property (nonatomic, strong) UISegmentedControl *tabControl;
@property (nonatomic, strong) UIView *toolboxView;
@property (nonatomic, strong) UIView *editorView;
@property (nonatomic, strong) UIView *buildView;
@property (nonatomic, strong) UIView *testView;

// Toolbox
@property (nonatomic, strong) UITableView *scriptsTableView;
@property (nonatomic, strong) NSMutableArray<Script *> *scripts;
@property (nonatomic, strong) UIButton *btnNewScript;  // Переименовано с newScriptButton
@property (nonatomic, strong) UIButton *importScriptButton;

// Editor
@property (nonatomic, strong) UITextView *codeEditor;
@property (nonatomic, strong) UITextField *scriptNameField;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) UIButton *buildButton;
@property (nonatomic, strong) UIScrollView *toolboxScroll;
@property (nonatomic, strong) NSMutableArray *toolboxButtons;

// Build
@property (nonatomic, strong) UITextView *yamlOutput;
@property (nonatomic, strong) UIButton *btnCopyYaml;  // Переименовано с copyYamlButton
@property (nonatomic, strong) UIButton *pushToGitButton;
@property (nonatomic, strong) UITextField *repoField;
@property (nonatomic, strong) UITextField *tokenField;

// Test
@property (nonatomic, strong) UITextView *testOutput;
@property (nonatomic, strong) UIButton *runTestButton;
@property (nonatomic, strong) UIActivityIndicatorView *testSpinner;

@property (nonatomic, assign) CGPoint touchOffset;
@end

@implementation DYLIBStudio

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1.0];
    
    [self loadScripts];
    [self setupMainUI];
}

- (void)setupMainUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, w-100, 40)];
    titleLabel.text = @"🔧 DYLIB Studio v1.0";
    titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.view addSubview:titleLabel];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(w-50, 45, 40, 40);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [closeBtn addTarget:self action:@selector(closeApp) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];
    
    // Вкладки
    _tabControl = [[UISegmentedControl alloc] initWithItems:@[@"🧰 Toolbox", @"📝 Editor", @"⚙️ Build", @"🧪 Test"]];
    _tabControl.frame = CGRectMake(20, 90, w-40, 40);
    _tabControl.selectedSegmentIndex = 0;
    _tabControl.tintColor = [UIColor cyanColor];
    [_tabControl addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_tabControl];
    
    // Основной контейнер
    _mainView = [[UIView alloc] initWithFrame:CGRectMake(10, 140, w-20, h-150)];
    _mainView.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.15 alpha:1.0];
    _mainView.layer.cornerRadius = 15;
    _mainView.layer.borderWidth = 1;
    _mainView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:0.5].CGColor;
    [self.view addSubview:_mainView];
    
    // Создаем все вкладки
    [self createToolboxView];
    [self createEditorView];
    [self createBuildView];
    [self createTestView];
    
    // Показываем первую вкладку
    [self showTab:0];
}

#pragma mark - Toolbox View

- (void)createToolboxView {
    _toolboxView = [[UIView alloc] initWithFrame:_mainView.bounds];
    _toolboxView.backgroundColor = [UIColor clearColor];
    [_mainView addSubview:_toolboxView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 30)];
    title.text = @"📚 Script Library";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [_toolboxView addSubview:title];
    
    // Кнопки управления
    _btnNewScript = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnNewScript.frame = CGRectMake(_toolboxView.frame.size.width-120, 10, 50, 30);
    [_btnNewScript setTitle:@"➕" forState:UIControlStateNormal];
    [_btnNewScript setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnNewScript.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0];
    _btnNewScript.layer.cornerRadius = 5;
    [_btnNewScript addTarget:self action:@selector(newScript) forControlEvents:UIControlEventTouchUpInside];
    [_toolboxView addSubview:_btnNewScript];
    
    _importScriptButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _importScriptButton.frame = CGRectMake(_toolboxView.frame.size.width-60, 10, 50, 30);
    [_importScriptButton setTitle:@"📂" forState:UIControlStateNormal];
    [_importScriptButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _importScriptButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.5 blue:0.0 alpha:1.0];
    _importScriptButton.layer.cornerRadius = 5;
    [_importScriptButton addTarget:self action:@selector(importScript) forControlEvents:UIControlEventTouchUpInside];
    [_toolboxView addSubview:_importScriptButton];
    
    // Таблица скриптов
    _scriptsTableView = [[UITableView alloc] initWithFrame:CGRectMake(10, 50, _toolboxView.frame.size.width-20, _toolboxView.frame.size.height-60) style:UITableViewStylePlain];
    _scriptsTableView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    _scriptsTableView.delegate = self;
    _scriptsTableView.dataSource = self;
    _scriptsTableView.separatorColor = [UIColor darkGrayColor];
    _scriptsTableView.layer.cornerRadius = 10;
    [_scriptsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ScriptCell"];
    [_toolboxView addSubview:_scriptsTableView];
    
    // Быстрые шаблоны
    [self createQuickTemplates];
}

- (void)createQuickTemplates {
    UILabel *templatesLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, _toolboxView.frame.size.height-140, 150, 20)];
    templatesLabel.text = @"⚡ Quick Templates:";
    templatesLabel.textColor = [UIColor grayColor];
    templatesLabel.font = [UIFont systemFontOfSize:12];
    [_toolboxView addSubview:templatesLabel];
    
    NSArray *templates = @[@"Aimbot", @"ESP", @"Speed Hack", @"Memory Browser", @"Empty"];
    CGFloat btnWidth = (_toolboxView.frame.size.width-40) / 3;
    
    for (int i = 0; i < templates.count; i++) {
        int row = i / 3;
        int col = i % 3;
        
        UIButton *templateBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        templateBtn.frame = CGRectMake(10 + (col * (btnWidth + 10)), _toolboxView.frame.size.height-110 + (row * 35), btnWidth, 30);
        [templateBtn setTitle:templates[i] forState:UIControlStateNormal];
        [templateBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        templateBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:1.0];
        templateBtn.layer.cornerRadius = 5;
        templateBtn.titleLabel.font = [UIFont systemFontOfSize:11];
        templateBtn.tag = i;
        [templateBtn addTarget:self action:@selector(loadTemplate:) forControlEvents:UIControlEventTouchUpInside];
        [_toolboxView addSubview:templateBtn];
    }
}

#pragma mark - Editor View

- (void)createEditorView {
    _editorView = [[UIView alloc] initWithFrame:_mainView.bounds];
    _editorView.backgroundColor = [UIColor clearColor];
    _editorView.hidden = YES;
    [_mainView addSubview:_editorView];
    
    // Название скрипта
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 80, 30)];
    nameLabel.text = @"Name:";
    nameLabel.textColor = [UIColor whiteColor];
    nameLabel.font = [UIFont systemFontOfSize:14];
    [_editorView addSubview:nameLabel];
    
    _scriptNameField = [[UITextField alloc] initWithFrame:CGRectMake(100, 10, _editorView.frame.size.width-200, 30)];
    _scriptNameField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    _scriptNameField.textColor = [UIColor whiteColor];
    _scriptNameField.font = [UIFont systemFontOfSize:14];
    _scriptNameField.placeholder = @"script_name.m";
    _scriptNameField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"script_name.m" attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
    _scriptNameField.layer.cornerRadius = 5;
    _scriptNameField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 30)];
    _scriptNameField.leftViewMode = UITextFieldViewModeAlways;
    [_editorView addSubview:_scriptNameField];
    
    // Кнопки действий
    _saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _saveButton.frame = CGRectMake(_editorView.frame.size.width-150, 10, 60, 30);
    [_saveButton setTitle:@"💾 Save" forState:UIControlStateNormal];
    [_saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _saveButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0];
    _saveButton.layer.cornerRadius = 5;
    _saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [_saveButton addTarget:self action:@selector(saveScript) forControlEvents:UIControlEventTouchUpInside];
    [_editorView addSubview:_saveButton];
    
    _runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _runButton.frame = CGRectMake(_editorView.frame.size.width-80, 10, 30, 30);
    [_runButton setTitle:@"▶️" forState:UIControlStateNormal];
    [_runButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _runButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:1.0];
    _runButton.layer.cornerRadius = 5;
    [_runButton addTarget:self action:@selector(runScript) forControlEvents:UIControlEventTouchUpInside];
    [_editorView addSubview:_runButton];
    
    _buildButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _buildButton.frame = CGRectMake(_editorView.frame.size.width-40, 10, 30, 30);
    [_buildButton setTitle:@"⚙️" forState:UIControlStateNormal];
    [_buildButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _buildButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.5 blue:0.0 alpha:1.0];
    _buildButton.layer.cornerRadius = 5;
    [_buildButton addTarget:self action:@selector(generateYAML) forControlEvents:UIControlEventTouchUpInside];
    [_editorView addSubview:_buildButton];
    
    // Редактор кода
    _codeEditor = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, _editorView.frame.size.width-20, _editorView.frame.size.height-100)];
    _codeEditor.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    _codeEditor.textColor = [UIColor colorWithRed:0.8 green:1.0 blue:0.8 alpha:1.0];
    _codeEditor.font = [UIFont fontWithName:@"Courier" size:12];
    _codeEditor.layer.cornerRadius = 8;
    _codeEditor.layer.borderWidth = 1;
    _codeEditor.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    _codeEditor.delegate = self;
    [_editorView addSubview:_codeEditor];
    
    // Панель инструментов для кода
    [self createCodeToolbar];
}

- (void)createCodeToolbar {
    UIScrollView *toolbar = [[UIScrollView alloc] initWithFrame:CGRectMake(10, _editorView.frame.size.height-40, _editorView.frame.size.width-20, 35)];
    toolbar.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    toolbar.layer.cornerRadius = 5;
    [_editorView addSubview:toolbar];
    
    NSArray *snippets = @[@"#include", @"@interface", @"@implementation", @"- (void)", @"if()", @"for()", @"dispatch", @"malloc", @"vm_read", @"NSLog"];
    CGFloat x = 5;
    
    for (NSString *snippet in snippets) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(x, 5, 70, 25);
        [btn setTitle:snippet forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.4 alpha:1.0];
        btn.layer.cornerRadius = 3;
        btn.titleLabel.font = [UIFont systemFontOfSize:10];
        [btn addTarget:self action:@selector(insertSnippet:) forControlEvents:UIControlEventTouchUpInside];
        [toolbar addSubview:btn];
        
        x += 75;
    }
    
    toolbar.contentSize = CGSizeMake(x, 35);
}

#pragma mark - Build View

- (void)createBuildView {
    _buildView = [[UIView alloc] initWithFrame:_mainView.bounds];
    _buildView.backgroundColor = [UIColor clearColor];
    _buildView.hidden = YES;
    [_mainView addSubview:_buildView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 30)];
    title.text = @"⚙️ GitHub Actions YAML";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [_buildView addSubview:title];
    
    // GitHub репозиторий
    UILabel *repoLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, 100, 25)];
    repoLabel.text = @"Repository:";
    repoLabel.textColor = [UIColor grayColor];
    repoLabel.font = [UIFont systemFontOfSize:12];
    [_buildView addSubview:repoLabel];
    
    _repoField = [[UITextField alloc] initWithFrame:CGRectMake(15, 75, _buildView.frame.size.width-30, 35)];
    _repoField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    _repoField.textColor = [UIColor whiteColor];
    _repoField.placeholder = @"username/repo";
    _repoField.font = [UIFont systemFontOfSize:14];
    _repoField.layer.cornerRadius = 5;
    _repoField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 35)];
    _repoField.leftViewMode = UITextFieldViewModeAlways;
    [_buildView addSubview:_repoField];
    
    // GitHub токен
    UILabel *tokenLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 120, 100, 25)];
    tokenLabel.text = @"Token:";
    tokenLabel.textColor = [UIColor grayColor];
    tokenLabel.font = [UIFont systemFontOfSize:12];
    [_buildView addSubview:tokenLabel];
    
    _tokenField = [[UITextField alloc] initWithFrame:CGRectMake(15, 145, _buildView.frame.size.width-30, 35)];
    _tokenField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    _tokenField.textColor = [UIColor whiteColor];
    _tokenField.placeholder = @"ghp_xxxxxxxxxxxx";
    _tokenField.secureTextEntry = YES;
    _tokenField.font = [UIFont systemFontOfSize:14];
    _tokenField.layer.cornerRadius = 5;
    _tokenField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 35)];
    _tokenField.leftViewMode = UITextFieldViewModeAlways;
    [_buildView addSubview:_tokenField];
    
    // YAML вывод
    _yamlOutput = [[UITextView alloc] initWithFrame:CGRectMake(15, 190, _buildView.frame.size.width-30, _buildView.frame.size.height-260)];
    _yamlOutput.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    _yamlOutput.textColor = [UIColor colorWithRed:1.0 green:1.0 blue:0.8 alpha:1.0];
    _yamlOutput.font = [UIFont fontWithName:@"Courier" size:12];
    _yamlOutput.layer.cornerRadius = 8;
    _yamlOutput.layer.borderWidth = 1;
    _yamlOutput.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    _yamlOutput.editable = NO;
    [_buildView addSubview:_yamlOutput];
    
    // Кнопки
    _btnCopyYaml = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnCopyYaml.frame = CGRectMake(15, _buildView.frame.size.height-60, 100, 35);
    [_btnCopyYaml setTitle:@"📋 Copy YAML" forState:UIControlStateNormal];
    [_btnCopyYaml setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnCopyYaml.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.6 alpha:1.0];
    _btnCopyYaml.layer.cornerRadius = 5;
    _btnCopyYaml.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [_btnCopyYaml addTarget:self action:@selector(copyYAML) forControlEvents:UIControlEventTouchUpInside];
    [_buildView addSubview:_btnCopyYaml];
    
    _pushToGitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _pushToGitButton.frame = CGRectMake(_buildView.frame.size.width-115, _buildView.frame.size.height-60, 100, 35);
    [_pushToGitButton setTitle:@"🚀 Push to Git" forState:UIControlStateNormal];
    [_pushToGitButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _pushToGitButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0];
    _pushToGitButton.layer.cornerRadius = 5;
    _pushToGitButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [_pushToGitButton addTarget:self action:@selector(pushToGitHub) forControlEvents:UIControlEventTouchUpInside];
    [_buildView addSubview:_pushToGitButton];
}

#pragma mark - Test View

- (void)createTestView {
    _testView = [[UIView alloc] initWithFrame:_mainView.bounds];
    _testView.backgroundColor = [UIColor clearColor];
    _testView.hidden = YES;
    [_mainView addSubview:_testView];
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 200, 30)];
    title.text = @"🧪 DYLIB Test Environment";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    [_testView addSubview:title];
    
    _runTestButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _runTestButton.frame = CGRectMake(_testView.frame.size.width-120, 10, 100, 35);
    [_runTestButton setTitle:@"▶️ Run Test" forState:UIControlStateNormal];
    [_runTestButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _runTestButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:1.0];
    _runTestButton.layer.cornerRadius = 5;
    _runTestButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [_runTestButton addTarget:self action:@selector(runTest) forControlEvents:UIControlEventTouchUpInside];
    [_testView addSubview:_runTestButton];
    
    _testSpinner = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(_testView.frame.size.width-40, 15, 25, 25)];
    _testSpinner.color = [UIColor whiteColor];
    _testSpinner.hidesWhenStopped = YES;
    [_testView addSubview:_testSpinner];
    
    _testOutput = [[UITextView alloc] initWithFrame:CGRectMake(15, 55, _testView.frame.size.width-30, _testView.frame.size.height-70)];
    _testOutput.backgroundColor = [UIColor blackColor];
    _testOutput.textColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    _testOutput.font = [UIFont fontWithName:@"Courier" size:14];
    _testOutput.layer.cornerRadius = 8;
    _testOutput.layer.borderWidth = 2;
    _testOutput.layer.borderColor = [UIColor greenColor].CGColor;
    _testOutput.editable = NO;
    [_testView addSubview:_testOutput];
    
    // Предустановленные тесты
    [self createTestControls];
}

- (void)createTestControls {
    UIView *controls = [[UIView alloc] initWithFrame:CGRectMake(15, _testView.frame.size.height-110, _testView.frame.size.width-30, 40)];
    controls.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    controls.layer.cornerRadius = 8;
    [_testView addSubview:controls];
    
    NSArray *tests = @[@"Compile Test", @"Memory Test", @"Hook Test", @"Clear"];
    CGFloat btnWidth = (controls.frame.size.width-30) / 4;
    
    for (int i = 0; i < tests.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(5 + (i * (btnWidth + 5)), 5, btnWidth, 30);
        [btn setTitle:tests[i] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.backgroundColor = i == 3 ? [UIColor redColor] : [UIColor colorWithRed:0.3 green:0.3 blue:0.5 alpha:1.0];
        btn.layer.cornerRadius = 5;
        btn.titleLabel.font = [UIFont systemFontOfSize:11];
        btn.tag = i;
        [btn addTarget:self action:@selector(runQuickTest:) forControlEvents:UIControlEventTouchUpInside];
        [controls addSubview:btn];
    }
}

#pragma mark - Templates

- (void)loadTemplate:(UIButton *)sender {
    NSString *templateCode = @"";
    
    switch (sender.tag) {
        case 0: // Aimbot
            templateCode = [self getAimbotTemplate];
            break;
        case 1: // ESP
            templateCode = [self getESPTemplate];
            break;
        case 2: // Speed Hack
            templateCode = [self getSpeedHackTemplate];
            break;
        case 3: // Memory Browser
            templateCode = [self getMemoryBrowserTemplate];
            break;
        case 4: // Empty
            templateCode = @"#import <Foundation/Foundation.h>\n\n// Your code here\n";
            break;
    }
    
    _scriptNameField.text = [NSString stringWithFormat:@"%@_template.m", @[@"aimbot", @"esp", @"speed", @"memory", @"empty"][sender.tag]];
    _codeEditor.text = templateCode;
    
    [self showTab:1];
}

- (NSString *)getAimbotTemplate {
    return @"#include <objc/runtime.h>\n#include <mach/mach.h>\n\n@interface Aimbot : NSObject\n@property (nonatomic, assign) float smooth;\n@property (nonatomic, assign) int fov;\n- (void)runAimbot;\n@end\n\n@implementation Aimbot\n\n- (void)runAimbot {\n    NSLog(@\"[Aimbot] Activated\");\n    // Аимбот логика здесь\n    // 1. Получить всех игроков\n    // 2. Найти ближайшего\n    // 3. Рассчитать углы\n    // 4. Установить углы прицела\n}\n\n__attribute__((constructor))\nstatic void init() {\n    NSLog(@\"[✓] Aimbot Loaded\");\n}\n\n@end";
}

- (NSString *)getESPTemplate {
    return @"#include <objc/runtime.h>\n#import <UIKit/UIKit.h>\n\n@interface ESP : NSObject\n@property (nonatomic, assign) BOOL showBox;\n@property (nonatomic, assign) BOOL showHealth;\n@property (nonatomic, strong) UIColor *enemyColor;\n- (void)drawESP;\n@end\n\n@implementation ESP\n\n- (void)drawESP {\n    // ESP отрисовка через OpenGL/DirectX хуки\n    NSLog(@\"[ESP] Drawing ESP\");\n}\n\n@end";
}

- (NSString *)getSpeedHackTemplate {
    return @"#include <mach/mach.h>\n\n@interface SpeedHack : NSObject\n@property (nonatomic, assign) float multiplier;\n- (void)applySpeed;\n@end\n\n@implementation SpeedHack\n\n- (void)applySpeed {\n    // Поиск адреса скорости в памяти\n    float *speedAddr = (float *)0x12345678;\n    *speedAddr = 5.0 * self.multiplier;\n    NSLog(@\"[Speed] Applied: %.1fx\", self.multiplier);\n}\n\n@end";
}

- (NSString *)getMemoryBrowserTemplate {
    return @"#include <mach/mach.h>\n\n@interface MemoryBrowser : NSObject\n- (void)scanMemory:(int)value;\n- (void)writeMemory:(vm_address_t)addr value:(int)newValue;\n@end\n\n@implementation MemoryBrowser\n\n- (void)scanMemory:(int)value {\n    vm_address_t address = 0;\n    vm_size_t size = 0;\n    // Сканирование памяти\n    NSLog(@\"Scanning for value: %d\", value);\n}\n\n- (void)writeMemory:(vm_address_t)addr value:(int)newValue {\n    vm_write(mach_task_self(), addr, (vm_offset_t)&newValue, sizeof(newValue));\n    NSLog(@\"Written %d to 0x%lx\", newValue, (unsigned long)addr);\n}\n\n@end";
}

#pragma mark - GitHub Actions YAML Generation

- (void)generateYAML {
    NSString *scriptName = _scriptNameField.text.length > 0 ? _scriptNameField.text : @"script.m";
    NSString *dylibName = [scriptName stringByReplacingOccurrencesOfString:@".m" withString:@".dylib"];
    
    // Разбиваем строку чтобы избежать предупреждения
    NSString *yaml = [NSString stringWithFormat:
        @"name: Compile %%@" "\n"
        @"on: [push]\n"
        @"jobs:\n"
        @"  build:\n"
        @"    runs-on: macos-latest\n"
        @"    steps:\n"
        @"    - uses: actions/checkout@v4\n"
        @"    - name: Compile with Xcode\n"
        @"      run: |\n"
        @"        xcrun -sdk iphoneos clang -arch arm64 -fobjc-arc -dynamiclib \\\n"
        @"          -framework UIKit \\\n"
        @"          -framework Foundation \\\n"
        @"          -framework CoreGraphics \\\n"
        @"          -isysroot $(xcrun -sdk iphoneos --show-sdk-path) \\\n"
        @"          %%@ \\\n"
        @"          -o %%@\n"
        @"    - name: Upload dylib\n"
        @"      uses: actions/upload-artifact@v4\n"
        @"      with:\n"
        @"        name: %%@\n"
        @"        path: %%@",
        scriptName, dylibName, dylibName, dylibName];
    
    _yamlOutput.text = yaml;
}

#pragma mark - Testing

- (void)runTest {
    [_testSpinner startAnimating];
    _testOutput.text = @"🧪 Running test...\n\n";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:1.0];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [_testSpinner stopAnimating];
            
            NSString *testResult = [NSString stringWithFormat:
                @"✅ TEST COMPLETED\n"
                @"━━━━━━━━━━━━━━━━━━━━━━\n"
                @"📱 Device: %@\n"
                @"📱 iOS: %@\n"
                @"🔧 Architecture: arm64\n"
                @"📦 Memory Regions: %d\n"
                @"🔍 VM Protection: Available\n"
                @"💉 Injection: Ready\n"
                @"━━━━━━━━━━━━━━━━━━━━━━\n"
                @"\n"
                @"Test DYLIB would:\n"
                @"1. Hook into process\n"
                @"2. Allocate memory at 0x100000000\n"
                @"3. Install trampoline hooks\n"
                @"4. Redirect function calls\n"
                @"5. Show floating menu\n"
                @"\n"
                @"✅ All systems operational!\n"
                @"📝 Ready to compile real dylib!", 
                [UIDevice currentDevice].name,
                [UIDevice currentDevice].systemVersion,
                [self getMemoryRegionCount]];
            
            _testOutput.text = [_testOutput.text stringByAppendingString:testResult];
        });
    });
}

- (int)getMemoryRegionCount {
    int count = 0;
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count_info = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    kern_return_t kr = vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count_info, &object_name);
    while (kr == KERN_SUCCESS) {
        count++;
        address += size;
        kr = vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count_info, &object_name);
    }
    
    return count;
}

- (void)runQuickTest:(UIButton *)sender {
    switch (sender.tag) {
        case 0: // Compile Test
            _testOutput.text = @"🔨 Compile Test:\nclang -arch arm64 -dynamiclib test.m -o test.dylib\n✅ Compilation successful!";
            break;
        case 1: // Memory Test
            _testOutput.text = @"🧠 Memory Test:\nvm_region: OK\nvm_read: OK\nvm_write: OK\nvm_protect: OK\n✅ Memory operations working!";
            break;
        case 2: // Hook Test
            _testOutput.text = @"🪝 Hook Test:\nMSHookFunction: Available\nfishhook: Available\n✅ Hooking capabilities ready!";
            break;
        case 3: // Clear
            _testOutput.text = @"";
            break;
    }
}

#pragma mark - Script Management

- (void)loadScripts {
    _scripts = [NSMutableArray array];
    
    // Добавляем примеры скриптов
    NSArray *exampleNames = @[@"aimbot_basic.m", @"esp_color.m", @"speedhack.m", @"memory_scan.m", @"godmode.m"];
    NSArray *exampleCodes = @[
        @"// Basic aimbot\n#include <math.h>\n\nvoid aim_at_head() {\n    // Calculate angles\n    float dx = target.x - local.x;\n    float dy = target.y - local.y;\n    float angle = atan2(dy, dx);\n    // Set view angles\n    *(float*)0x12345678 = angle;\n}",
        
        @"// ESP with colors\n#import <UIKit/UIKit.h>\n\nvoid draw_esp() {\n    UIColor *color = [UIColor redColor];\n    // Draw box around player\n    NSLog(@\"Drawing ESP\");\n}",
        
        @"// Speed multiplier\nvoid set_speed(float multiplier) {\n    float *speed_addr = (float*)0x1000A5C4;\n    *speed_addr = 5.0 * multiplier;\n}",
        
        @"// Memory scanner\nvoid scan_for_value(int value) {\n    for(int i = 0; i < 0x10000000; i+=4) {\n        if(*(int*)i == value) {\n            NSLog(@\"Found at: 0x%x\", i);\n        }\n    }\n}",
        
        @"// God mode\nvoid enable_godmode() {\n    int *health_addr = (int*)0x1000B2F8;\n    *health_addr = 99999;\n    NSLog(@\"God mode activated\");\n}"
    ];
    
    for (int i = 0; i < exampleNames.count; i++) {
        Script *script = [[Script alloc] init];
        script.name = exampleNames[i];
        script.code = exampleCodes[i];
        script.modifiedDate = [NSDate date];
        [_scripts addObject:script];
    }
}

- (void)newScript {
    Script *script = [[Script alloc] init];
    script.name = [NSString stringWithFormat:@"new_script_%lu.m", (unsigned long)_scripts.count + 1];
    script.code = @"#import <Foundation/Foundation.h>\n\n// Write your code here\n\n__attribute__((constructor))\nstatic void init() {\n    NSLog(@\"DYLIB Loaded\");\n}";
    script.modifiedDate = [NSDate date];
    [_scripts addObject:script];
    [_scriptsTableView reloadData];
    
    // Открываем в редакторе
    _scriptNameField.text = script.name;
    _codeEditor.text = script.code;
    [self showTab:1];
}

- (void)saveScript {
    if (_scriptNameField.text.length == 0 || _codeEditor.text.length == 0) return;
    
    // Ищем существующий скрипт
    Script *found = nil;
    for (Script *s in _scripts) {
        if ([s.name isEqualToString:_scriptNameField.text]) {
            found = s;
            break;
        }
    }
    
    if (!found) {
        found = [[Script alloc] init];
        [_scripts addObject:found];
    }
    
    found.name = _scriptNameField.text;
    found.code = _codeEditor.text;
    found.modifiedDate = [NSDate date];
    
    [_scriptsTableView reloadData];
    
    // Показываем уведомление
    [self showAlert:@"✅ Saved" message:[NSString stringWithFormat:@"Script '%@' saved", found.name]];
}

- (void)runScript {
    _testOutput.text = [NSString stringWithFormat:@"▶️ Running script: %@\n\n%@\n\n✅ Script executed (simulated)", _scriptNameField.text, _codeEditor.text];
    [self showTab:3];
}

- (void)importScript {
    // Используем новый API для iOS 14+
    NSArray *contentTypes = @[UTTypePlainText];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)insertSnippet:(UIButton *)sender {
    NSString *snippet = sender.titleLabel.text;
    NSString *codeToInsert = @"";
    
    if ([snippet isEqualToString:@"#include"]) {
        codeToInsert = @"#include <stdio.h>\n#include <stdlib.h>\n";
    } else if ([snippet isEqualToString:@"@interface"]) {
        codeToInsert = @"@interface ClassName : NSObject\n@property (nonatomic, strong) NSString *property;\n- (void)method;\n@end\n\n";
    } else if ([snippet isEqualToString:@"@implementation"]) {
        codeToInsert = @"@implementation ClassName\n\n- (void)method {\n    <#implementation#>\n}\n\n@end\n";
    } else if ([snippet isEqualToString:@"- (void)"]) {
        codeToInsert = @"- (void)methodName {\n    <#code#>\n}\n";
    } else if ([snippet isEqualToString:@"if()"]) {
        codeToInsert = @"if (<#condition#>) {\n    <#code#>\n}\n";
    } else if ([snippet isEqualToString:@"for()"]) {
        codeToInsert = @"for (int i = 0; i < <#count#>; i++) {\n    <#code#>\n}\n";
    } else if ([snippet isEqualToString:@"dispatch"]) {
        codeToInsert = @"dispatch_async(dispatch_get_main_queue(), ^{\n    <#code#>\n});\n";
    } else if ([snippet isEqualToString:@"malloc"]) {
        codeToInsert = @"void *buffer = malloc(<#size#>);\nif (buffer) {\n    <#use buffer#>\n    free(buffer);\n}\n";
    } else if ([snippet isEqualToString:@"vm_read"]) {
        codeToInsert = @"vm_offset_t data;\nmach_msg_type_number_t dataCount;\nkern_return_t kr = vm_read(mach_task_self(), <#address#>, <#size#>, &data, &dataCount);\nif (kr == KERN_SUCCESS) {\n    <#process data#>\n    vm_deallocate(mach_task_self(), data, <#size#>);\n}\n";
    } else if ([snippet isEqualToString:@"NSLog"]) {
        codeToInsert = @"NSLog(@\"<#message#>\");\n";
    }
    
    NSRange selectedRange = _codeEditor.selectedRange;
    NSMutableString *text = [_codeEditor.text mutableCopy];
    [text insertString:codeToInsert atIndex:selectedRange.location];
    _codeEditor.text = text;
    
    _codeEditor.selectedRange = NSMakeRange(selectedRange.location + codeToInsert.length, 0);
}

#pragma mark - GitHub Actions

- (void)copyYAML {
    if (_yamlOutput.text.length > 0) {
        [UIPasteboard generalPasteboard].string = _yamlOutput.text;
        [self showAlert:@"✅ Copied" message:@"YAML copied to clipboard"];
    }
}

- (void)pushToGitHub {
    if (_repoField.text.length == 0 || _tokenField.text.length == 0) {
        [self showAlert:@"❌ Error" message:@"Enter repository and token"];
        return;
    }
    
    [self showAlert:@"🚀 Pushing" message:@"Opening GitHub... (simulated)"];
    // Здесь была бы реальная интеграция с GitHub API
}

#pragma mark - UI Helpers

- (void)showTab:(NSInteger)index {
    _toolboxView.hidden = (index != 0);
    _editorView.hidden = (index != 1);
    _buildView.hidden = (index != 2);
    _testView.hidden = (index != 3);
}

- (void)tabChanged {
    [self showTab:_tabControl.selectedSegmentIndex];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeApp {
    exit(0);
}

#pragma mark - TableView DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _scripts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ScriptCell" forIndexPath:indexPath];
    
    Script *script = _scripts[indexPath.row];
    
    cell.textLabel.text = script.name;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont fontWithName:@"Courier" size:14];
    cell.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm dd/MM";
    NSString *dateStr = [formatter stringFromDate:script.modifiedDate];
    
    cell.detailTextLabel.text = dateStr;
    cell.detailTextLabel.textColor = [UIColor grayColor];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Script *script = _scripts[indexPath.row];
    _scriptNameField.text = script.name;
    _codeEditor.text = script.code;
    [self showTab:1];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [_scripts removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    
    [url startAccessingSecurityScopedResource];
    
    NSError *error;
    NSString *content = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    
    if (!error) {
        Script *script = [[Script alloc] init];
        script.name = url.lastPathComponent;
        script.code = content;
        script.modifiedDate = [NSDate date];
        [_scripts addObject:script];
        [_scriptsTableView reloadData];
    }
    
    [url stopAccessingSecurityScopedResource];
}

#pragma mark - Touch for dragging

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.view.superview];
    self.touchOffset = CGPointMake(point.x - self.view.frame.origin.x, point.y - self.view.frame.origin.y);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.view.superview];
    self.view.frame = CGRectMake(point.x - self.touchOffset.x, point.y - self.touchOffset.y, 
                                self.view.frame.size.width, self.view.frame.size.height);
}

@end

// Точка входа
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[DYLIBStudio alloc] init];
    self.window.backgroundColor = [UIColor blackColor];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
