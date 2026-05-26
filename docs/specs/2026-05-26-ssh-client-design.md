# Picshell — Flutter SSH Client with iTerm2 Image Support

## 概述

跨平台（iOS + Android）SSH 客户端，核心特性为支持 iTerm2 内联图片协议（ESC]1337），允许用户在终端中直接查看远程图片。

## 技术栈

- **框架**：Flutter 3.x
- **SSH**：dartssh2
- **终端渲染**：fork xterm_flutter，扩展图像协议支持
- **状态管理**：Riverpod
- **本地存储**：Hive

## 架构

```
┌───────────────────────────────────────────┐
│              Flutter App                  │
├──────────────┬────────────────────────────┤
│  UI Layer    │  Terminal Screen           │
│              │  ├── Tab Bar (多会话)      │
│              │  ├── Terminal Widget       │
│              │  │   ├── Text Canvas       │
│              │  │   └── Image Overlay     │
│              │  └── Host Manager Screen   │
├──────────────┼────────────────────────────┤
│  Service     │  SSH Service (dartssh2)    │
│  Layer       │  iTerm2 Parser             │
│              │  Agent Forward Service     │
│              │  Host Store (本地持久化)   │
├──────────────┼────────────────────────────┤
│  Platform    │  dartssh2 / dart:ffi       │
│  Layer       │  Hive                      │
└──────────────┴────────────────────────────┘
```

## 模块设计

### 1. 终端渲染（Fork xterm_flutter）

改造点：
- 在 output stream 解析层插入 iTerm2 转义序列拦截器
- 新增图像渲染层，将解码后的 `ui.Image` 绘制到终端 Canvas 对应行位置
- 支持滚动时图像跟随文本行移动

### 2. iTerm2 协议解析

协议格式：
```
ESC ] 1337 ; File = <key>=<value> ; <base64-data> BEL
```

支持的参数：
- `name` — 文件标识（分片拼接用）
- `size` — 原始字节数
- `width` / `height` — 显示尺寸（px / % / auto）
- `preserveAspectRatio` — 保持比例（0/1）
- `inline` — 内联显示（1）或下载（0）

处理流程：
1. 解析阶段：识别 ESC]1337; 前缀，提取参数和 Base64 payload
2. 分片拼接：按 `name` 聚合多个 chunk
3. 解码：Base64 → `ui.Image`
4. 渲染：在终端 Canvas 对应位置绘制图像

### 3. SSH 服务层

基于 dartssh2 封装：
- **连接管理**：连接/断开/重连
- **认证方式**：
  - 密码认证
  - SSH 密钥认证（本地生成或导入私钥）
  - Agent 转发（支持跳板机场景）
- **会话隔离**：每个标签页独立的 `SSHSession` 实例
- **数据流**：stdin/stdout 双向流，stdout 接入终端解析器

### 4. 多会话管理

- **标签页**：支持新建、关闭、切换；会话状态保存/恢复
- **主机收藏**：分组管理，支持快速连接
- **密钥管理**：本地存储 SSH 私钥，支持导入/删除

### 5. 数据存储

本地存储结构：
```
hosts: [
  {
    id: string,
    name: string,
    host: string,
    port: int,
    username: string,
    authType: password | key,
    keyId: string?,
    groupId: string?
  }
]

keys: [
  {
    id: string,
    name: string,
    privateKey: encrypted_string,
    publicKey: string
  }
]

sessions: [
  {
    id: string,
    hostId: string,
    lastActive: timestamp
  }
]
```

## 项目结构

```
lib/
├── app/
│   ├── app.dart
│   └── routes.dart
├── screens/
│   ├── terminal/
│   │   ├── terminal_screen.dart
│   │   └── terminal_tab_bar.dart
│   └── hosts/
│       ├── host_list_screen.dart
│       └── host_edit_screen.dart
├── widgets/
│   ├── terminal_widget/
│   │   ├── terminal_widget.dart      # fork 改造核心
│   │   └── iterm2_image_renderer.dart
│   └── image_viewer/
│       └── inline_image_widget.dart
├── models/
│   ├── host.dart
│   ├── ssh_key.dart
│   └── session.dart
├── services/
│   ├── ssh_service.dart
│   ├── agent_forward_service.dart
│   ├── iterm2_parser.dart
│   └── host_store.dart
└── utils/
    └── base64_stream_decoder.dart
```

## 开发阶段（建议顺序）

1. **基础终端** — Fork xterm_flutter，验证纯文本终端可正常工作
2. **SSH 连接** — dartssh2 封装，实现密码/密钥认证
3. **iTerm2 协议** — 拦截 ESC]1337，实现图片解码和渲染
4. **多会话** — 标签页管理
5. **主机管理** — 收藏、分组、密钥存储
6. **Agent 转发** — 跳板机支持

## 待定事项

- 图片缓存策略（内存限制、LRU 淘汰）
