//
//  NodeFields.h
//  MacBox
//
//  Created by Mark on 31/08/2017.
//  Copyright © 2017 Mark McGuill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PasswordHistory.h"
#import "NodeFileAttachment.h"
#import "StringValue.h"
#import "OTPToken.h"
#import "SerializationPackage.h"

@class Node;

NS_ASSUME_NONNULL_BEGIN

@interface NodeFields : NSObject

- (instancetype _Nullable)init;

- (instancetype _Nullable)initWithUsername:(NSString*_Nonnull)username
                                       url:(NSString*_Nonnull)url
                                  password:(NSString*_Nonnull)password
                                     notes:(NSString*_Nonnull)notes
                                     email:(NSString*_Nonnull)email NS_DESIGNATED_INITIALIZER;

@property (nonatomic, strong, nonnull) NSString *password;
@property (nonatomic, strong, nonnull) NSString *username;
@property (nonatomic, strong, nonnull) NSString *email;
@property (nonatomic, strong, nonnull) NSString *url;
@property (nonatomic, strong, nonnull) NSString *notes;
@property (nonatomic, strong, nullable) NSDate *created;
@property (nonatomic, strong, nullable) NSDate *modified;
@property (nonatomic, strong, nullable) NSDate *accessed;
@property (nonatomic, strong, nullable) NSDate *passwordModified;
@property (nonatomic, strong, nullable) NSDate *expires;
@property (nonatomic, strong, nullable) NSDate *locationChanged;
@property (nonatomic, strong, nullable, readonly) NSNumber *usageCount;

@property (nonatomic, strong, nonnull) NSMutableArray<NodeFileAttachment*> *attachments;
@property (nonatomic, retain, nonnull) PasswordHistory *passwordHistory; // Password Safe History
@property NSMutableArray<Node*> *keePassHistory;

+ (BOOL)isTotpCustomFieldKey:(NSString*)key;

+ (NodeFields *)deserialize:(NSDictionary *)dict;
- (NSDictionary*)serialize:(SerializationPackage*)serialization;

- (NodeFields*)cloneOrDuplicate:(BOOL)clearHistory cloneMetadataDates:(BOOL)cloneMetadataDates;

- (NSMutableArray<NodeFileAttachment*>*)cloneAttachments;
- (NSMutableDictionary<NSString*, StringValue*>*)cloneCustomFields;

// Custom Fields

@property (nonatomic, strong, nonnull) NSDictionary<NSString*, StringValue*> *customFields;
- (void)removeAllCustomFields;
- (void)removeCustomField:(NSString*)key;
- (void)setCustomField:(NSString*)key value:(StringValue*)value;

- (void)touch:(BOOL)modified;
- (void)touchWithExplicitModifiedDate:(NSDate*)modDate; // largely designed for undo...

- (void)setTouchProperties:(NSDate*_Nullable)accessed modified:(NSDate*_Nullable)modified usageCount:(NSNumber*_Nullable)usageCount;

///////////////////////////////////////////////
// TOTP

@property (nonatomic, readonly) OTPToken* otpToken;

+ (nullable OTPToken*)getOtpTokenFromRecord:(NSString*)password fields:(NSDictionary*)fields notes:(NSString*)notes; // Unit Testing

+ (OTPToken*_Nullable)getOtpTokenFromString:(NSString *)string
                                 forceSteam:(BOOL)forceSteam
                                     issuer:(NSString*)issuer
                                   username:(NSString*)username;

- (void)setTotp:(OTPToken*)token appendUrlToNotes:(BOOL)appendUrlToNotes;

- (void)clearTotp;

//

@property (readonly) BOOL expired;
@property (readonly) BOOL nearlyExpired;

// Alternative URLs - Just a view on Custom Fields with Keys matching (KP2A_URL[_*])

@property (readonly) NSArray<NSString*> *alternativeUrls;

@end

NS_ASSUME_NONNULL_END
