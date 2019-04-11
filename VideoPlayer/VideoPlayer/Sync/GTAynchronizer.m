//
//  GTAynchronizer.m
//  VideoPlayer
//
//  Created by liuchunxi on 2019/4/11.
//  Copyright © 2019年 imera. All rights reserved.
//

#import "GTAynchronizer.h"
#import <pthread.h>

#define FloatEqual(A, B) (ABS(A - B) < CGFLOAT_MIN)

NSString * const kMinBufferDuration = @"kMinBufferDuration";
NSString * const kMaxBufferDuration = @"kMaxBufferDuration";

static CGFloat kDefaultMinBufferDuration = 0.2;
static CGFloat kDefaultMaxBufferDuration = 0.4;

@interface GTAynchronizer () {
    CGFloat _minBufferDuration;
    CGFloat _maxBufferDuration;
    
    GTVideoDecoder *_decoder;
    
    NSMutableArray *_audioFrames;
    NSMutableArray *_videoFrames;
    
    BOOL _isOnDecoding;
    
    pthread_mutex_t _audioDecoderLock;
    pthread_cond_t _audioDecoderCondition;
    pthread_t _audioDecoderThread;
}

@end

@implementation GTAynchronizer

static void * runDecoderThread(void *ptr) {
    GTAynchronizer *sync = (__bridge GTAynchronizer *)ptr;
    [sync run];
    return NULL;
}


- (BOOL)openFile:(NSString *)filePath parameters:(NSDictionary *)parameters {
    _decoder = [[GTVideoDecoder alloc] init];
    
    if (![_decoder openFile:filePath parameters:parameters]) {
        return NO;
    }
    if (_decoder.videoWidth <= 0 || _decoder.videoHeight <= 0) {
        return NO;
    }
    
    _minBufferDuration = [parameters[kMinBufferDuration] floatValue];
    _maxBufferDuration = [parameters[kMaxBufferDuration] floatValue];
    if (FloatEqual(_minBufferDuration, 0.f) || FloatEqual(_maxBufferDuration, 0.f) || _minBufferDuration < _maxBufferDuration) {
        _minBufferDuration = kDefaultMinBufferDuration;
        _maxBufferDuration = kDefaultMaxBufferDuration;
    }
    
    _audioFrames = [NSMutableArray array];
    _videoFrames = [NSMutableArray array];
    
    [self startDecoderThread];
    [self startDecoderFirstBufferThread];
    
    return YES;
}

#pragma mark - decode frame
- (void)startDecoderThread {
    _isOnDecoding = YES;
    
    pthread_mutex_init(&_audioDecoderLock, NULL);
    pthread_cond_init(&_audioDecoderCondition, NULL);
    pthread_create(&_audioDecoderThread, NULL, runDecoderThread, (__bridge void *)self);
}

- (void)run {
    while (_isOnDecoding) {
        pthread_mutex_lock(&_audioDecoderLock);
        pthread_cond_wait(&_audioDecoderCondition, &_audioDecoderLock);
        pthread_mutex_unlock(&_audioDecoderLock);
        [self decodeFrames];
    }
}

- (void)decodeFrames {
    
}

- (void)startDecoderFirstBufferThread {
    
}

@end


