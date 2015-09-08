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

#import "TGOpusAudioRecorder.h"

@interface TGAudioRecorder () <AVAudioRecorderDelegate>
{
    TGTimer *_timer;
    
    TGOpusAudioRecorder *_modernRecorder;
}

@end

@implementation TGAudioRecorder

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        [[TGAudioRecorder audioRecorderQueue] dispatchOnQueue:^
        {
            _modernRecorder = [[TGOpusAudioRecorder alloc] initWithFileEncryption:false];
        }];
    }
    return self;
}

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

static NSMutableDictionary *recordTimers()
{
    static NSMutableDictionary *dict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        dict = [[NSMutableDictionary alloc] init];
    });
    
    return dict;
}

static int currentTimerId = 0;

static void playSoundCompleted(__unused SystemSoundID ssID, __unused void *clientData)
{
    [[TGAudioRecorder audioRecorderQueue] dispatchOnQueue:^
    {
        int timerId = currentTimerId;
        TGTimer *timer = (TGTimer *)recordTimers()[@(timerId)];
        if ([timer isScheduled])
            [timer resetTimeout:0.05];
    }];
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
                NSTimeInterval prepareStart = CFAbsoluteTimeGetCurrent();
                
                [_timer invalidate];
                
                static int nextTimerId = 0;
                int timerId = nextTimerId++;
                
                __weak TGAudioRecorder *weakSelf = self;
                NSTimeInterval timeout = MIN(1.0, MAX(0.1, 1.0 - (CFAbsoluteTimeGetCurrent() - prepareStart)));
                _timer = [[TGTimer alloc] initWithTimeout:timeout repeat:false completion:^
                {
                    __strong TGAudioRecorder *strongSelf = weakSelf;
                    [strongSelf _commitRecord];
                } queue:[TGAudioRecorder audioRecorderQueue].nativeQueue];
                recordTimers()[@(timerId)] = _timer;
                [_timer start];
                
                currentTimerId = timerId;
                
                static SystemSoundID soundId;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^
                {
                    NSString *path = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] resourcePath], @"begin_record.caf"];
                    NSURL *filePath = [NSURL fileURLWithPath:path isDirectory:false];
                    AudioServicesCreateSystemSoundID((__bridge CFURLRef)filePath, &soundId);
                    if (soundId != 0)
                        AudioServicesAddSystemSoundCompletion(soundId, NULL, kCFRunLoopCommonModes, &playSoundCompleted, NULL);
                });
                
                AudioServicesPlaySystemSound(soundId);
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
    return [_modernRecorder currentDuration];
}

- (void)_commitRecord
{
    [_modernRecorder record];
    
    dispatch_async(dispatch_get_main_queue(), ^
    {
        id<TGAudioRecorderDelegate> delegate = _delegate;
        if ([delegate respondsToSelector:@selector(audioRecorderDidStartRecording:)])
            [delegate audioRecorderDidStartRecording:self];
    });
}

- (void)cleanup
{
    TGOpusAudioRecorder *modernRecorder = _modernRecorder;
    _modernRecorder = nil;
    
    TGTimer *timer = _timer;
    _timer = nil;
    
    [[TGAudioRecorder audioRecorderQueue] dispatchOnQueue:^
    {
        [timer invalidate];
        
        if (modernRecorder != nil)
            [modernRecorder stop:NULL];
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
        
        if (_modernRecorder != nil)
        {
            NSTimeInterval recordedDuration = 0.0;
            NSString *path = [_modernRecorder stop:&recordedDuration];
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
