#include "imgui.h"
#include "imgui_impl_ios.h"
#include "imgui_impl_opengl3.h"
#include <objc/runtime.h>
#include <UIKit/UIKit.h>

static bool g_menu_visible = true;
static void (*orig_drawRect)(id, SEL, CGRect);

static void hooked_drawRect(id self, SEL _cmd, CGRect rect) {
    orig_drawRect(self, _cmd, rect);
    
    if (g_menu_visible) {
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImpliOS_NewFrame((__bridge void*)self);
        ImGui::NewFrame();
        
        ImGui::Begin("Menu", &g_menu_visible);
        ImGui::Text("Hello");
        ImGui::End();
        
        ImGui::Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    }
}

__attribute__((constructor))
static void init() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        UIView *view = window.rootViewController.view;
        
        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        ImGui_ImpliOS_Init((__bridge void*)view);
        ImGui_ImplOpenGL3_Init("#version 100");
        
        Method method = class_getInstanceMethod([view class], @selector(drawRect:));
        orig_drawRect = (void *)method_setImplementation(method, (IMP)hooked_drawRect);
    });
}
