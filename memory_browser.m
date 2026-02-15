#include <objc/runtime.h>
#include <UIKit/UIKit.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <sys/mman.h>

@interface MemoryBrowser : UIView <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UIButton *scanTypeButton;
@property (nonatomic, strong) UIButton *freezeButton;
@property (nonatomic, strong) UISegmentedControl *valueTypeControl;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *addressLabel;
@property (nonatomic, strong) NSMutableArray *searchResults;
@property (nonatomic, strong) NSMutableArray *frozenAddresses;
@property (nonatomic, strong) NSTimer *freezeTimer;
@property (nonatomic, assign) CGPoint touchOffset;
@property (nonatomic, assign) int scanType; // 0: New scan, 1: Next scan
@property (nonatomic, strong) NSString *lastSearchValue;
@property (nonatomic, strong) NSMutableDictionary *memoryRegions;
@end

@implementation MemoryBrowser

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.frame = CGRectMake(20, 50, 380, 600);
        self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.98];
        self.layer.cornerRadius = 15;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0].CGColor;
        
        _searchResults = [NSMutableArray array];
        _frozenAddresses = [NSMutableArray array];
        _memoryRegions = [NSMutableDictionary dictionary];
        _scanType = 0;
        
        [self setupUI];
        [self getMemoryRegions];
        
        // Таймер для замороженных значений
        _freezeTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateFrozenValues) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)setupUI {
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, 250, 30)];
    titleLabel.text = @"🧠 MEMORY BROWSER v1.0";
    titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self addSubview:titleLabel];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(340, 10, 30, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [closeBtn addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:closeBtn];
    
    // Статус
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 45, 350, 20)];
    _statusLabel.text = @"Status: Ready | Regions: 0";
    _statusLabel.textColor = [UIColor greenColor];
    _statusLabel.font = [UIFont systemFontOfSize:12];
    [self addSubview:_statusLabel];
    
    // Тип значения
    UILabel *typeLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 75, 80, 25)];
    typeLabel.text = @"Value Type:";
    typeLabel.textColor = [UIColor whiteColor];
    typeLabel.font = [UIFont systemFontOfSize:12];
    [self addSubview:typeLabel];
    
    _valueTypeControl = [[UISegmentedControl alloc] initWithItems:@[@"Byte", @"Int", @"Float", @"Double", @"String"]];
    _valueTypeControl.frame = CGRectMake(100, 75, 260, 30);
    _valueTypeControl.selectedSegmentIndex = 1; // Int по умолчанию
    _valueTypeControl.tintColor = [UIColor cyanColor];
    [self addSubview:_valueTypeControl];
    
    // Поле поиска
    _searchField = [[UITextField alloc] initWithFrame:CGRectMake(15, 115, 250, 35)];
    _searchField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    _searchField.textColor = [UIColor whiteColor];
    _searchField.font = [UIFont systemFontOfSize:14];
    _searchField.placeholder = @"Enter value to search...";
    _searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Enter value to search..." attributes:@{NSForegroundColorAttributeName: [UIColor grayColor]}];
    _searchField.layer.cornerRadius = 5;
    _searchField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 35)];
    _searchField.leftViewMode = UITextFieldViewModeAlways;
    _searchField.delegate = self;
    _searchField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    _searchField.returnKeyType = UIReturnKeySearch;
    [self addSubview:_searchField];
    
    // Кнопки сканирования
    _searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _searchButton.frame = CGRectMake(275, 115, 45, 35);
    [_searchButton setTitle:@"🔍" forState:UIControlStateNormal];
    [_searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _searchButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0];
    _searchButton.layer.cornerRadius = 5;
    [_searchButton addTarget:self action:@selector(newScan) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_searchButton];
    
    _scanTypeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _scanTypeButton.frame = CGRectMake(325, 115, 45, 35);
    [_scanTypeButton setTitle:@"▶️" forState:UIControlStateNormal];
    [_scanTypeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _scanTypeButton.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.8 alpha:1.0];
    _scanTypeButton.layer.cornerRadius = 5;
    [_scanTypeButton addTarget:self action:@selector(nextScan) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_scanTypeButton];
    
    // Информация об адресе
    _addressLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 160, 350, 20)];
    _addressLabel.text = @"Address: Select a result to edit";
    _addressLabel.textColor = [UIColor yellowColor];
    _addressLabel.font = [UIFont systemFontOfSize:11];
    [self addSubview:_addressLabel];
    
    // Кнопка заморозки
    _freezeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _freezeButton.frame = CGRectMake(250, 155, 120, 30);
    [_freezeButton setTitle:@"❄️ Freeze Selected" forState:UIControlStateNormal];
    [_freezeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _freezeButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.8 alpha:1.0];
    _freezeButton.layer.cornerRadius = 5;
    _freezeButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [_freezeButton addTarget:self action:@selector(freezeSelected) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_freezeButton];
    
    // Таблица результатов
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(10, 195, 360, 380) style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.separatorColor = [UIColor darkGrayColor];
    _tableView.layer.cornerRadius = 10;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self addSubview:_tableView];
    
    // Кнопки управления
    [self createControlButtons];
}

