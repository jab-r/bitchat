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

 // Initialize the MLS module
 RCT_EXPORT_METHOD(initialize:(NSString *)groupID      
                   resolver:(RCTPromiseResolveBlock)resolve
                   rejecter:(RCTPromiseRejectBlock)reject)
 {
     // 1. Grab the App-Group container
     NSURL *container = [[NSFileManager defaultManager]
         containerURLForSecurityApplicationGroupIdentifier:groupID];
     if (!container) {
         NSString *homeDir = NSHomeDirectory();
         container = [NSURL fileURLWithPath:homeDir];
     }
 
     
    // 2. Create the “MLSStorage” folder inside it
    NSURL *storageDir = [container URLByAppendingPathComponent:@"MLSStorage"];
    NSError *fsError = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:storageDir
                            withIntermediateDirectories:YES
                                                attributes:nil
                                                    error:&fsError];
    if (fsError) {
        reject(@"init_error", @"Failed to create storage directory", fsError);
        return;
    }

    // 3. Tell Rust to use this directory as its storage root
    //    Your Rust sqlstorageprovider will then do:
    //      open “<storageDir>/<identity>.sqlite”
    mls_set_storage_path(storageDir.path.UTF8String);

    // 4. Now create the MLS client
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
        
        // Note: The Rust FFI function expects base64 encoded strings and will decode them,
        // so we pass the strings directly without additional encoding/decoding
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
        
        // Note: The Rust FFI function expects base64 encoded strings and will decode them,
        // so we pass the strings directly without additional encoding/decoding
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

