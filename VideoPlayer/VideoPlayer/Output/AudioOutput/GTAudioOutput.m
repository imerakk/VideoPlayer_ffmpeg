//
//  GTAudioOutput.m
//  VideoPlayer
//
//  Created by liuchunxi on 2019/4/3.
//  Copyright © 2019年 imera. All rights reserved.
//

#import "GTAudioOutput.h"
#import <AVFoundation/AVFoundation.h>
#import "AVAudioSession+RouteUtils.h"

static void CheckStatus(OSStatus status, NSString *message);
static OSStatus inputRenderCallBack(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);


@interface GTAudioOutput ()
{
    SInt16 *_outData;
}

@property (nonatomic, assign) NSInteger channels;
@property (nonatomic, assign) NSInteger sampleRate;
@property (nonatomic, weak) id<FillDataDelegate> mDelegate;
@property (nonatomic, strong) AVAudioSession *audioSession;

@property (nonatomic, assign) AUGraph auGraph;
@property (nonatomic, assign) AUNode ioNode;
@property (nonatomic, assign) AUNode convertNode;
@property (nonatomic, assign) AudioUnit ioUnit;
@property (nonatomic, assign) AudioUnit convertUnit;

@end

@implementation GTAudioOutput

- (instancetype)initWithChannels:(NSInteger)channels sampleRate:(NSInteger)sampleRate dalegate:(id<FillDataDelegate>)delegate {
    self = [super init];
    if (self) {
        _channels = channels;
        _sampleRate = sampleRate;
        _mDelegate = delegate;
        _outData = (SInt16 *)calloc(8192, sizeof(SInt16));
        
        [self setupAudioSession];
        [self createAudioUnitGraph];
    }
    
    return self;
}

- (OSStatus)renderData:(AudioBufferList *)ioData
           atTimeStamp:(const AudioTimeStamp *)timeStamp
            forElement:(UInt32)element
          numberFrames:(UInt32)numFrames
                 flags:(AudioUnitRenderActionFlags *)flags
{
    @autoreleasepool {
        for (int i=0; i<ioData->mNumberBuffers; i++) {
            memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
        }
        
        if (_mDelegate) {
            [_mDelegate fillAudioData:_outData numFrames:numFrames numChannles:_channels];
            for (int i=0; i<ioData->mNumberBuffers; i++) {
                memcpy(ioData->mBuffers[i].mData, _outData, ioData->mBuffers[i].mDataByteSize);
            }
        }
        
        return noErr;
    }
}

- (void)setupAudioSession {
    _audioSession = [AVAudioSession sharedInstance];
    
    NSError *error = nil;
    [_audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error) {
        NSLog(@"fail setCategory AVAudioSessionCategoryPlayAndRecord");
    }
    
    error = nil;
    [_audioSession setPreferredSampleRate:_sampleRate error:&error];
    if (error) {
        NSLog(@"fail setPreferredSampleRate");
    }
    
    error = nil;
    [_audioSession setActive:YES error:&error];
    if (error) {
        NSLog(@"fail setActive");
    }

    [self addRouteChangeListener];
}

- (void)addRouteChangeListener
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNotificationAudioRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
    [self adjustOnRouteChange];
}

#pragma mark - notification observer
- (void)onNotificationAudioRouteChange:(NSNotification *)sender {
    [self adjustOnRouteChange];
}

