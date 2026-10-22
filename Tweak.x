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

// The FATSOMA wordmark in the header and the filled "selected" tab bar icons
// are image assets drawn black (the app has no dark variants), so forcing dark
// mode leaves them black. Recolor exactly those assets, by name, to white.
static BOOL needsWhiteImage(NSString *name) {
    if (![name isKindOfClass:[NSString class]]) return NO;
    if ([name isEqualToString:@"fatsoma-landing-logo-black"]) return YES;                // header logo
    if ([name hasPrefix:@"Tab Bar/"] && [name hasSuffix:@"-active"]) return YES;         // selected tabs
    return NO;
}

static UIImage *whitened(UIImage *img, NSString *name) {
    if (!img || !needsWhiteImage(name) || !isDarkModeEnabled()) return img;
    if (@available(iOS 13.0, *)) {
        return [img imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    return img;
}

%hook UIImage
+ (UIImage *)imageNamed:(NSString *)name {
    UIImage *img = %orig;
    return whitened(img, name);
}
+ (UIImage *)imageNamed:(NSString *)name inBundle:(NSBundle *)bundle compatibleWithTraitCollection:(UITraitCollection *)traits {
    UIImage *img = %orig;
    return whitened(img, name);
}
+ (UIImage *)imageNamed:(NSString *)name inBundle:(NSBundle *)bundle withConfiguration:(UIImageConfiguration *)configuration {
    UIImage *img = %orig;
    return whitened(img, name);
}
%end

// Fallback in case the tab bar draws its icons as templates tinted black.
%hook UITabBar
- (void)setTintColor:(UIColor *)color {
    CGFloat white = 0, alpha = 0;
    if (isDarkModeEnabled() && [color getWhite:&white alpha:&alpha] && white < 0.1) {
        %orig([UIColor whiteColor]);
        return;
    }
    %orig;
}
%end
