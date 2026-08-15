# PR 合并指南与注意事项

> 生成于 2026-08-14。适用对象：5 个功能 PR（#3–#7）+ 依赖 PR（#2 tier2）。
> 集成验证：`integration/all-features` 本地分支，223 通过 + 3 skipped（SOCKS 无 sshd 时真 skip），`flutter analyze lib/` 零 error 零 warning。

## PR 总览

| PR | 分支 | base | 功能 | 状态 |
|---|---|---|---|---|
| #2 | `feat/ssh-tier2` | master | 端口转发 / ProxyJump / ssh config 导入 | open |
| #3 | `feat/appearance` | master | 配色方案 + 字体/字号/行高 | open |
| #4 | `feat/socks-dynamic` | `feat/ssh-tier2` | SOCKS5 动态转发 (`ssh -D`) | open |
| #5 | `feat/biometric-unlock` | master | 生物识别解锁 + 凭据加密 | open |
| #6 | `feat/terminal-search` | master | 滚动搜索 Ctrl+F | open |
| #7 | `feat/graphics-protocols` | master | Kitty + Sixel 图形协议 | open |

所有分支均已 push 且与 origin 同步（ahead=0 behind=0）。
`integration/all-features` 仅在本地（未 push），作为合并参考与全量验证用。

## 集成时出现过的冲突（复现过两次，必现）

| 文件 | 冲突双方 | 解法 |
|---|---|---|
| `lib/providers/settings_provider.dart` | #3 appearance 字段 vs #5 biometric 字段 | 两套字段合并（palette/fontFamily/fontSize/lineHeight + requireBiometric/relockOnBackground）；冲突 6 处，手写整文件最稳 |
| `lib/screens/settings/settings_screen.dart` | #3 公共 `SectionHeader` + Appearance 区段 / #5 Security 区段 / #2 SSH import 区段 | 三个区段都保留，统一用公共 `SectionHeader`；imports 取并集（host_store、ssh_config_parser 两个 unused import 已在源分支删除，不要再引入） |
| `lib/main.dart` | #2 的 `forward_rule` 导入 vs #5 的 vault 导入 | imports 并集 |
| `lib/widgets/terminal_widget/terminal_widget.dart` | #3 theme/textStyle vs #6 搜索栏（两边都重写了 build） | search 的 Stack 结构 + appearance 的 theme/textStyle 一起传给 TerminalView |
| `lib/services/host_store.dart` | #5 代际 box 重写 vs #2 的 `copyWith` 用法 | staging 拷贝用 `host.copyWith()`——同时保证 HiveObject 单 box 约束 + 保留 proxyHostId/forwards 字段 |

> 手动解冲突拿不准时，对照本地 `integration/all-features` 分支的最终文件抄。

## 合并顺序

1. **先合 #2（tier2）→ 再合 #4（SOCKS）**（#4 base 就是 tier2）。
2. #3/#5/#6/#7 base 都是 master，顺序无强制；但每合一个，后面 PR 会显示新冲突，需逐个本地解（见上表）。
3. GitHub "Update branch" 只能自动解无重叠文件；上表 4 个文件必然手动解。

## 特别注意

### feat/appearance 是 force-push 过的
rebase 到 master 剔除了捆绑的 tier2 提交。本地旧副本需：
```bash
git fetch && git checkout feat/appearance && git reset --hard origin/feat/appearance
```
旧 SHA（`1b926c3`）已作废。

### #5 的数据格式变化（发布注意）
- 代际 box：host/key 记录存 `hosts_gN`/`ssh_keys_gN`，活跃代际在 `vault_meta` box 的单个 int。
- **升级安全**：init 自动把旧 `hosts`/`ssh_keys` 迁移为 gen 1（有测试覆盖 legacy 迁移）。
- **降级不安全**：升级后再装回旧版 app，旧版读不到新 box 名 → hosts 显示为空。发布后建议不支持 downgrade。
- reEncryptAll 现为代际事务化：全量暂存到 g(N+1) → 单次原子 put 翻转代际 → 删旧 box。崩溃任意点均保持一致。

### #5 密钥存储加固
- iOS/macOS：`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`（无备份/迁移，需设备已设密码且解锁）。
- Android：`EncryptedSharedPreferences`。
- ⚠️ **未设设备密码的设备**上 keychain 项不可写——理论上此类设备 `canAuthenticate` 也是 false 走不到该路径，但值得真机确认。

### 平台构建
#5 改了 Android `MainActivity`（→ `FlutterFragmentActivity`）+ `USE_BIOMETRIC` 权限，iOS 加 `NSFaceIDUsageDescription`，macos 新增 `Podfile` 及各平台 plugin registrants。合并后首次构建：
```bash
flutter pub get
cd ios && pod install && cd ..   # macos 同理
```

### 真机验证清单（自动化未覆盖）
- [ ] FaceID/TouchID 提示 + `flutter_secure_storage` 读写（含无密码设备行为，见上）
- [ ] 真实 `kitty icat` 冒烟（sixel 已有真实 img2sixel fixture 测试，kitty 侧仍是构造字节）
- [ ] JetBrains Mono 的 CJK fallback 表现
- [ ] SOCKS：连真实 sshd 后 `curl --socks5 127.0.0.1:<port>` 冒烟
- [ ] macOS 沙盒下 local_auth 行为（若桌面在支持范围）

## 已知的后续工作（review 记录在案、明确推迟）

- #5：OS 级生物识别绑定密钥（`SecAccessControl(biometryAny)` / `CryptoObject`）——local_auth 2.x 不暴露，需换方案
- #5：`relockOnBackground` 目前仅 UI 门（内存中密钥与 provider 缓存明文不清除）
- #7：Kitty f=24/32 原始像素路径未实现（需 PNG 编码接入 Kitty handler）
- #7：PNG 编码器用 `dart:io`（native-only；iTerm2/Kitty-PNG 路径不受影响）
- 全局：设置页 i18n 已统一英文，真正的 i18n 层待做
- 终端连字（ligatures）需重写 xterm painter（设置里有禁用占位开关）

## 测试运行备注

- SOCKS 集成测试需要 sshd 在 `127.0.0.1:2222`（`picshell-sshd:local` 镜像）：
  ```bash
  docker run -d --rm --name picshell-sshd-run -p 2222:22 picshell-sshd:local
  flutter test test/services/forward_listener_socks_test.dart
  docker stop picshell-sshd-run
  ```
  无 sshd 时 3 个测试真 skip（非 vacuous pass）。
- Sixel fixture 测试需要 `test/fixtures/`（已入库，无需本地工具）。
- widget 测试中 Hive 相关 setter 需 `tester.runAsync`（fake-async 死锁）；Hive 测试用 `setUpAll` init（Hive 缓存 home 目录）。
