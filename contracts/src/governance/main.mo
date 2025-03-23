import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Hash "mo:base/Hash";
import Error "mo:base/Error";

// Import token canister interface
import DIP20Interface "../ip_registry/dip20Interface";

actor Governance {
  // Types
  public type ProposalID = Nat;
  
  public type ProposalStatus = {
    #Open;
    #Passed;
    #Rejected;
    #Executed;
  };
  
  public type Proposal = {
    id: ProposalID;
    title: Text;
    description: Text;
    proposer: Principal;
    yesVotes: Nat;
    noVotes: Nat;
    status: ProposalStatus;
    voters: [Principal];
    created: Int;
    updated: Int;
  };
  
  public type ProposalPublic = {
    id: ProposalID;
    title: Text;
    description: Text;
    proposer: Principal;
    yesVotes: Nat;
    noVotes: Nat;
    status: ProposalStatus;
    created: Int;
    updated: Int;
  };
  
  // Storage
  private stable var proposalsEntries : [(ProposalID, Proposal)] = [];
  private stable var nextProposalId : ProposalID = 1;
  
  private var proposals = HashMap.HashMap<ProposalID, Proposal>(1, Nat.equal, Hash.hash);
  
  // Token canister ID - will be updated after deployment
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
  
  // Get self principal
  private stable var selfPrincipal : Principal = Principal.fromActor(Governance);
  
  // System initialization
  system func preupgrade() {
    proposalsEntries := Iter.toArray(proposals.entries());
  };
  
  system func postupgrade() {
    if (proposalsEntries.size() > 0) {
      proposals := HashMap.fromIter<ProposalID, Proposal>(
        proposalsEntries.vals(), proposalsEntries.size(), Nat.equal, Hash.hash);
    } else {
      proposals := HashMap.HashMap<ProposalID, Proposal>(1, Nat.equal, Hash.hash);
    };
    proposalsEntries := [];
  };
  
  // Helper functions
  private func toPublicProposal(proposal : Proposal) : ProposalPublic {
    {
      id = proposal.id;
      title = proposal.title;
      description = proposal.description;
      proposer = proposal.proposer;
      yesVotes = proposal.yesVotes;
      noVotes = proposal.noVotes;
      status = proposal.status;
      created = proposal.created;
      updated = proposal.updated;
    }
  };
  
  // Core Methods
  public shared(msg) func createProposal(title: Text, description: Text) : async Result.Result<ProposalID, Text> {
    let proposer = msg.caller;
    
    // Optional: require token deposit
    // let depositAmount : Nat = 100;
    // let transferResult = await getTokenCanister().transferFrom(proposer, selfPrincipal, depositAmount);
    
    // switch (transferResult) {
    //   case (#Err(e)) {
    //     var errorMsg = "Token deposit failed: ";
    //     switch (e) {
    //       case (#InsufficientAllowance) { errorMsg := errorMsg # "Insufficient allowance" };
    //       case (#InsufficientBalance) { errorMsg := errorMsg # "Insufficient balance" };
    //       case (_) { errorMsg := errorMsg # "Unknown error" };
    //     };
    //     return #err(errorMsg);
    //   };
    //   case (#Ok(_)) {
    //     // Continue with proposal creation
    //   };
    // };
    
    let proposalId = nextProposalId;
    nextProposalId += 1;
    
    let newProposal : Proposal = {
      id = proposalId;
      title = title;
      description = description;
      proposer = proposer;
      yesVotes = 0;
      noVotes = 0;
      status = #Open;
      voters = [];
      created = Time.now();
      updated = Time.now();
    };
    
    proposals.put(proposalId, newProposal);
    
    return #ok(proposalId);
  };
  
  public shared(msg) func vote(proposalId: ProposalID, voteYes: Bool) : async Result.Result<(), Text> {
    let voter = msg.caller;
    
    switch (proposals.get(proposalId)) {
      case (null) {
        return #err("Proposal not found");
      };
      case (?proposal) {
        switch (proposal.status) {
          case (#Open) {};
          case (_) {
            return #err("Proposal is not open for voting");
          };
        };
        
        // Check if user already voted
        let alreadyVoted = Array.find<Principal>(proposal.voters, func(p) { Principal.equal(p, voter) });
        
        switch (alreadyVoted) {
          case (?_) {
            return #err("You have already voted on this proposal");
          };
          case (null) {
            // Get voter's token balance for vote weight 
            let voterBalance = await getTokenCanister().balanceOf(voter);
            
            // If voter has zero tokens, they can't vote
            if (voterBalance == 0) {
              return #err("You need to hold VIBE tokens to vote");
            };
            
            // Weight votes by token balance - minimal weight of 1
            let voteWeight = if (voterBalance > 0) voterBalance else 1;
            
            // Update votes
            let updatedVoters = Array.append(proposal.voters, [voter]);
            let updatedProposal = {
              id = proposal.id;
              title = proposal.title;
              description = proposal.description;
              proposer = proposal.proposer;
              yesVotes = if (voteYes) proposal.yesVotes + voteWeight else proposal.yesVotes;
              noVotes = if (voteYes) proposal.noVotes else proposal.noVotes + voteWeight;
              status = proposal.status;
              voters = updatedVoters;
              created = proposal.created;
              updated = Time.now();
            };
            
            proposals.put(proposalId, updatedProposal);
            
            return #ok();
          };
        };
      };
    };
  };
  
  public shared(msg) func finalizeProposal(proposalId: ProposalID) : async Result.Result<Bool, Text> {
    switch (proposals.get(proposalId)) {
      case (null) {
        return #err("Proposal not found");
      };
      case (?proposal) {
        switch (proposal.status) {
          case (#Open) {};
          case (_) {
            return #err("Proposal is not open");
          };
        };
        
        // Simple resolution: more yes than no votes
        let passed = proposal.yesVotes > proposal.noVotes;
        let newStatus = if (passed) #Passed else #Rejected;
        
        let updatedProposal = {
          id = proposal.id;
          title = proposal.title;
          description = proposal.description;
          proposer = proposal.proposer;
          yesVotes = proposal.yesVotes;
          noVotes = proposal.noVotes;
          status = newStatus;
          voters = proposal.voters;
          created = proposal.created;
          updated = Time.now();
        };
        
        proposals.put(proposalId, updatedProposal);
        
        // Here you would implement any on-chain actions if the proposal passed
        // For example: await ipRegistryCanister.updateMinStake(newMinStake);
        
        return #ok(passed);
      };
    };
  };
  
  public query func getProposal(proposalId: ProposalID) : async ?ProposalPublic {
    switch (proposals.get(proposalId)) {
      case (null) { null };
      case (?proposal) { ?toPublicProposal(proposal) };
    };
  };
  
  public query func listProposals() : async [ProposalPublic] {
    let result = Buffer.Buffer<ProposalPublic>(0);
    
    for ((_, proposal) in proposals.entries()) {
      result.add(toPublicProposal(proposal));
    };
    
    return Buffer.toArray(result);
  };
} 