- (void)createControlButtons {
    CGFloat y = 585;
    NSArray *buttons = @[
        @{@"title": @"Clear", @"color": [UIColor redColor], @"action": @"clearResults"},
        @{@"title": @"Regions", @"color": [UIColor purpleColor], @"action": @"showRegions"},
        @{@"title": @"Unfreeze All", @"color": [UIColor orangeColor], @"action": @"unfreezeAll"}
    ];
    
    for (int i = 0; i < buttons.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(10 + (i * 125), y, 115, 30);
        [btn setTitle:buttons[i][@"title"] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.backgroundColor = buttons[i][@"color"];
        btn.layer.cornerRadius = 5;
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [btn addTarget:self action:NSSelectorFromString(buttons[i][@"action"]) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:btn];
    }
}

#pragma mark - Memory Operations

- (void)getMemoryRegions {
    mach_port_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    [_memoryRegions removeAllObjects];
    int regionCount = 0;
    
    while (1) {
        kern_return_t kr = vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if (info.protection & VM_PROT_READ) {
            NSMutableDictionary *region = [NSMutableDictionary dictionary];
            region[@"address"] = @(address);
            region[@"size"] = @(size);
            region[@"protection"] = [NSString stringWithFormat:@"%c%c%c", 
                                     (info.protection & VM_PROT_READ) ? 'r' : '-',
                                     (info.protection & VM_PROT_WRITE) ? 'w' : '-',
                                     (info.protection & VM_PROT_EXECUTE) ? 'x' : '-'];
            [_memoryRegions setObject:region forKey:@(address)];
            regionCount++;
        }
        
        address += size;
    }
    
    _statusLabel.text = [NSString stringWithFormat:@"Status: Ready | Regions: %d | Results: %lu", regionCount, (unsigned long)_searchResults.count];
}

- (void)newScan {
    NSString *searchValue = _searchField.text;
    if (searchValue.length == 0) return;
    
    _lastSearchValue = searchValue;
    _scanType = 0;
    [_searchResults removeAllObjects];
    
    [self performScan:searchValue firstScan:YES];
}

- (void)nextScan {
    if (_lastSearchValue.length == 0 || _searchResults.count == 0) return;
    
    _scanType = 1;
    [self performScan:_lastSearchValue firstScan:NO];
}

- (void)performScan:(NSString *)value firstScan:(BOOL)firstScan {
    int type = (int)_valueTypeControl.selectedSegmentIndex;
    
    if (firstScan) {
        // Сканируем все регионы памяти
        for (NSNumber *addressKey in _memoryRegions.allKeys) {
            vm_address_t addr = [addressKey unsignedLongLongValue];
            NSDictionary *region = _memoryRegions[addressKey];
            vm_size_t size = [region[@"size"] unsignedLongValue];
            
            [self scanRegion:addr size:size value:value type:type];
        }
    } else {
        // Сканируем только предыдущие результаты
        NSMutableArray *newResults = [NSMutableArray array];
        for (NSDictionary *result in _searchResults) {
            vm_address_t addr = [result[@"address"] unsignedLongLongValue];
            id currentValue = [self readMemoryAtAddress:addr type:type];
            
            if ([self compareValue:currentValue withSearch:value type:type]) {
                [newResults addObject:result];
            }
        }
        _searchResults = newResults;
    }
    
    [_tableView reloadData];
    _statusLabel.text = [NSString stringWithFormat:@"Status: Scan complete | Results: %lu", (unsigned long)_searchResults.count];
}

- (void)scanRegion:(vm_address_t)address size:(vm_size_t)size value:(NSString *)searchValue type:(int)type {
    for (vm_address_t addr = address; addr < address + size; addr += [self typeSize:type]) {
        id currentValue = [self readMemoryAtAddress:addr type:type];
        
        if ([self compareValue:currentValue withSearch:searchValue type:type]) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            result[@"address"] = @(addr);
            result[@"value"] = currentValue;
            result[@"type"] = @(type);
            [_searchResults addObject:result];
        }
    }
}

