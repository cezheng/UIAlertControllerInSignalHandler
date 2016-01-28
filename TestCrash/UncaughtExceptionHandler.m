//
//  UncaughtExceptionHandler.m
//  UncaughtExceptions
//
//  Created by Matt Gallagher on 2010/05/25.
//  Copyright 2010 Matt Gallagher. All rights reserved.
//
//  Permission is given to use this source code file, free of charge, in any
//  project, commercial or otherwise, entirely at your risk, with the condition
//  that any redistribution (in part or whole) of source code must retain
//  this copyright and permission notice. Attribution in compiled projects is
//  appreciated but not required.
//

#import "UncaughtExceptionHandler.h"
#include <execinfo.h>
#include <libkern/OSAtomic.h>

NSString *const UncaughtExceptionHandlerSignalExceptionName =
    @"UncaughtExceptionHandlerSignalExceptionName";
NSString *const UncaughtExceptionHandlerSignalKey =
    @"UncaughtExceptionHandlerSignalKey";
NSString *const UncaughtExceptionHandlerAddressesKey =
    @"UncaughtExceptionHandlerAddressesKey";

volatile int32_t UncaughtExceptionCount = 0;
const int32_t UncaughtExceptionMaximum = 10;

const NSInteger UncaughtExceptionHandlerSkipAddressCount = 4;
const NSInteger UncaughtExceptionHandlerReportAddressCount = 5;

@implementation UncaughtExceptionHandler

- (void)validateAndSaveCriticalApplicationData {
}

- (void)handleException:(NSException *)exception {
  [self validateAndSaveCriticalApplicationData];

  UIAlertController *alert = [UIAlertController
      alertControllerWithTitle:NSLocalizedString(@"Unhandled exception", nil)
                       message:
                           [NSString
                               stringWithFormat:
                                   NSLocalizedString(
                                       @"You can try to continue but the "
                                       @"application may be unstable.\n\n"
                                       @"Debug details follow:\n%@\n%@",
                                       nil),
                                   [exception reason],
                                   [[exception userInfo]
                                       objectForKey:
                                           UncaughtExceptionHandlerAddressesKey]]
                preferredStyle:UIAlertControllerStyleActionSheet];

  UIAlertAction *quitAction =
      [UIAlertAction actionWithTitle:NSLocalizedString(@"Quit", nil)
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *_Nonnull action) {
                               dismissed = true;
                             }];
  [alert addAction:quitAction];

  UIWindow *window = [[UIApplication sharedApplication] keyWindow];

  // If I present the UIAlertController by presentViewController
  // then the UIAlertController is freezed
  // not responding to any touch events
  [[window rootViewController] presentViewController:alert
                                            animated:YES
                                          completion:nil];
  // If I change the above line to

  // [window setRootViewController:alert];

  // then the UIAlertController can be scrolled or clicked
  // but whenever I click any buttons
  // it fails with `trying to dismiss UIAlertContler xxx with unknown presenter`

  CFRunLoopRef runLoop = CFRunLoopGetCurrent();
  CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);

  while (!dismissed) {
    for (NSString *mode in (NSArray *)allModes) {
      CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);
    }
  }

  CFRelease(allModes);

  NSSetUncaughtExceptionHandler(NULL);
  signal(SIGABRT, SIG_DFL);
  signal(SIGILL, SIG_DFL);
  signal(SIGSEGV, SIG_DFL);
  signal(SIGFPE, SIG_DFL);
  signal(SIGBUS, SIG_DFL);
  signal(SIGPIPE, SIG_DFL);

  if ([[exception name] isEqual:UncaughtExceptionHandlerSignalExceptionName]) {
    kill(getpid(),
         [[[exception userInfo] objectForKey:UncaughtExceptionHandlerSignalKey]
             intValue]);
  } else {
    [exception raise];
  }
}

@end

void HandleException(NSException *exception) {
  int32_t exceptionCount = OSAtomicIncrement32(&UncaughtExceptionCount);
  if (exceptionCount > UncaughtExceptionMaximum) {
    return;
  }

  NSArray *callStack = [NSThread callStackSymbols];
  NSMutableDictionary *userInfo =
      [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
  [userInfo setObject:callStack forKey:UncaughtExceptionHandlerAddressesKey];

  NSException *except = [[NSException exceptionWithName:[exception name]
                                                 reason:[exception reason]
                                               userInfo:userInfo] autorelease];
  if ([NSThread isMainThread]) {
    [[[[UncaughtExceptionHandler alloc] init] autorelease]
        handleException:except];
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[[[UncaughtExceptionHandler alloc] init] autorelease]
          handleException:except];
    });
  }
}

void SignalHandler(int signal) {
  int32_t exceptionCount = OSAtomicIncrement32(&UncaughtExceptionCount);
  if (exceptionCount > UncaughtExceptionMaximum) {
    return;
  }

  NSMutableDictionary *userInfo = [NSMutableDictionary
      dictionaryWithObject:[NSNumber numberWithInt:signal]
                    forKey:UncaughtExceptionHandlerSignalKey];

  NSArray *callStack = [NSThread callStackSymbols];
  [userInfo setObject:callStack forKey:UncaughtExceptionHandlerAddressesKey];
  [userInfo setObject:[NSNumber numberWithInt:signal]
               forKey:UncaughtExceptionHandlerSignalKey];

  NSException *except = [NSException
      exceptionWithName:UncaughtExceptionHandlerSignalExceptionName
                 reason:[NSString
                            stringWithFormat:NSLocalizedString(
                                                 @"Signal %d was raised.", nil),
                                             signal]
               userInfo:userInfo];

  if ([NSThread isMainThread]) {
    [[[[UncaughtExceptionHandler alloc] init] autorelease]
        handleException:except];
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      [[[[UncaughtExceptionHandler alloc] init] autorelease]
          handleException:except];
    });
  }
}

void InstallUncaughtExceptionHandler() {
  NSSetUncaughtExceptionHandler(&HandleException);
  signal(SIGABRT, SignalHandler);
  signal(SIGILL, SignalHandler);
  signal(SIGSEGV, SignalHandler);
  signal(SIGFPE, SignalHandler);
  signal(SIGBUS, SignalHandler);
  signal(SIGPIPE, SignalHandler);
}
