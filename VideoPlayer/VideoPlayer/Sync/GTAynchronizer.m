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
    CGFloat _bufferDuration;
    
    GTVideoDecoder *_decoder;
    
    NSMutableArray *_audioFrames;
    NSMutableArray *_videoFrames;
    
    BOOL _isOnDecoding;
    
    /* 控制解码时机 */
    pthread_mutex_t _videoDecoderLock;
    pthread_cond_t _videoDecoderCondition;
    pthread_t _videoDecoderThread;
    
    /* 控制第一段解码 */
    pthread_mutex_t _videoFirstDecoderLock;
    pthread_cond_t _videoFirstDecoderCondition;
    pthread_t _videoFirstDecoderThread;
    BOOL _isOnFirstDecoding;
    
    NSData *_currentAudioFrame;
    NSUInteger _currentAudioFramePosition;
    CGFloat _audioPosition;
    
    CGFloat _syncMaxTimeDiff;
}

@end

@implementation GTAynchronizer

static void * runDecoderThread(void *ptr) {
    GTAynchronizer *sync = (__bridge GTAynchronizer *)ptr;
    [sync run];
    return NULL;
}

static void * runDecoderFirstBuffer(void *ptr) {
    GTAynchronizer *sync = (__bridge GTAynchronizer *)ptr;
    [sync runDecoderFirstBufferThread];
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
    
    _syncMaxTimeDiff = 0.05;
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
    
    pthread_mutex_init(&_videoDecoderLock, NULL);
    pthread_cond_init(&_videoDecoderCondition, NULL);
    pthread_create(&_videoDecoderThread, NULL, runDecoderThread, (__bridge void *)self);
}

- (void)run {
    while (_isOnDecoding) {
        pthread_mutex_lock(&_videoDecoderLock);
        pthread_cond_wait(&_videoDecoderCondition, &_videoDecoderLock);
        pthread_mutex_unlock(&_videoDecoderLock);
        [self decodeFramesForDuration:_maxBufferDuration];
    }
}

- (void)decodeFramesForDuration:(CGFloat)duration {
    BOOL good = YES;
    while (good) {
        @autoreleasepool {
            if (_decoder) {
                NSArray *frames = [_decoder decodeFrames:0.0];
                
                if (_decoder.vaildAudio) {
                    @synchronized (_audioFrames) {
                        for (Frame *frame in frames) {
                            if (frame.type == AudioFrameType) {
                                [_audioFrames addObject:frame];
                                _bufferDuration += frame.duration;
                            }
                        }
                    }
                }
                
                if (_decoder.vaildVideo) {
                    @synchronized (_videoFrames) {
                        for (Frame *frame in frames) {
                            if (frame.type == VideoFrameType) {
                                [_videoFrames addObject:frame];
                            }
                        }
                    }
                }
            }
            good = _bufferDuration > duration;
        }
    }
}

- (void)startDecoderFirstBufferThread {
    pthread_mutex_init(&_videoFirstDecoderLock, NULL);
    pthread_cond_init(&_videoFirstDecoderCondition, NULL);
    _isOnFirstDecoding = YES;
    pthread_create(&_videoFirstDecoderThread, NULL, runDecoderFirstBuffer, (__bridge void *)self);
}

- (void)runDecoderFirstBufferThread {
    [self decodeFramesForDuration:0.5];
    
    pthread_mutex_lock(&_videoFirstDecoderLock);
    pthread_cond_signal(&_videoFirstDecoderCondition);
    pthread_mutex_unlock(&_videoFirstDecoderLock);
    _isOnFirstDecoding = NO;
}

- (void)audioCallBackFillData:(SInt16 *)outData numFrames:(NSInteger)numFrames numChannels:(NSInteger)numChannels {
    [self checkPlayStatus];
    
    while (numFrames > 0) {
        if (!_currentAudioFrame) {
            @synchronized (_audioFrames) {
                if (_audioFrames.count > 0) {
                    AudioFrame *currentAudioFrame = _audioFrames[0];
                    _bufferDuration -= currentAudioFrame.duration;
                    [_audioFrames removeObjectAtIndex:0];
                    
                    _audioPosition = currentAudioFrame.position;
                    _currentAudioFramePosition = 0;
                    _currentAudioFrame = currentAudioFrame.samples;
                }
            }
        }
        
        if (_currentAudioFrame) {
            const void *bytes = _currentAudioFrame.bytes + _currentAudioFramePosition;
            const NSUInteger bytesLeft = _currentAudioFrame.length - _currentAudioFramePosition;
            const NSUInteger frameSizeOf = numChannels * sizeof(SInt16);
            const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
            NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
            
            memcmp(outData, bytes, bytesToCopy);
            numFrames -= framesToCopy;
            outData += framesToCopy + numChannels;
            
            if (bytesToCopy < bytesLeft) {
                _currentAudioFramePosition += bytesToCopy;
            }
            else {
                _currentAudioFrame = nil;
            }
        }
        else {
            memset(outData, 0, sizeof(SInt16)*numFrames*numChannels);
            break;
        }
    }
}

- (void)checkPlayStatus {
    if (_decoder == NULL) {
        return;
    }
    
    if (!_isOnFirstDecoding && _bufferDuration < _minBufferDuration) {
        [self signDecoderThread];
    }
}

- (void)signDecoderThread {
    pthread_mutex_lock(&_videoDecoderLock);
    pthread_cond_signal(&_videoDecoderCondition);
    pthread_mutex_unlock(&_videoDecoderLock);
}

- (VideoFrame *)getCorrectVideoFrame {
    VideoFrame *videoFrame = nil;
    @synchronized (_videoFrames) {
        while (_videoFrames.count > 0) {
            videoFrame = _videoFrames[0];
            CGFloat diff = _audioPosition - videoFrame.position;
            if (diff < (0 - _syncMaxTimeDiff)) { //视频比音频快很多，继续渲染上一帧
                videoFrame = NULL;
                break;
            }
            else if (diff > _syncMaxTimeDiff) { //视频比音频慢很多，渲染下一帧
                [_videoFrames removeObjectAtIndex:0];
                videoFrame = NULL;
                continue;
            }
            else {
                [_videoFrames removeObjectAtIndex:0];
                break;
            }
        }
    }
    
    return videoFrame;
}

- (void)closeFile {
    if (_isOnFirstDecoding) {
        pthread_mutex_lock(&_videoFirstDecoderLock);
        pthread_cond_wait(&_videoDecoderCondition, &_videoFirstDecoderLock);
        pthread_mutex_unlock(&_videoFirstDecoderLock);
        pthread_mutex_destroy(&_videoFirstDecoderLock);
        pthread_cond_destroy(&_videoFirstDecoderCondition);
    }
    
    _isOnDecoding = false;
    pthread_mutex_lock(&_videoDecoderLock);
    pthread_cond_signal(&_videoDecoderCondition);
    pthread_mutex_unlock(&_videoDecoderLock);
    pthread_join(_videoDecoderThread, NULL);
    pthread_mutex_destroy(&_videoDecoderLock);
    pthread_cond_destroy(&_videoDecoderCondition);
    
    if (_decoder) {
        [_decoder clearResource];
    }
    
    @synchronized (_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized (_audioFrames) {
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
}

- (NSInteger)videoWidth {
    return _decoder.videoWidth;
}

- (NSInteger)videoHeight {
    return _decoder.videoHeight;
}

- (NSInteger)audioChannels {
    return _decoder.audioChannels;
}

- (NSInteger)audioSampleRate {
    return _decoder.audioSampleRate;
}

@end


