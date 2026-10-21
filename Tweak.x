#import <UIKit/UIKit.h>

static BOOL isDarkModeEnabled() {
    NSNumber *val = [[NSUserDefaults standardUserDefaults] objectForKey:@"CustomDarkModeEnabled"];
    return val ? [val boolValue] : YES;
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
    
    // 3-finger double-tap gesture anywhere to toggle theme
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCustomDarkMode)];
    tap.numberOfTouchesRequired = 3;
    tap.numberOfTapsRequired = 2;
    [self addGestureRecognizer:tap];
}

%new
- (void)toggleCustomDarkMode {
    BOOL current = isDarkModeEnabled();
    [[NSUserDefaults standardUserDefaults] setBool:!current forKey:@"CustomDarkModeEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    applyThemeToWindows();
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Theme Changed" 
                                                                   message:(!current ? @"Dark Mode Enabled" : @"Light Mode Enabled") 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self.rootViewController presentViewController:alert animated:YES completion:nil];
}

%end

// Intelligent view background re-mapping (ignoring image/media views)
%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (isDarkModeEnabled()) {
        // Skip UIImageView, UITableViewCell backgrounds, or navigation bars to prevent breaking images
        if ([self isKindOfClass:[UIImageView class]] || [self isKindOfClass:[UINavigationBar class]]) {
            %orig;
            return;
        }
        
        CGFloat white = 0, alpha = 0;
        // If the app sets a pure white background, shift it to dark charcoal
        if ([color getWhite:&white alpha:&alpha] && white > 0.92 && alpha > 0.9) {
            %orig([UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:alpha]);
            return;
        }
    }
    %orig;
}
%end

// Ensure text on buttons or headers is readable
%hook UILabel
- (void)setTextColor:(UIColor *)color {
    if (isDarkModeEnabled()) {
        CGFloat white = 0, alpha = 0;
        // If text is dark/black, change it to white for contrast on dark backgrounds
        if ([color getWhite:&white alpha:&alpha] && white < 0.2 && alpha > 0.9) {
            %orig([UIColor whiteColor]);
            return;
        }
    }
    %orig;
}
%end

// Fix buttons text color where background might have inverted
%hook UIButton
- (void)setTitleColor:(UIColor *)color forState:(UIControlState)state {
    if (isDarkModeEnabled()) {
        CGFloat white = 0, alpha = 0;
        if ([color getWhite:&white alpha:&alpha] && white < 0.2 && alpha > 0.9) {
            %orig([UIColor whiteColor], state);
            return;
        }
    }
    %orig;
}
%end
