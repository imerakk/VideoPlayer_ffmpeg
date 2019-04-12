//
//  GTAudioOutput.h
//  VideoPlayer
//
//  Created by liuchunxi on 2019/4/3.
//  Copyright © 2019年 imera. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FillDataDelegate <NSObject>

- (NSInteger)fillAudioData:(SInt16 *)sampleBuffer numFrames:(NSInteger)numFrames numChannles:(NSInteger)numChannles;

@end

@interface GTAudioOutput : NSObject

- (instancetype)initWithChannels:(NSInteger)channels sampleRate:(NSInteger)sampleRate dalegate:(id<FillDataDelegate>)delegate;

- (BOOL)play;
- (void)stop;

@end

NS_ASSUME_NONNULL_END


