import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import Blob "mo:base/Blob";

// Import token canister interface
import DIP20Interface "./dip20Interface";

actor IpRegistry {
  // Types
  public type IpID = Nat;
  public type DisputeID = Nat;
  
  public type IPStatus = {
    #Unverified;
    #Verified;
    #UnderDispute;
    #Revoked;
  };
  
  public type License = {
    id: Nat;
    licensee: Principal;
    terms: Text;
    royalty: Nat;
    valid: Bool;
    createdAt: Int;
  };
  
  public type Dispute = {
    id: DisputeID;
    ipId: IpID;
    challenger: Principal;
    reason: Text;
    votes_for: Nat;
    votes_against: Nat;
    voters: [Principal];
    stake: Nat;
    status: {#Open; #Resolved: Bool};
    createdAt: Int;
  };
  
  // Separate stake map to make it stable
  public type StakeEntry = {
    staker: Principal;
    amount: Nat;
  };
  
  // Add file metadata to store MIME type and original filename
  public type FileMetadata = {
    filename: Text;
    mimeType: Text;
    fileSize: Nat;
  };
  
  public type IpRecord = {
    owner: Principal;
    title: Text;
    description: Text;
    file_hash: Text;
    status: IPStatus;
    stakes: Nat;
    stakes_entries: [StakeEntry];
    licenses: [License];
    disputes: [DisputeID];
    created: Int;
    updated: Int;
    ownership_history: [(Principal, Int)]; // Track ownership history with timestamps
    file_metadata: ?FileMetadata; // Optional file metadata
  };
  
  public type IpRecordPublic = {
    id: IpID;
    owner: Principal;
    title: Text;
    description: Text;
    file_hash: Text;
    status: IPStatus;
    stakes: Nat;
    licenses: [License];
    disputes: [DisputeID];
    created: Int;
    updated: Int;
    file_metadata: ?FileMetadata; // Include file metadata in public record
  };
  
  public type EventKind = {
    #IpCreated: IpID;
    #IpStaked: (IpID, Principal, Nat);
    #DisputeRaised: DisputeID;
    #DisputeVote: (DisputeID, Principal, Bool);
    #DisputeResolved: (DisputeID, Bool);
    #LicenseIssued: (IpID, Principal);
    #OwnershipTransferred: (IpID, Principal, Principal);
  };
  
  public type Event = {
    kind: EventKind;
    timestamp: Int;
  };
  
  // Storage
  private stable var ipRecordsEntries : [(IpID, IpRecord)] = [];
  private stable var disputesEntries : [(DisputeID, Dispute)] = [];
  private stable var eventsArray : [Event] = [];
  private stable var nextIpId : IpID = 1;
  private stable var nextDisputeId : DisputeID = 1;
  private stable var nextLicenseId : Nat = 1;
  private stable var fileChunksEntries : [(IpID, [(Nat, Blob)])] = [];
  
  private var assets = HashMap.HashMap<IpID, IpRecord>(1, Nat.equal, Hash.hash);
  private var disputes = HashMap.HashMap<DisputeID, Dispute>(1, Nat.equal, Hash.hash);
  private var ipFileChunks = HashMap.HashMap<IpID, HashMap.HashMap<Nat, Blob>>(1, Nat.equal, Hash.hash);
  private var events = Buffer.Buffer<Event>(0);

  // Token canister - we'll use an updatable canister ID
  private stable var tokenCanisterId : Text = "rrkah-fqaaa-aaaaa-aaaaq-cai";
  
  // Function to get the token canister actor
  private func getTokenCanister() : DIP20Interface.Self {
    actor(tokenCanisterId) : DIP20Interface.Self
  };
  
  // Function to update the token canister ID
  public shared(msg) func updateTokenCanisterId(newId : Text) : async () {
    // In a production environment, add access control
    // if (msg.caller != owner) { return };
    tokenCanisterId := newId;
  };
  
  // Near the beginning of the actor, add a constant for self principal
  private stable var selfPrincipal : Principal = Principal.fromActor(IpRegistry);
  
  // Helper functions
  private func addEvent(kind : EventKind) {
    let event : Event = {
      kind = kind;
      timestamp = Time.now();
    };
    events.add(event);
  };
  
  private func getRecord(ipId : IpID) : ?IpRecord {
    assets.get(ipId)
  };
  
  private func toPublicRecord(id : IpID, record : IpRecord) : IpRecordPublic {
    {
      id = id;
      owner = record.owner;
      title = record.title;
      description = record.description;
      file_hash = record.file_hash;
      status = record.status;
      stakes = record.stakes;
      licenses = record.licenses;
      disputes = record.disputes;
      created = record.created;
      updated = record.updated;
      file_metadata = record.file_metadata;
    }
  };
  
  private func stakesEntriesToMap(entries: [StakeEntry]) : HashMap.HashMap<Principal, Nat> {
    let map = HashMap.HashMap<Principal, Nat>(0, Principal.equal, Principal.hash);
    for (entry in entries.vals()) {
      map.put(entry.staker, entry.amount);
    };
    return map;
  };
  
  private func stakesMapToEntries(map: HashMap.HashMap<Principal, Nat>) : [StakeEntry] {
    let buffer = Buffer.Buffer<StakeEntry>(0);
    for ((staker, amount) in map.entries()) {
      buffer.add({ staker = staker; amount = amount });
    };
    return Buffer.toArray(buffer);
  };
  
  // Helper function to update stake
  private func updateStake(record: IpRecord, staker: Principal, amount: Nat) : IpRecord {
    let stakesMap = stakesEntriesToMap(record.stakes_entries);
    let currentStake = switch (stakesMap.get(staker)) {
      case (null) { 0 };
      case (?val) { val };
    };
    
    stakesMap.put(staker, currentStake + amount);
    
    {
      owner = record.owner;
      title = record.title;
      description = record.description;
      file_hash = record.file_hash;
      status = record.status;
      stakes = record.stakes + amount;
      stakes_entries = stakesMapToEntries(stakesMap);
      licenses = record.licenses;
      disputes = record.disputes;
      created = record.created;
      updated = Time.now();
      ownership_history = record.ownership_history;
      file_metadata = record.file_metadata;
    }
  };
  
  // System initialization
  system func preupgrade() {
    ipRecordsEntries := Iter.toArray(assets.entries());
    disputesEntries := Iter.toArray(disputes.entries());
    eventsArray := Buffer.toArray(events);
    
    let tempFileChunks = Buffer.Buffer<(IpID, [(Nat, Blob)])>(0);
    for ((ipId, chunkMap) in ipFileChunks.entries()) {
      let chunksArray = Iter.toArray(chunkMap.entries());
      tempFileChunks.add((ipId, chunksArray));
    };
    fileChunksEntries := Buffer.toArray(tempFileChunks);
  };
  
  system func postupgrade() {
    assets := HashMap.fromIter<IpID, IpRecord>(
      ipRecordsEntries.vals(), 1, Nat.equal, Hash.hash);
    disputes := HashMap.fromIter<DisputeID, Dispute>(
      disputesEntries.vals(), 1, Nat.equal, Hash.hash);
    events := Buffer.fromArray<Event>(eventsArray);
    
    for ((ipId, chunks) in fileChunksEntries.vals()) {
      let chunkMap = HashMap.HashMap<Nat, Blob>(1, Nat.equal, Hash.hash);
      for ((idx, data) in chunks.vals()) {
        chunkMap.put(idx, data);
      };
      ipFileChunks.put(ipId, chunkMap);
    };
    
    ipRecordsEntries := [];
    disputesEntries := [];
    eventsArray := [];
    fileChunksEntries := [];
  };
  
  // Add ownership verification helper
  private func verifyOwnership(ipId: IpID, caller: Principal) : Bool {
    switch (assets.get(ipId)) {
      case (null) { false };
      case (?record) { record.owner == caller };
    }
  };

  // Add ownership transfer function
  public shared(msg) func transferOwnership(ipId: IpID, newOwner: Principal) : async Result.Result<(), Text> {
    switch (assets.get(ipId)) {
      case (null) { #err("IP record not found") };
      case (?record) {
        if (record.owner != msg.caller) {
          #err("Only the current owner can transfer ownership")
        } else {
          let updatedRecord = {
            owner = newOwner;
            title = record.title;
            description = record.description;
            file_hash = record.file_hash;
            status = record.status;
            stakes = record.stakes;
            stakes_entries = record.stakes_entries;
            licenses = record.licenses;
            disputes = record.disputes;
            created = record.created;
            updated = Time.now();
            ownership_history = Array.append(record.ownership_history, [(msg.caller, Time.now())]);
            file_metadata = record.file_metadata;
          };
          assets.put(ipId, updatedRecord);
          addEvent(#OwnershipTransferred(ipId, msg.caller, newOwner));
          #ok()
        }
      }
    }
  };
  
  // Core Methods
  public shared(msg) func createIpRecord(title: Text, description: Text, fileHash: Text) : async IpID {
    let owner = msg.caller;
    let id = nextIpId;
    nextIpId += 1;
    
    let newIpRecord : IpRecord = {
      owner = owner;
      title = title;
      description = description;
      file_hash = fileHash;
      status = #Unverified;
      stakes = 0;
      stakes_entries = [];
      licenses = [];
      disputes = [];
      created = Time.now();
      updated = Time.now();
      ownership_history = [(owner, Time.now())];
      file_metadata = null; // Initialize with no file metadata
    };
    
    assets.put(id, newIpRecord);
    addEvent(#IpCreated(id));
    id
  };
  
  public shared(msg) func uploadChunk(ipId: IpID, index: Nat, chunk: Blob) : async Result.Result<(), Text> {
    let record = getRecord(ipId);
    
    switch (record) {
      case (null) {
        return #err("IP record not found");
      };
      case (?rec) {
        if (rec.owner != msg.caller) {
          return #err("Only the owner can upload chunks");
        };
        
        var chunkMap = switch (ipFileChunks.get(ipId)) {
          case (null) {
            let newMap = HashMap.HashMap<Nat, Blob>(0, Nat.equal, Hash.hash);
            ipFileChunks.put(ipId, newMap);
            newMap
          };
          case (?map) { map };
        };
        
        chunkMap.put(index, chunk);
        return #ok();
      };
    };
  };
  
  public shared(msg) func finishUpload(ipId: IpID, fileSize: Nat) : async Result.Result<(), Text> {
    let record = getRecord(ipId);
    
    switch (record) {
      case (null) {
        return #err("IP record not found");
      };
      case (?rec) {
        if (rec.owner != msg.caller) {
          return #err("Only the owner can finish upload");
        };
        
        // Here you would validate that all chunks are present based on fileSize
        // For simplicity, we're just acknowledging the upload completion
        
        let updatedRecord = {
          owner = rec.owner;
          title = rec.title;
          description = rec.description;
          file_hash = rec.file_hash;
          status = #Verified;  // Optionally change status
          stakes = rec.stakes;
          stakes_entries = rec.stakes_entries;
          licenses = rec.licenses;
          disputes = rec.disputes;
          created = rec.created;
          updated = Time.now();
          ownership_history = rec.ownership_history;
          file_metadata = rec.file_metadata;
        };
        
        assets.put(ipId, updatedRecord);
        return #ok();
      };
    };
  };
  
  public shared(msg) func stake(ipId: IpID, amount: Nat) : async Result.Result<(), Text> {
    if (not verifyOwnership(ipId, msg.caller)) {
      return #err("Only the IP owner can stake");
    };
    
    switch (assets.get(ipId)) {
      case (null) { #err("IP record not found") };
      case (?record) {
        let updatedRecord = updateStake(record, msg.caller, amount);
        assets.put(ipId, updatedRecord);
        addEvent(#IpStaked(ipId, msg.caller, amount));
        #ok()
      }
    }
  };
  
  public shared(msg) func raiseDispute(ipId: IpID, reason: Text, stake: Nat) : async Result.Result<DisputeID, Text> {
    let record = getRecord(ipId);
    
    switch (record) {
      case (null) {
        return #err("IP record not found");
      };
      case (?rec) {
        if (rec.owner == msg.caller) {
          return #err("Owner cannot dispute their own IP");
        };
        
        // Transfer tokens for dispute stake
        let transferResult = await getTokenCanister().transferFrom(msg.caller, selfPrincipal, stake);
        
        switch (transferResult) {
          case (#Ok(_)) {
            let disputeId = nextDisputeId;
            nextDisputeId += 1;
            
            let newDispute : Dispute = {
              id = disputeId;
              ipId = ipId;
              challenger = msg.caller;
              reason = reason;
              votes_for = 0;
              votes_against = 0;
              voters = [];
              stake = stake;
              status = #Open;
              createdAt = Time.now();
            };
            
            disputes.put(disputeId, newDispute);
            
            // Update IP record to include dispute and change status
            var currentDisputes = rec.disputes;
            let updatedDisputes = Array.append(currentDisputes, [disputeId]);
            
            let updatedRecord = {
              owner = rec.owner;
              title = rec.title;
              description = rec.description;
              file_hash = rec.file_hash;
              status = #UnderDispute;
              stakes = rec.stakes;
              stakes_entries = rec.stakes_entries;
              licenses = rec.licenses;
              disputes = updatedDisputes;
              created = rec.created;
              updated = Time.now();
              ownership_history = rec.ownership_history;
              file_metadata = rec.file_metadata;
            };
            
            assets.put(ipId, updatedRecord);
            addEvent(#DisputeRaised(disputeId));
            
            return #ok(disputeId);
          };
          case (#Err(e)) {
            var errorMsg = "Token transfer failed: ";
            switch (e) {
              case (#InsufficientAllowance) { errorMsg := errorMsg # "Insufficient allowance" };
              case (#InsufficientBalance) { errorMsg := errorMsg # "Insufficient balance" };
              case (_) { errorMsg := errorMsg # "Unknown error" };
            };
            return #err(errorMsg);
          };
        };
      };
    };
  };
  
  public shared(msg) func voteOnDispute(disputeId: DisputeID, supportOriginal: Bool) : async Result.Result<(), Text> {
    let dispute = disputes.get(disputeId);
    
    switch (dispute) {
      case (null) {
        return #err("Dispute not found");
      };
      case (?disp) {
        switch (disp.status) {
          case (#Open) {};
          case (#Resolved(_)) {
            return #err("Dispute is not open for voting");
          };
        };
        
        // Check if user already voted
        let alreadyVoted = Array.find<Principal>(disp.voters, func(p) { Principal.equal(p, msg.caller) });
        
        switch (alreadyVoted) {
          case (?_) {
            return #err("You have already voted on this dispute");
          };
          case (null) {
            // Update votes
            let updatedVoters = Array.append(disp.voters, [msg.caller]);
            let updatedDispute = {
              id = disp.id;
              ipId = disp.ipId;
              challenger = disp.challenger;
              reason = disp.reason;
              votes_for = if (supportOriginal) disp.votes_for + 1 else disp.votes_for;
              votes_against = if (supportOriginal) disp.votes_against else disp.votes_against + 1;
              voters = updatedVoters;
              stake = disp.stake;
              status = disp.status;
              createdAt = disp.createdAt;
            };
            
            disputes.put(disputeId, updatedDispute);
            addEvent(#DisputeVote(disputeId, msg.caller, supportOriginal));
            
            return #ok();
          };
        };
      };
    };
  };
  
  public shared(msg) func resolveDispute(disputeId: DisputeID) : async Result.Result<Bool, Text> {
    let dispute = disputes.get(disputeId);
    
    switch (dispute) {
      case (null) {
        return #err("Dispute not found");
      };
      case (?disp) {
        switch (disp.status) {
          case (#Open) {};
          case (#Resolved(_)) {
            return #err("Dispute is already resolved");
          };
        };
        
        // Simple resolution: more votes for than against means original IP upheld
        let originalWins = disp.votes_for > disp.votes_against;
        
        // Update dispute status
        let updatedDispute = {
          id = disp.id;
          ipId = disp.ipId;
          challenger = disp.challenger;
          reason = disp.reason;
          votes_for = disp.votes_for;
          votes_against = disp.votes_against;
          voters = disp.voters;
          stake = disp.stake;
          status = #Resolved(originalWins);
          createdAt = disp.createdAt;
        };
        
        disputes.put(disputeId, updatedDispute);
        
        // Update IP record status
        let record = getRecord(disp.ipId);
        
        switch (record) {
          case (null) {
            return #err("IP record not found");
          };
          case (?rec) {
            let newStatus = if (originalWins) #Verified else #Revoked;
            
            let updatedRecord = {
              owner = rec.owner;
              title = rec.title;
              description = rec.description;
              file_hash = rec.file_hash;
              status = newStatus;
              stakes = rec.stakes;
              stakes_entries = rec.stakes_entries;
              licenses = rec.licenses;
              disputes = rec.disputes;
              created = rec.created;
              updated = Time.now();
              ownership_history = rec.ownership_history;
              file_metadata = rec.file_metadata;
            };
            
            assets.put(disp.ipId, updatedRecord);
            addEvent(#DisputeResolved(disputeId, originalWins));
            
            return #ok(originalWins);
          };
        };
      };
    };
  };
  
  public shared(msg) func issueLicense(ipId: IpID, licensee: Principal, terms: Text, royalty: Nat) : async Result.Result<Nat, Text> {
    if (not verifyOwnership(ipId, msg.caller)) {
      return #err("Only the IP owner can issue licenses");
    };
    
    switch (assets.get(ipId)) {
      case (null) { #err("IP record not found") };
      case (?record) {
        let licenseId = nextLicenseId;
        nextLicenseId += 1;
        
        let newLicense : License = {
          id = licenseId;
          licensee = licensee;
          terms = terms;
          royalty = royalty;
          valid = true;
          createdAt = Time.now();
        };
        
        let updatedLicenses = Array.append(record.licenses, [newLicense]);
        let updatedRecord = {
          owner = record.owner;
          title = record.title;
          description = record.description;
          file_hash = record.file_hash;
          status = record.status;
          stakes = record.stakes;
          stakes_entries = record.stakes_entries;
          licenses = updatedLicenses;
          disputes = record.disputes;
          created = record.created;
          updated = Time.now();
          ownership_history = record.ownership_history;
          file_metadata = record.file_metadata;
        };
        
        assets.put(ipId, updatedRecord);
        addEvent(#LicenseIssued(ipId, licensee));
        #ok(licenseId)
      }
    }
  };
  
  public query func getIp(ipId: IpID) : async ?IpRecordPublic {
    let record = getRecord(ipId);
    
    switch (record) {
      case (null) { null };
      case (?rec) { ?toPublicRecord(ipId, rec) };
    };
  };
  
  public query func listAllIPs() : async [IpRecordPublic] {
    let result = Buffer.Buffer<IpRecordPublic>(0);
    
    for ((id, record) in assets.entries()) {
      result.add(toPublicRecord(id, record));
    };
    
    return Buffer.toArray(result);
  };
  
  public query func getEvents() : async [Event] {
    return Buffer.toArray(events);
  };
  
  // Add function to update file metadata
  public shared(msg) func updateFileMetadata(ipId: IpID, filename: Text, mimeType: Text, fileSize: Nat) : async Result.Result<(), Text> {
    let record = getRecord(ipId);
    
    switch (record) {
      case (null) {
        return #err("IP record not found");
      };
      case (?rec) {
        if (rec.owner != msg.caller) {
          return #err("Only the owner can update file metadata");
        };
        
        let metadata : FileMetadata = {
          filename = filename;
          mimeType = mimeType;
          fileSize = fileSize;
        };
        
        let updatedRecord = {
          owner = rec.owner;
          title = rec.title;
          description = rec.description;
          file_hash = rec.file_hash;
          status = rec.status;
          stakes = rec.stakes;
          stakes_entries = rec.stakes_entries;
          licenses = rec.licenses;
          disputes = rec.disputes;
          created = rec.created;
          updated = Time.now();
          ownership_history = rec.ownership_history;
          file_metadata = ?metadata;
        };
        
        assets.put(ipId, updatedRecord);
        return #ok();
      };
    };
  };
  
  // Update the getFileInfo function to use the new metadata field
  public query func getFileInfo(ipId: IpID): async Result.Result<{chunkCount: Nat; fileSize: Nat; mimeType: Text; filename: Text}, Text> {
    let record = getRecord(ipId);
    
    switch (record) {
      case (null) {
        return #err("IP record not found");
      };
      case (?rec) {
        switch (ipFileChunks.get(ipId)) {
          case (null) {
            return #err("No file data found for this IP record");
          };
          case (?chunkMap) {
            // Get the total number of chunks
            let chunkCount = Iter.size(chunkMap.entries());
            
            // Use file metadata if available
            switch (rec.file_metadata) {
              case (?metadata) {
                return #ok({
                  chunkCount = chunkCount;
                  fileSize = metadata.fileSize;
                  mimeType = metadata.mimeType;
                  filename = metadata.filename;
                });
              };
              
              // Fall back to the old method if metadata is not available
              case (null) {
                // Simple logic to guess MIME type from the title or description
                var mimeType = "application/octet-stream"; // Default MIME type
                var filename = rec.title; // Default filename without extension
                
                let titleLower = Text.toLowercase(rec.title);
                if (Text.contains(titleLower, #text ".pdf")) {
                  mimeType := "application/pdf";
                  filename := rec.title;
                } else if (Text.contains(titleLower, #text ".png") or Text.contains(titleLower, #text "image")) {
                  mimeType := "image/png";
                  if (not Text.contains(titleLower, #text ".png")) {
                    filename := rec.title # ".png";
                  };
                } else if (Text.contains(titleLower, #text ".jpg") or Text.contains(titleLower, #text "jpeg")) {
                  mimeType := "image/jpeg";
                  if (not Text.contains(titleLower, #text ".jpg") and not Text.contains(titleLower, #text ".jpeg")) {
                    filename := rec.title # ".jpg";
                  };
                } else if (Text.contains(titleLower, #text ".txt") or Text.contains(titleLower, #text "text")) {
                  mimeType := "text/plain";
                  if (not Text.contains(titleLower, #text ".txt")) {
                    filename := rec.title # ".txt";
                  };
                } else if (Text.contains(titleLower, #text ".html") or Text.contains(titleLower, #text "html")) {
                  mimeType := "text/html";
                  if (not Text.contains(titleLower, #text ".html")) {
                    filename := rec.title # ".html";
                  };
                } else if (Text.contains(titleLower, #text ".json")) {
                  mimeType := "application/json";
                  if (not Text.contains(titleLower, #text ".json")) {
                    filename := rec.title # ".json";
                  };
                } else if (Text.contains(titleLower, #text ".mp3") or Text.contains(titleLower, #text "audio")) {
                  mimeType := "audio/mpeg";
                  if (not Text.contains(titleLower, #text ".mp3")) {
                    filename := rec.title # ".mp3";
                  };
                } else if (Text.contains(titleLower, #text ".mp4") or Text.contains(titleLower, #text "video")) {
                  mimeType := "video/mp4";
                  if (not Text.contains(titleLower, #text ".mp4")) {
                    filename := rec.title # ".mp4";
                  };
                } else {
                  // Don't add .bin extension - keep original filename
                  filename := rec.title;
                };
                
                return #ok({
                  chunkCount = chunkCount;
                  fileSize = chunkCount * 500 * 1024; // Approximate, 500KB per chunk
                  mimeType = mimeType;
                  filename = filename;
                });
              };
            };
          };
        };
      };
    };
  };
  
  public query func getFileChunk(ipId: IpID, index: Nat): async Result.Result<Blob, Text> {
    let record = getRecord(ipId);
    
    switch (record) {
      case (null) {
        return #err("IP record not found");
      };
      case (?rec) {
        switch (ipFileChunks.get(ipId)) {
          case (null) {
            return #err("No file data found for this IP record");
          };
          case (?chunkMap) {
            switch (chunkMap.get(index)) {
              case (null) {
                return #err("Chunk not found");
              };
              case (?chunk) {
                return #ok(chunk);
              };
            };
          };
        };
      };
    };
  };
  
  // Get all IPs by hash, with verified ones on top
  public query func getIpsByHash(hash: Text) : async [IpRecordPublic] {
    // Create a buffer to store matching IPs
    let matchingIps = Buffer.Buffer<(IpID, IpRecordPublic)>(0);
    
    // Find all IPs with the matching hash
    for ((id, record) in assets.entries()) {
      if (Text.equal(record.file_hash, hash)) {
        let publicRecord : IpRecordPublic = {
          id = id;
          owner = record.owner;
          title = record.title;
          description = record.description;
          file_hash = record.file_hash;
          status = record.status;
          stakes = record.stakes;
          licenses = record.licenses;
          disputes = record.disputes;
          created = record.created;
          updated = record.updated;
          file_metadata = record.file_metadata;
        };
        matchingIps.add((id, publicRecord));
      }
    };
    
    // Sort with verified on top, then by timestamp (newest first)
    let sortedIps = Buffer.toArray(matchingIps);
    let sorted = Array.sort<(IpID, IpRecordPublic)>(sortedIps, func((_, a), (_, b)) {
      // First, compare verification status
      switch (a.status, b.status) {
        case (#Verified, #Verified) { 
          // Both verified, sort by creation date descending
          if (a.created > b.created) #less else #greater 
        };
        case (#Verified, _) { #less }; // a is verified, b is not
        case (_, #Verified) { #greater };  // b is verified, a is not
        case (_, _) {
          // Neither are verified, sort by creation date descending
          if (a.created > b.created) #less else #greater
        };
      }
    });
    
    // Extract just the records from the sorted array
    Array.map<(IpID, IpRecordPublic), IpRecordPublic>(sorted, func((_, record)) { record })
  };
} 