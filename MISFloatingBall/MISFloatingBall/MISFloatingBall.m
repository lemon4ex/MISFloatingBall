//
//  MISFloatingBall.m
//  MISFloatingBall
//
//  Created by Mistletoe on 2017/4/22.
//  Copyright © 2017年 Mistletoe. All rights reserved.
//

#import "MISFloatingBall.h"
#include <objc/runtime.h>

typedef NS_ENUM(NSUInteger, MISFloatingBallContentType) {
    MISFloatingBallContentTypeImage = 0,    // 图片
    MISFloatingBallContentTypeText,         // 文字
    MISFloatingBallContentTypeCustomView    // 自定义视图(添加到上方的自定义视图默认 userInteractionEnabled = NO)
};

@interface MISRootViewController : UIViewController
@property (nonatomic) BOOL shouldAutorotate;
@property (nonatomic) UIInterfaceOrientationMask supportedInterfaceOrientations;
@end

@implementation MISRootViewController
- (BOOL)shouldAutorotate
{
    return _shouldAutorotate;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return _supportedInterfaceOrientations;
}
@end

#pragma mark - MISFloatingBallWindow

@interface MISFloatingBallWindow : UIWindow
@end

@implementation MISFloatingBallWindow

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    __block MISFloatingBall *floatingBall = nil;
    [self.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:[MISFloatingBall class]]) {
            floatingBall = (MISFloatingBall *)obj;
            *stop = YES;
        }
    }];
    
    if (CGRectContainsPoint(floatingBall.bounds,
            [floatingBall convertPoint:point fromView:self])) {
        return [super pointInside:point withEvent:event];
    }
    
    return NO;
}
@end

#pragma mark - MISFloatingBallManager

@interface MISFloatingBallManager : NSObject
@property (nonatomic, assign) BOOL canRuntime;
@property (nonatomic,   weak) UIView *superView;
@end

@implementation MISFloatingBallManager

+ (instancetype)shareManager {
    static MISFloatingBallManager *ballMgr = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ballMgr = [[MISFloatingBallManager alloc] init];
    });
    
    return ballMgr;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.canRuntime = NO;
    }
    return self;
}
@end

#pragma mark - UIView (MISAddSubview)

@interface UIView (MISAddSubview)

@end

@implementation UIView (MISAddSubview)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        method_exchangeImplementations(class_getInstanceMethod(self, @selector(addSubview:)), class_getInstanceMethod(self, @selector(mis_addSubview:)));
    });
}

- (void)mis_addSubview:(UIView *)subview {
    [self mis_addSubview:subview];
    
    if ([MISFloatingBallManager shareManager].canRuntime) {
        if ([[MISFloatingBallManager shareManager].superView isEqual:self]) {
            [self.subviews enumerateObjectsUsingBlock:^(UIView * obj, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([obj isKindOfClass:[MISFloatingBall class]]) {
                    [self insertSubview:subview belowSubview:(MISFloatingBall *)obj];
                }
            }];
        }
    }
}

@end

#pragma mark - MISFloatingBall

@interface MISFloatingBall()
@property (nonatomic, strong) UIView *parentView;
@property (nonatomic, assign) CGPoint centerOffset;
@property (nonatomic, strong) MISRootViewController *rootViewController;
@property (nonatomic, strong) UIImageView *ballImageView;
@property (nonatomic, strong) UILabel *ballLabel;
@property (nonatomic, strong) UIView *ballCustomView;
@property (nonatomic, strong) NSTimer *autoEdgeRetractTimer;
@end

static const NSInteger minUpDownLimits = 60 * 1.5f;   // MISFloatingBallEdgePolicyAllEdge 下，悬浮球到达一个界限开始自动靠近上下边缘

#ifndef __OPTIMIZE__
#define MISLog(...) NSLog(__VA_ARGS__)
#else
#define MISLog(...) {}
#endif

@implementation MISFloatingBall

#pragma mark - Life Cycle

