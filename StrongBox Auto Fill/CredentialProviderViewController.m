//
//  CredentialProviderViewController.m
//  Strongbox Auto Fill
//
//  Created by Mark on 11/10/2018.
//  Copyright © 2018 Mark McGuill. All rights reserved.
//

#import "CredentialProviderViewController.h"
#import "SafesList.h"
#import "NSArray+Extensions.h"
#import "SafesListTableViewController.h"
#import "Settings.h"
#import "iCloudSafesCoordinator.h"
#import "Alerts.h"
#import "mach/mach.h"
#import "QuickTypeRecordIdentifier.h"
#import "OTPToken+Generation.h"
#import "Utils.h"
#import "OpenSafeSequenceHelper.h"
#import "AutoFillManager.h"

#import "LocalDeviceStorageProvider.h"

#import "ClipboardManager.h"

@interface CredentialProviderViewController () <UIAdaptivePresentationControllerDelegate>

@property (nonatomic, strong) UINavigationController* databasesListNavController;
@property (nonatomic, strong) NSArray<ASCredentialServiceIdentifier *> * serviceIdentifiers;

@property BOOL quickTypeMode;

@end

@implementation CredentialProviderViewController

+ (void)initialize {
    if(self == [CredentialProviderViewController class]) {
        [iCloudSafesCoordinator.sharedInstance initializeiCloudAccessWithCompletion:^(BOOL available) {
            NSLog(@"iCloud Access Initialized...");
        }];
    }
}

// QuickType Support...

-(void)provideCredentialWithoutUserInteractionForIdentity:(ASPasswordCredentialIdentity *)credentialIdentity {
    NSLog(@"provideCredentialWithoutUserInteractionForIdentity: [%@]", credentialIdentity);
    [self exitWithUserInteractionRequired];
}

- (void)prepareInterfaceToProvideCredentialForIdentity:(ASPasswordCredentialIdentity *)credentialIdentity {
    BOOL lastRunGood = [self enterWithLastCrashCheck:YES];

    if (!lastRunGood) {
        [self showLastRunCrashedMessage:^{
            [self initializeQuickType:credentialIdentity];
        }];
    }
    else {
        [self initializeQuickType:credentialIdentity];
    }
}

- (void)initializeQuickType:(ASPasswordCredentialIdentity *)credentialIdentity {
    QuickTypeRecordIdentifier* identifier = [QuickTypeRecordIdentifier fromJson:credentialIdentity.recordIdentifier];
    NSLog(@"prepareInterfaceToProvideCredentialForIdentity: [%@] => Found: [%@]", credentialIdentity, identifier);
    
    if(identifier) {
        SafeMetaData* safe = [SafesList.sharedInstance.snapshot firstOrDefault:^BOOL(SafeMetaData * _Nonnull obj) {
            return [obj.uuid isEqualToString:identifier.databaseId];
        }];
        
        if(safe) {
            // Delay a litte to avoid UI Weirdness glitch
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                BOOL useAutoFillCache = ![self liveAutoFillIsPossibleWithSafe:safe];

                Settings.sharedInstance.autoFillExitedCleanly = NO; // Crash will mean this stays at no
                [OpenSafeSequenceHelper beginSequenceWithViewController:self
                                                                   safe:safe
                                                      openAutoFillCache:useAutoFillCache
                                                    canConvenienceEnrol:NO
                                                         isAutoFillOpen:YES
                                                 manualOpenOfflineCache:NO
                                            biometricAuthenticationDone:NO
                                                             completion:^(Model * _Nullable model, NSError * _Nullable error) {
                    Settings.sharedInstance.autoFillExitedCleanly = YES;

                                                                 NSLog(@"AutoFill: Open Database: Model=[%@] - Error = [%@]", model, error);
                    if(model) {
                        [self onOpenedQuickType:model identifier:identifier];
                    }
                    else if(error == nil) {
                        [self cancel:nil]; // User cancelled
                    }
                    else {
                        [Alerts error:self
                                title:NSLocalizedString(@"cred_vc_error_opening_title", @"Strongbox: Error Opening Database")
                                error:error
                           completion:^{
                            [self exitWithErrorOccurred:error ? error : [Utils createNSError:@"Could not open database" errorCode:-1]];
                        }];
                    }
                }];
            });
        }
        else {
            [AutoFillManager.sharedInstance clearAutoFillQuickTypeDatabase];
            
            [Alerts info:self
                   title:@"Strongbox: Unknown Database"
                 message:@"This appears to be a reference to an older Strongbox database which can no longer be found. Strongbox's QuickType AutoFill database has now been cleared, and so you will need to reopen your databases to refresh QuickType AutoFill."
              completion:^{
                [self exitWithErrorOccurred:[Utils createNSError:@"Could not find this database in Strongbox any longer." errorCode:-1]];
            }];
        }
    }
    else {
        [AutoFillManager.sharedInstance clearAutoFillQuickTypeDatabase];
        
        [Alerts info:self
               title:@"Strongbox: Error Locating Entry"
             message:@"Strongbox could not find this entry, it is possibly stale. Strongbox's QuickType AutoFill database has now been cleared, and so you will need to reopen your databases to refresh QuickType AutoFill." completion:^{
            
            [self exitWithErrorOccurred:[Utils createNSError:@"Could not find this record in Strongbox any longer." errorCode:-1]];
        }];
    }
}

