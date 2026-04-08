[English](./README.md) | [简体中文](./README.zh-CN.md)

# AirdropGroup Contracts

One-time Merkle airdrop claim with permanent inviter binding, on-chain group join, and **OZT Proof** (issuer has no token minting rights).

## Table of Contents

- [Overview](#overview)
- [Public Snapshot (31158025 Airdrop)](#public-snapshot-31158025-airdrop)
- [Rebuilding the Merkle Tree Locally](#rebuilding-the-merkle-tree-locally)
- [OZT Proof](#ozt-proof)
- [Architecture](#architecture)
- [Contract Reference](#contract-reference)
- [Usage Flow](#usage-flow)
- [Security](#security)

## Overview

The AirdropGroup module provides:

- **One-time claim**: Each address in the Merkle tree may claim once; leaf = `keccak256(abi.encode(account))`.
- **Inviter binding**: At claim time the user may bind an inviter; the binding is permanent (first bind wins).
- **Dual rewards**: Claimer and inviter both receive **密马.com** rewards via `OZTToken.mintByClaim`.
- **On-chain group join**: After claim, both claimer and inviter are added to the **MerkelGroup Community** (see below) via `ICommunityClaimJoin.claimJoin(address)`.
- **OZT-compliant minting**: Only the claim contract can mint; token owner can renounce/transfer to burn address so the project has no minting power.

Optional controls: blacklist, max invitees per inviter (0 = unlimited), and Merkle root freeze (irreversible).

---

## Public Snapshot (31158025 Airdrop)

The following data is disclosed for the current **31158025** airdrop snapshot so anyone can independently verify the distribution source data and recompute the Merkle root:

- **Merkle root**: `0xaccd3dd1875a2af125296ee50acbbfd9069d88e703bb9dedcb49ed65cb4c53bb`
- **Original address archive**: [Download ZIP](https://aqua-biological-spider-837.mypinata.cloud/ipfs/bafybeibi3on6bmczzutq73y3jrsroobr6lp5sxcxtptzltv6ez56jv77pa)

Anyone may download the original address archive, rebuild the Merkle tree locally, and compare the computed root with the on-chain root published by the claim contract.

### Rebuilding the Merkle Tree Locally

The published archive is a ZIP file containing CSV address data. After extracting the ZIP, read the CSV file locally and rebuild the root with the same rules used by the airdrop snapshot:

- Normalize every address to lowercase and validate it as an EVM address.
- Build each leaf as `keccak256(abi.encode(address))`.
- For each parent node, sort the two child hashes by byte order first, then hash with `keccak256(abi.encodePacked(bytes32, bytes32))`.
- If a level has an odd number of nodes, promote the last node unchanged to the next level.

Core logic example:

```ts
import fs from "node:fs/promises";
import { encodeAbiParameters, isAddress, keccak256 } from "viem";

function normalizeLowerAddress(address: string): `0x${string}` {
  const normalized = address.trim().toLowerCase();
  if (!isAddress(normalized)) {
    throw new Error(`invalid address: ${address}`);
  }
  return normalized as `0x${string}`;
}

function buildLeaf(address: `0x${string}`): `0x${string}` {
  return keccak256(encodeAbiParameters([{ type: "address" }], [address]));
}

function hashPairSorted(left: `0x${string}`, right: `0x${string}`): `0x${string}` {
  const leftBytes = Buffer.from(left.slice(2), "hex");
  const rightBytes = Buffer.from(right.slice(2), "hex");
  const pair =
    Buffer.compare(leftBytes, rightBytes) <= 0
      ? Buffer.concat([leftBytes, rightBytes])
      : Buffer.concat([rightBytes, leftBytes]);

  return keccak256(`0x${pair.toString("hex")}`);
}

function buildMerkleRoot(addresses: string[]): `0x${string}` {
  let level = addresses.map((address) => buildLeaf(normalizeLowerAddress(address)));
  if (level.length === 0) {
    throw new Error("empty address list");
  }

  while (level.length > 1) {
    const nextLevel: `0x${string}`[] = [];

    for (let i = 0; i < level.length; i += 2) {
      if (i + 1 >= level.length) {
        nextLevel.push(level[i]);
      } else {
        nextLevel.push(hashPairSorted(level[i], level[i + 1]));
      }
    }

    level = nextLevel;
  }

  return level[0];
}

async function main() {
  // Extract the ZIP first, then point this to the CSV file inside it.
  const csvText = await fs.readFile("./addresses.csv", "utf8");
  const lines = csvText.split(/\r?\n/).filter(Boolean);
  const [header, ...rows] = lines;
  const headers = header.split(",").map((item) => item.trim().toLowerCase());
  const walletAddressIndex = headers.indexOf("wallet_address");

  const addresses = rows.map((line) => {
    const columns = line.split(",");
    return walletAddressIndex >= 0 ? columns[walletAddressIndex] : columns[0];
  });

  console.log(buildMerkleRoot(addresses));
}

await main();
```

If the output equals `0xaccd3dd1875a2af125296ee50acbbfd9069d88e703bb9dedcb49ed65cb4c53bb`, then the local reconstruction matches the published snapshot.

---

## OZT Proof

**OZT (Zero Token control by issuer)** is a proof system that demonstrates **the project has no token issuance rights**. It relies on Merkle trees, on-chain fixation of the root, and permanent renunciation of mint/owner authority.

### Definition

OZT Proof is a **cryptographic and on-chain** guarantee that:

1. Eligibility is defined only by a **Merkle root** (derived from a public snapshot).
2. The root is **fixed on-chain** and can be **frozen** so it cannot be changed.
3. **Only the claim contract** can mint, and it mints only to addresses that prove inclusion in the Merkle tree (and optionally to their inviters).
4. The **token owner** can transfer ownership to a burn address, so no central party retains mint or admin power.

Together, this ensures fair, rule-based distribution with no backdoor issuance.

### Five-Layer Logic (summary)

1. **Merkle binding**: The Merkle root has a unique mapping to the set of leaves. Changing a single address in the snapshot changes the root; the snapshot cannot be altered without detection.
2. **Snapshot → root**: A snapshot (e.g. “all addresses with ≥ $100 on BSC”) is turned into a Merkle tree; the root is the public commitment to that set.
3. **Public verification**: The full leaf list (or tree data) can be published (e.g. on GitHub). Anyone can recompute the root and compare it to the value stored on-chain.
4. **Root on-chain**: The verified root is set (and optionally frozen) in the claim contract on a public chain (e.g. BSC), so the eligibility rule is immutable and auditable.
5. **No issuer control**: The token contract’s owner is transferred to a burn address (or renounced). The only minter is the claim contract, which only mints to provable snapshot addresses (and their invitees). The project gives up all mint and admin rights.

### Verification Loop

The community can verify OZT without trusting the project:

1. Download the Merkle tree file (e.g. from GitHub).
2. Compute the Merkle root locally.
3. Compare it to the root stored in the claim contract (and check that the root is frozen if applicable).
4. Confirm the token contract owner is a burn address (or renounced).
5. Confirm that minting is restricted to the claim contract and that the claim contract only mints for valid Merkle proof (and inviter rewards).

All steps are independently verifiable on-chain and from public data.

### Value

- **Decentralized issuance**: Only on-chain rules and snapshot-derived Merkle proofs determine who can receive tokens; no single party can mint at will.
- **Cryptographic fairness**: The snapshot and the root are bound; eligibility is objective and tamper-evident.
- **Rigid supply**: Total minted is bounded by the number of eligible claimers and the fixed reward per claim (and per inviter). Once the root is frozen and owner is burned, the cap is enforced by the contract.

---

## Architecture

### Contracts

| Contract        | Role |
|----------------|------|
| **密马.com (OZTToken)**   | ERC20 token; only `claimContract` can mint via `mintByClaim`. Owner can be set once to claim contract, then transferred to burn address. |
| **AirdropClaim** | Holds Merkle root (set once, optionally frozen). Users claim with Merkle proof; optional inviter binding; mints to claimer and inviter; calls `ICommunityClaimJoin.claimJoin` for both. |

### Interfaces

- **IOZTToken**: `mintByClaim(to, amount)`, `setClaimContractOnce(claimContract_)`.
- **ICommunityClaimJoin**: `claimJoin(account)` — called so claimer and inviter join an on-chain group.

### Group joined after claim (MerkelGroup Community)

The community contract that receives claimers and inviters is the **MerkelGroup [Community](../MerkelGroup/Community.sol)**. In that contract:

- **`claimJoin(address account)`** adds `account` as a member with the community’s maximum tier in the current epoch. It is callable only by addresses in the **claim operator** list (`onlyClaimOperator`).
- The Community owner must call **`setClaimOperator(airdropClaimAddress, true)`** so that the AirdropClaim contract is allowed to call `claimJoin`. Without this, `AirdropClaim.claim` would revert when it tries to add the claimer and inviter to the community.

So: after a successful claim, both the claimer and the inviter are added to that Community group (same one used for Merkle-based join and rooms).

### Deployment Order

1. Deploy **密马.com (OZTToken)** (name, symbol, initialOwner).
2. Deploy **AirdropClaim** (owner, token, community, merkleRoot), where `community` is the MerkelGroup **Community** address.
3. On the **Community** contract: call **setClaimOperator**(airdropClaimAddress, true) so AirdropClaim can call `claimJoin`.
4. On **密马.com (OZTToken)**: call **setClaimContractOnce**(airdropClaimAddress).
5. On AirdropClaim: set Merkle root if not set in constructor; optionally **freezeMerkleRoot**.
6. (Optional) Transfer **密马.com (OZTToken)** owner to burn address so no one can change claim contract or mint.

### Images

**Claim flow**

![Claim flow](./images/claim.jpg)

**Invite flow**

![Invite flow](./images/invite.jpg)

---

## Contract Reference

### AirdropClaim

- **Constructor**: `(initialOwner, token_, community_, merkleRoot_)` — `token_` is the **密马.com** token contract (`OZTToken`), `community_` is the MerkelGroup Community (must have AirdropClaim set as claim operator via `Community.setClaimOperator`); `merkleRoot_` can be `bytes32(0)` and set later once.
- **Claim**: `claim(proof, inviter)` — `proof` is Merkle proof for `msg.sender` (leaf = `keccak256(abi.encode(msg.sender))`); `inviter` can be `address(0)`. First successful claim binds inviter permanently; claimer and inviter get rewards and `community.claimJoin` is called for both.
- **Admin**: `setMerkleRoot` (only before any root was set and before freeze), `freezeMerkleRoot`, `setCommunity`, `setBlacklist`, `setInviterLimit`, `rescueERC20`.
- **Views**: `merkleRoot()`, `isClaimed(account)`, `inviterOf(invitee)`, `inviteeCount(inviter)`, `getInvitees(inviter, offset, limit)`.

### 密马.com (OZTToken)

- **Constructor**: `(name_, symbol_, initialOwner)`.
- **One-time**: `setClaimContractOnce(claimContract_)` — only the claim contract can call `mintByClaim` after this.
- **Minting**: `mintByClaim(to, amount)` — only callable by `claimContract` (set above).

---

## Usage Flow

1. **Off-chain**: Build snapshot of eligible addresses; build Merkle tree; publish leaf list/tree (e.g. GitHub); compute root.
2. **On-chain**: Set root in AirdropClaim (or pass in constructor); optionally freeze root; ensure **密马.com (OZTToken)** has `claimContract` set and, for full OZT, transfer the token owner to the burn address.
3. **User**: Get Merkle proof for their address; call `claim(proof, inviter)`; receive token reward; inviter receives reward; both are joined to the community via `claimJoin`.

---

## Security

- **One claim per address**: Enforced by `_claimed` in AirdropClaim.
- **Merkle root**: Set once; optional freeze prevents any future change.
- **Inviter binding**: Immutable after first claim; prevents inviter gaming.
- **Mint authority**: Only AirdropClaim can mint **密马.com** after `setClaimContractOnce`; AirdropClaim mints only to claimer and inviter according to fixed rules. Renouncing/transferring the token owner to the burn address removes all project-side control (OZT).
