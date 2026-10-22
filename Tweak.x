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

// True for colours that are black or very dark grey (not brand colours).
static BOOL isNearBlack(UIColor *color) {
    if (![color isKindOfClass:[UIColor class]]) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0;
        if (![color getWhite:&w alpha:&a]) return NO;
        r = g = b = w;
    }
    CGFloat mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
    return a > 0.1 && mx < 0.3 && (mx - mn) < 0.1;
}

// True if every visible pixel of the image is black/dark grey, i.e. a
// monochrome icon drawn for a light background. Colourful icons, white icons,
// illustrations and grey (inactive) icons all return NO.
static BOOL isDarkMonochromeImage(UIImage *img) {
    CGSize size = img.size;
    if (size.width <= 0 || size.height <= 0 || size.width > 512 || size.height > 512) return NO;

    enum { N = 48 };
    uint8_t px[N * N * 4];
    memset(px, 0, sizeof(px));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, N, N, 8, N * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return NO;
    CGContextTranslateCTM(ctx, 0, N);
    CGContextScaleCTM(ctx, 1, -1);
    UIGraphicsPushContext(ctx);
    [img drawInRect:CGRectMake(0, 0, N, N)];
    UIGraphicsPopContext();
    CGContextRelease(ctx);

    int opaque = 0, light = 0;
    for (int i = 0; i < N * N; i++) {
        uint8_t a = px[i * 4 + 3];
        if (a < 128) continue;              // skip transparent and antialiased edges
        int r = px[i * 4] * 255 / a, g = px[i * 4 + 1] * 255 / a, b = px[i * 4 + 2] * 255 / a;
        int mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
        opaque++;
        if (mx > 90 || mx - mn > 30) light++;
    }
    return opaque >= 8 && light * 50 <= opaque;   // allow up to 2% stray pixels
}

static BOOL shouldWhitenNamedImage(UIImage *img, NSString *name) {
    if (needsWhiteImage(name)) return YES;
    if (![name isKindOfClass:[NSString class]]) return NO;
    static NSMutableDictionary<NSString *, NSNumber *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; });
    NSNumber *verdict;
    @synchronized (cache) { verdict = cache[name]; }
    if (!verdict) {
        verdict = @(isDarkMonochromeImage(img));
        @synchronized (cache) { cache[name] = verdict; }
    }
    return verdict.boolValue;
}

static UIImage *whitened(UIImage *img, NSString *name) {
    if (!img || !isDarkModeEnabled() || !shouldWhitenNamedImage(img, name)) return img;
    if (@available(iOS 13.0, *)) {
        return [img imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    return img;
}

// Rewrites black/dark-grey text colours in styled (attributed) text to white.
// `fillMissing` also colours runs that have no colour at all, which a text
// view would otherwise draw black.
static NSAttributedString *lightenedText(NSAttributedString *text, BOOL fillMissing) {
    if (![text isKindOfClass:[NSAttributedString class]] || text.length == 0 || !isDarkModeEnabled()) return text;
    NSMutableAttributedString *out = nil;
    NSRange all = NSMakeRange(0, text.length);
    __block NSMutableArray<NSValue *> *ranges = [NSMutableArray new];
    [text enumerateAttribute:NSForegroundColorAttributeName inRange:all options:0
                  usingBlock:^(id value, NSRange range, BOOL *stop) {
        if ((value == nil && fillMissing) || isNearBlack(value)) [ranges addObject:[NSValue valueWithRange:range]];
    }];
    if (ranges.count == 0) return text;
    out = [text mutableCopy];
    for (NSValue *v in ranges) {
        [out addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:v.rangeValue];
    }
    return out;
}

// True if the view (or a parent close by) sits on a light background, such as
// a white button chip, where a dark icon should stay dark.
static BOOL isOnLightBackground(UIView *view) {
    UIView *v = view;
    for (int depth = 0; v && depth < 3; depth++, v = v.superview) {
        UIColor *bg = v.backgroundColor;
        if (!bg && v.layer.backgroundColor) bg = [UIColor colorWithCGColor:v.layer.backgroundColor];
        CGFloat w = 0, a = 0;
        if (bg && [bg getWhite:&w alpha:&a] && a > 0.5) return w > 0.8;   // first solid background decides
    }
    return NO;
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

// Icons tinted black in code (e.g. image.withTintColor(.black)).
%hook UIImage
- (UIImage *)imageWithTintColor:(UIColor *)color {
    if (isDarkModeEnabled() && isNearBlack(color)) color = [UIColor whiteColor];
    return %orig(color);
}
- (UIImage *)imageWithTintColor:(UIColor *)color renderingMode:(UIImageRenderingMode)renderingMode {
    if (isDarkModeEnabled() && isNearBlack(color)) color = [UIColor whiteColor];
    return %orig(color, renderingMode);
}
%end

// Template icons tinted black (search, back chevron, settings rows...).
%hook UIView
- (void)setTintColor:(UIColor *)color {
    if (isDarkModeEnabled() && isNearBlack(color) && !isOnLightBackground(self)) {
        %orig([UIColor whiteColor]);
        return;
    }
    %orig;
}
%end

// Styled text (event descriptions etc.) carries its own black colour, which
// bypasses -setTextColor:.
%hook UILabel
- (void)setAttributedText:(NSAttributedString *)text {
    %orig(lightenedText(text, NO));
}
%end

%hook UITextView
- (void)setTextColor:(UIColor *)color {
    if (isDarkModeEnabled() && isNearBlack(color)) color = [UIColor whiteColor];
    %orig(color);
}
- (void)setAttributedText:(NSAttributedString *)text {
    %orig(lightenedText(text, YES));
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