- (void)adjustOnRouteChange
{
    AVAudioSessionRouteDescription *currentRoute = [[AVAudioSession sharedInstance] currentRoute];
    if (currentRoute) {
        if ([[AVAudioSession sharedInstance] usingWiredMicrophone]) {
        } else {
            if (![[AVAudioSession sharedInstance] usingBlueTooth]) {
                [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
            }
        }
    }
}

- (void)createAudioUnitGraph {
    OSStatus status = noErr;
    
    status = NewAUGraph(&_auGraph);
    CheckStatus(status, @"Could not create a new AUGraph");
    
    [self addAudioNodes];
    [self getUnitsFromNodes];
    [self setAudioUnitProperty];
    [self connectAudioNodes];
    
    CAShow(_auGraph);
    status = AUGraphInitialize(_auGraph);
    CheckStatus(status, @"Could not initialize AUGraph");
}

- (void)addAudioNodes {
    OSStatus status = noErr;
    
    AudioComponentDescription ioDescription;
    bzero(&ioDescription, sizeof(ioDescription));
    ioDescription.componentType = kAudioUnitType_Output;
    ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    status = AUGraphAddNode(_auGraph, &ioDescription, &_ioNode);
    CheckStatus(status, @"Could not create io node");
    
    AudioComponentDescription convertDescription;
    bzero(&convertDescription, sizeof(convertDescription));
    convertDescription.componentType = kAudioUnitType_FormatConverter;
    convertDescription.componentSubType = kAudioUnitSubType_AUConverter;
    convertDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    status = AUGraphAddNode(_auGraph, &convertDescription, &_convertNode);
    CheckStatus(status, @"Cound not create convert node");
}

- (void)getUnitsFromNodes {
    OSStatus status = noErr;
    
    status = AUGraphOpen(_auGraph);
    CheckStatus(status, @"Could not open AUGraph");
    
    status = AUGraphNodeInfo(_auGraph, _ioNode, NULL, &_ioUnit);
    CheckStatus(status, @"Could not get io unit");
    
    status = AUGraphNodeInfo(_auGraph, _convertNode, NULL, &_convertUnit);
    CheckStatus(status, @"Could not get convert unit");
}

- (void)setAudioUnitProperty {
    OSStatus status = noErr;
    
    UInt32 bytesPerSample = sizeof(Float32);
    AudioStreamBasicDescription streamFormat;
    bzero(&streamFormat, sizeof(streamFormat));
    streamFormat.mSampleRate = _sampleRate;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    streamFormat.mBytesPerFrame = bytesPerSample;
    streamFormat.mBytesPerPacket = bytesPerSample;
    streamFormat.mBitsPerChannel = 8 * bytesPerSample;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mChannelsPerFrame = (UInt32)_channels;
    status = AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &streamFormat, sizeof(streamFormat));
    CheckStatus(status, @"Could not set property for convert unit input");
    
    UInt32 convertBytesPerSample = sizeof(SInt16);
    AudioStreamBasicDescription convertStreamFormat;
    bzero(&convertStreamFormat, sizeof(convertStreamFormat));
    convertStreamFormat.mFormatID = kAudioFormatLinearPCM;
    convertStreamFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    convertStreamFormat.mChannelsPerFrame = (UInt32)_channels;
    convertStreamFormat.mSampleRate = _sampleRate;
    convertStreamFormat.mFramesPerPacket = 1;
    convertStreamFormat.mBytesPerFrame = (UInt32)(convertBytesPerSample * _channels);
    convertStreamFormat.mBytesPerPacket = (UInt32)(convertBytesPerSample * _channels);
    convertStreamFormat.mBitsPerChannel = 8 * convertBytesPerSample;
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &convertStreamFormat, sizeof(convertStreamFormat));
    CheckStatus(status, @"Could not set property for convert unit input");
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamFormat, sizeof(streamFormat));
    CheckStatus(status, @"Could not set property for convert unit output");
}

- (void)connectAudioNodes {
    OSStatus status = noErr;
    
    status = AUGraphConnectNodeInput(_auGraph, _convertNode, 0, _ioNode, 0);
    CheckStatus(status, @"Could not connect I/O and convert node)");
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProcRefCon = (__bridge void *)self;
    callbackStruct.inputProc = &inputRenderCallBack;
    
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callbackStruct, sizeof(callbackStruct));
    
    CheckStatus(status, @"Could not set render callback on mixer input scope");
}

- (BOOL)play {
    OSStatus status = AUGraphStart(_auGraph);
    CheckStatus(status, @"Could not start graph");
    return status == noErr;
}

- (void)stop {
    OSStatus status = AUGraphStop(_auGraph);
    CheckStatus(status, @"Could not stop graph");
}

- (void)dealloc {
    if (_outData) {
        free(_outData);
        _outData = NULL;
    }
    
    [self destoryAudioGraph];
}

- (void)destoryAudioGraph {
    AUGraphStop(_auGraph);
    AUGraphUninitialize(_auGraph);
    AUGraphClose(_auGraph);
    AUGraphRemoveNode(_auGraph, _ioNode);
    AUGraphRemoveNode(_auGraph, _convertNode);
    DisposeAUGraph(_auGraph);
}

@end


static OSStatus inputRenderCallBack(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    GTAudioOutput *audioOutput = (__bridge id)inRefCon;
    return [audioOutput renderData:ioData
                       atTimeStamp:inTimeStamp
                        forElement:inBusNumber
                      numberFrames:inNumberFrames
                             flags:ioActionFlags];
}

static void CheckStatus(OSStatus status, NSString *message) {
    if (status != noErr) {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        if (isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3])) {
            NSLog(@"%@: %s", message, fourCC);
        }
        else {
            NSLog(@"%@: %d", message, (int)status);
        }
    }
}

