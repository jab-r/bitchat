#import "MLSModule.h"
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>

// Import the Rust FFI header
#ifdef __cplusplus
extern "C" {
#endif

// Rust FFI functions
void* mls_client_create(void);
void mls_set_storage_path(const char *path_ptr);
void* mls_create_group(const void* client, const char* group_id, const char* creator_id);
void* mls_join_group(const void* client, const char* group_id, const char* receiver_id, const char* welcome_message);
void* mls_join_group_with_ratchet_tree(const void* client, const char* group_id, const char* receiver_id, const char* welcome_message, const char* ratchet_tree_b64);
uint8_t* mls_export_ratchet_tree(const void* client, const char* group_id, const char* user_id, int* out_len);
uint8_t* mls_add_member(const void* client, const char* group_id, const char* creator_id, const char* receiver_id, const char* key_package, int* out_len, uint8_t** out_welcome, int* out_welcome_len);
uint8_t* mls_encrypt_message(const void* client, const char* group_id, const char* creator_id, const char* message, int* out_len);
char* mls_decrypt_message(const void* client, const char* group_id, const char* creator_id, const uint8_t* encrypted_message, int encrypted_len);
char* mls_generate_key_package(const void* client, const char* identity);
uint8_t* mls_create_commit(const void* client, const char* group_id, const char* creator_id, const uint8_t** key_packages, const int* key_package_lens,
                          int key_package_count, const uint8_t** proposals, const int* proposal_lens,
                          int proposal_count, int* out_commit_len, uint8_t** out_welcome, int* out_welcome_len);
unsigned long mls_get_current_epoch(const void* client, const char* group_id, const char* user_id);
char** mls_generate_keypackages(const void* client, const char* identity, int count, int* out_count, int** out_lens);
int mls_add_keypackage(const void* client, const char* identity, const char* key_package);
// New storage FFI functions
void mls_set_storage_key(const char *user_id_ptr, const char *key_ptr);
void mls_set_storage_rekey(const char *user_id_ptr, const char *old_key_ptr, const char *new_key_ptr);
uint8_t* mls_add_members(const void* client, const char* group_id, const char* creator_id, const char** receiver_keypackages, int receiver_count, int** out_lens, int* out_count);
char* mls_export_secret(const void* client, const char* group_id, const char* creator_id, const char* label, const uint8_t* context, int context_len, unsigned int length);
char** mls_group_members(const void* client, const char* group_id, const char* user_id, int* out_len);

// New FFI functions
int mls_process_message(const void* client, const char* group_id, const char* user_id, const uint8_t* message_bytes, int message_len, int* out_type, uint8_t** out_content, int* out_content_len, uint8_t** out_sender, int* out_sender_len, int* out_validated);
int mls_accept_proposal(const void* client, const char* group_id, const char* user_id, const uint8_t* message_bytes, int message_len);
uint8_t* mls_create_add_proposal(const void* client, const char* group_id, const char* sender_id, const uint8_t* key_package_bytes, int key_package_len, int* out_len);
uint8_t* mls_create_remove_proposal(const void* client, const char* group_id, const char* creator_id, unsigned int member_index, int* out_len);
uint8_t* mls_remove_members(const void* client, const char* group_id, const char* creator_id, const int** member_indices, int member_count, int* out_count);
uint8_t* mls_self_update(const void* client, const char* group_id, const char* member_id, int* out_len, uint8_t** out_welcome, int* out_welcome_len);
uint8_t* mls_self_remove(const void* client, const char* group_id, const char* member_id, int* out_len);
uint8_t* mls_create_application_message(const void* client, const char* group_id, const char* user_id, const uint8_t* plaintext, int plaintext_len, int* out_len);
uint8_t* mls_commit_pending_proposals(const void* client, const char* group_id, const char* creator_id, int* out_len, uint8_t** out_welcome, int* out_welcome_len);

// Memory management functions
void mls_free_client(void* client);
void mls_free_string(char* ptr);
void mls_free_bytes(uint8_t* ptr);
void mls_free_group(void* group_handle);
void mls_free_string_array(char** ptr, int count);

// MLSProcessResult struct
typedef struct {
    uint32_t message_type;
    char* content;
    void* proposal;
    void* commit;
    uint64_t epoch;
} MLSProcessResult;

#ifdef __cplusplus
}
#endif

