#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges Objective-C `@try/@catch` into Swift's error system.
///
/// `AVAudioEngine` reports many failures — most notably connecting an insert AudioUnit whose bus
/// cannot accept the requested format (`kAudioUnitErr_FormatNotSupported`, -10868) — by raising an
/// `NSException`, which Swift cannot catch with `do/try`. Routing those calls through here turns the
/// exception into a Swift `throws`, so a misbehaving or incompatible third-party plugin can never
/// crash the host application.
@interface OxAudioExceptionCatcher : NSObject
+ (BOOL)perform:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
