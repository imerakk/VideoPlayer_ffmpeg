//
//  GTVideoDecoder.h
//  VideoPlayer
//
//  Created by liuchunxi on 2019/3/29.
//  Copyright © 2019年 imera. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

#ifndef RTMP_TCURL_KEY
#define RTMP_TCURL_KEY                              @"RTMP_TCURL_KEY"
#endif

#ifndef PROBE_SIZE
#define PROBE_SIZE                                  @"PROBE_SIZE"
#endif

#ifndef MAX_ANALYZE_DURATION
#define MAX_ANALYZE_DURATION                        @"MAX_ANALYZE_DURATION"
#endif

#ifndef FPS_PROBE_SIZE
#define FPS_PROBE_SIZE                              @"FPS_PROBE_SIZE"
#endif

typedef NS_ENUM(NSUInteger, FrameType) {
    AudioFrameType = 0,
    VideoFrameType = 1
};

@interface Frame : NSObject
@property (nonatomic, assign) FrameType type;
@end

@interface AudioFrame : Frame
@property (nonatomic, strong) NSData *samples;
@property (nonatomic, assign) CGFloat duration;
@property (nonatomic, assign) CGFloat position;
@end

@interface VideoFrame : Frame
@property (nonatomic, strong) NSData *luma;
@property (nonatomic, strong) NSData *chromaB;
@property (nonatomic, strong) NSData *chromaR;
@property (nonatomic, assign) CGFloat position;
@property (nonatomic, assign) CGFloat duration;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) CGFloat lineSize;
@end


@interface GTVideoDecoder : NSObject

- (BOOL)openFile:(NSString *)filePath parameters:(NSDictionary *)parameters;
- (NSArray *)decodeFrames:(CGFloat)minDuration;
- (void)clearResource;

- (NSInteger)videoWidth;
- (NSInteger)videoHeight;

@end

NS_ASSUME_NONNULL_END
