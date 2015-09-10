/*
 * This is the source code of Telegram for iOS v. 1.1
 * It is licensed under GNU GPL v. 2 or later.
 * You should have received a copy of the license in this archive (see LICENSE).
 *
 * Copyright Peter Iakovlev, 2013.
 */

#import "TGAudioRecorder.h"
#import "ASQueue.h"
#import "TGTimer.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "TGAlertView.h"

#define TGUseModernAudio true

@interface TGAudioRecorder () <AVAudioRecorderDelegate>
{
//    TGTimer *_timer;
    NSURL *_outputFileURL;
    AVAudioRecorder *_recorder;
}

@end

@implementation TGAudioRecorder

- (void)dealloc
{
    [self cleanup];
}

+ (ASQueue *)audioRecorderQueue
{
    static ASQueue *queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        queue = [[ASQueue alloc] initWithName:"org.telegram.audioRecorderQueue"];
    });
    return queue;
}

- (void)start
{
    NSLog(@"[TGAudioRecorder start]");
    
    [[TGAudioRecorder audioRecorderQueue] dispatchOnQueue:^
    {
        void (^recordBlock)(bool) = ^(bool granted)
        {
            if (granted)
            {
                int64_t randomId = 0;
                arc4random_buf(&randomId, 8);
                NSArray *pathComponents = @[NSTemporaryDirectory(), [[NSString alloc] initWithFormat:@"%" PRIx64 ".m4a", randomId]];
                _outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];

                // Setup audio session
                AVAudioSession *session = [AVAudioSession sharedInstance];
                [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];

                NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];
                
                [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];
                [recordSetting setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
                [recordSetting setValue:[NSNumber numberWithInt: 2] forKey:AVNumberOfChannelsKey];
                
                _recorder = [[AVAudioRecorder alloc] initWithURL:_outputFileURL settings:recordSetting error:nil];
                _recorder.delegate = self;
                _recorder.meteringEnabled = YES;
                [_recorder prepareToRecord];
                [_recorder record];
            }
            else
            {
                [[[TGAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"Conversation.MicrophoneAccessDisabled", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"Common.OK",nil) otherButtonTitles:nil] show];
            }
        };
        
        if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)])
        {
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted)
            {
                dispatch_async(dispatch_get_main_queue(), ^
                {
                    recordBlock(granted);
                });
            }];
        }
        else
            recordBlock(true);
    }];
}

- (NSTimeInterval)currentDuration
{
    return [_recorder currentTime];
}

- (void)_commitRecord
{
    [_recorder record];
    
    dispatch_async(dispatch_get_main_queue(), ^
    {
        id<TGAudioRecorderDelegate> delegate = _delegate;
        if ([delegate respondsToSelector:@selector(audioRecorderDidStartRecording:)])
            [delegate audioRecorderDidStartRecording:self];
    });
}

- (void)cleanup
{
    AVAudioRecorder *modernRecorder = _recorder;
    _recorder = nil;
    
    [[TGAudioRecorder audioRecorderQueue] dispatchOnQueue:^
    {
        if (modernRecorder != nil)
            [modernRecorder stop];
    }];
}

- (void)cancel
{
    [[TGAudioRecorder audioRecorderQueue] dispatchOnQueue:^
    {
        [self cleanup];
    }];
}

- (void)finish:(void (^)(NSString *, NSTimeInterval))completion
{
    [[TGAudioRecorder audioRecorderQueue] dispatchOnQueue:^
    {
        NSString *resultPath = nil;
        NSTimeInterval resultDuration = 0.0;
        
        if (_recorder != nil)
        {
            NSTimeInterval recordedDuration = [_recorder currentTime];
            NSString* path = _outputFileURL.path;
            [_recorder stop];
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];
            [audioSession setActive:NO error:nil];

            if (path != nil && recordedDuration > 0.5)
            {
                resultPath = path;
                resultDuration = recordedDuration;
            }
        }
        
        if (completion != nil)
            completion(resultPath, resultDuration);
    }];
}

@end
