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
#include "libavutil/avutil.h"
#include "libavutil/imgutils.h"

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

static NSData *copyFrameData(uint8_t *src, int length) {
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:src length:length];
    return [data copy];
}

@implementation Frame
@end

@implementation AudioFrame
@end

@implementation VideoFrame
@end

@interface GTVideoDecoder ()
{
    NSArray *_videoStreams;
    NSArray *_audioStreams;
    
    AVFormatContext *_formatContext;
    SwrContext *_swrContext;
    AVCodecContext *_videoCodecContext;
    AVCodecContext *_audioCodecContext;
    
    AVFrame *_audioFrame;
    AVFrame *_videoFrame;
    
    NSUInteger _videoStreamIndex;
    NSUInteger _audioStreamIndex;
    
    CGFloat _videoTimeBase;
    CGFloat _videoFPS;
    CGFloat _audioTimeBase;
    
    void *_swrBuffer;
    NSUInteger _swrBufferSize;
    
    struct SwsContext* _swsContext;
    uint8_t *_videoBuffer[4];
    int _videoBufferLineSize[4];
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
    _videoStreamIndex = -1;
    _audioStreamIndex = -1;
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
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
    if (_audioFrame) {
        av_frame_free(&_audioFrame);
    }
    if (_videoFrame) {
        av_frame_free(&_videoFrame);
    }
    if (_swrContext) {
        swr_free(&_swrContext);
    }
}

- (NSArray *)decodeFrames:(CGFloat)minDuration {
    if (_videoStreamIndex == -1 && _audioStreamIndex == -1) {
        return nil;
    }
    
    BOOL finish = NO;
    CGFloat decodeDuration = 0;
    AVPacket *packet = av_packet_alloc();
    NSMutableArray *frames = [NSMutableArray array];
    while (!finish) {
        if (av_read_frame(_formatContext, packet) < 0) {
            break;
        }
        
        if (packet->stream_index == _audioStreamIndex) { //音频流
            NSArray *audioFrames = [self decoderAudioWithPacket:packet];
        
            for (AudioFrame *audio in audioFrames) {
                [frames addObject:audio];
                
                if (_videoStreamIndex == -1) {
                    decodeDuration += audio.duration;
                    if (decodeDuration > minDuration) {
                        finish = YES;
                        break;
                    }
                }
            }
        }
        else if (packet->stream_index == _videoStreamIndex) { //视频流
            NSArray *videoFrames = [self decodeVideoWithPacket:packet];
            
            for (VideoFrame *video in videoFrames) {
                [frames addObject:video];
                decodeDuration += video.duration;
                if (decodeDuration > minDuration) {
                    finish = YES;
                }
            }
        }
    }
    
    av_packet_free(&packet);
    
    return [frames copy];
}

- (void)closeScaler {
    if (_videoBuffer) {
        av_freep(_videoBuffer[0]);
    }
    if (_swsContext) {
        sws_freeContext(_swsContext);
        _swsContext = NULL;
    }
}