- (int)typeSize:(int)type {
    switch (type) {
        case 0: return 1;  // Byte
        case 1: return 4;  // Int
        case 2: return 4;  // Float
        case 3: return 8;  // Double
        case 4: return 32; // String (примерно)
        default: return 4;
    }
}

- (id)readMemoryAtAddress:(vm_address_t)address type:(int)type {
    switch (type) {
        case 0: { // Byte
            uint8_t value = 0;
            vm_size_t size = sizeof(value);
            vm_offset_t data;
            mach_msg_type_number_t dataCount = size;
            
            kern_return_t kr = vm_read(mach_task_self(), address, size, &data, &dataCount);
            if (kr == KERN_SUCCESS) {
                memcpy(&value, (void*)data, size);
                vm_deallocate(mach_task_self(), data, size);
                return @(value);
            }
            break;
        }
        case 1: { // Int
            int value = 0;
            vm_size_t size = sizeof(value);
            vm_offset_t data;
            mach_msg_type_number_t dataCount = size;
            
            kern_return_t kr = vm_read(mach_task_self(), address, size, &data, &dataCount);
            if (kr == KERN_SUCCESS) {
                memcpy(&value, (void*)data, size);
                vm_deallocate(mach_task_self(), data, size);
                return @(value);
            }
            break;
        }
        case 2: { // Float
            float value = 0;
            vm_size_t size = sizeof(value);
            vm_offset_t data;
            mach_msg_type_number_t dataCount = size;
            
            kern_return_t kr = vm_read(mach_task_self(), address, size, &data, &dataCount);
            if (kr == KERN_SUCCESS) {
                memcpy(&value, (void*)data, size);
                vm_deallocate(mach_task_self(), data, size);
                return @(value);
            }
            break;
        }
        case 3: { // Double
            double value = 0;
            vm_size_t size = sizeof(value);
            vm_offset_t data;
            mach_msg_type_number_t dataCount = size;
            
            kern_return_t kr = vm_read(mach_task_self(), address, size, &data, &dataCount);
            if (kr == KERN_SUCCESS) {
                memcpy(&value, (void*)data, size);
                vm_deallocate(mach_task_self(), data, size);
                return @(value);
            }
            break;
        }
        case 4: { // String
            char buffer[32] = {0};
            vm_size_t size = sizeof(buffer);
            vm_offset_t data;
            mach_msg_type_number_t dataCount = size;
            
            kern_return_t kr = vm_read(mach_task_self(), address, size, &data, &dataCount);
            if (kr == KERN_SUCCESS) {
                memcpy(buffer, (void*)data, size);
                vm_deallocate(mach_task_self(), data, size);
                return [NSString stringWithCString:buffer encoding:NSASCIIStringEncoding];
            }
            break;
        }
    }
    return nil;
}

