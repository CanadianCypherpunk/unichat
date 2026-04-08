<div align="right">
  <a href="./README.md">English</a> ·
  <a href="./README.zh-CN.md"><strong>简体中文</strong></a>
</div>

<h1 align="center">密马.com 智能合约</h1>

<p align="center">
  面向去中心化社交平台的区块链通信与社区管理合约套件。
</p>

<p align="center">
  <a href="./README.md">
    <img alt="Language: English" src="https://img.shields.io/badge/Language-English-blue">
  </a>
  <a href="./README.zh-CN.md">
    <img alt="语言：简体中文" src="https://img.shields.io/badge/%E8%AF%AD%E8%A8%80-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-red">
  </a>
</p>

---

## 目录

- [概述](#概述)
- [合约模块](#合约模块)
- [架构](#架构)
- [技术栈](#技术栈)
- [核心功能](#核心功能)
- [快速开始](#快速开始)
- [部署指南](#部署指南)
- [应用场景示例](#应用场景示例)
- [安全](#安全)
- [贡献](#贡献)

## 概述

密马.com 是为 Web3 社交应用设计的模块化智能合约生态。它提供代币门控社区、链上消息、经济激励与去中心化治理等基础能力。

### 设计理念

**模块化**：每个合约模块解决一类问题，可独立使用或组合使用。

**可扩展**：通过 Merkle 树与最小代理实现省气设计，支持大量用户。

**灵活**：可配置参数，适配不同业务场景。

**安全**：基于久经考验的 OpenZeppelin 库，具备完善的访问控制。

### 可以构建什么？

- **代币门控社区**：要求用户持有指定代币才能加入
- **DAO 沟通平台**：链上消息与治理集成
- **NFT 持有者社区**：按 NFT 持有情况区分访问等级
- **社交金融（SoFi）应用**：聊天与代币奖励、分配结合
- **去中心化 Discord/Telegram**：抗审查的群组沟通

## 合约模块

### 🎁 RedPacketGroup
**用途**：带经济模型的代币门控社区

代币门控群组管理：入场费分配（9% 群主、21% 推荐人、70% 奖池）、子群层级、红包奖励、链上治理投票及完整管理工具。

**主要特性**：
- 入场费分成（9% 群主 / 21% 推荐人 / 70% 红包池）
- 三种红包类型（入场、普通、定时）
- 民主治理（主群 51%、子群 75% 投票）
- 子群管理，独立群主
- 限流、禁言与罚款
- 推荐追踪与排行榜

**适用场景**：投资俱乐部、DAO 社区、游戏公会、订阅群组

**文档**：[contract/RedPacketGroup/README.md](./contract/RedPacketGroup/README.md)

---

### 📨 DirectMessage
**用途**：私密 1 对 1 加密消息

链上点对点消息合约，对话历史永久存储在链上。支持 RSA 公钥注册实现端到端加密、黑名单、消息统计，以及与红包的无缝集成。

**主要特性**：
- 链上消息存储（单条最大 1KB）
- RSA 公钥注册与默认回退
- 黑名单（双向拉黑检查）
- 按时间段的消息统计
- 红包集成（随消息发送代币）
- 对话对象追踪

**适用场景**：去中心化聊天、协商平台、可验证沟通

**文档**：[contract/DirectMessage/README.md](./contract/DirectMessage/README.md)

---

### 🏘️ MerkelGroup
**用途**：基于 Merkle 树白名单的可扩展社区

使用 Merkle 树白名单验证的大规模社区管理，省气且支持大量成员；层级访问、嵌套房间、加密群消息与分布式密钥管理。

**主要特性**：
- Merkle 树白名单（省气）
- 按 Epoch 更新成员
- 等级体系（1–7 级，基于资产）
- 嵌套房间（大社区 → 小房间）
- RSA 群密钥分发
- 加密/明文消息

**适用场景**：NFT 持有者社区、分级会员、教育平台、大型 DAO

**文档**：[contract/MerkelGroup/README.md](./contract/MerkelGroup/README.md)

---

### 🧧 RedPacket
**用途**：独立代币发放系统

灵活的红包合约，支持个人与群组代币发放。基于推荐机制的代币白名单（质押 UNICHAT 上架代币）、可配置平台抽成、均分/随机分配算法，以及与聊天合约的集成。

**主要特性**：
- 个人红包（1 对 1 转账）
- 群红包（均分或随机）
- 通过 UNICHAT 质押的代币白名单
- 按代币可配置税率
- 过期与退款
- 与聊天合约集成

**适用场景**：代币空投、社区奖励、营销活动、游戏奖励

**文档**：[contract/RedPacket/README.md](./contract/RedPacket/README.md)

## 架构

### 系统概览

```
┌─────────────────────────────────────────────────┐
│           UniChat 智能合约套件                   │
└─────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ RedPacketGrp │ │ MerkleGroup  │ │DirectMessage │
│   生态       │ │   生态       │ │   合约       │
└──────────────┘ └──────────────┘ └──────────────┘
        │               │               │
        ├─Registry      ├─Factory       └─RSA 密钥
        ├─Factory       ├─Community        黑名单
        └─Group         └─Room             消息
                                            
                ┌──────────────┐
                │  RedPacket   │
                │   合约       │
                └──────────────┘
                     （共享）
```

### 集成模式

#### 模式 1：独立模块
```
DirectMessage（P2P 聊天）
    ↓ 可选
RedPacket（代币礼物）
```
简单点对点消息，可选代币转账。

#### 模式 2：社区 + 红包
```
MerkleGroup 社区
    ├─> 成员（Merkle 验证）
    ├─> 房间（嵌套聊天）
    └─> RedPacket（群组奖励）
```
大规模社区，带奖励与嵌套讨论。

#### 模式 3：经济型群组
```
RedPacketGroup
    ├─> 代币门控
    ├─> 入场费 → 红包
    ├─> 治理投票
    └─> 子群
```
带内置经济模型的代币门控社区。

#### 模式 4：完整集成
```
MerkleGroup 社区
    ├─> DirectMessage（成员间 P2P）
    ├─> RedPacket（空投）
    └─> 房间
            ├─> 群红包
            └─> 私密讨论
```
具备全部能力的完整社交平台。

## 技术栈

### 智能合约层

- **Solidity**：^0.8.24 - ^0.8.28
  - 现代语言特性
  - 自定义错误以节省 gas
  - 打包结构体优化存储

- **OpenZeppelin Contracts**：v5.x
  - `Ownable`：单所有者访问控制
  - `AccessControl`：基于角色的权限
  - `ReentrancyGuard`：重入保护
  - `Pausable`：紧急暂停
  - `SafeERC20`：安全代币交互
  - `MerkleProof`：白名单验证

### 设计模式

- **EIP-1167 最小代理**：省气的克隆
  - 用于：GroupFactory、CommunityFactory
  - 节省约 90% 部署 gas

- **工厂模式**：标准化合约创建
  - 可预测地址
  - 一致初始化
  - 与注册表集成

- **Merkle 树验证**：可扩展白名单
  - O(log n) 验证 gas
  - 单根存储
  - 保护隐私

### 存储优化

**打包结构体**：
```solidity
struct Member {
    bool exists;        // 1 字节
    uint64 joinAt;      // 8 字节  
    uint32 subgroupId;  // 4 字节
}                       // 总计：13 字节（一个槽位）
```

**带分页的动态数组**：
- 避免无界循环
- 省气的查询
- 便于前端使用

**基于映射的存储**：
- O(1) 查找
- 无需遍历
- 最小 gas 成本

## 核心功能

### 通信

#### 链上消息
- **永久存储**：消息永久保存在区块链
- **分页**：高效获取长对话历史
- **内容类型**：明文与加密消息
- **大小限制**：依合约不同约 280–2048 字节
- **元数据**：支持 IPFS CID 引用富内容

#### 加密支持
- **RSA 公钥**：链上密钥注册
- **客户端加密**：保护隐私
- **密钥轮换**：更新密钥不丢历史
- **群密钥**：通过 Merkle 树分发

#### 管理工具
- **黑名单**：用户自主拉黑
- **限流**：防刷（日/周限制）
- **禁言**：管理员临时静音
- **罚款**：经济惩罚（以 USDT 计）
- **踢出/封禁**：移除违规成员

### 代币经济

#### 入场费
```
新成员支付：100 代币
├─> 9% → 群主
├─> 21% → 推荐人（或平台）
└─> 70% → 红包池
    └─> 分发给现有成员
```

#### 红包
1. **入场红包**：加入时自动创建（入场费的 70%）
2. **普通红包**：用户创建，任意代币与金额
3. **定时红包**：每日自动发放（最长 365 天）

#### 分配算法
- **随机**：预分配金额，带随机因子
- **均分**：所有领取者平均分配
- **顺序**：先到先得领取

#### 代币白名单
- **核心代币**：平台批准（USDT、WETH 等）
- **社区代币**：通过 UNICHAT 质押添加
- **抽成**：按代币可配置平台费率

### 访问控制

#### 代币门控
- **余额检查**：须持有群组代币
- **验证合约**：自定义资格逻辑
- **最低持有量**：可配置阈值
- **多代币**：不同群可设不同代币

#### Merkle 树白名单
- **省气**：单根验证
- **隐私**：不暴露成员列表
- **可更新**：按 Epoch 刷新
- **分级**：1–7 级会员

#### 治理
- **主群选举**：需 51% 成员投票
- **子群选举**：75% 投票阈值
- **冷却期**：6 个月 / 4 年
- **即时生效**：达到阈值自动执行

### 层级与组织

#### RedPacketGroup 结构
```
主群（成员不限）
├─> 子群 1（成员子集）
├─> 子群 2（成员子集）
└─> 子群 N（成员子集）

入场费分成：
- 仅主群：9% 主群主
- 含子群：4.5% 主群 + 4.5% 子群
```

#### MerkleGroup 结构
```
社区（10,000+ 成员）
├─> 房间 1（10–50 人）
├─> 房间 2（10–50 人）
└─> 房间 N（10–50 人）

访问：社区成员资格 → 房间邀请
```

## 快速开始

### 环境要求

```bash
# 安装 Node.js 与 pnpm
node --version  # v18+
pnpm --version  # v8+

# 安装 Hardhat 或 Foundry
pnpm add --save-dev hardhat
# 或
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 安装

```bash
# 克隆仓库
git clone <repository-url>
cd unichat

# 安装依赖
pnpm install

# 编译合约
pnpm hardhat compile
# 或
forge build
```

### 运行测试

```bash
# Hardhat
pnpm hardhat test

# Foundry
forge test
```

### 部署合约

```bash
# 在 hardhat.config.js 中配置网络
# 在 .env 中配置私钥

# 部署到测试网
pnpm hardhat run scripts/deploy.js --network sepolia

# 在 Etherscan 验证
pnpm hardhat verify --network sepolia <CONTRACT_ADDRESS>
```

## 部署指南

### 1. RedPacketGroup 部署

```solidity
// 步骤 1：部署注册表
UniChatRegistry registry = new UniChatRegistry(
    unichatToken,
    usdtToken,
    bigOwner,
    platformOwner,
    treasury
);

// 步骤 2：部署群组实现
RedPacketGroup implementation = new RedPacketGroup();

// 步骤 3：部署工厂
GroupFactory factory = new GroupFactory(
    address(registry),
    address(implementation)
);

// 步骤 4：配置注册表
registry.setGroupFactory(address(factory));

// 步骤 5：白名单代币
registry.approveTokenListing(myToken, true);

// 步骤 6：创建群组
address group = factory.createGroup(
    myToken,
    100e18,
    "我的社区",
    "请互相尊重"
);
```

### 2. MerkleGroup 部署

```solidity
// 步骤 1：部署实现
Community communityImpl = new Community();
Room roomImpl = new Room();

// 步骤 2：部署工厂
CommunityFactory factory = new CommunityFactory(
    unichatToken,
    treasury,
    50e18,  // 房间创建费
    address(communityImpl),
    address(roomImpl)
);

// 步骤 3：创建社区
address community = factory.createCommunity(
    ownerAddr,
    topicToken,
    7,  // maxTier
    "NFT 持有者",
    "QmAvatar..."
);

// 步骤 4：设置 Merkle 根
Community(community).setMerkleRoot(root, "ipfs://...");
```

### 3. RedPacket 部署

```solidity
// 部署 RedPacket 合约
UniChatRedPacket redPacket = new UniChatRedPacket(
    unichatToken,
    treasury,
    360000,      // 默认 100 小时过期
    10000e18     // 1 万 UNICHAT 质押量
);

// 配置核心代币
redPacket.setCoreToken(usdtAddr, true, "QmUSDT...");
redPacket.setCoreToken(wethAddr, true, "QmWETH...");

// 设置税率
redPacket.setDefaultTaxRate(usdtAddr, 100);  // 1%
redPacket.setDefaultTaxRate(wethAddr, 50);   // 0.5%

// 白名单聊天合约
redPacket.setChatContract(directMessageAddr, true);
redPacket.setChatContract(communityAddr, true);
```

### 4. DirectMessage 部署

```solidity
// 使用默认 RSA 密钥部署
DirectMessage dm = new DirectMessage(
    platformOwner,
    defaultRSAPublicKey
);

// 关联 RedPacket
dm.setRedPacket(address(redPacket));
```

## 应用场景示例

### 示例 1：投资 DAO

```
组件：RedPacketGroup + RedPacket

配置：
- 群组代币：DAO 治理代币
- 入场费：1000 DAO 代币
- 子群：VIP（大户）、研究、交易

特性：
- 入场费即时奖励现有成员
- 子群内违规交易规则罚款
- 从金库的每日定时奖励
- 治理投票管理金库
```

### 示例 2：NFT 社区

```
组件：MerkleGroup + RedPacket

配置：
- 主题代币：NFT 合集地址
- 等级：1–5 基于 NFT 持有
- 房间：不同稀有度讨论

特性：
- Merkle 白名单（仅 NFT 持有者）
- 按等级的房间访问
- 向持有者发放红包空投
- 加密讨论房间
```

### 示例 3：P2P 市场

```
组件：DirectMessage + RedPacket

配置：
- 用户 A 挂单
- 用户 B 通过 DirectMessage 议价
- 通过个人红包付款
- 链上留存交易证明

特性：
- 永久议价记录
- 集成支付
- 通过消息历史解决纠纷
```

### 示例 4：游戏公会

```
组件：RedPacketGroup + MerkleGroup

配置：
- RedPacketGroup：主公会（入场费）
- MerkleGroup 社区：按游戏分组
- 子群：战队/小队

特性：
- 入场费注入奖池
- 按游戏的房间
- 随机红包赛
- 按表现升级等级
```

## 安全

### 审计状态

⚠️ **审计前**：本合约尚未经过审计，使用风险自负。

**主网上线前建议**：
1. 专业安全审计
2. 充分测试网部署
3. 漏洞赏金计划
4. 限额渐进上线

### 安全机制

#### 访问控制
- **基于角色**：OWNER、BIG_OWNER、成员等
- **修饰符**：`onlyOwner`、`onlyMember` 等
- **校验**：零地址、金额校验

#### 重入保护
- **nonReentrant**：所有外部代币交互
- **检查-效果-交互**：遵循该模式
- **先更新状态**：再外部调用

#### 输入校验
- **地址**：禁止零地址
- **金额**：禁止零金额（适用处）
- **数组边界**：分页限制
- **状态**：红包状态、成员状态

#### 应急控制
- **Pausable**：所有者可紧急暂停
- **BIG_OWNER**：平台管理员覆盖权限
- **提款**：所有者紧急提款函数

### 已考虑常见漏洞

✅ **重入**：所有代币转账使用 ReentrancyGuard  
✅ **整数溢出**：Solidity 0.8+ 内置检查  
✅ **访问控制**：完整角色检查  
✅ **抢跑**：视为链上特性接受  
✅ **拒绝服务**：分页避免无界循环  

### 用户建议

**群主**：
- 设置合理入场费
- 关注定时红包
- 积极管理
- 明确群规

**成员**：
- 核实群组真实性
- 理解经济模型
- 妥善保管私钥
- 举报异常行为

**开发者**：
- 在测试网充分测试
- 关注漏洞与依赖更新
- 遵循升级流程

## 贡献

欢迎贡献，可以从以下方面参与：

### 贡献方向

- **测试**：完善测试用例
- **文档**：改进说明与示例
- **优化**：Gas 优化建议
- **安全**：报告漏洞
- **功能**：提出或实现新功能

### 贡献流程

1. **Fork 仓库**：在 GitHub 创建你的 Fork
2. **创建分支**：`git checkout -b feature/amazing-feature`
3. **编写测试**：新代码需有测试覆盖
4. **遵循风格**：与现有代码风格一致
5. **提交**：使用约定式提交（feat/fix/docs）
6. **测试**：跑完整测试
7. **Pull Request**：提交并写清说明

### 代码风格

```solidity
// 推荐
function createPacket(
    address token,
    uint256 amount
) external nonReentrant returns (uint256 packetId) {
    require(amount > 0, "ZeroAmount");
    // ...
}

// 使用自定义错误
error ZeroAmount();
function createPacket(...) external {
    if (amount == 0) revert ZeroAmount();
}
```

### 测试要求

- 所有函数有单元测试
- 多合约流程有集成测试
- 覆盖边界情况
- Gas 优化测试
- 安全相关测试

## 许可证

MIT License，详见各合约文件。

Copyright (c) 2024 UniChat

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.

## 链接与资源

- **文档**：见各合约 README
- **GitHub**：<repository-url>
- **官网**：<project-website>
- **Discord**：<discord-invite>
- **Twitter**：<twitter-handle>

## 路线图

### 第一阶段：核心合约 ✅
- [x] RedPacketGroup 系统
- [x] MerkleGroup 系统
- [x] RedPacket 合约
- [x] DirectMessage 合约

### 第二阶段：增强（2024 Q2）
- [ ] NFT 门控群组
- [ ] 多代币入场费
- [ ] 高级治理模块
- [ ] 声誉系统

### 第三阶段：扩展（2024 Q3）
- [ ] Layer 2 部署（Arbitrum、Optimism）
- [ ] 跨链消息
- [ ] 移动端优化流程
- [ ] 无 gas 交易（meta-transactions）

### 第四阶段：生态（2024 Q4）
- [ ] DAO 金库管理
- [ ] 自动化做市
- [ ] AI 辅助管理
- [ ] 分析看板

## 支持

- **问题**：在 GitHub Issues 反馈
- **安全**：security@unichat.io（漏洞相关）
- **文档**：本 README 与合约文档
- **社区**：加入 Discord

---

**为 Web3 社交而建 ❤️**

**版本**：1.0.0  
**最后更新**：2024  
**网络兼容**：所有 EVM 兼容链
