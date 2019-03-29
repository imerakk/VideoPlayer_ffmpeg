//
//  GTVideoDecoder.m
//  VideoPlayer
//
//  Created by liuchunxi on 2019/3/29.
//  Copyright © 2019年 imera. All rights reserved.
//

#import "GTVideoDecoder.h"
#import <Accelerate/Accelerate.h>
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libswresample/swresample.h"
#include "libavutil/pixdesc.h"

static NSArray *collectStreams(AVFormatContext *formatContext, enum AVMediaType codecType) {
    NSMutableArray *array = [NSMutableArray array];
    for (int i=0; i<formatContext->nb_streams; i++) {
        if (formatContext->streams[i]->codecpar->codec_type == codecType) {
            [array addObject:@(i)];
        }
    }
    
    return [array copy];
}

static void avStreamFPSTimeBase(AVStream *stream, CGFloat defaultTimeBase, CGFloat *pFPS, CGFloat *pTimeBase) {
    if (stream == NULL || pFPS == NULL || pTimeBase == NULL) {
        return;
    }
    
    if (stream->time_base.den && stream->time_base.num) {
        *pTimeBase = av_q2d(stream->time_base);
    }
    else {
        *pTimeBase = defaultTimeBase;
    }
    
    if (stream->avg_frame_rate.den && stream->avg_frame_rate.num) {
        *pFPS = av_q2d(stream->avg_frame_rate);
    }
    else {
        *pFPS = 1.0 / *pTimeBase;
    }
}


@interface GTVideoDecoder ()
{
    NSArray *_videoStreams;
    NSArray *_audioStreams;
    AVFormatContext *_formatContext;
    
    AVCodecContext *_videoCodecContext;
    AVCodecContext *_audioCodecContext;
    
    NSUInteger _videoStreamIndex;
    NSUInteger _audioStreamIndex;
    
    CGFloat _videoTimeBase;
    CGFloat _videoFPS;
    CGFloat _audioTimeBase;
}

@end

@implementation GTVideoDecoder

- (BOOL)openFile:(NSString *)filePath parameters:(NSDictionary *)parameters {
    if (!filePath) {
        return NO;
    }
    
    if (![self openInputWithFilePath:filePath parameters:parameters]) {
        [self clearResource];
        return NO;
    }
    
    if (![self openAudioStream] || ![self openVideoStream]) {
        [self clearResource];
        return NO;
    }

    return YES;
}

- (void)clearResource {
    if (_formatContext) {
        avformat_free_context(_formatContext);
        avformat_close_input(&_formatContext);
    }
    if (_videoCodecContext) {
        avcodec_free_context(&_videoCodecContext);
    }
    if (_audioCodecContext) {
        avcodec_free_context(&_audioCodecContext);
    }
}

- (NSArray *)decodeFrame:(CGFloat)minDuration {
    return nil;
}

- (BOOL)openVideoStream {
    _videoStreams = collectStreams(_formatContext, AVMEDIA_TYPE_VIDEO);
    for (NSNumber *streamIndex in _videoStreams) {
        NSUInteger iStream = streamIndex.unsignedIntegerValue;
        AVCodecParameters *codecPara = _formatContext->streams[iStream]->codecpar;
        AVCodec *codec = avcodec_find_decoder(codecPara->codec_id);
        if (codec == NULL) {
            NSLog(@"fail avcodec_find_decoder for video");
            return NO;
        }
        
        AVCodecContext *codecContext = avcodec_alloc_context3(codec);
        if (avcodec_parameters_to_context(codecContext, codecPara) < 0) {
            NSLog(@"fail avcodec_parameters_to_context for video");
            return NO;
        }
        
        if (avcodec_open2(codecContext, codec, NULL) < 0) {
            NSLog(@"fail avcodec_open2 for video");
            return NO;
        }
        
        _videoCodecContext = codecContext;
        _videoStreamIndex = iStream;
        avStreamFPSTimeBase(_formatContext->streams[iStream], 0.04, &_videoFPS, &_videoTimeBase);
        break;
    }
    
    return YES;
}

- (BOOL)openAudioStream {
    _audioStreams = collectStreams(_formatContext, AVMEDIA_TYPE_AUDIO);
    for (NSNumber *streamIndex in _audioStreams) {
        NSUInteger iStream = streamIndex.unsignedIntegerValue;
        AVCodecParameters *codecPara = _formatContext->streams[iStream]->codecpar;
        AVCodec *codec = avcodec_find_decoder(codecPara->codec_id);
        if (codec == NULL) {
            NSLog(@"fail avcodec_find_decoder for audio");
            return NO;
        }
        
        AVCodecContext *codecContext = avcodec_alloc_context3(codec);
        if (avcodec_parameters_to_context(codecContext, codecPara) < 0) {
            NSLog(@"fail avcodec_parameters_to_context for audio");
            return NO;
        }
        
        if (avcodec_open2(codecContext, codec, NULL) < 0) {
            NSLog(@"fail avcodec_open2 for audio");
            return NO;
        }
        
        _audioCodecContext = codecContext;
        _audioStreamIndex = iStream;
        avStreamFPSTimeBase(_formatContext->streams[iStream], 0.025, 0, &_audioTimeBase);
        break;
    }
    return YES;
}

- (BOOL)openInputWithFilePath:(NSString *)filePath parameters:(NSDictionary *)parameters {
    AVFormatContext *formatContext = avformat_alloc_context();
    const char *url = [filePath UTF8String];
    AVDictionary *options = NULL;
    /*
    NSString *rtmpUrl = parameters[RTMP_TCURL_KEY];
    if (rtmpUrl.length > 0) {
        const char *rtmpCStr = [rtmpUrl UTF8String];
        av_dict_set(&options, "rtmp_tcurl", rtmpCStr, 0);
    }
    */
    int res = avformat_open_input(&formatContext, url, NULL, &options);
    if (res != 0) {
        NSLog(@"fail avformat_open_input");
        return NO;
    }
    
    [self initAnalyzeDurationAndProbeSize:formatContext paramaeters:parameters];
    
    res = avformat_find_stream_info(formatContext, NULL);
    if (res < 0) {
        NSLog(@"fail avformat_find_stream_info");
        return NO;
    }
    
    _formatContext = formatContext;
    return YES;
}

- (void)initAnalyzeDurationAndProbeSize:(AVFormatContext *)formatContext paramaeters:(NSDictionary *)paramaters {
    CGFloat probeSize = [paramaters[PROBE_SIZE] floatValue];
    formatContext->probesize = probeSize ?: 50 * 1024;
    
    CGFloat maxAnalyzeDuration = [paramaters[MAX_ANALYZE_DURATION] floatValue];
    formatContext->max_analyze_duration = maxAnalyzeDuration ?: 1.0 * AV_TIME_BASE;
    
    unsigned int fpsProbeSzie = [paramaters[FPS_PROBE_SIZE] unsignedIntValue];
    formatContext->fps_probe_size = fpsProbeSzie;
}


@end