- (BOOL)writeMemoryAtAddress:(vm_address_t)address value:(id)value type:(int)type {
    kern_return_t kr;
    
    // Сначала меняем защиту памяти
    vm_protect(mach_task_self(), address, [self typeSize:type], FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    
    switch (type) {
        case 0: { // Byte
            uint8_t val = [value intValue];
            kr = vm_write(mach_task_self(), address, (vm_offset_t)&val, sizeof(val));
            break;
        }
        case 1: { // Int
            int val = [value intValue];
            kr = vm_write(mach_task_self(), address, (vm_offset_t)&val, sizeof(val));
            break;
        }
        case 2: { // Float
            float val = [value floatValue];
            kr = vm_write(mach_task_self(), address, (vm_offset_t)&val, sizeof(val));
            break;
        }
        case 3: { // Double
            double val = [value doubleValue];
            kr = vm_write(mach_task_self(), address, (vm_offset_t)&val, sizeof(val));
            break;
        }
        case 4: { // String
            const char *str = [value UTF8String];
            kr = vm_write(mach_task_self(), address, (vm_offset_t)str, strlen(str) + 1);
            break;
        }
        default:
            return NO;
    }
    
    return (kr == KERN_SUCCESS);
}

- (BOOL)compareValue:(id)current withSearch:(NSString *)search type:(int)type {
    if (!current) return NO;
    
    switch (type) {
        case 0: // Byte
        case 1: // Int
            return [current intValue] == [search intValue];
        case 2: // Float
            return fabsf([current floatValue] - [search floatValue]) < 0.001;
        case 3: // Double
            return fabs([current doubleValue] - [search doubleValue]) < 0.001;
        case 4: // String
            return [current isEqualToString:search];
        default:
            return NO;
    }
}

#pragma mark - Freeze Operations

- (void)freezeSelected {
    NSIndexPath *selectedPath = [_tableView indexPathForSelectedRow];
    if (!selectedPath) {
        _addressLabel.text = @"⚠️ No address selected!";
        return;
    }
    
    NSDictionary *result = _searchResults[selectedPath.row];
    vm_address_t addr = [result[@"address"] unsignedLongLongValue];
    int type = [result[@"type"] intValue];
    id value = result[@"value"];
    
    // Проверяем, не заморожен ли уже
    for (NSDictionary *frozen in _frozenAddresses) {
        if ([frozen[@"address"] unsignedLongLongValue] == addr) {
            _addressLabel.text = @"⚠️ Already frozen!";
            return;
        }
    }
    
    NSMutableDictionary *frozenItem = [NSMutableDictionary dictionary];
    frozenItem[@"address"] = @(addr);
    frozenItem[@"value"] = value;
    frozenItem[@"type"] = @(type);
    [_frozenAddresses addObject:frozenItem];
    
    _addressLabel.text = [NSString stringWithFormat:@"❄️ Frozen: 0x%llx = %@", (unsigned long long)addr, value];
}

- (void)updateFrozenValues {
    for (NSMutableDictionary *frozen in _frozenAddresses) {
        vm_address_t addr = [frozen[@"address"] unsignedLongLongValue];
        id value = frozen[@"value"];
        int type = [frozen[@"type"] intValue];
        
        [self writeMemoryAtAddress:addr value:value type:type];
    }
}

- (void)unfreezeAll {
    [_frozenAddresses removeAllObjects];
    _addressLabel.text = @"🔓 All values unfrozen";
}

#pragma mark - UITableView DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _searchResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    
    NSDictionary *result = _searchResults[indexPath.row];
    vm_address_t addr = [result[@"address"] unsignedLongLongValue];
    id value = result[@"value"];
    int type = [result[@"type"] intValue];
    
    NSString *typeStr = @[@"Byte", @"Int", @"Float", @"Double", @"Str"][type];
    NSString *addrStr = [NSString stringWithFormat:@"0x%08llx", (unsigned long long)addr];
    NSString *valueStr = [NSString stringWithFormat:@"%@", value];
    
    cell.textLabel.text = [NSString stringWithFormat:@"%@ | %@ = %@", addrStr, typeStr, valueStr];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont fontWithName:@"Courier" size:12];
    cell.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    
    // Проверяем, заморожен ли адрес
    for (NSDictionary *frozen in _frozenAddresses) {
        if ([frozen[@"address"] unsignedLongLongValue] == addr) {
            cell.backgroundColor = [UIColor colorWithRed:0.0 green:0.3 blue:0.5 alpha:1.0];
            break;
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *result = _searchResults[indexPath.row];
    vm_address_t addr = [result[@"address"] unsignedLongLongValue];
    id value = result[@"value"];
    
    _addressLabel.text = [NSString stringWithFormat:@"📍 Selected: 0x%llx = %@", (unsigned long long)addr, value];
    
    // Показываем диалог для изменения значения
    [self showEditDialogForAddress:addr currentValue:value type:[result[@"type"] intValue] indexPath:indexPath];
}

- (void)showEditDialogForAddress:(vm_address_t)address currentValue:(id)currentValue type:(int)type indexPath:(NSIndexPath *)indexPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edit Memory"
                                                                   message:[NSString stringWithFormat:@"Address: 0x%llx\nCurrent: %@", (unsigned long long)address, currentValue]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"New value";
        textField.text = [NSString stringWithFormat:@"%@", currentValue];
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    
    UIAlertAction *writeAction = [UIAlertAction actionWithTitle:@"Write" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        NSString *newValue = alert.textFields[0].text;
        if (newValue.length > 0) {
            if ([self writeMemoryAtAddress:address value:newValue type:type]) {
                // Обновляем значение в результатах
                NSMutableDictionary *result = _searchResults[indexPath.row];
                result[@"value"] = newValue;
                [_tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                
                _addressLabel.text = [NSString stringWithFormat:@"✅ Written: 0x%llx = %@", (unsigned long long)address, newValue];
            } else {
                _addressLabel.text = @"❌ Write failed!";
            }
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:writeAction];
    [alert addAction:cancelAction];
    
    // Находим текущий view controller
    UIViewController *vc = [self getCurrentViewController];
    [vc presentViewController:alert animated:YES completion:nil];
}

- (UIViewController *)getCurrentViewController {
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *vc = window.rootViewController;
    
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    
    return vc;
}

#pragma mark - Actions

- (void)clearResults {
    [_searchResults removeAllObjects];
    [_tableView reloadData];
    _lastSearchValue = nil;
    _statusLabel.text = @"Status: Results cleared";
}

- (void)showRegions {
    NSMutableString *regionsText = [NSMutableString string];
    for (NSNumber *addr in _memoryRegions.allKeys) {
        NSDictionary *region = _memoryRegions[addr];
        [regionsText appendFormat:@"0x%08llx - %@ (%@)\n", 
         [addr unsignedLongLongValue], 
         region[@"size"],
         region[@"protection"]];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Memory Regions"
                                                                   message:regionsText
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *vc = [self getCurrentViewController];
    [vc presentViewController:alert animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self newScan];
    return YES;
}

- (void)close {
    [_freezeTimer invalidate];
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
    [_freezeTimer invalidate];
}

@end

// Хук для загрузки
static void (*orig_viewDidAppear)(id, SEL, BOOL);

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) return;
        
        BOOL exists = NO;
        for (UIView *v in window.subviews) {
            if ([v isKindOfClass:[MemoryBrowser class]]) {
                exists = YES;
                break;
            }
        }
        
        if (!exists) {
            MemoryBrowser *browser = [[MemoryBrowser alloc] init];
            [window addSubview:browser];
        }
    });
}

__attribute__((constructor))
static void init() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class class = [UIViewController class];
        Method original = class_getInstanceMethod(class, @selector(viewDidAppear:));
        orig_viewDidAppear = (void *)method_setImplementation(original, (IMP)hooked_viewDidAppear);
        NSLog(@"[✓] Memory Browser v1.0 Loaded");
    });
}