@implementation MLSModule

RCT_EXPORT_MODULE()

// Return a background queue for processing
- (dispatch_queue_t)methodQueue
{
    return dispatch_queue_create("com.reactnativemls.MLSQueue", DISPATCH_QUEUE_SERIAL);
}

// Export methods to JavaScript

 // Initialize the MLS module for macOS
 RCT_EXPORT_METHOD(initialize:(NSString *)groupID      
                   resolver:(RCTPromiseResolveBlock)resolve
                   rejecter:(RCTPromiseRejectBlock)reject)
 {
     // For macOS, use Application Support directory
     NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
     NSString *applicationSupportDirectory = [paths firstObject];
     
     if (!applicationSupportDirectory) {
         reject(@"init_error", @"Failed to get Application Support directory", nil);
         return;
     }
     
     // Create the "MLSStorage" folder inside Application Support
     NSString *storageDir = [applicationSupportDirectory stringByAppendingPathComponent:@"MLSStorage"];
     NSError *fsError = nil;
     [[NSFileManager defaultManager] createDirectoryAtPath:storageDir
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&fsError];
     if (fsError) {
         reject(@"init_error", @"Failed to create storage directory", fsError);
         return;
     }

     // Tell Rust to use this directory as its storage root
     mls_set_storage_path(storageDir.UTF8String);

     // Now create the MLS client
     void *client = mls_client_create();
     if (!client) {
         reject(@"init_error", @"mls_client_create() failed", nil);
         return;
     }
     self.mlsClient = client;
     resolve(nil);
 }

// Set storage key for a user
RCT_EXPORT_METHOD(setStorageKey:(NSString *)userId
                  key:(NSString *)key
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        const char *user_id_cstr = [userId UTF8String];
        const char *key_cstr = [key UTF8String];
        mls_set_storage_key(user_id_cstr, key_cstr);
        resolve(nil);
    } @catch (NSException *exception) {
        reject(@"set_storage_key_error", exception.reason, nil);
    }
}

// Rekey storage for a user
RCT_EXPORT_METHOD(setStorageRekey:(NSString *)userId
                  oldKey:(NSString *)oldKey
                  newKey:(NSString *)newKey
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    @try {
        const char *user_id_cstr = [userId UTF8String];
        const char *old_key_cstr = [oldKey UTF8String];
        const char *new_key_cstr = [newKey UTF8String];
        mls_set_storage_rekey(user_id_cstr, old_key_cstr, new_key_cstr);
        resolve(nil);
    } @catch (NSException *exception) {
        reject(@"set_storage_rekey_error", exception.reason, nil);
    }
}

- (void)dealloc
{
    // Free the client when the module is deallocated
    if (self.mlsClient) {
        mls_free_client(self.mlsClient);
        self.mlsClient = NULL;
    }
}

