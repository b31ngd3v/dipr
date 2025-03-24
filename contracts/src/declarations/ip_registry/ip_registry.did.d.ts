import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export type DisputeID = bigint;
export interface Event { 'kind' : EventKind, 'timestamp' : bigint }
export type EventKind = { 'IpCreated' : IpID } |
  { 'DisputeRaised' : DisputeID } |
  { 'DisputeVote' : [DisputeID, Principal, boolean] } |
  { 'DisputeResolved' : [DisputeID, boolean] } |
  { 'IpStaked' : [IpID, Principal, bigint] } |
  { 'LicenseIssued' : [IpID, Principal] };
export type IPStatus = { 'UnderDispute' : null } |
  { 'Unverified' : null } |
  { 'Verified' : null } |
  { 'Revoked' : null };
export type IpID = bigint;
export interface IpRecordPublic {
  'id' : IpID,
  'stakes' : bigint,
  'status' : IPStatus,
  'title' : string,
  'created' : bigint,
  'disputes' : Array<DisputeID>,
  'licenses' : Array<License>,
  'owner' : Principal,
  'description' : string,
  'file_hash' : string,
  'updated' : bigint,
}
export interface License {
  'id' : bigint,
  'terms' : string,
  'valid' : boolean,
  'licensee' : Principal,
  'createdAt' : bigint,
  'royalty' : bigint,
}
export type Result = { 'ok' : null } |
  { 'err' : string };
export type Result_1 = { 'ok' : boolean } |
  { 'err' : string };
export type Result_2 = { 'ok' : DisputeID } |
  { 'err' : string };
export type Result_3 = { 'ok' : bigint } |
  { 'err' : string };
export interface _SERVICE {
  'createIpRecord' : ActorMethod<[string, string, string], IpID>,
  'finishUpload' : ActorMethod<[IpID, bigint], Result>,
  'getEvents' : ActorMethod<[], Array<Event>>,
  'getIp' : ActorMethod<[IpID], [] | [IpRecordPublic]>,
  'issueLicense' : ActorMethod<[IpID, Principal, string, bigint], Result_3>,
  'listAllIPs' : ActorMethod<[], Array<IpRecordPublic>>,
  'raiseDispute' : ActorMethod<[IpID, string, bigint], Result_2>,
  'resolveDispute' : ActorMethod<[DisputeID], Result_1>,
  'stake' : ActorMethod<[IpID, bigint], Result>,
  'updateTokenCanisterId' : ActorMethod<[string], undefined>,
  'uploadChunk' : ActorMethod<[IpID, bigint, Uint8Array | number[]], Result>,
  'voteOnDispute' : ActorMethod<[DisputeID, boolean], Result>,
}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