- (BOOL)setupScaler {
    [self closeScaler];
    int res = av_image_alloc(_videoBuffer, _videoBufferLineSize, _videoCodecContext->width, _videoCodecContext->height, AV_PIX_FMT_YUV420P, 1);
    if (res < 0) {
        NSLog(@"fail av_image_alloc for video");
        return NO;
    }
    
    _swsContext = sws_getContext(_videoCodecContext->width, _videoCodecContext->height, _videoCodecContext->pix_fmt, _videoCodecContext->width, _videoCodecContext->height, AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
    if (!_swsContext) {
        NSLog(@"fail sws_getContext for video");
        return NO;
    }

    return YES;
}

- (NSArray *)decodeVideoWithPacket:(AVPacket *)packet {
    if (!packet) {
        return nil;
    }
    
    int res = avcodec_send_packet(_videoCodecContext, packet);
    if (res < 0) {
        NSLog(@"fail avcodec_send_frame for video");
        return nil;
    }
    
    NSMutableArray *videoFrames = [NSMutableArray array];
    while (res > 0) {
        res = avcodec_receive_frame(_videoCodecContext, _videoFrame);
        if (!_videoFrame->data[0]) {
            break;
        }
        
        VideoFrame *videoFrame = [[VideoFrame alloc] init];
        if (_videoCodecContext->pix_fmt == AV_PIX_FMT_YUV420P || _videoCodecContext->pix_fmt == AV_PIX_FMT_YUVJ420P) {
            videoFrame.luma = copyFrameData(_videoFrame->data[0], _videoFrame->linesize[0]*_videoCodecContext->height);
            videoFrame.chromaB = copyFrameData(_videoFrame->data[1], _videoFrame->linesize[1]*_videoCodecContext->height);
            videoFrame.chromaR = copyFrameData(_videoFrame->data[2], _videoFrame->linesize[2]*_videoCodecContext->height);
        }
        else {
            if (!_swsContext && ![self setupScaler]) {
                NSLog(@"fail set up video scaler");
                break;
            }
            
            sws_scale(_swsContext, (const uint8_t **)_videoFrame->data, _videoFrame->linesize, 0, _videoCodecContext->height, _videoBuffer, _videoBufferLineSize);
            videoFrame.luma = copyFrameData(_videoBuffer[0], _videoBufferLineSize[0]*_videoCodecContext->height);
            videoFrame.chromaB = copyFrameData(_videoBuffer[1], _videoBufferLineSize[1]*_videoCodecContext->height);
            videoFrame.chromaR = copyFrameData(_videoBuffer[2], _videoBufferLineSize[2]*_videoCodecContext->height);
        }
        videoFrame.type = VideoFrameType;
        videoFrame.width = _videoCodecContext->width;
        videoFrame.height = _videoCodecContext->height;
        videoFrame.lineSize = _videoFrame->linesize[0];
        videoFrame.position = _videoFrame->best_effort_timestamp * _videoTimeBase;
        videoFrame.duration = _videoFrame->pkt_duration * _videoTimeBase;
        [videoFrames addObject:videoFrame];
    }
    
    return [videoFrames copy];
}

- (NSArray *)decoderAudioWithPacket:(AVPacket *)packet {
    int res = avcodec_send_packet(_audioCodecContext, packet);
    if (res < 0) {
        NSLog(@"fail avcodec_send_packet for audio");
        return nil;
    }
    
    NSMutableArray *audioFrames = [NSMutableArray array];
    NSInteger numSamples;
    void *audioData;
    while (res >= 0) {
        res = avcodec_receive_frame(_audioCodecContext, _audioFrame);
        if (!_audioFrame->data[0]) {
            break;
        }
        
        if (_swrContext) {
            NSUInteger ratio = 1;
            int bufSize = av_samples_get_buffer_size(NULL, _audioCodecContext->channels, (int)(_audioFrame->nb_samples*ratio), AV_SAMPLE_FMT_S16, 1);
            if (!_swrBuffer || _swrBufferSize < bufSize) {
                _swrBufferSize = bufSize;
                _swrBuffer = realloc(_swrBuffer, _swrBufferSize);
            }
            
            Byte *outBuf[2] = {_swrBuffer, 0};
            numSamples = swr_convert(_swrContext, outBuf, (int)(_audioFrame->nb_samples*ratio), (const uint8_t**)_audioFrame->data, _audioFrame->nb_samples);
            if (numSamples < 0) {
                NSLog(@"fail swr_convert for audio");
                break;
            }
            
            audioData = _swrBuffer;
        }
        else {
            if (_audioCodecContext->sample_fmt != AV_SAMPLE_FMT_S16) {
                NSLog(@"Audio format is invaild");
                break;
            }
            
            audioData = _audioFrame->data[0];
            numSamples = _audioFrame->nb_samples;
        }
        
        NSMutableData *pcmData = [NSMutableData data];
        [pcmData appendBytes:audioData length:_audioFrame->channels*numSamples*sizeof(SInt16)];
        
        AudioFrame *audioFrame = [[AudioFrame alloc] init];
        audioFrame.type = AudioFrameType;
        audioFrame.samples = pcmData;
        audioFrame.duration = _audioFrame->pkt_duration * _audioTimeBase;
        audioFrame.position = _audioFrame->pkt_pos * _audioTimeBase;
    }
    
    return [audioFrames copy];
}

- (BOOL)openVideoStream {
    _videoStreams = collectStreams(_formatContext, AVMEDIA_TYPE_VIDEO);
    _videoStreamIndex = -1;
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
        
        _videoFrame = av_frame_alloc();
        if (_videoFrame == NULL) {
            NSLog(@"fail av_frame_alloc for video");
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
    _audioStreamIndex = -1;
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
        
        SwrContext *swrContext = NULL;
        if (!(codecContext->sample_fmt == AV_SAMPLE_FMT_S16)) { //重采样
            swrContext = swr_alloc_set_opts(NULL, codecContext->channel_layout, AV_SAMPLE_FMT_S16, codecContext->sample_rate, codecContext->channel_layout, codecContext->sample_fmt, codecContext->sample_rate, 0, NULL);
            if (!swrContext || swr_init(swrContext)) {
                NSLog(@"fail swr_init for audio");
                return NO;
            }
        }
        
        _audioFrame = av_frame_alloc();
        if (_audioFrame == NULL) {
            NSLog(@"fail av_frame_alloc for audio");
            return NO;
        }
        
        _audioCodecContext = codecContext;
        _audioStreamIndex = iStream;
        _swrContext = swrContext;
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

- (NSInteger)videoWidth {
    return _videoCodecContext ? _videoCodecContext->width : 0;
}

- (NSInteger)videoHeight {
    return _videoCodecContext ? _videoCodecContext->height : 0;
}

- (NSInteger)vaildVideo {
    return _videoStreamIndex != -1;
}

- (NSInteger)vaildAudio {
    return _audioStreamIndex != -1;
}

- (NSInteger)audioChannels {
    return _audioCodecContext ? _audioCodecContext->channels : 0;
}

- (NSInteger)audioSampleRate {
    return _audioCodecContext ? _audioCodecContext->sample_rate : 0;
}

@end