- (void)dealloc {
    MISLog(@"MISFloatingBall dealloc");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
    [MISFloatingBallManager shareManager].canRuntime = NO;
    [MISFloatingBallManager shareManager].superView = nil;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame inSpecifiedView:nil effectiveEdgeInsets:UIEdgeInsetsZero];
}

- (instancetype)initWithFrame:(CGRect)frame inSpecifiedView:(UIView *)specifiedView {
    return [self initWithFrame:frame inSpecifiedView:specifiedView effectiveEdgeInsets:UIEdgeInsetsZero];
}

- (instancetype)initWithFrame:(CGRect)frame inSpecifiedView:(nullable UIView *)specifiedView effectiveEdgeInsets:(UIEdgeInsets)effectiveEdgeInsets {
    return [self initWithFrame:frame inSpecifiedView:specifiedView effectiveEdgeInsets:effectiveEdgeInsets clickHandler:nil];
}

- (instancetype)initWithFrame:(CGRect)frame
              inSpecifiedView:(nullable UIView *)specifiedView
          effectiveEdgeInsets:(UIEdgeInsets)effectiveEdgeInsets
                 clickHandler:(MISFloatingBallClickHandler)clickHandler
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        
        _autoCloseEdge = NO;
        _autoEdgeRetract = NO;
        _edgePolicy = MISFloatingBallEdgePolicyAllEdge;
        _effectiveEdgeInsets = effectiveEdgeInsets;
        _edgeRetractOffset = CGPointMake(self.bounds.size.width * 0.3, self.bounds.size.height * 0.3);
        _edgeRetractAlpha = 0.8f;
        _shouldAutorotate = YES;
        _supportedInterfaceOrientations = UIInterfaceOrientationMaskAll;
        _clickHandler = clickHandler;
        
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureRecognizer:)];
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureRecognizer:)];
        
        [self addGestureRecognizer:tapGesture];
        [self addGestureRecognizer:panGesture];
        [self configSpecifiedView:specifiedView];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willChangeOrientationHandler:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
        
    }
    return self;
}

- (void)updateTransformWithOrientation:(UIInterfaceOrientation)orientation
{
    CGFloat width = CGRectGetWidth(self.parentView.bounds);
    CGFloat height = CGRectGetHeight(self.parentView.bounds);
    if (width > height) {
        CGFloat temp = width;
        width = height;
        height = temp;
    }
    CGAffineTransform transform;
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            transform = CGAffineTransformMakeRotation(-M_PI_2);
            break;
        case UIInterfaceOrientationLandscapeRight:
            transform = CGAffineTransformMakeRotation(M_PI_2);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            transform = CGAffineTransformMakeRotation(-M_PI);
            break;
        default:
            transform = CGAffineTransformIdentity;
            break;
    }
    self.parentView.transform = transform;
    self.parentView.frame = CGRectMake(CGRectGetMinX(self.parentView.frame), CGRectGetMinY(self.parentView.frame), width, height);
}

- (void)updateFrameWithOrientation:(UIInterfaceOrientation)orientation
{
    CGFloat width = CGRectGetWidth(self.parentView.bounds);
    CGFloat height = CGRectGetHeight(self.parentView.bounds);
    if (width > height) {
        CGFloat temp = width;
        width = height;
        height = temp;
    }

    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
        case UIInterfaceOrientationLandscapeRight:
        {
            CGFloat rightMaxX = height - self.bounds.size.width + self.effectiveEdgeInsets.right;
            CGRect frame = self.frame;
            frame.origin.x = rightMaxX;
            frame.origin.y = (width - self.bounds.size.height) / 2;
            self.frame = frame;
        }
            break;
        default:
        {
            CGFloat rightMaxX = width - self.bounds.size.width + self.effectiveEdgeInsets.right;
            CGRect frame = self.frame;
            frame.origin.x = rightMaxX;
            frame.origin.y = (height - self.bounds.size.height) / 2;
            self.frame = frame;
        }
            break;
    }
}

