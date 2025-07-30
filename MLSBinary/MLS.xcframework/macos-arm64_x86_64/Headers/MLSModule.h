#import <React/RCTBridgeModule.h>

@interface MLSModule : NSObject <RCTBridgeModule>

// Store the MLS client pointer
@property (nonatomic, assign) void* mlsClient;

/**
 * Initialize the MLS module
 * @param groupID The app group ID for shared storage (macOS only)
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)initialize:(NSString *)groupID
          resolver:(RCTPromiseResolveBlock)resolver
          rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Set storage encryption key for a user
 * @param userId The user ID
 * @param key The encryption key
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)setStorageKey:(NSString *)userId
                  key:(NSString *)key
             resolver:(RCTPromiseResolveBlock)resolver
             rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Rekey storage encryption for a user
 * @param userId The user ID
 * @param oldKey The old encryption key
 * @param newKey The new encryption key
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)setStorageRekey:(NSString *)userId
                 oldKey:(NSString *)oldKey
                 newKey:(NSString *)newKey
               resolver:(RCTPromiseResolveBlock)resolver
               rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Create a new MLS group
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)createGroup:(NSString *)groupId
          creatorId:(NSString *)creatorId
           resolver:(RCTPromiseResolveBlock)resolver
           rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Join an existing MLS group
 * @param groupId The ID of the group
 * @param receiverId The ID of the receiver
 * @param welcomeMessage The welcome message
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)joinGroup:(NSString *)groupId
       receiverId:(NSString *)receiverId
   welcomeMessage:(NSString *)welcomeMessage
         resolver:(RCTPromiseResolveBlock)resolver
         rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Join an existing MLS group with ratchet tree
 * @param groupId The ID of the group
 * @param receiverId The ID of the receiver
 * @param welcomeMessage The welcome message
 * @param ratchetTree The ratchet tree
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)joinGroupWithRatchetTree:(NSString *)groupId
                      receiverId:(NSString *)receiverId
                  welcomeMessage:(NSString *)welcomeMessage
                      ratchetTree:(NSString *)ratchetTree
                        resolver:(RCTPromiseResolveBlock)resolver
                        rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Export ratchet tree from a group
 * @param groupId The ID of the group
 * @param userId The ID of the user
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)exportRatchetTree:(NSString *)groupId
                   userId:(NSString *)userId
                 resolver:(RCTPromiseResolveBlock)resolver
                 rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Add a member to an MLS group
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param receiverId The ID of the receiver
 * @param keyPackage The key package
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)addMember:(NSString *)groupId
        creatorId:(NSString *)creatorId
       receiverId:(NSString *)receiverId
       keyPackage:(NSString *)keyPackage
         resolver:(RCTPromiseResolveBlock)resolver
         rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Add multiple members to an MLS group
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param receiverKeyPackages Array of key packages
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)addMembers:(NSString *)groupId
         creatorId:(NSString *)creatorId
receiverKeyPackages:(NSArray *)receiverKeyPackages
          resolver:(RCTPromiseResolveBlock)resolver
          rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Remove members from an MLS group
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param memberIndices Array of member indices to remove
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)removeMembers:(NSString *)groupId
            creatorId:(NSString *)creatorId
        memberIndices:(NSArray *)memberIndices
             resolver:(RCTPromiseResolveBlock)resolver
             rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Commit pending proposals in an MLS group
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)commitPendingProposals:(NSString *)groupId
                     creatorId:(NSString *)creatorId
                      resolver:(RCTPromiseResolveBlock)resolver
                      rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Generate a key package
 * @param identity The identity
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)generateKeyPackage:(NSString *)identity
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Generate multiple key packages
 * @param identity The identity
 * @param count The number of key packages to generate
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)generateKeyPackages:(NSString *)identity
                      count:(NSInteger)count
                   resolver:(RCTPromiseResolveBlock)resolver
                   rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Import a key package
 * @param identity The identity
 * @param keyPackage The key package to import
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)importKeyPackage:(NSString *)identity
              keyPackage:(NSString *)keyPackage
                resolver:(RCTPromiseResolveBlock)resolver
                rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Export a secret from an MLS group
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param label The label for the secret
 * @param context The context data
 * @param length The length of the secret
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)exportSecret:(NSString *)groupId
           creatorId:(NSString *)creatorId
               label:(NSString *)label
             context:(NSData *)context
              length:(NSInteger)length
            resolver:(RCTPromiseResolveBlock)resolver
            rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Encrypt a message
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param message The message to encrypt
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)encryptMessage:(NSString *)groupId
             creatorId:(NSString *)creatorId
               message:(NSString *)message
              resolver:(RCTPromiseResolveBlock)resolver
              rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Decrypt a message
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param encryptedMessage The encrypted message to decrypt
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)decryptMessage:(NSString *)groupId
             creatorId:(NSString *)creatorId
      encryptedMessage:(NSString *)encryptedMessage
              resolver:(RCTPromiseResolveBlock)resolver
              rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Create a commit
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator
 * @param keyPackages Array of key packages
 * @param proposals Array of proposals
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)createCommit:(NSString *)groupId
           creatorId:(NSString *)creatorId
         keyPackages:(NSArray *)keyPackages
           proposals:(NSArray *)proposals
            resolver:(RCTPromiseResolveBlock)resolver
            rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Get current epoch
 * @param groupId The ID of the group
 * @param userId The ID of the user
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)getCurrentEpoch:(NSString *)groupId
                 userId:(NSString *)userId
               resolver:(RCTPromiseResolveBlock)resolver
               rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Process an MLS message
 * @param groupId The ID of the group
 * @param userId The ID of the user processing the message
 * @param encryptedMessage The encrypted message to process (base64 encoded)
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)processMessage:(NSString *)groupId
               userId:(NSString *)userId
      encryptedMessage:(NSString *)encryptedMessage
              resolver:(RCTPromiseResolveBlock)resolver
              rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Accept a proposal
 * @param groupId The ID of the group
 * @param userId The ID of the user
 * @param message The proposal message
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)acceptProposal:(NSString *)groupId
                userId:(NSString *)userId
               message:(NSString *)message
              resolver:(RCTPromiseResolveBlock)resolver
              rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Create a proposal to add a member to a group
 * @param groupId The ID of the group
 * @param senderId The ID of the sender (group creator/admin)
 * @param keyPackage The key package of the new member
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)createAddProposal:(NSString *)groupId
                 senderId:(NSString *)senderId
               keyPackage:(NSString *)keyPackage
                 resolver:(RCTPromiseResolveBlock)resolver
                 rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Create a proposal to remove a member from a group
 * @param groupId The ID of the group
 * @param creatorId The ID of the creator (group admin)
 * @param memberIndex The index of the member to remove
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)createRemoveProposal:(NSString *)groupId
                   creatorId:(NSString *)creatorId
                memberIndex:(NSInteger)memberIndex
                   resolver:(RCTPromiseResolveBlock)resolver
                   rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Update the key for the current member in an MLS group
 * @param groupId The ID of the group
 * @param memberId The ID of the member
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)selfUpdate:(NSString *)groupId
          memberId:(NSString *)memberId
          resolver:(RCTPromiseResolveBlock)resolver
          rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Remove self from an MLS group
 * @param groupId The ID of the group
 * @param memberId The ID of the member to remove
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)selfRemove:(NSString *)groupId
          memberId:(NSString *)memberId
          resolver:(RCTPromiseResolveBlock)resolver
          rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Create an application message for an MLS group
 * @param groupId The ID of the group
 * @param userId The ID of the user
 * @param message The plaintext message
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)createApplicationMessage:(NSString *)groupId
                         userId:(NSString *)userId
                        message:(NSString *)message
                       resolver:(RCTPromiseResolveBlock)resolver
                       rejecter:(RCTPromiseRejectBlock)rejecter;

/**
 * Get group members
 * @param groupId The ID of the group
 * @param userId The ID of the user
 * @param resolver Promise resolver
 * @param rejecter Promise rejecter
 */
- (void)groupMembers:(NSString *)groupId
              userId:(NSString *)userId
            resolver:(RCTPromiseResolveBlock)resolver
            rejecter:(RCTPromiseRejectBlock)rejecter;

@end