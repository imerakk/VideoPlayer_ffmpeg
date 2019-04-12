//
//  GTAynchronizer.h
//  VideoPlayer
//
//  Created by liuchunxi on 2019/4/11.
//  Copyright © 2019年 imera. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GTVideoDecoder.h"

extern NSString * const kMinBufferDuration;
extern NSString * const kMaxBufferDuration;

NS_ASSUME_NONNULL_BEGIN

@interface GTAynchronizer : NSObject

- (BOOL)openFile:(NSString *)filePath parameters:(NSDictionary *)parameters;

- (void)closeFile;

- (void)audioCallBackFillData:(SInt16 *)outData
                    numFrames:(NSInteger)numFrames
                  numChannels:(NSInteger)numChannels;

- (VideoFrame *)getCorrectVideoFrame;

- (NSInteger)videoWidth;
- (NSInteger)videoHeight;

- (NSInteger)audioChannels;
- (NSInteger)audioSampleRate;


@end

NS_ASSUME_NONNULL_END
