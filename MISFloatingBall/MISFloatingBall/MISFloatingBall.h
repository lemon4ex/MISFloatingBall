//
//  MISFloatingBall.h
//  MISFloatingBall
//
//  Created by Mistletoe on 2017/4/22.
//  Copyright © 2017年 Mistletoe. All rights reserved.
//  悬浮球

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**< 靠边策略(默认所有边框均可停靠) */
typedef NS_ENUM(NSUInteger, MISFloatingBallEdgePolicy) {
    MISFloatingBallEdgePolicyAllEdge = 0,    ///< 所有边框都可，符合正常使用习惯，滑到某一位置时候才上下停靠，参见系统的 assistiveTouch)
    MISFloatingBallEdgePolicyLeftRight,      ///< 只能左右停靠
    MISFloatingBallEdgePolicyUpDown,         ///< 只能上下停靠
};

@class MISFloatingBall;
@protocol MISFloatingBallDelegate;

typedef void (^MISFloatingBallClickHandler)(MISFloatingBall *floatingBall);

@interface MISFloatingBall : UIView

@property (nonatomic, strong, readonly) UIImageView *ballImageView;
@property (nonatomic, strong, readonly) UILabel *ballLabel;
@property (nonatomic, strong, readonly) UIView *ballCustomView;

@property (nonatomic, weak) id<MISFloatingBallDelegate> delegate; ///< 悬浮球代理
@property (nonatomic, assign, getter=isAutoCloseEdge) BOOL autoCloseEdge; ///< 是否自动靠边
@property (nonatomic, assign) MISFloatingBallEdgePolicy edgePolicy; ///< 靠边策略
@property (nonatomic, assign) UIEdgeInsets effectiveEdgeInsets; ///< 靠边时的边距

@property (nonatomic, assign) BOOL autoEdgeRetract; ///< 靠边自动隐藏
@property (nonatomic, assign) NSTimeInterval autoEdgeOffsetDuration; ///< 靠边隐藏动画时间
@property (nonatomic, assign) CGPoint edgeRetractOffset; ///< 缩进结果偏移量
@property (nonatomic, assign) CGFloat edgeRetractAlpha;  ///< 缩进后的透明度

@property (nonatomic, assign) BOOL shouldAutorotate; ///< 是否在设备旋转时自动旋转
@property (nonatomic, assign) UIInterfaceOrientationMask supportedInterfaceOrientations; ///< 支持的屏幕炫装方向

@property (nonatomic, strong) MISFloatingBallClickHandler clickHandler; ///< 点击悬浮球后的回调

/**
 初始化只会在当前指定的 view 范围内生效的悬浮球
 当 view 为 nil 的时候，和直接使用 initWithFrame 初始化效果一直，默认为全局生效的悬浮球
 
 @param frame 尺寸
 @param specifiedView 将要显示所在的view
 @param effectiveEdgeInsets 限制显示的范围，UIEdgeInsetsMake(50, 50, -50, -50)
 则表示显示范围周围上下左右各缩小了 50 范围
 @return 生成的悬浮球实例
 */
- (instancetype)initWithFrame:(CGRect)frame
              inSpecifiedView:(nullable UIView *)specifiedView
          effectiveEdgeInsets:(UIEdgeInsets)effectiveEdgeInsets;

- (instancetype)initWithFrame:(CGRect)frame
              inSpecifiedView:(nullable UIView *)specifiedView
          effectiveEdgeInsets:(UIEdgeInsets)effectiveEdgeInsets
                 clickHandler:(nullable MISFloatingBallClickHandler)clickHandler;

- (void)show;
- (void)hide;

// 设置按钮的内容，可设置为文本，图片和自定义内容
- (void)setTextContent:(NSString *)content;
- (void)setImageContent:(UIImage *)content;
- (void)setCustomContent:(UIView *)content;

/**
 当悬浮球靠近边缘的时候，自动像边缘缩进一段间距 (只有 autoCloseEdge 为YES时候才会生效)
*/
- (void)autoEdgeRetractDuration:(NSTimeInterval)duration edgeRetractOffset:(CGPoint)offset edgeRetractAlpha:(float)alpha;

@end

@protocol MISFloatingBallDelegate <NSObject>
@optional
- (void)didClickFloatingBall:(MISFloatingBall *)floatingBall;
@end

NS_ASSUME_NONNULL_END