- (void)updateWithOrientation:(UIInterfaceOrientation)orientation
{
    [self setAlpha:1.0f];
    // cancel
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoEdgeOffset) object:nil];
    
    if ([[UIDevice currentDevice].systemVersion floatValue] < 8.0) {
        [self updateTransformWithOrientation:orientation];
    } else {
        [self updateFrameWithOrientation:orientation];
    }
    if (self.autoEdgeRetract) {
        [self beginAutoEdgeRetractTimer];
    }
}

- (void)willChangeOrientationHandler:(NSNotification *)notification
{
    if (notification.name == UIApplicationWillChangeStatusBarOrientationNotification) {
        [UIView animateWithDuration:[UIApplication sharedApplication].statusBarOrientationAnimationDuration animations:^{
            UIInterfaceOrientation orientation = (UIInterfaceOrientation)[notification.userInfo[UIApplicationStatusBarOrientationUserInfoKey] integerValue];
            [self updateWithOrientation:orientation];
        }];
    }
}

- (void)configSpecifiedView:(UIView *)specifiedView {
    if (specifiedView) {
        _parentView = specifiedView;
    }
    else {
        UIWindow *window = [[MISFloatingBallWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        window.windowLevel = CGFLOAT_MAX; //UIWindowLevelStatusBar - 1;
        _rootViewController = [[MISRootViewController alloc]init];
        _rootViewController.shouldAutorotate = _shouldAutorotate;
        _rootViewController.supportedInterfaceOrientations = _supportedInterfaceOrientations;
        window.rootViewController = _rootViewController;
        window.rootViewController.view.backgroundColor = [UIColor clearColor];
        window.rootViewController.view.userInteractionEnabled = NO;
        [window makeKeyAndVisible];
        
        _parentView = window;
    }
    
    _parentView.hidden = YES;
    _centerOffset = CGPointMake(_parentView.bounds.size.width * 0.6, _parentView.bounds.size.height * 0.6);
    
    // setup ball manager
    [MISFloatingBallManager shareManager].canRuntime = YES;
    [MISFloatingBallManager shareManager].superView = specifiedView;
}

#pragma mark - Private Methods

// 靠边
- (void)autoCloseEdge {
    [UIView animateWithDuration:0.5f animations:^{
        // center
        self.center = [self calculatePoisitionWithEndOffset:CGPointZero];//center;
    } completion:^(BOOL finished) {
        // 靠边之后自动缩进边缘处
        if (self.autoEdgeRetract) {
            [self beginAutoEdgeRetractTimer];
        }
    }];
}

- (void)autoEdgeOffset {
    [UIView animateWithDuration:0.5f animations:^{
        self.center = [self calculatePoisitionWithEndOffset:self.edgeRetractOffset];
        self.alpha = self.edgeRetractAlpha;
    }];
}

- (CGPoint)calculatePoisitionWithEndOffset:(CGPoint)offset {
    CGFloat ballHalfW   = self.bounds.size.width * 0.5;
    CGFloat ballHalfH   = self.bounds.size.height * 0.5;
    CGFloat parentViewW = self.parentView.bounds.size.width;
    CGFloat parentViewH = self.parentView.bounds.size.height;
    CGPoint center = self.center;
    
    if (MISFloatingBallEdgePolicyLeftRight == self.edgePolicy) {
        // 左右
        center.x = (center.x < self.parentView.bounds.size.width * 0.5) ? (ballHalfW - offset.x + self.effectiveEdgeInsets.left) : (parentViewW + offset.x - ballHalfW + self.effectiveEdgeInsets.right);
    }
    else if (MISFloatingBallEdgePolicyUpDown == self.edgePolicy) {
        center.y = (center.y < self.parentView.bounds.size.height * 0.5) ? (ballHalfH - offset.y + self.effectiveEdgeInsets.top) : (parentViewH + offset.y - ballHalfH + self.effectiveEdgeInsets.bottom);
    }
    else if (MISFloatingBallEdgePolicyAllEdge == self.edgePolicy) {
        if (center.y < minUpDownLimits) {
            center.y = ballHalfH - offset.y + self.effectiveEdgeInsets.top;
        }
        else if (center.y > parentViewH - minUpDownLimits) {
            center.y = parentViewH + offset.y - ballHalfH + self.effectiveEdgeInsets.bottom;
        }
        else {
            center.x = (center.x < self.parentView.bounds.size.width  * 0.5) ? (ballHalfW - offset.x + self.effectiveEdgeInsets.left) : (parentViewW + offset.x - ballHalfW + self.effectiveEdgeInsets.right);
        }
    }
    return center;
}

#pragma mark - Public Methods

- (void)show {
    self.parentView.hidden = NO;
    [self.parentView addSubview:self];
}

- (void)hide {
    self.parentView.hidden = YES;
    [self removeFromSuperview];
}

- (void)visible {
    [self show];
}

- (void)disVisible {
    [self hide];
}

- (void)autoEdgeRetractDuration:(NSTimeInterval)duration edgeRetractOffset:(CGPoint)offset edgeRetractAlpha:(float)alpha {
    if (self.isAutoCloseEdge) {
        // 只有自动靠近边缘的时候才生效
        self.edgeRetractAlpha = alpha;
        self.edgeRetractOffset = offset;
        self.autoEdgeOffsetDuration = duration;
        self.autoEdgeRetract = YES;
    }
}

- (void)setTextContent:(NSString *)content
{
    [self setContent:content contentType:MISFloatingBallContentTypeText];
}

- (void)setImageContent:(UIImage *)content
{
    [self setContent:content contentType:MISFloatingBallContentTypeImage];
}

- (void)setCustomContent:(UIView *)content
{
    [self setContent:content contentType:MISFloatingBallContentTypeCustomView];
}

- (void)setContent:(id)content contentType:(MISFloatingBallContentType)contentType {
    BOOL notUnknowType = (MISFloatingBallContentTypeCustomView == contentType) || (MISFloatingBallContentTypeImage == contentType) || (MISFloatingBallContentTypeText == contentType);
    NSAssert(notUnknowType, @"can't set ball content with an unknow content type");
    
    [self.ballCustomView removeFromSuperview];
    if (MISFloatingBallContentTypeImage == contentType) {
        NSAssert([content isKindOfClass:[UIImage class]], @"can't set ball content with a not image content for image type");
        [self.ballLabel setHidden:YES];
        [self.ballCustomView setHidden:YES];
        [self.ballImageView setHidden:NO];
        [self.ballImageView setImage:(UIImage *)content];
    }
    else if (MISFloatingBallContentTypeText == contentType) {
        NSAssert([content isKindOfClass:[NSString class]], @"can't set ball content with a not nsstring content for text type");
        [self.ballLabel setHidden:NO];
        [self.ballCustomView setHidden:YES];
        [self.ballImageView setHidden:YES];
        [self.ballLabel setText:(NSString *)content];
    }
    else if (MISFloatingBallContentTypeCustomView == contentType) {
        NSAssert([content isKindOfClass:[UIView class]], @"can't set ball content with a not uiview content for custom view type");
        [self.ballLabel setHidden:YES];
        [self.ballCustomView setHidden:NO];
        [self.ballImageView setHidden:YES];
        
        self.ballCustomView = (UIView *)content;
        
        CGRect frame = self.ballCustomView.frame;
        frame.origin.x = (self.bounds.size.width - self.ballCustomView.bounds.size.width) * 0.5;
        frame.origin.y = (self.bounds.size.height - self.ballCustomView.bounds.size.height) * 0.5;
        self.ballCustomView.frame = frame;
        
        self.ballCustomView.userInteractionEnabled = NO;
        [self addSubview:self.ballCustomView];
    }
}

#pragma mark - GestureRecognizer

// 手势处理
- (void)panGestureRecognizer:(UIPanGestureRecognizer *)panGesture {
    if (UIGestureRecognizerStateBegan == panGesture.state) {
        [self setAlpha:1.0f];
        
        // cancel
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoEdgeOffset) object:nil];
    }
    else if (UIGestureRecognizerStateChanged == panGesture.state) {
        CGPoint translation = [panGesture translationInView:self];
        
        CGPoint center = self.center;
        center.x += translation.x;
        center.y += translation.y;
        self.center = center;
        
        CGFloat   leftMinX = 0.0f + self.effectiveEdgeInsets.left;
        CGFloat    topMinY = 0.0f + self.effectiveEdgeInsets.top;
        CGFloat  rightMaxX = self.parentView.bounds.size.width - self.bounds.size.width + self.effectiveEdgeInsets.right;
        CGFloat bottomMaxY = self.parentView.bounds.size.height - self.bounds.size.height + self.effectiveEdgeInsets.bottom;
        
        CGRect frame = self.frame;
        frame.origin.x = frame.origin.x > rightMaxX ? rightMaxX : frame.origin.x;
        frame.origin.x = frame.origin.x < leftMinX ? leftMinX : frame.origin.x;
        frame.origin.y = frame.origin.y > bottomMaxY ? bottomMaxY : frame.origin.y;
        frame.origin.y = frame.origin.y < topMinY ? topMinY : frame.origin.y;
        self.frame = frame;
        
        // zero
        [panGesture setTranslation:CGPointZero inView:self];
    }
    else if (UIGestureRecognizerStateEnded == panGesture.state) {
        if (self.isAutoCloseEdge) {
            [self autoCloseEdge];
        }
    }
}

