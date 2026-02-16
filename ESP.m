- (void)readGameMemory {
    task_t task;
    task_for_pid(mach_task_self(), [self getPid:@"Standoff2"], &task);
    
    uint64_t baseAddress = [self getBaseAddress:task];
    
    // Читаем количество игроков (обычно 10-12)
    int playerCount = [self readInt:task address:baseAddress + 0x4E8A2B8];
    
    // Получаем локального игрока
    uint64_t localPlayerPtr = [self readPointer:task address:baseAddress + 0x4E8A2AC];
    
    // Получаем список всех игроков
    uint64_t entityListPtr = [self readPointer:task address:baseAddress + 0x4E8A2B4];
    
    // Матрица для преобразования координат
    float viewMatrix[16];
    [self readBuffer:task address:baseAddress + 0x4E8A460 buffer:&viewMatrix size:sizeof(viewMatrix)];
    
    [players removeAllObjects];
    
    for (int i = 0; i < playerCount; i++) {
        // Каждый указатель на игрока занимает 8 байт (64-битная система)
        uint64_t playerPtr = [self readPointer:task address:entityListPtr + (i * 0x8)];
        
        // Пропускаем нулевые указатели и локального игрока
        if (playerPtr == 0 || playerPtr == localPlayerPtr) continue;
        
        PlayerData player;
        
        // Читаем координаты
        player.position.x = [self readFloat:task address:playerPtr + 0xA0];
        player.position.y = [self readFloat:task address:playerPtr + 0xA4];
        player.position.z = [self readFloat:task address:playerPtr + 0xA8];
        
        // Позиция головы (ноги + рост персонажа)
        player.headPosition.x = player.position.x;
        player.headPosition.y = player.position.y + 1.85f; // Рост персонажа
        player.headPosition.z = player.position.z;
        
        // Читаем здоровье и команду
        player.health = [self readFloat:task address:playerPtr + 0x1C0];
        player.team = [self readInt:task address:playerPtr + 0x140];
        player.isVisible = [self readBool:task address:playerPtr + 0x360];
        
        // Читаем имя игрока
        [self readBuffer:task address:playerPtr + 0x38 buffer:player.name size:32];
        
        // Конвертируем в экранные координаты с использованием матрицы
        CGPoint screenPos = [self worldToScreen:player.position matrix:viewMatrix];
        player.screenX = screenPos.x;
        player.screenY = screenPos.y;
        
        [players addObject:[NSValue valueWithBytes:&player objCType:@encode(PlayerData)]];
    }
    
    mach_port_deallocate(mach_task_self(), task);
}
