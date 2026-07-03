#import "OxAudioExceptionCatcher.h"

@implementation OxAudioExceptionCatcher

+ (BOOL)perform:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = exception.reason ?: exception.name ?: @"AVAudioEngine graph error";
            *error = [NSError errorWithDomain:@"Ox0badf00d.AudioEngineException"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
}

@end
