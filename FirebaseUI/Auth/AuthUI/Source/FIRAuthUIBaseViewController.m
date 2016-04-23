//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "FIRAuthUIBaseViewController.h"

#import <FirebaseAuth/FirebaseAuth.h>
#import "FIRAuthUIStrings.h"
#import "FIRAuthUIUtils.h"
#import "FIRAuthUI_Internal.h"

/** @var kEmailRegex
    @brief Regular expression for matching email addresses.
 */
static NSString *const kEmailRegex = @".+@([a-zA-Z0-9\\-]+\\.)+[a-zA-Z0-9]{2,63}";

/** @var kAuthUICodingKey
    @brief The key used to encode @c FIRAuthUI instance for NSCoding.
 */
static NSString *const kAuthUICodingKey = @"authUI";

/** @class FIRAuthUIAlertViewDelegate
    @brief A @c UIAlertViewDelegate which allows @c UIAlertView to be used with blocks more easily.
 */
@interface FIRAuthUIAlertViewDelegate : NSObject <UIAlertViewDelegate>

/** @fn init
    @brief Please use initWithCancelHandler:otherHandlers.
 */
- (nullable instancetype)init NS_UNAVAILABLE;

/** @fn initWithCancelHandler:otherHandlers:
    @brief Designated initializer.
    @param cancelHandler The block to call when the alert view is cancelled.
    @param otherHandler Handlers for other buttons of the alert view. The number of handlers must
        match the number of other buttons of the alert view.
 */
- (nullable instancetype)initWithCancelHandler:(nullable FIRAuthUIAlertActionHandler)cancelHandler
    otherHandlers:(nullable NSArray<FIRAuthUIAlertActionHandler> *)otherHandlers
    NS_DESIGNATED_INITIALIZER;

@end

@implementation FIRAuthUIAlertViewDelegate {
  FIRAuthUIAlertActionHandler _cancelHandler;
  NSArray<FIRAuthUIAlertActionHandler> *_otherHandlers;
  FIRAuthUIAlertViewDelegate *_retainedSelf;
}

- (nullable instancetype)initWithCancelHandler:(nullable FIRAuthUIAlertActionHandler)cancelHandler
    otherHandlers:(nullable NSArray<FIRAuthUIAlertActionHandler> *)otherHandlers {
  self = [super init];
  if (self) {
    _cancelHandler = cancelHandler;
    _otherHandlers = otherHandlers;
    _retainedSelf = self;
  }
  return self;
}

#pragma mark - FIRAuthUIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
  if (buttonIndex == alertView.cancelButtonIndex) {
    if (_cancelHandler) {
      _cancelHandler();
    }
  } else if (alertView.firstOtherButtonIndex != -1) {
    NSInteger otherButtonIndex = buttonIndex - alertView.firstOtherButtonIndex;
    if (_otherHandlers && _otherHandlers.count > otherButtonIndex) {
      FIRAuthUIAlertActionHandler handler = _otherHandlers[otherButtonIndex];
      handler();
    }
  }
  _cancelHandler = nil;
  _otherHandlers = nil;
  _retainedSelf = nil;
}

@end

@implementation FIRAuthUIBaseViewController

- (instancetype)initWithAuthUI:(FIRAuthUI *)authUI {
  self = [super initWithNibName:NSStringFromClass([self class])
                         bundle:[FIRAuthUIUtils frameworkBundle]];
  if (self) {
    _auth = authUI.auth;
    _authUI = authUI;
  }
  return self;
}

#pragma mark - NSCoding

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
  FIRAuthUI *authUI = [aDecoder decodeObjectOfClass:[FIRAuthUI class] forKey:kAuthUICodingKey];
  if (!authUI) {
    return nil;
  }
  return [self initWithAuthUI:authUI];
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
  [aCoder encodeObject:_authUI forKey:kAuthUICodingKey];
}

#pragma mark - Utilities

+ (BOOL)isValidEmail:(NSString *)email {
  static dispatch_once_t onceToken;
  static NSPredicate *emailPredicate;
  dispatch_once(&onceToken, ^{
    emailPredicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", kEmailRegex];
  });
  return [emailPredicate evaluateWithObject:email];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
  if ([UIAlertController class]) {
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction =
        [UIAlertAction actionWithTitle:[FIRAuthUIStrings OK]
                                 style:UIAlertActionStyleDefault
                               handler:nil];
    [alertController addAction:okAction];
    [self presentViewController:alertController animated:YES completion:nil];
  } else {
    UIAlertView *alert =
        [[UIAlertView alloc] initWithTitle:title
                                   message:message
                                  delegate:nil
                         cancelButtonTitle:nil
                         otherButtonTitles:[FIRAuthUIStrings OK], nil];
    [alert show];
  }
}

- (void)showSignInAlertWithEmail:(NSString *)email
                        provider:(id<FIRAuthProviderUI>)provider
                         handler:(FIRAuthUIAlertActionHandler)handler {
  NSString *message =
      [NSString stringWithFormat:[FIRAuthUIStrings providerUsedPreviouslyMessage],
          email, provider.shortName];
  if ([UIAlertController class]) {
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:[FIRAuthUIStrings welcomeBack]
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *signInAction =
        [UIAlertAction actionWithTitle:provider.signInLabel
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
          handler();
        }];
    [alertController addAction:signInAction];
    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:[FIRAuthUIStrings cancel]
                                 style:UIAlertActionStyleCancel
                               handler:nil];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
  } else {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[FIRAuthUIStrings welcomeBack]
                                                        message:message
                                                       delegate:self
                                              cancelButtonTitle:[FIRAuthUIStrings cancel]
                                              otherButtonTitles:provider.signInLabel, nil];
    FIRAuthUIAlertViewDelegate *delegate =
        [[FIRAuthUIAlertViewDelegate alloc] initWithCancelHandler:nil otherHandlers:@[ handler ]];
    alertView.delegate = delegate;
    [alertView show];
  }
}

@end