- (void)tapGestureRecognizer:(UIPanGestureRecognizer *)tapGesture {
    __weak __typeof(self) weakSelf = self;
    if (self.clickHandler) {
        self.clickHandler(weakSelf);
    }
    
    if ([_delegate respondsToSelector:@selector(didClickFloatingBall:)]) {
        [_delegate didClickFloatingBall:self];
    }
}

#pragma mark - Timer
- (void)beginAutoEdgeRetractTimer {
    _autoEdgeRetractTimer = [NSTimer timerWithTimeInterval:self.autoEdgeOffsetDuration target:self selector:@selector(autoEdgeRetractTimerFired) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_autoEdgeRetractTimer forMode:NSRunLoopCommonModes];
}

- (void)stopAutoEdgeRetractTimer {
    [_autoEdgeRetractTimer invalidate];
    _autoEdgeRetractTimer = nil;
}

- (void)autoEdgeRetractTimerFired {
    [self stopAutoEdgeRetractTimer];
    [self autoEdgeOffset];
}

#pragma mark - Setter / Getter

- (void)setAutoCloseEdge:(BOOL)autoCloseEdge {
    _autoCloseEdge = autoCloseEdge;
    
    if (autoCloseEdge) {
        [self autoCloseEdge];
    }
}

- (UIImageView *)ballImageView {
    if (!_ballImageView) {
        _ballImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        [self addSubview:_ballImageView];
    }
    return _ballImageView;
}

- (UILabel *)ballLabel {
    if (!_ballLabel) {
        _ballLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _ballLabel.textAlignment = NSTextAlignmentCenter;
        _ballLabel.numberOfLines = 1.0f;
        _ballLabel.minimumScaleFactor = 0.0f;
        _ballLabel.adjustsFontSizeToFitWidth = YES;
        [self addSubview:_ballLabel];
    }
    return _ballLabel;
}

- (void)setShouldAutorotate:(BOOL)shouldAutorotate
{
    _shouldAutorotate = shouldAutorotate;
    if (_rootViewController) {
       _rootViewController.shouldAutorotate = _shouldAutorotate;
    }
}

- (void)setSupportedInterfaceOrientations:(UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    _supportedInterfaceOrientations = supportedInterfaceOrientations;
    if (_rootViewController) {
        _rootViewController.supportedInterfaceOrientations = _supportedInterfaceOrientations;
    }
}
@end