- (void)onOpenedQuickType:(Model*)model identifier:(QuickTypeRecordIdentifier*)identifier {
    Node* node = [model.database.rootGroup.allChildRecords firstOrDefault:^BOOL(Node * _Nonnull obj) {
        return [obj.uuid.UUIDString isEqualToString:identifier.nodeId]; // PERF
    }];
    
    if(node) {
        NSString* user = [model.database dereference:node.fields.username node:node];
        NSString* password = [model.database dereference:node.fields.password node:node];
        
        //NSLog(@"Return User/Pass from Node: [%@] - [%@] [%@]", user, password, node);

        // Copy TOTP code if configured to do so...
        
        if(node.fields.otpToken) {
            NSString* value = node.fields.otpToken.password;
            if (value.length) {
                [ClipboardManager.sharedInstance copyStringWithDefaultExpiration:value];
                NSLog(@"Copied TOTP to Pasteboard...");
            }
        }
        
        [self exitWithCredential:user password:password];
    }
    else {
        [AutoFillManager.sharedInstance clearAutoFillQuickTypeDatabase];
        
        [Alerts info:self title:@"Strongbox: Error Locating This Record"
             message:@"Strongbox could not find this record in the database any longer. It is possibly stale. Strongbox's QuickType AutoFill database has now been cleared, and so you will need to reopen your databases to refresh QuickType AutoFill."
          completion:^{
            [self exitWithErrorOccurred:[Utils createNSError:@"Could not find record in database" errorCode:-1]];
        }];
    }
}

- (void)prepareCredentialListForServiceIdentifiers:(NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers {
    NSLog(@"prepareCredentialListForServiceIdentifiers = %@", serviceIdentifiers);
    self.serviceIdentifiers = serviceIdentifiers;
    
    BOOL lastRunGood = [self enterWithLastCrashCheck:NO];

    UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName:@"MainInterface" bundle:nil];
    self.databasesListNavController = [mainStoryboard instantiateViewControllerWithIdentifier:@"SafesListNavigationController"];
    SafesListTableViewController* databasesList = ((SafesListTableViewController*)(self.databasesListNavController.topViewController));
    
    databasesList.rootViewController = self;
    databasesList.lastRunGood = lastRunGood;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if(!self.quickTypeMode) {
        [self showSafesListView];
    }
}

- (void)showSafesListView {
    if(self.presentedViewController) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
    
    if(!self.databasesListNavController) {
        [Alerts warn:self title:@"Error" message:@"There was an error loading the Safes List View. Please mail support@strongboxsafe.com to inform the developer." completion:^{
            [self exitWithErrorOccurred:[Utils createNSError:@"There was an error loading the Safes List View" errorCode:-1]];
        }];
    }
    else {
        SafesListTableViewController* databasesList = ((SafesListTableViewController*)(self.databasesListNavController.topViewController));

        self.databasesListNavController.presentationController.delegate = self;

        if(!databasesList.lastRunGood) {
            [self showLastRunCrashedMessage:^{
                [self presentViewController:self.databasesListNavController animated:NO completion:nil];
            }];
        }
        else {
            [self presentViewController:self.databasesListNavController animated:NO completion:nil];
        }
    }
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    NSLog(@"presentationControllerDidDismiss");
    [self cancel:nil];
}

- (BOOL)isLiveAutoFillProvider:(StorageProvider)storageProvider {
    return  storageProvider == kFilesAppUrlBookmark ||
            storageProvider == kiCloud ||
            storageProvider == kWebDAV ||
            storageProvider == kSFTP;
}

- (BOOL)liveAutoFillIsPossibleWithSafe:(SafeMetaData*)safeMetaData {
    if(!safeMetaData.autoFillEnabled || safeMetaData.alwaysUseCacheForAutoFill) {
        return NO;
    }
    
    if([self isLiveAutoFillProvider:safeMetaData.storageProvider]) {
        return YES;
    }
    
    if(safeMetaData.storageProvider == kLocalDevice) {
        return [LocalDeviceStorageProvider.sharedInstance isUsingSharedStorage:safeMetaData];
    }
    
    return NO;
}

