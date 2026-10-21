#import <UIKit/UIKit.h>

static BOOL isDarkModeEnabled() {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"CustomDarkModeEnabled"];
    return val ? [val boolValue] : YES; // Default to YES
}

static void applyThemeToWindows() {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = isDarkModeEnabled() ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            window.overrideUserInterfaceStyle = style;
        }
    }
}

%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    UIWindow *window = %orig;
    if (@available(iOS 13.0, *)) {
        window.overrideUserInterfaceStyle = isDarkModeEnabled() ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    }
    return window;
}

- (void)makeKeyAndVisible {
    %orig;
    if (@available(iOS 13.0, *)) {
        self.overrideUserInterfaceStyle = isDarkModeEnabled() ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    }
    
    // Add a 3-finger tap gesture to toggle Dark Mode from anywhere, including Settings
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCustomDarkMode)];
    tap.numberOfTouchesRequired = 3;
    tap.numberOfTapsRequired = 2; // Double tap with 3 fingers
    [self addGestureRecognizer:tap];
}

%new
- (void)toggleCustomDarkMode {
    BOOL current = isDarkModeEnabled();
    [[NSUserDefaults standardUserDefaults] setBool:!current forKey:@"CustomDarkModeEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    applyThemeToWindows();
    
    // Show a quick alert confirming the change
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Theme Changed" 
                                                                   message:(!current ? @"Dark Mode Enabled" : @"Light Mode Enabled") 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.rootViewController presentViewController:alert animated:YES completion:nil];
}

%end

// Optional: If the app hardcodes white backgrounds on standard views, hook UIView
%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (isDarkModeEnabled()) {
        // Check if the color is pure white or very close to white
        CGFloat white = 0, alpha = 0;
        if ([color getWhite:&white alpha:&alpha] && white > 0.95 && alpha > 0.9) {
            %orig([UIColor colorWithRed:0.11 green:0.11 blue:0.12 alpha:alpha]); // iOS system dark gray
            return;
        }
    }
    %orig;
}
%end

// Invert black text to white if backgrounds are darkened
%hook UILabel
- (void)setTextColor:(UIColor *)color {
    if (isDarkModeEnabled()) {
        CGFloat white = 0, alpha = 0;
        if ([color getWhite:&white alpha:&alpha] && white < 0.1 && alpha > 0.9) {
            %orig([UIColor whiteColor]);
            return;
        }
    }
    %orig;
}
%end