// Create a new MLS group
RCT_EXPORT_METHOD(createGroup:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        void* groupHandle = mls_create_group(self.mlsClient, groupIdStr, creatorIdStr);
        
        if (groupHandle != NULL) {
            // Free the group handle
            mls_free_group(groupHandle);
            
            // Return the group ID as a string
            resolver(groupId);
        } else {
            rejecter(@"E_MLS", @"Failed to create group", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Join an existing MLS group
RCT_EXPORT_METHOD(joinGroup:(NSString *)groupId
                  receiverId:(NSString *)receiverId
                  welcomeMessage:(NSString *)welcomeMessage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* receiverIdStr = [receiverId UTF8String];
        const char* welcomeMessageStr = [welcomeMessage UTF8String];
        
        void* groupHandle = mls_join_group(self.mlsClient, groupIdStr, receiverIdStr, welcomeMessageStr);
        
        if (groupHandle != NULL) {
            // Free the group handle
            mls_free_group(groupHandle);
            
            // Return the group ID as a string
            resolver(groupId);
        } else {
            rejecter(@"E_MLS", @"Failed to join group", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Join an existing MLS group with ratchet tree
RCT_EXPORT_METHOD(joinGroupWithRatchetTree:(NSString *)groupId
                  receiverId:(NSString *)receiverId
                  welcomeMessage:(NSString *)welcomeMessage
                  ratchetTree:(NSString *)ratchetTree
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* receiverIdStr = [receiverId UTF8String];
        const char* welcomeMessageStr = [welcomeMessage UTF8String];
        const char* ratchetTreeStr = [ratchetTree UTF8String];
        
        void* groupHandle = mls_join_group_with_ratchet_tree(self.mlsClient, groupIdStr, receiverIdStr, welcomeMessageStr, ratchetTreeStr);
        
        if (groupHandle != NULL) {
            // Free the group handle
            mls_free_group(groupHandle);
            
            // Return the group ID as a string
            resolver(groupId);
        } else {
            rejecter(@"E_MLS", @"Failed to join group with ratchet tree", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Export ratchet tree from a group
RCT_EXPORT_METHOD(exportRatchetTree:(NSString *)groupId
                  userId:(NSString *)userId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* userIdStr = [userId UTF8String];
        
        int out_len = 0;
        uint8_t* ratchetTreeBytes = mls_export_ratchet_tree(self.mlsClient, groupIdStr, userIdStr, &out_len);
        
        if (ratchetTreeBytes && out_len > 0) {
            NSData *data = [NSData dataWithBytes:ratchetTreeBytes length:out_len];
            NSString *base64String = [data base64EncodedStringWithOptions:0];
            
            // Free the bytes
            mls_free_bytes(ratchetTreeBytes);
            
            resolver(base64String);
        } else {
            rejecter(@"E_MLS", @"Failed to export ratchet tree", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Generate a key package
RCT_EXPORT_METHOD(generateKeyPackage:(NSString *)identity
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* identityStr = [identity UTF8String];
        char* keyPackage = mls_generate_key_package(self.mlsClient, identityStr);
        
        if (keyPackage) {
            NSString *keyPackageString = [NSString stringWithUTF8String:keyPackage];
            
            // Free the string
            mls_free_string(keyPackage);
            
            resolver(keyPackageString);
        } else {
            rejecter(@"E_MLS", @"Failed to generate key package", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Generate multiple key packages
RCT_EXPORT_METHOD(generateKeyPackages:(NSString *)identity
                  count:(NSInteger)count
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* identityStr = [identity UTF8String];
        int out_count = 0;
        int* out_lens = NULL;
        char** keyPackages = mls_generate_keypackages(self.mlsClient, identityStr, (int)count, &out_count, &out_lens);
        
        if (keyPackages && out_count > 0) {
            NSMutableArray *keyPackageArray = [NSMutableArray arrayWithCapacity:out_count];
            
            for (int i = 0; i < out_count; i++) {
                if (keyPackages[i]) {
                    NSString *keyPackageString = [NSString stringWithUTF8String:keyPackages[i]];
                    [keyPackageArray addObject:keyPackageString];
                }
            }
            
            // Free the string array
            mls_free_string_array(keyPackages, out_count);
            
            resolver(keyPackageArray);
        } else {
            rejecter(@"E_MLS", @"Failed to generate key packages", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Import a key package
RCT_EXPORT_METHOD(importKeyPackage:(NSString *)identity
                  keyPackage:(NSString *)keyPackage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* identityStr = [identity UTF8String];
        const char* keyPackageStr = [keyPackage UTF8String];
        
        int result = mls_add_keypackage(self.mlsClient, identityStr, keyPackageStr);
        
        if (result == 0) {
            resolver(@(YES));
        } else {
            rejecter(@"E_MLS", @"Failed to import key package", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Add a member to an MLS group
RCT_EXPORT_METHOD(addMember:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  receiverId:(NSString *)receiverId
                  keyPackage:(NSString *)keyPackage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        const char* receiverIdStr = [receiverId UTF8String];
        const char* keyPackageStr = [keyPackage UTF8String];
        
        int out_len = 0;
        uint8_t* out_welcome = NULL;
        int out_welcome_len = 0;
        
        uint8_t* commitBytes = mls_add_member(self.mlsClient, groupIdStr, creatorIdStr, receiverIdStr, keyPackageStr, &out_len, &out_welcome, &out_welcome_len);
        
        if (commitBytes && out_len > 0) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            
            // Add commit data
            NSData *commitData = [NSData dataWithBytes:commitBytes length:out_len];
            NSString *commitBase64 = [commitData base64EncodedStringWithOptions:0];
            result[@"commit"] = commitBase64;
            
            // Add welcome message if present
            if (out_welcome && out_welcome_len > 0) {
                NSData *welcomeData = [NSData dataWithBytes:out_welcome length:out_welcome_len];
                NSString *welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
                result[@"welcome"] = welcomeBase64;
                mls_free_bytes(out_welcome);
            }
            
            // Free the commit bytes
            mls_free_bytes(commitBytes);
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to add member", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Add multiple members to an MLS group
RCT_EXPORT_METHOD(addMembers:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  receiverKeyPackages:(NSArray *)receiverKeyPackages
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        
        // Convert NSArray to C array
        int receiver_count = (int)[receiverKeyPackages count];
        const char** receiver_keypackages = (const char**)malloc(receiver_count * sizeof(char*));
        
        for (int i = 0; i < receiver_count; i++) {
            NSString *keyPackage = receiverKeyPackages[i];
            receiver_keypackages[i] = [keyPackage UTF8String];
        }
        
        int* out_lens = NULL;
        int out_count = 0;
        
        uint8_t* result = mls_add_members(self.mlsClient, groupIdStr, creatorIdStr, receiver_keypackages, receiver_count, &out_lens, &out_count);
        
        free(receiver_keypackages);
        
        if (result && out_count > 0) {
            NSData *resultData = [NSData dataWithBytes:result length:out_lens[0]];
            NSString *resultBase64 = [resultData base64EncodedStringWithOptions:0];
            
            // Free the result
            mls_free_bytes(result);
            
            resolver(resultBase64);
        } else {
            rejecter(@"E_MLS", @"Failed to add members", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Remove members from an MLS group
RCT_EXPORT_METHOD(removeMembers:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  memberIndices:(NSArray *)memberIndices
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        
        // Convert NSArray to C array
        int member_count = (int)[memberIndices count];
        const int** member_indices = (const int**)malloc(member_count * sizeof(int*));
        int* indices = (int*)malloc(member_count * sizeof(int));
        
        for (int i = 0; i < member_count; i++) {
            indices[i] = [memberIndices[i] intValue];
            member_indices[i] = &indices[i];
        }
        
        int out_count = 0;
        uint8_t* result = mls_remove_members(self.mlsClient, groupIdStr, creatorIdStr, member_indices, member_count, &out_count);
        
        free(member_indices);
        free(indices);
        
        if (result && out_count > 0) {
            NSData *resultData = [NSData dataWithBytes:result length:out_count];
            NSString *resultBase64 = [resultData base64EncodedStringWithOptions:0];
            
            // Free the result
            mls_free_bytes(result);
            
            resolver(resultBase64);
        } else {
            rejecter(@"E_MLS", @"Failed to remove members", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Commit pending proposals in an MLS group
RCT_EXPORT_METHOD(commitPendingProposals:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        
        int out_len = 0;
        uint8_t* out_welcome = NULL;
        int out_welcome_len = 0;
        
        uint8_t* commitBytes = mls_commit_pending_proposals(self.mlsClient, groupIdStr, creatorIdStr, &out_len, &out_welcome, &out_welcome_len);
        
        if (commitBytes && out_len > 0) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            
            // Add commit data
            NSData *commitData = [NSData dataWithBytes:commitBytes length:out_len];
            NSString *commitBase64 = [commitData base64EncodedStringWithOptions:0];
            result[@"commit"] = commitBase64;
            
            // Add welcome message if present
            if (out_welcome && out_welcome_len > 0) {
                NSData *welcomeData = [NSData dataWithBytes:out_welcome length:out_welcome_len];
                NSString *welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
                result[@"welcome"] = welcomeBase64;
                mls_free_bytes(out_welcome);
            }
            
            // Free the commit bytes
            mls_free_bytes(commitBytes);
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to commit pending proposals", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Export a secret from an MLS group
RCT_EXPORT_METHOD(exportSecret:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  label:(NSString *)label
                  context:(NSData *)context
                  length:(NSInteger)length
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        const char* labelStr = [label UTF8String];
        
        const uint8_t* contextBytes = context ? (const uint8_t*)[context bytes] : NULL;
        int contextLen = context ? (int)[context length] : 0;
        
        char* secret = mls_export_secret(self.mlsClient, groupIdStr, creatorIdStr, labelStr, contextBytes, contextLen, (unsigned int)length);
        
        if (secret) {
            NSString *secretString = [NSString stringWithUTF8String:secret];
            
            // Free the string
            mls_free_string(secret);
            
            resolver(secretString);
        } else {
            rejecter(@"E_MLS", @"Failed to export secret", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Encrypt a message
RCT_EXPORT_METHOD(encryptMessage:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  message:(NSString *)message
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        const char* messageStr = [message UTF8String];
        
        int out_len = 0;
        uint8_t* encryptedBytes = mls_encrypt_message(self.mlsClient, groupIdStr, creatorIdStr, messageStr, &out_len);
        
        if (encryptedBytes && out_len > 0) {
            NSData *encryptedData = [NSData dataWithBytes:encryptedBytes length:out_len];
            NSString *encryptedBase64 = [encryptedData base64EncodedStringWithOptions:0];
            
            // Free the bytes
            mls_free_bytes(encryptedBytes);
            
            resolver(encryptedBase64);
        } else {
            rejecter(@"E_MLS", @"Failed to encrypt message", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Decrypt a message
RCT_EXPORT_METHOD(decryptMessage:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  encryptedMessage:(NSString *)encryptedMessage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        
        // Decrypt a message
        
        // Convert the base64 string to bytes
        NSData* encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedMessage options:0];
        
        if (encryptedData != nil) {
            const uint8_t* encryptedBytes = (const uint8_t*)[encryptedData bytes];
            int encryptedLen = (int)[encryptedData length];
            
            char* decryptedStr = mls_decrypt_message(self.mlsClient, groupIdStr, creatorIdStr, encryptedBytes, encryptedLen);
            
            if (decryptedStr != NULL) {
                NSString* decryptedMessage = [NSString stringWithUTF8String:decryptedStr];
                
                // Free the decrypted string
                mls_free_string(decryptedStr);
                
                resolver(decryptedMessage);
            } else {
                rejecter(@"E_MLS", @"Failed to decrypt message", nil);
            }
        } else {
            rejecter(@"E_MLS", @"Invalid encrypted message format", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Create a commit
RCT_EXPORT_METHOD(createCommit:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  keyPackages:(NSArray *)keyPackages
                  proposals:(NSArray *)proposals
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        
        // Convert the key packages to byte arrays
        NSMutableArray* keyPackageDataArray = [NSMutableArray arrayWithCapacity:[keyPackages count]];
        const uint8_t** keyPackagePtrsArray = (const uint8_t**)malloc(sizeof(uint8_t*) * [keyPackages count]);
        int* keyPackageLensArray = (int*)malloc(sizeof(int) * [keyPackages count]);
        
        for (int i = 0; i < [keyPackages count]; i++) {
            NSString* keyPackage = keyPackages[i];
            NSData* data = [[NSData alloc] initWithBase64EncodedString:keyPackage options:0];
            [keyPackageDataArray addObject:data];
            keyPackagePtrsArray[i] = (const uint8_t*)[data bytes];
            keyPackageLensArray[i] = (int)[data length];
        }
        
        // Convert the proposals to byte arrays
        NSMutableArray* proposalDataArray = [NSMutableArray arrayWithCapacity:[proposals count]];
        const uint8_t** proposalPtrsArray = (const uint8_t**)malloc(sizeof(uint8_t*) * [proposals count]);
        int* proposalLensArray = (int*)malloc(sizeof(int) * [proposals count]);
        
        for (int i = 0; i < [proposals count]; i++) {
            NSDictionary* proposal = proposals[i];
            NSString* proposalData = proposal[@"data"];
            NSData* data = [[NSData alloc] initWithBase64EncodedString:proposalData options:0];
            [proposalDataArray addObject:data];
            proposalPtrsArray[i] = (const uint8_t*)[data bytes];
            proposalLensArray[i] = (int)[data length];
        }
        
        int out_commit_len = 0;
        uint8_t* out_welcome = NULL;
        int out_welcome_len = 0;
        
        uint8_t* commitBytes = mls_create_commit(self.mlsClient, groupIdStr, creatorIdStr, 
                                               keyPackagePtrsArray, keyPackageLensArray, (int)[keyPackages count],
                                               proposalPtrsArray, proposalLensArray, (int)[proposals count],
                                               &out_commit_len, &out_welcome, &out_welcome_len);
        
        free(keyPackagePtrsArray);
        free(keyPackageLensArray);
        free(proposalPtrsArray);
        free(proposalLensArray);
        
        if (commitBytes && out_commit_len > 0) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            
            // Add commit data
            NSData *commitData = [NSData dataWithBytes:commitBytes length:out_commit_len];
            NSString *commitBase64 = [commitData base64EncodedStringWithOptions:0];
            result[@"commit"] = commitBase64;
            
            // Add welcome message if present
            if (out_welcome && out_welcome_len > 0) {
                NSData *welcomeData = [NSData dataWithBytes:out_welcome length:out_welcome_len];
                NSString *welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
                result[@"welcome"] = welcomeBase64;
                mls_free_bytes(out_welcome);
            }
            
            // Free the commit bytes
            mls_free_bytes(commitBytes);
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to create commit", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Get current epoch
RCT_EXPORT_METHOD(getCurrentEpoch:(NSString *)groupId
                  userId:(NSString *)userId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* userIdStr = [userId UTF8String];
        
        unsigned long epoch = mls_get_current_epoch(self.mlsClient, groupIdStr, userIdStr);
        
        resolver(@(epoch));
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Process an MLS message
RCT_EXPORT_METHOD(processMessage:(NSString *)groupId
                  userId:(NSString *)userId
                  encryptedMessage:(NSString *)encryptedMessage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* userIdStr = [userId UTF8String];
        
        // Convert the base64 string to bytes
        NSData* messageData = [[NSData alloc] initWithBase64EncodedString:encryptedMessage options:0];
        
        if (messageData != nil) {
            const uint8_t* messageBytes = (const uint8_t*)[messageData bytes];
            int messageLen = (int)[messageData length];
            
            int out_type = 0;
            uint8_t* out_content = NULL;
            int out_content_len = 0;
            uint8_t* out_sender = NULL;
            int out_sender_len = 0;
            int out_validated = 0;
            
            int result = mls_process_message(self.mlsClient, groupIdStr, userIdStr, messageBytes, messageLen,
                                           &out_type, &out_content, &out_content_len, &out_sender, &out_sender_len, &out_validated);
            
            if (result == 0) {
                NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
                resultDict[@"messageType"] = @(out_type);
                resultDict[@"validated"] = @(out_validated == 1);
                
                if (out_content && out_content_len > 0) {
                    NSData *contentData = [NSData dataWithBytes:out_content length:out_content_len];
                    NSString *contentBase64 = [contentData base64EncodedStringWithOptions:0];
                    resultDict[@"content"] = contentBase64;
                    mls_free_bytes(out_content);
                }
                
                if (out_sender && out_sender_len > 0) {
                    NSData *senderData = [NSData dataWithBytes:out_sender length:out_sender_len];
                    NSString *senderBase64 = [senderData base64EncodedStringWithOptions:0];
                    resultDict[@"sender"] = senderBase64;
                    mls_free_bytes(out_sender);
                }
                
                resolver(resultDict);
            } else {
                rejecter(@"E_MLS", @"Failed to process message", nil);
            }
        } else {
            rejecter(@"E_MLS", @"Invalid message format", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Accept a proposal
RCT_EXPORT_METHOD(acceptProposal:(NSString *)groupId
                  userId:(NSString *)userId
                  message:(NSString *)message
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* userIdStr = [userId UTF8String];
        
        // Convert the base64 string to bytes
        NSData* messageData = [[NSData alloc] initWithBase64EncodedString:message options:0];
        
        if (messageData != nil) {
            const uint8_t* messageBytes = (const uint8_t*)[messageData bytes];
            int messageLen = (int)[messageData length];
            
            int result = mls_accept_proposal(self.mlsClient, groupIdStr, userIdStr, messageBytes, messageLen);
            
            if (result == 0) {
                resolver(@(YES));
            } else {
                rejecter(@"E_MLS", @"Failed to accept proposal", nil);
            }
        } else {
            rejecter(@"E_MLS", @"Invalid message format", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Create a proposal to add a member to a group
RCT_EXPORT_METHOD(createAddProposal:(NSString *)groupId
                  senderId:(NSString *)senderId
                  keyPackage:(NSString *)keyPackage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* senderIdStr = [senderId UTF8String];
        
        // Convert the base64 string to bytes
        NSData* keyPackageData = [[NSData alloc] initWithBase64EncodedString:keyPackage options:0];
        
        if (keyPackageData != nil) {
            const uint8_t* keyPackageBytes = (const uint8_t*)[keyPackageData bytes];
            int keyPackageLen = (int)[keyPackageData length];
            
            int out_len = 0;
            uint8_t* proposalBytes = mls_create_add_proposal(self.mlsClient, groupIdStr, senderIdStr, keyPackageBytes, keyPackageLen, &out_len);
            
            if (proposalBytes && out_len > 0) {
                NSData *proposalData = [NSData dataWithBytes:proposalBytes length:out_len];
                NSString *proposalBase64 = [proposalData base64EncodedStringWithOptions:0];
                
                // Free the bytes
                mls_free_bytes(proposalBytes);
                
                resolver(proposalBase64);
            } else {
                rejecter(@"E_MLS", @"Failed to create add proposal", nil);
            }
        } else {
            rejecter(@"E_MLS", @"Invalid key package format", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Create a proposal to remove a member from a group
RCT_EXPORT_METHOD(createRemoveProposal:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  memberIndex:(NSInteger)memberIndex
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        
        int out_len = 0;
        uint8_t* proposalBytes = mls_create_remove_proposal(self.mlsClient, groupIdStr, creatorIdStr, (unsigned int)memberIndex, &out_len);
        
        if (proposalBytes && out_len > 0) {
            NSData *proposalData = [NSData dataWithBytes:proposalBytes length:out_len];
            NSString *proposalBase64 = [proposalData base64EncodedStringWithOptions:0];
            
            // Free the bytes
            mls_free_bytes(proposalBytes);
            
            resolver(proposalBase64);
        } else {
            rejecter(@"E_MLS", @"Failed to create remove proposal", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Update the key for the current member in an MLS group
RCT_EXPORT_METHOD(selfUpdate:(NSString *)groupId
                  memberId:(NSString *)memberId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* memberIdStr = [memberId UTF8String];
        
        int out_len = 0;
        uint8_t* out_welcome = NULL;
        int out_welcome_len = 0;
        
        uint8_t* updateBytes = mls_self_update(self.mlsClient, groupIdStr, memberIdStr, &out_len, &out_welcome, &out_welcome_len);
        
        if (updateBytes && out_len > 0) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            
            // Add update data
            NSData *updateData = [NSData dataWithBytes:updateBytes length:out_len];
            NSString *updateBase64 = [updateData base64EncodedStringWithOptions:0];
            result[@"update"] = updateBase64;
            
            // Add welcome message if present
            if (out_welcome && out_welcome_len > 0) {
                NSData *welcomeData = [NSData dataWithBytes:out_welcome length:out_welcome_len];
                NSString *welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
                result[@"welcome"] = welcomeBase64;
                mls_free_bytes(out_welcome);
            }
            
            // Free the update bytes
            mls_free_bytes(updateBytes);
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to perform self update", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Remove self from an MLS group
RCT_EXPORT_METHOD(selfRemove:(NSString *)groupId
                  memberId:(NSString *)memberId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* memberIdStr = [memberId UTF8String];
        
        int out_len = 0;
        uint8_t* removeBytes = mls_self_remove(self.mlsClient, groupIdStr, memberIdStr, &out_len);
        
        if (removeBytes && out_len > 0) {
            NSData *removeData = [NSData dataWithBytes:removeBytes length:out_len];
            NSString *removeBase64 = [removeData base64EncodedStringWithOptions:0];
            
            // Free the bytes
            mls_free_bytes(removeBytes);
            
            resolver(removeBase64);
        } else {
            rejecter(@"E_MLS", @"Failed to perform self remove", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Create an application message for an MLS group
RCT_EXPORT_METHOD(createApplicationMessage:(NSString *)groupId
                  userId:(NSString *)userId
                  message:(NSString *)message
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* userIdStr = [userId UTF8String];
        
        // Convert the message to bytes
        NSData* messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t* messageBytes = (const uint8_t*)[messageData bytes];
        int messageLen = (int)[messageData length];
        
        int out_len = 0;
        uint8_t* appMessageBytes = mls_create_application_message(self.mlsClient, groupIdStr, userIdStr, messageBytes, messageLen, &out_len);
        
        if (appMessageBytes && out_len > 0) {
            NSData *appMessageData = [NSData dataWithBytes:appMessageBytes length:out_len];
            NSString *appMessageBase64 = [appMessageData base64EncodedStringWithOptions:0];
            
            // Free the bytes
            mls_free_bytes(appMessageBytes);
            
            resolver(appMessageBase64);
        } else {
            rejecter(@"E_MLS", @"Failed to create application message", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Get group members
RCT_EXPORT_METHOD(groupMembers:(NSString *)groupId
                  userId:(NSString *)userId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    @try {
        if (!self.mlsClient) {
            rejecter(@"E_MLS", @"MLS client not initialized", nil);
            return;
        }
        
        const char* groupIdStr = [groupId UTF8String];
        const char* userIdStr = [userId UTF8String];
        
        int out_len = 0;
        char** members = mls_group_members(self.mlsClient, groupIdStr, userIdStr, &out_len);
        
        if (members && out_len > 0) {
            NSMutableArray *memberArray = [NSMutableArray arrayWithCapacity:out_len];
            
            for (int i = 0; i < out_len; i++) {
                if (members[i]) {
                    NSString *memberString = [NSString stringWithUTF8String:members[i]];
                    [memberArray addObject:memberString];
                }
            }
            
            // Free the string array
            mls_free_string_array(members, out_len);
            
            resolver(memberArray);
        } else {
            rejecter(@"E_MLS", @"Failed to get group members", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

@end