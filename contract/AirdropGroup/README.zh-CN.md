[English](./README.md) | [简体中文](./README.zh-CN.md)

# AirdropGroup 合约

基于 Merkle 树的一次性空投领取、永久邀请人绑定、链上群组加入，以及 **OZT 证明**（项目方无代币发行权）。

## 目录

- [概述](#概述)
- [OZT 证明](#ozt-证明)
- [架构](#架构)
- [合约说明](#合约说明)
- [使用流程](#使用流程)
- [安全](#安全)

## 概述

AirdropGroup 模块提供：

- **一次性领取**：Merkle 树中每个地址仅可领取一次；叶子为 `keccak256(abi.encode(account))`。
- **邀请人绑定**：领取时可绑定邀请人，绑定后不可更改（先绑先得）。
- **双份奖励**：领取人与邀请人分别通过 `OZTToken.mintByClaim` 获得代币奖励。
- **链上入群**：领取后，领取人与邀请人会通过 `ICommunityClaimJoin.claimJoin(address)` 加入 **MerkelGroup 的 Community** 群组（见下）。
- **符合 OZT 的铸造**：仅领取合约可铸造；代币 Owner 可放弃或转至黑洞地址，使项目方不再拥有任何铸造权。

可选控制：黑名单、每邀请人最大被邀请数（0 表示不限制）、Merkle 根冻结（不可逆）。

---

## OZT 证明

**OZT（项目方无代币发行权）** 是一套基于默克尔树密码学特性、链上合约固化与项目方权限销毁的证明体系，通过多层不可逆验证，确保代币发行权完全由链上规则与有效地址决定，项目方无法干预、预留或篡改。

### 核心定义

OZT 证明通过以下机制实现「项目方无代币发行权」：

1. **资格仅由 Merkle 根决定**：根哈希由公开快照数据生成，与底层地址列表一一对应。
2. **根哈希链上固化**：根写入领取合约并可在部署后**冻结**，一旦冻结不可再改。
3. **仅领取合约可铸造**：代币合约只允许指定的领取合约调用 `mintByClaim`，且该合约仅对通过 Merkle 验证的地址（及对应邀请人）铸造。
4. **项目方放弃控制权**：将代币合约的 Owner 转入黑洞地址（或放弃），则无人可再修改领取合约或动用管理员权限，实现发行权彻底去中心化。

### 五层核心原理（与合约对应）

1. **密码学底层**：默克尔树的根哈希与底层地址列表存在唯一映射，任意修改一个地址，根哈希都会改变，从源头杜绝篡改。
2. **快照与根绑定**：将满足条件的用户地址（如 BSC 链上资产≥100$）做成快照，基于该快照构建默克尔树并计算根哈希，实现「快照内容」与「根哈希」强绑定。
3. **开源可验证**：将默克尔树原始文件（或完整叶子列表）上传至 GitHub 等公开位置，任何人可下载并本地计算根哈希，与链上公布的根对比，实现数据透明。
4. **根哈希链上固化**：在领取合约（AirdropClaim）中设置并可选**冻结** Merkle 根，链上可查且不可篡改，发行规则完全由合约与根决定。
5. **项目方发行权销毁**：在代币合约（OZTToken）上，将 Owner 转入黑洞地址或放弃，项目方永久失去 `setClaimContractOnce`、合约升级等权限；唯一能铸造的只有已绑定的领取合约，而领取合约仅对通过 Merkle 证明的地址（及邀请人）按规则铸造。

### 验证闭环

社区可独立完成验证，无需信任项目方：

1. 从 GitHub 等渠道下载默克尔树文件。
2. 本地计算根哈希。
3. 与链上领取合约中的根哈希对比（若已冻结可一并确认），验证数据真实性。
4. 核查代币合约 Owner 是否为黑洞地址，验证权限已销毁。
5. 确认铸造仅由领取合约执行，且领取合约仅对快照内地址（及邀请人）按固定规则铸造，验证发行权归属链上规则。

### 核心价值

- **发行权去中心化**：发行权完全由链上有效地址与默克尔规则决定，无单一主体可随意增发。
- **密码学级公平**：依托默克尔树唯一映射，快照与发行规则不可篡改，准入门槛由链上数据客观判定。
- **刚性约束**：每地址领取量固定（如 10 枚），总发行量由「有效地址数量 × 单次领取量」及邀请奖励规则决定，合约与根冻结后无法人为放大。

---

## 架构

### 合约组成

| 合约 | 作用 |
|------|------|
| **OZTToken** | ERC20 代币；仅 `claimContract` 可调用 `mintByClaim` 铸造。Owner 可一次性设置为领取合约后，再转至黑洞地址。 |
| **AirdropClaim** | 持有 Merkle 根（可设置一次并可冻结）。用户凭 Merkle 证明领取；可选邀请人绑定；为领取人及邀请人铸造；对二者调用 `ICommunityClaimJoin.claimJoin`。 |

### 接口

- **IOZTToken**：`mintByClaim(to, amount)`、`setClaimContractOnce(claimContract_)`。
- **ICommunityClaimJoin**：`claimJoin(account)` — 用于使领取人、邀请人加入链上群组。

### 领取后加入的群组（MerkelGroup Community）

接收领取人与邀请人的社区合约即 **MerkelGroup 的 [Community](../MerkelGroup/Community.sol)**。在该合约中：

- **`claimJoin(address account)`** 会将 `account` 以当前 epoch 的**最高 tier** 加入社区。该函数仅允许**领取操作员**（claim operator）列表中的地址调用（`onlyClaimOperator`）。
- Community 的 owner 必须调用 **`setClaimOperator(airdropClaim 地址, true)`**，将 AirdropClaim 合约设为领取操作员，否则 AirdropClaim 在领取时调用 `claimJoin` 会因权限不足而 revert。

因此：用户成功领取后，领取人与邀请人都会被加入该 Community 群组（与 Merkle 入群、房间等使用的是同一个 Community）。

### 部署顺序

1. 部署 **OZTToken**（name, symbol, initialOwner）。
2. 部署 **AirdropClaim**（owner, token, community, merkleRoot），其中 `community` 为 MerkelGroup **Community** 合约地址。
3. 在 **Community** 合约上调用 **setClaimOperator**(airdropClaim 地址, true)，使 AirdropClaim 有权调用 `claimJoin`。
4. 在 OZTToken 上调用 **setClaimContractOnce**(airdropClaim 地址)。
5. 在 AirdropClaim 中设置 Merkle 根（若构造时未设）；可选调用 **freezeMerkleRoot**。
6. （可选）将 OZTToken 的 **Owner** 转至黑洞地址，实现项目方完全放弃控制权。

### 示意图

**领取流程**

![领取流程](./images/claim.jpg)

**邀请流程**

![邀请流程](./images/invite.jpg)

---

## 合约说明

### AirdropClaim

- **构造**：`(initialOwner, token_, community_, merkleRoot_)` — `token_` 为 OZTToken，`community_` 为 MerkelGroup 的 Community（需在该 Community 上通过 `setClaimOperator` 将本合约设为领取操作员）；`merkleRoot_` 可为 `bytes32(0)` 后仅设置一次。
- **领取**：`claim(proof, inviter)` — `proof` 为 `msg.sender` 的 Merkle 证明（叶子 = `keccak256(abi.encode(msg.sender))`）；`inviter` 可为 `address(0)`。首次领取时可绑定邀请人且不可更改；领取人与邀请人获得奖励，并分别调用 `community.claimJoin`。
- **管理**：`setMerkleRoot`（仅在未设置过根且未冻结前）、`freezeMerkleRoot`、`setCommunity`、`setBlacklist`、`setInviterLimit`、`rescueERC20`。
- **视图**：`merkleRoot()`、`isClaimed(account)`、`inviterOf(invitee)`、`inviteeCount(inviter)`、`getInvitees(inviter, offset, limit)`。

### OZTToken

- **构造**：`(name_, symbol_, initialOwner)`。
- **一次性设置**：`setClaimContractOnce(claimContract_)` — 此后仅该领取合约可调用 `mintByClaim`。
- **铸造**：`mintByClaim(to, amount)` — 仅可由已设置的 `claimContract` 调用。

---

## 使用流程

1. **链下**：生成合格地址快照；构建默克尔树；公开叶子/树文件（如 GitHub）；计算根哈希。
2. **链上**：在 AirdropClaim 中设置根（或构造时传入）；可选冻结根；在 OZTToken 上设置领取合约；若做完整 OZT，将代币 Owner 转至黑洞地址。
3. **用户**：获取自己地址的 Merkle 证明；调用 `claim(proof, inviter)`；获得代币奖励；邀请人获得奖励；二者通过 `claimJoin` 加入社区。

---

## 安全

- **每地址仅可领取一次**：由 AirdropClaim 的 `_claimed` 保证。
- **Merkle 根**：仅可设置一次；冻结后不可再改。
- **邀请人绑定**：首次领取时确定后不可变更，避免邀请关系被篡改。
- **铸造权**：仅 AirdropClaim 在 `setClaimContractOnce` 后可为 OZTToken 铸造，且仅按规则向领取人及邀请人铸造。将代币 Owner 转至黑洞后，项目方无任何控制权（OZT）。