// Export ratchet tree
RCT_EXPORT_METHOD(exportRatchetTree:(NSString *)groupId
                   userId:(NSString *)userId
                   resolver:(RCTPromiseResolveBlock)resolver
                   rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* userIdStr = [userId UTF8String];
    
    int treeLen = 0;
    uint8_t* treeBytes = mls_export_ratchet_tree(self.mlsClient, groupIdStr, userIdStr, &treeLen);
    
    if (treeBytes != NULL) {
        // Convert the tree bytes to a base64 string
        NSData* treeData = [NSData dataWithBytes:treeBytes length:treeLen];
        NSString* treeBase64 = [treeData base64EncodedStringWithOptions:0];
        
        // Free the tree bytes
        mls_free_bytes(treeBytes);
        
        resolver(treeBase64);
    } else {
        rejecter(@"export_ratchet_tree_error", @"Failed to export ratchet tree", nil);
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
        
        int commitLen = 0;
        uint8_t* welcomeBytes = NULL;
        int welcomeLen = 0;
        
        uint8_t* commitBytes = mls_add_member(self.mlsClient, groupIdStr, creatorIdStr, receiverIdStr, keyPackageStr, &commitLen, &welcomeBytes, &welcomeLen);
        
        if (commitBytes != NULL) {
            // Convert the commit bytes to a base64 string
            NSData* commitData = [NSData dataWithBytes:commitBytes length:commitLen];
            NSString* commitBase64 = [commitData base64EncodedStringWithOptions:0];
            
            // Convert the welcome bytes to a base64 string if they exist
            NSString* welcomeBase64 = nil;
            if (welcomeBytes != NULL) {
                NSData* welcomeData = [NSData dataWithBytes:welcomeBytes length:welcomeLen];
                welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
                mls_free_bytes(welcomeBytes);
            }
            
            // Free the commit bytes
            mls_free_bytes(commitBytes);
            
            // Create result dictionary
            NSDictionary* result = @{
                @"id": [[NSUUID UUID] UUIDString],
                @"type": @"add",
                @"sender": creatorId,
                @"data": commitBase64
            };
            
            // Add welcome message if available
            if (welcomeBase64 != nil) {
                NSMutableDictionary* mutableResult = [result mutableCopy];
                [mutableResult setObject:welcomeBase64 forKey:@"welcome"];
                result = mutableResult;
            }
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to add member to MLS group", nil);
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
        
        // Convert NSArray to array of int pointers
        NSUInteger count = [memberIndices count];
        int* indices = (int*)malloc(count * sizeof(int));
        const int** indicesPtrs = (const int**)malloc(count * sizeof(const int*));
        
        for (NSUInteger i = 0; i < count; i++) {
            indices[i] = [[memberIndices objectAtIndex:i] intValue];
            indicesPtrs[i] = &indices[i];
        }
        
        int commitLen = 0;
        uint8_t* commitBytes = mls_remove_members(self.mlsClient, groupIdStr, creatorIdStr, indicesPtrs, (int)count, &commitLen);
        
        // Free the allocated memory
        free(indices);
        free(indicesPtrs);
        
        if (commitBytes != NULL) {
            // Convert the commit bytes to a base64 string
            NSData* commitData = [NSData dataWithBytes:commitBytes length:commitLen];
            NSString* commitBase64 = [commitData base64EncodedStringWithOptions:0];
            
            // Free the commit bytes
            mls_free_bytes(commitBytes);
            
            // Create result dictionary
            NSDictionary* result = @{
                @"id": [[NSUUID UUID] UUIDString],
                @"type": @"remove",
                @"sender": @"self",
                @"data": commitBase64
            };
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to remove members from MLS group", nil);
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
        
        int commitLen = 0;
        uint8_t* welcomeBytes = NULL;
        int welcomeLen = 0;
        
        uint8_t* commitBytes = mls_commit_pending_proposals(self.mlsClient, groupIdStr, creatorIdStr, &commitLen, &welcomeBytes, &welcomeLen);
        
        if (commitBytes != NULL) {
            // Convert the commit bytes to a base64 string
            NSData* commitData = [NSData dataWithBytes:commitBytes length:commitLen];
            NSString* commitBase64 = [commitData base64EncodedStringWithOptions:0];
            
            // Convert the welcome bytes to a base64 string if they exist
            NSString* welcomeBase64 = nil;
            if (welcomeBytes != NULL) {
                NSData* welcomeData = [NSData dataWithBytes:welcomeBytes length:welcomeLen];
                welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
                mls_free_bytes(welcomeBytes);
            }
            
            // Free the commit bytes
            mls_free_bytes(commitBytes);
            
            // Create result dictionary
            NSMutableDictionary* result = [[NSMutableDictionary alloc] init];
            [result setObject:commitBase64 forKey:@"commit"];
            
            if (welcomeBase64 != nil) {
                [result setObject:welcomeBase64 forKey:@"welcome"];
            }
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to commit pending proposals", nil);
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
        
        char* keyPackageStr = mls_generate_key_package(self.mlsClient, identityStr);
        
        if (keyPackageStr != NULL) {
            NSString* keyPackage = [NSString stringWithUTF8String:keyPackageStr];
            
            // Free the key package string
            mls_free_string(keyPackageStr);
            
            // Return the key package string directly
            resolver(keyPackage);
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
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* identityStr = [identity UTF8String];
    int outCount = 0;
    int* outLens = NULL;
    
    char** keyPackageStrs = (char**)mls_generate_keypackages(self.mlsClient, identityStr, (int)count, &outCount, &outLens);
    
    if (keyPackageStrs != NULL && outCount > 0) {
        NSMutableArray* keyPackages = [NSMutableArray arrayWithCapacity:outCount];
        
        for (int i = 0; i < outCount; i++) {
            if (keyPackageStrs[i] != NULL) {
                NSString* keyPackage = [NSString stringWithUTF8String:keyPackageStrs[i]];
                [keyPackages addObject:keyPackage];
                
                // Free the key package string
                mls_free_string(keyPackageStrs[i]);
            }
        }
        
        // Free the array of strings
        mls_free_string_array(keyPackageStrs, outCount);
        
        // Free the lengths array
        if (outLens != NULL) {
            free(outLens);
        }
        
        resolver(keyPackages);
    } else {
        rejecter(@"generate_key_packages_error", @"Failed to generate key packages", nil);
    }
}

// Import a key package
RCT_EXPORT_METHOD(importKeyPackage:(NSString *)identity
                  keyPackage:(NSString *)keyPackage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* identityStr = [identity UTF8String];
    const char* keyPackageStr = [keyPackage UTF8String];
    
    // Use mls_add_keypackage to import the key package
    int result = mls_add_keypackage(self.mlsClient, identityStr, keyPackageStr);
    
    if (result == 1) {
        resolver(nil);
    } else {
        rejecter(@"import_key_package_error", @"Failed to import key package", nil);
    }
}

// Add multiple members to a group
RCT_EXPORT_METHOD(addMembers:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  receiverKeyPackages:(NSArray *)receiverKeyPackages
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* creatorIdStr = [creatorId UTF8String];
    
    // Convert the receiver key packages to C strings
    NSUInteger count = [receiverKeyPackages count];
    const char** receiverKeyPackageStrs = (const char**)malloc(count * sizeof(char*));
    
    for (NSUInteger i = 0; i < count; i++) {
        NSString* keyPackage = receiverKeyPackages[i];
        receiverKeyPackageStrs[i] = [keyPackage UTF8String];
    }
    
    int* outLens = NULL;
    int outCount = 0;
    
    uint8_t* result = mls_add_members(self.mlsClient, groupIdStr, creatorIdStr, receiverKeyPackageStrs, (int)count, &outLens, &outCount);
    
    // Free the receiver key package strings
    free(receiverKeyPackageStrs);
    
    if (result != NULL && outCount >= 2) {
        // Extract the commit and welcome bytes
        uint8_t* commitBytes = ((uint8_t**)result)[0];
        uint8_t* welcomeBytes = ((uint8_t**)result)[1];
        int commitLen = outLens[0];
        int welcomeLen = outLens[1];
        
        // Convert the bytes to base64 strings
        NSData* commitData = [NSData dataWithBytes:commitBytes length:commitLen];
        NSString* commitBase64 = [commitData base64EncodedStringWithOptions:0];
        
        NSData* welcomeData = [NSData dataWithBytes:welcomeBytes length:welcomeLen];
        NSString* welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
        
        // Create the result dictionary
        NSDictionary* resultDict = @{
            @"commit": commitBase64,
            @"welcome": welcomeBase64
        };
        
        // Free the result bytes
        mls_free_bytes(commitBytes);
        mls_free_bytes(welcomeBytes);
        free(result);
        
        // Free the lengths array
        if (outLens != NULL) {
            free(outLens);
        }
        
        resolver(resultDict);
    } else {
        if (outLens != NULL) {
            free(outLens);
        }
        if (result != NULL) {
            free(result);
        }
        rejecter(@"add_members_error", @"Failed to add members to group", nil);
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
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* creatorIdStr = [creatorId UTF8String];
    const char* labelStr = [label UTF8String];
    
    // Convert the context to bytes
    const uint8_t* contextBytes = NULL;
    int contextLen = 0;
    
    if (context != nil) {
        contextBytes = (const uint8_t *)[context bytes];
        contextLen = (int)[context length];
    }
    
    char* secretStr = mls_export_secret(self.mlsClient, groupIdStr, creatorIdStr, labelStr, contextBytes, contextLen, (unsigned int)length);
    
    if (secretStr != NULL) {
        NSString* secret = [NSString stringWithUTF8String:secretStr];
        
        // Free the secret string
        mls_free_string(secretStr);
        
        resolver(secret);
    } else {
        rejecter(@"export_secret_error", @"Failed to export secret", nil);
    }
}

// Encrypt a message
RCT_EXPORT_METHOD(encryptMessage:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  message:(NSString *)message
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* creatorIdStr = [creatorId UTF8String];
    const char* messageStr = [message UTF8String];
    
    int encryptedLen = 0;
    uint8_t* encryptedBytes = mls_encrypt_message(self.mlsClient, groupIdStr, creatorIdStr, messageStr, &encryptedLen);
    
    if (encryptedBytes != NULL) {
        // Convert the encrypted bytes to a base64 string
        NSData* encryptedData = [NSData dataWithBytes:encryptedBytes length:encryptedLen];
        NSString* encryptedBase64 = [encryptedData base64EncodedStringWithOptions:0];
        
        // Free the encrypted bytes
        mls_free_bytes(encryptedBytes);
        
        resolver(encryptedBase64);
    } else {
        rejecter(@"encrypt_message_error", @"Failed to encrypt message", nil);
    }
}

// Decrypt a message
RCT_EXPORT_METHOD(decryptMessage:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  encryptedMessage:(NSString *)encryptedMessage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    // Convert the base64 string to bytes
    NSData* encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedMessage options:0];
    
    if (encryptedData != nil) {
        const char* groupIdStr = [groupId UTF8String];
        const char* creatorIdStr = [creatorId UTF8String];
        const uint8_t* encryptedBytes = (const uint8_t*)[encryptedData bytes];
        int encryptedLen = (int)[encryptedData length];
        
        char* decryptedStr = mls_decrypt_message(self.mlsClient, groupIdStr, creatorIdStr, encryptedBytes, encryptedLen);
        
        if (decryptedStr != NULL) {
            NSString* decryptedMessage = [NSString stringWithUTF8String:decryptedStr];
            
            // Free the decrypted string
            mls_free_string(decryptedStr);
            
            resolver(decryptedMessage);
        } else {
            rejecter(@"decrypt_message_error", @"Failed to decrypt message", nil);
        }
    } else {
        rejecter(@"decrypt_message_error", @"Invalid encrypted message format", nil);
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
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* creatorIdStr = [creatorId UTF8String];
    
    // Convert the key packages to byte arrays
    NSMutableArray* keyPackageDataArray = [NSMutableArray arrayWithCapacity:[keyPackages count]];
    NSMutableArray* keyPackagePtrs = [NSMutableArray arrayWithCapacity:[keyPackages count]];
    NSMutableArray* keyPackageLens = [NSMutableArray arrayWithCapacity:[keyPackages count]];
    
    for (NSString* keyPackage in keyPackages) {
        NSData* data = [[NSData alloc] initWithBase64EncodedString:keyPackage options:0];
        [keyPackageDataArray addObject:data];
        [keyPackagePtrs addObject:[NSValue valueWithPointer:[data bytes]]];
        [keyPackageLens addObject:@([data length])];
    }
    
    // Convert the proposals to byte arrays
    NSMutableArray* proposalDataArray = [NSMutableArray arrayWithCapacity:[proposals count]];
    NSMutableArray* proposalPtrs = [NSMutableArray arrayWithCapacity:[proposals count]];
    NSMutableArray* proposalLens = [NSMutableArray arrayWithCapacity:[proposals count]];
    
    for (NSDictionary* proposal in proposals) {
        NSString* proposalData = proposal[@"data"];
        NSData* data = [[NSData alloc] initWithBase64EncodedString:proposalData options:0];
        [proposalDataArray addObject:data];
        [proposalPtrs addObject:[NSValue valueWithPointer:[data bytes]]];
        [proposalLens addObject:@([data length])];
    }
    
    // Create C arrays for the key packages and proposals
    const uint8_t** keyPackagePtrsArray = (const uint8_t**)malloc(sizeof(uint8_t*) * [keyPackages count]);
    int* keyPackageLensArray = (int*)malloc(sizeof(int) * [keyPackages count]);
    
    const uint8_t** proposalPtrsArray = (const uint8_t**)malloc(sizeof(uint8_t*) * [proposals count]);
    int* proposalLensArray = (int*)malloc(sizeof(int) * [proposals count]);
    
    for (NSUInteger i = 0; i < [keyPackages count]; i++) {
        keyPackagePtrsArray[i] = (const uint8_t*)[[keyPackagePtrs objectAtIndex:i] pointerValue];
        keyPackageLensArray[i] = [[keyPackageLens objectAtIndex:i] intValue];
    }
    
    for (NSUInteger i = 0; i < [proposals count]; i++) {
        proposalPtrsArray[i] = (const uint8_t*)[[proposalPtrs objectAtIndex:i] pointerValue];
        proposalLensArray[i] = [[proposalLens objectAtIndex:i] intValue];
    }
    
    // Call the Rust function
    int commitLen = 0;
    uint8_t* welcomeBytes = NULL;
    int welcomeLen = 0;
    
    uint8_t* commitBytes = mls_create_commit(
        self.mlsClient,
        groupIdStr,
        creatorIdStr,
        keyPackagePtrsArray,
        keyPackageLensArray,
        (int)[keyPackages count],
        proposalPtrsArray,
        proposalLensArray,
        (int)[proposals count],
        &commitLen,
        &welcomeBytes,
        &welcomeLen
    );
    
    // Free the C arrays
    free(keyPackagePtrsArray);
    free(keyPackageLensArray);
    free(proposalPtrsArray);
    free(proposalLensArray);
    
    if (commitBytes != NULL) {
        // Convert the commit bytes to a base64 string
        NSData* commitData = [NSData dataWithBytes:commitBytes length:commitLen];
        NSString* commitBase64 = [commitData base64EncodedStringWithOptions:0];
        
        // Convert the welcome bytes to a base64 string if they exist
        NSString* welcomeBase64 = nil;
        if (welcomeBytes != NULL) {
            NSData* welcomeData = [NSData dataWithBytes:welcomeBytes length:welcomeLen];
            welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
            mls_free_bytes(welcomeBytes);
        }
        
        // Create the result object
        NSMutableArray* proposalIds = [NSMutableArray arrayWithCapacity:[proposals count]];
        for (NSDictionary* proposal in proposals) {
            [proposalIds addObject:proposal[@"id"]];
        }
        
        NSMutableDictionary* result = [NSMutableDictionary dictionaryWithDictionary:@{
            @"id": [[NSUUID UUID] UUIDString],
            @"proposals": proposalIds,
            @"sender": @"self",
            @"data": commitBase64
        }];
        
        if (welcomeBase64) {
            [result setObject:welcomeBase64 forKey:@"welcome"];
        }
        
        // Free the commit bytes
        mls_free_bytes(commitBytes);
        
        resolver(result);
    } else {
        rejecter(@"create_commit_error", @"Failed to create commit", nil);
    }
}

// Get current epoch
RCT_EXPORT_METHOD(getCurrentEpoch:(NSString *)groupId
                  userId:(NSString *)userId
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }

    const char* groupIdStr = [groupId UTF8String];
    const char* userIdStr = [userId UTF8String];

    unsigned long epoch = mls_get_current_epoch(self.mlsClient, groupIdStr, userIdStr);
    resolver(@(epoch));
}

// Process an MLS message
RCT_EXPORT_METHOD(processMessage:(NSString *)groupId
                  userId:(NSString *)userId
                  encryptedMessage:(NSString *)encryptedMessage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    // Convert the base64 string to bytes
    NSData* encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedMessage options:0];
    
    if (encryptedData != nil) {
        const char* groupIdStr = [groupId UTF8String];
        const char* userIdStr = [userId UTF8String];
        const uint8_t* encryptedBytes = (const uint8_t*)[encryptedData bytes];
        int encryptedLen = (int)[encryptedData length];
        
        // Output parameters
        int messageType = 0;
        uint8_t* contentBytes = NULL;
        int contentLen = 0;
        uint8_t* senderBytes = NULL;
        int senderLen = 0;
        int validated = 0;
        
        // Call the Rust FFI function
        int result = mls_process_message(
            self.mlsClient,
            groupIdStr,
            userIdStr,
            encryptedBytes,
            encryptedLen,
            &messageType,
            &contentBytes,
            &contentLen,
            &senderBytes,
            &senderLen,
            &validated
        );
        
        if (result == 1) {
            // Create the result dictionary
            NSMutableDictionary* resultDict = [NSMutableDictionary dictionary];
            
            // Add the message type
            NSString* typeStr;
            switch (messageType) {
                case 0:
                    typeStr = @"application";
                    break;
                case 1:
                    typeStr = @"proposal";
                    break;
                case 2:
                    typeStr = @"commit";
                    break;
                case 3:
                    typeStr = @"welcome";
                    break;
                default:
                    typeStr = @"unknown";
            }
            [resultDict setObject:typeStr forKey:@"type"];
            
            // Add the content if available
            if (contentBytes != NULL && contentLen > 0) {
                NSData* contentData = [NSData dataWithBytes:contentBytes length:contentLen];
                
                // Try to convert to string if it's application message content
                if (messageType == 0) {
                    NSString* contentStr = [[NSString alloc] initWithData:contentData encoding:NSUTF8StringEncoding];
                    if (contentStr) {
                        [resultDict setObject:contentStr forKey:@"content"];
                    } else {
                        [resultDict setObject:[contentData base64EncodedStringWithOptions:0] forKey:@"content"];
                    }
                } else {
                    [resultDict setObject:[contentData base64EncodedStringWithOptions:0] forKey:@"content"];
                }
                
                // Free the content bytes
                mls_free_bytes(contentBytes);
            }
            
            // Add the sender if available
            if (senderBytes != NULL && senderLen > 0) {
                NSData* senderData = [NSData dataWithBytes:senderBytes length:senderLen];
                NSString* senderStr = [[NSString alloc] initWithData:senderData encoding:NSUTF8StringEncoding];
                if (senderStr) {
                    [resultDict setObject:senderStr forKey:@"sender"];
                }
                
                // Free the sender bytes
                mls_free_bytes(senderBytes);
            }
            
            // Add the validated flag
            [resultDict setObject:@(validated == 1) forKey:@"validated"];
            
            resolver(resultDict);
        } else {
            rejecter(@"process_message_error", @"Failed to process message", nil);
        }
    } else {
        rejecter(@"process_message_error", @"Invalid encrypted message format", nil);
    }
}

// Create a proposal to add a member to a group
RCT_EXPORT_METHOD(createAddProposal:(NSString *)groupId
                  senderId:(NSString *)senderId
                  keyPackage:(NSString *)keyPackage
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* senderIdStr = [senderId UTF8String];
    
    // Convert the key package to bytes
    NSData* keyPackageData = [[NSData alloc] initWithBase64EncodedString:keyPackage options:0];
    
    if (keyPackageData != nil) {
        const uint8_t* keyPackageBytes = (const uint8_t*)[keyPackageData bytes];
        int keyPackageLen = (int)[keyPackageData length];
        
        // Output parameter
        int proposalLen = 0;
        
        // Call the Rust FFI function
        uint8_t* proposalBytes = mls_create_add_proposal(
            self.mlsClient,
            groupIdStr,
            senderIdStr,
            keyPackageBytes,
            keyPackageLen,
            &proposalLen
        );
        
        if (proposalBytes != NULL) {
            // Convert the proposal bytes to a base64 string
            NSData* proposalData = [NSData dataWithBytes:proposalBytes length:proposalLen];
            NSString* proposalBase64 = [proposalData base64EncodedStringWithOptions:0];
            
            // Free the proposal bytes
            mls_free_bytes(proposalBytes);
            
            resolver(proposalBase64);
        } else {
            rejecter(@"create_add_proposal_error", @"Failed to create add proposal", nil);
        }
    } else {
        rejecter(@"create_add_proposal_error", @"Invalid key package format", nil);
    }
}

// Create a proposal to remove a member from a group
RCT_EXPORT_METHOD(createRemoveProposal:(NSString *)groupId
                  creatorId:(NSString *)creatorId
                  memberIndex:(NSInteger)memberIndex
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* creatorIdStr = [creatorId UTF8String];
    
    // Output parameter
    int proposalLen = 0;
    
    // Call the Rust FFI function
    uint8_t* proposalBytes = mls_create_remove_proposal(
        self.mlsClient,
        groupIdStr,
        creatorIdStr,
        (unsigned int)memberIndex,
        &proposalLen
    );
    
    if (proposalBytes != NULL) {
        // Convert the proposal bytes to a base64 string
        NSData* proposalData = [NSData dataWithBytes:proposalBytes length:proposalLen];
        NSString* proposalBase64 = [proposalData base64EncodedStringWithOptions:0];
        
        // Free the proposal bytes
        mls_free_bytes(proposalBytes);
        
        resolver(proposalBase64);
    } else {
        rejecter(@"create_remove_proposal_error", @"Failed to create remove proposal", nil);
    }
}

// Update the key for the current member in an MLS group (renamed from rotateKey)
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
        
        int commitLen = 0;
        uint8_t* welcomeBytes = NULL;
        int welcomeLen = 0;
        
        uint8_t* commitBytes = mls_self_update(self.mlsClient, groupIdStr, memberIdStr, &commitLen, &welcomeBytes, &welcomeLen);
        
        if (commitBytes != NULL) {
            // Convert the commit bytes to a base64 string
            NSData* commitData = [NSData dataWithBytes:commitBytes length:commitLen];
            NSString* commitBase64 = [commitData base64EncodedStringWithOptions:0];
            
            // Convert the welcome bytes to a base64 string if they exist
            NSString* welcomeBase64 = nil;
            if (welcomeBytes != NULL) {
                NSData* welcomeData = [NSData dataWithBytes:welcomeBytes length:welcomeLen];
                welcomeBase64 = [welcomeData base64EncodedStringWithOptions:0];
                mls_free_bytes(welcomeBytes);
            }
            
            // Create the result object
            NSDictionary* result = @{
                @"commit": commitBase64,
                @"welcome": welcomeBase64 ?: [NSNull null]
            };
            
            // Free the commit bytes
            mls_free_bytes(commitBytes);
            
            resolver(result);
        } else {
            rejecter(@"E_MLS", @"Failed to update key for member", nil);
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
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* memberIdStr = [memberId UTF8String];
    
    // Output parameter
    int proposalLen = 0;
    
    // Call the Rust FFI function
    uint8_t* proposalBytes = mls_self_remove(
        self.mlsClient,
        groupIdStr,
        memberIdStr,
        &proposalLen
    );
    
    if (proposalBytes != NULL) {
        // Convert the proposal bytes to a base64 string
        NSData* proposalData = [NSData dataWithBytes:proposalBytes length:proposalLen];
        NSString* proposalBase64 = [proposalData base64EncodedStringWithOptions:0];
        
        // Free the proposal bytes
        mls_free_bytes(proposalBytes);
        
        resolver(proposalBase64);
    } else {
        rejecter(@"self_remove_error", @"Failed to create self-remove proposal", nil);
    }
}

// Create an application message for an MLS group
RCT_EXPORT_METHOD(createApplicationMessage:(NSString *)groupId
                  userId:(NSString *)userId
                  message:(NSString *)message
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* userIdStr = [userId UTF8String];
    
    // Convert the message to bytes
    NSData* messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t* messageBytes = (const uint8_t*)[messageData bytes];
    int messageLen = (int)[messageData length];
    
    // Output parameter
    int encryptedLen = 0;
    
    // Call the Rust FFI function
    uint8_t* encryptedBytes = mls_create_application_message(
        self.mlsClient,
        groupIdStr,
        userIdStr,
        messageBytes,
        messageLen,
        &encryptedLen
    );
    
    if (encryptedBytes != NULL) {
        // Convert the encrypted bytes to a base64 string
        NSData* encryptedData = [NSData dataWithBytes:encryptedBytes length:encryptedLen];
        NSString* encryptedBase64 = [encryptedData base64EncodedStringWithOptions:0];
        
        // Free the encrypted bytes
        mls_free_bytes(encryptedBytes);
        
        resolver(encryptedBase64);
    } else {
        rejecter(@"create_application_message_error", @"Failed to create application message", nil);
    }
}

// Accept an MLS proposal message
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
        
        // Decode the base64 message to bytes
        NSData* messageData = [[NSData alloc] initWithBase64EncodedString:message options:0];
        if (!messageData) {
            rejecter(@"E_MLS", @"Failed to decode base64 message", nil);
            return;
        }
        
        const uint8_t* messageBytes = (const uint8_t*)[messageData bytes];
        int messageLen = (int)[messageData length];
        
        // Call the Rust FFI function
        int result = mls_accept_proposal(
            self.mlsClient,
            groupIdStr,
            userIdStr,
            messageBytes,
            messageLen
        );
        
        if (result == 1) {
            resolver(@YES);
        } else {
            rejecter(@"E_MLS", @"Failed to accept proposal", nil);
        }
    } @catch (NSException *exception) {
        rejecter(@"E_MLS", exception.reason, nil);
    }
}

// Get the members of an MLS group
RCT_EXPORT_METHOD(groupMembers:(NSString *)groupId
                   userId:(NSString *)userId
                   resolver:(RCTPromiseResolveBlock)resolver
                   rejecter:(RCTPromiseRejectBlock)rejecter)
{
    if (!self.mlsClient) {
        rejecter(@"client_error", @"MLS client not initialized", nil);
        return;
    }
    
    const char* groupIdStr = [groupId UTF8String];
    const char* userIdStr = [userId UTF8String];
    
    // Output parameter
    int count = 0;
    
    // Call the Rust FFI function
    char** members = mls_group_members(self.mlsClient, groupIdStr, userIdStr, &count);
    
    if (members != NULL && count > 0) {
        // Create a JavaScript array
        NSMutableArray* membersArray = [NSMutableArray arrayWithCapacity:count];
        
        // Fill the array with member IDs
        for (int i = 0; i < count; i++) {
            if (members[i] != NULL) {
                NSString* memberId = [NSString stringWithUTF8String:members[i]];
                [membersArray addObject:memberId];
            }
        }
        
        // Free the C string array
        mls_free_string_array(members, count);
        
        resolver(membersArray);
    } else {
        rejecter(@"group_members_error", @"Failed to get group members", nil);
    }
}

@end