- (BOOL)autoFillIsPossibleWithSafe:(SafeMetaData*)safeMetaData {
    if(!safeMetaData.autoFillEnabled) {
        return NO;
    }
    
    if([self isLiveAutoFillProvider:safeMetaData.storageProvider] && !safeMetaData.alwaysUseCacheForAutoFill) {
        return YES;
    }
    
    if(safeMetaData.storageProvider == kLocalDevice && [LocalDeviceStorageProvider.sharedInstance isUsingSharedStorage:safeMetaData]) {
        return YES;
    }
    
    return safeMetaData.autoFillCacheAvailable;
}

- (NSArray<ASCredentialServiceIdentifier *> *)getCredentialServiceIdentifiers {
    return self.serviceIdentifiers;
}

void showWelcomeMessageIfAppropriate(UIViewController *vc) { 
    if(!Settings.sharedInstance.hasShownAutoFillLaunchWelcome) {
        Settings.sharedInstance.hasShownAutoFillLaunchWelcome = YES;
        
        [Alerts info:vc
               title:NSLocalizedString(@"auto_fill_welcome_message_header", @"Welcome")
             message:NSLocalizedString(@"auto_fill_welcome_live_storage_warning_message", @"It should be noted that the following storage providers do not support live access to your database from App Extensions:" \
         "\nDropbox, OneDrive & Google Drive\n"\
         "In these cases, Strongbox can use a cache... Enjoy Strongbox Auto Fill!\n-Mark")];
    }
}

- (IBAction)cancel:(id)sender {
    [self exitWithUserCancelled];
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// All Entry/Exits through these 4 points...

- (BOOL)enterWithLastCrashCheck:(BOOL)quickType {
    NSLog(@"Auto-Fill Entered - Quick Type Mode = [%d]", quickType);
    
    self.quickTypeMode = quickType;
    
    BOOL lastRunGood = Settings.sharedInstance.autoFillExitedCleanly;
    
    // MMcG: Don't do this here as iOS can and does regularly terminate the extension without notice
    // in normal situations. Only do this immediately before Database Open/Unlock
    //
    //    Settings.sharedInstance.autoFillExitedCleanly = NO; // Crash will mean this stays at no

    if(!lastRunGood) {
        NSLog(@"Last run of Auto Fill did not exit cleanly! Warn User that a crash occurred...");
    }
    
    return lastRunGood;
}

- (void)showLastRunCrashedMessage:(void (^)(void))completion {
    NSString* title = NSLocalizedString(@"autofill_did_not_close_cleanly_title", @"Auto Fill Crash Occurred");
    NSString* message = NSLocalizedString(@"autofill_did_not_close_cleanly_message", @"It looks like the last time you used Auto Fill you had a crash. This is usually due to a memory limitation. Please check your database file size and your Argon2 memory settings (should be <= 64MB).");

    [Alerts info:self title:title message:message completion:completion];
}

- (void)exitWithUserCancelled {
    NSLog(@"EXIT: User Cancelled");
    Settings.sharedInstance.autoFillExitedCleanly = YES;
    
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain code:ASExtensionErrorCodeUserCanceled userInfo:nil]];
}

- (void)exitWithUserInteractionRequired {
    NSLog(@"EXIT: User Interaction Required");
    [self.extensionContext cancelRequestWithError:[NSError errorWithDomain:ASExtensionErrorDomain
                                                                      code:ASExtensionErrorCodeUserInteractionRequired
                                                                  userInfo:nil]];
}

- (void)exitWithErrorOccurred:(NSError*)error {
    NSLog(@"EXIT: Error Occured [%@]", error);
    Settings.sharedInstance.autoFillExitedCleanly = YES; // Still a clean exit - no crash
    
    [self.extensionContext cancelRequestWithError:error];
}

- (void)exitWithCredential:(NSString*)username password:(NSString*)password {
    NSLog(@"EXIT: Success");
    Settings.sharedInstance.autoFillExitedCleanly = YES;
    
    ASPasswordCredential *credential = [[ASPasswordCredential alloc] initWithUser:username password:password];
    [self.extensionContext completeRequestWithSelectedCredential:credential completionHandler:nil];
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//- (void)didReceiveMemoryWarning {
//    NSLog(@"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");
//    NSLog(@"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");
//    NSLog(@"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX MEMORY WARNING RECEIVED: %f XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX", [self __getMemoryUsedPer1]);
//    NSLog(@"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");
//    NSLog(@"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");
//}
//
//- (float)__getMemoryUsedPer1
//{
//    struct mach_task_basic_info info;
//    mach_msg_type_number_t size = sizeof(info);
//    kern_return_t kerr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &size);
//    if (kerr == KERN_SUCCESS)
//    {
//        float used_bytes = info.resident_size;
//        float total_bytes = [NSProcessInfo processInfo].physicalMemory;
//        //NSLog(@"Used: %f MB out of %f MB (%f%%)", used_bytes / 1024.0f / 1024.0f, total_bytes / 1024.0f / 1024.0f, used_bytes * 100.0f / total_bytes);
//        return used_bytes / total_bytes;
//    }
//    return 1;
//}

@end
