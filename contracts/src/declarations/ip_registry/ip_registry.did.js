export const idlFactory = ({ IDL }) => {
  const IpID = IDL.Nat;
  const Result = IDL.Variant({ 'ok' : IDL.Null, 'err' : IDL.Text });
  const DisputeID = IDL.Nat;
  const EventKind = IDL.Variant({
    'IpCreated' : IpID,
    'DisputeRaised' : DisputeID,
    'DisputeVote' : IDL.Tuple(DisputeID, IDL.Principal, IDL.Bool),
    'DisputeResolved' : IDL.Tuple(DisputeID, IDL.Bool),
    'IpStaked' : IDL.Tuple(IpID, IDL.Principal, IDL.Nat),
    'LicenseIssued' : IDL.Tuple(IpID, IDL.Principal),
  });
  const Event = IDL.Record({ 'kind' : EventKind, 'timestamp' : IDL.Int });
  const IPStatus = IDL.Variant({
    'UnderDispute' : IDL.Null,
    'Unverified' : IDL.Null,
    'Verified' : IDL.Null,
    'Revoked' : IDL.Null,
  });
  const License = IDL.Record({
    'id' : IDL.Nat,
    'terms' : IDL.Text,
    'valid' : IDL.Bool,
    'licensee' : IDL.Principal,
    'createdAt' : IDL.Int,
    'royalty' : IDL.Nat,
  });
  const IpRecordPublic = IDL.Record({
    'id' : IpID,
    'stakes' : IDL.Nat,
    'status' : IPStatus,
    'title' : IDL.Text,
    'created' : IDL.Int,
    'disputes' : IDL.Vec(DisputeID),
    'licenses' : IDL.Vec(License),
    'owner' : IDL.Principal,
    'description' : IDL.Text,
    'file_hash' : IDL.Text,
    'updated' : IDL.Int,
  });
  const Result_3 = IDL.Variant({ 'ok' : IDL.Nat, 'err' : IDL.Text });
  const Result_2 = IDL.Variant({ 'ok' : DisputeID, 'err' : IDL.Text });
  const Result_1 = IDL.Variant({ 'ok' : IDL.Bool, 'err' : IDL.Text });
  return IDL.Service({
    'createIpRecord' : IDL.Func([IDL.Text, IDL.Text, IDL.Text], [IpID], []),
    'finishUpload' : IDL.Func([IpID, IDL.Nat], [Result], []),
    'getEvents' : IDL.Func([], [IDL.Vec(Event)], ['query']),
    'getIp' : IDL.Func([IpID], [IDL.Opt(IpRecordPublic)], ['query']),
    'issueLicense' : IDL.Func(
        [IpID, IDL.Principal, IDL.Text, IDL.Nat],
        [Result_3],
        [],
      ),
    'listAllIPs' : IDL.Func([], [IDL.Vec(IpRecordPublic)], ['query']),
    'raiseDispute' : IDL.Func([IpID, IDL.Text, IDL.Nat], [Result_2], []),
    'resolveDispute' : IDL.Func([DisputeID], [Result_1], []),
    'stake' : IDL.Func([IpID, IDL.Nat], [Result], []),
    'updateTokenCanisterId' : IDL.Func([IDL.Text], [], []),
    'uploadChunk' : IDL.Func([IpID, IDL.Nat, IDL.Vec(IDL.Nat8)], [Result], []),
    'voteOnDispute' : IDL.Func([DisputeID, IDL.Bool], [Result], []),
  });
};
export const init = ({ IDL }) => { return []; };
