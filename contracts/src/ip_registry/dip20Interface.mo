module {
  // Return types
  public type TxReceipt = {
    #Ok: Nat;
    #Err: {
      #InsufficientAllowance;
      #InsufficientBalance;
      #ErrorOperationStyle;
      #Unauthorized;
      #LedgerTrap;
      #ErrorTo;
      #Other: Text;
      #BlockUsed;
      #AmountTooSmall;
    };
  };

  public type Metadata = {
    logo : Text;
    name : Text;
    symbol : Text;
    decimals : Nat8;
    totalSupply : Nat;
    owner : Principal;
    fee : Nat;
  };

  // The public interface of the token
  public type Self = actor {
    transfer : (to: Principal, value: Nat) -> async TxReceipt;
    transferFrom : (from: Principal, to: Principal, value: Nat) -> async TxReceipt;
    approve : (spender: Principal, value: Nat) -> async TxReceipt;
    balanceOf : (who: Principal) -> async Nat;
    allowance : (owner: Principal, spender: Principal) -> async Nat;
    totalSupply : () -> async Nat;
    getMetadata : () -> async Metadata;
  };
} 