//
//  GTVideoPlayerViewController.m
//  VideoPlayer
//
//  Created by liuchunxi on 2019/4/12.
//  Copyright © 2019年 imera. All rights reserved.
//

#import "GTVideoPlayerViewController.h"

@interface GTVideoPlayerViewController () <FillDataDelegate> {
    NSString *_filePath;
    CGRect _contentFrame;
    NSDictionary *_parameters;
    
    GTAynchronizer *_sync;
    VideoOutput *_videoOutput;
    GTAudioOutput *_audioOutput;
    
    BOOL _isPlaying;
}

@end

@implementation GTVideoPlayerViewController

+ (instancetype)viewControllerWithFilePath:(NSString *)filePath contentFrame:(CGRect)contentFrame parameters:(nullable NSDictionary *)parameters {
    return [[GTVideoPlayerViewController alloc] initWithFilePath:filePath contentFrame:contentFrame parameters:parameters];
}

- (instancetype)initWithFilePath:(NSString *)filePath contentFrame:(CGRect)contentFrame parameters:(nullable NSDictionary *)parameters {
    self = [super init];
    if (self) {
        _filePath = filePath;
        _contentFrame = contentFrame;
        _parameters = parameters;
        [self start];
    }
    
    return self;
}

- (void)start {
    _sync = [[GTAynchronizer alloc] init];
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            BOOL res = [strongSelf->_sync openFile:strongSelf->_filePath parameters:strongSelf->_parameters];
            if (res) {
                strongSelf->_videoOutput = [strongSelf createVideoOutput];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.view.backgroundColor = [UIColor whiteColor];
                    [strongSelf.view addSubview:strongSelf->_videoOutput];
                });
                
                strongSelf->_audioOutput = [strongSelf createAudioOutput];
            }
        }
    });
}

- (VideoOutput *)createVideoOutput {
    VideoOutput *videoOutput = [[VideoOutput alloc] initWithFrame:_contentFrame textureWidth:_sync.videoWidth textureHeight:_sync.videoHeight usingHWCodec:NO];
    videoOutput.contentMode = UIViewContentModeScaleToFill;
    return videoOutput;
}

- (GTAudioOutput *)createAudioOutput {
    NSInteger channels = _sync.audioChannels;
    NSInteger sampleRate = _sync.audioSampleRate;
    
    GTAudioOutput *audioOutput = [[GTAudioOutput alloc] initWithChannels:channels sampleRate:sampleRate dalegate:self];
    return audioOutput;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)play {
    if (_isPlaying) {
        return;
    }
    
    if (_audioOutput) {
        [_audioOutput play];
        _isPlaying = YES;
    }
}

- (void)pause {
    if (!_isPlaying) {
        return;
    }
    
    if (_audioOutput) {
        [_audioOutput stop];
        _isPlaying = NO;
    }
}

- (void)stop {
    if (_audioOutput) {
        [_audioOutput stop];
        _audioOutput = nil;
    }
    
    if (_sync) {
        [_sync closeFile];
        _sync = nil;
    }
    
    if (_videoOutput) {
        [_videoOutput destroy];
        [_videoOutput removeFromSuperview];
        _videoOutput = nil;
    }
    
    _isPlaying = NO;
}

#pragma mark - FillDataDelegate
- (NSInteger)fillAudioData:(SInt16 *)sampleBuffer numFrames:(NSInteger)numFrames numChannles:(NSInteger)numChannles {
    if (_sync) {
        [_sync audioCallBackFillData:sampleBuffer numFrames:numFrames numChannels:numChannles];
        VideoFrame *videoFrame = [_sync getCorrectVideoFrame];
        if (videoFrame) {
            [_videoOutput presentVideoFrame:videoFrame];
        }
    }
    
    return 1;
}


@end
