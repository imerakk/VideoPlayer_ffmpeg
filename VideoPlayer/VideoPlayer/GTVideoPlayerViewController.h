//
//  GTVideoPlayerViewController.h
//  VideoPlayer
//
//  Created by liuchunxi on 2019/4/12.
//  Copyright © 2019年 imera. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GTAynchronizer.h"
#import "GTAudioOutput.h"
#import "VideoOutput.h"

NS_ASSUME_NONNULL_BEGIN

@interface GTVideoPlayerViewController : UIViewController

+ (instancetype)viewControllerWithFilePath:(NSString *)filePath
                              contentFrame:(CGRect)contentFrame
                                parameters:(nullable NSDictionary *)parameters;

- (void)play;
- (void)pause;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
