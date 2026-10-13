# review.md 处理记录

## 1.1.1 权限回归修复

发布 1.1 后，真实使用发现系统设置允许照片访问但应用仍报告未授权。核验正在运行的下载包后，确认其启用了 Hardened Runtime，却没有任何资源访问 entitlement。补上 `com.apple.security.personal-information.photos-library` 并在构建结束检查 arm64 和 x86_64 的实际签名，避免仅检查源码或签名完整性而遗漏功能权限。此前“构建通过”不能视为实际图库访问验证通过。

本修复不关闭 Hardened Runtime，不启用其他资源权限，不加入照片修改/删除调用；不将 Photos Library entitlement 冒充沙箱或系统授权。依据：[Apple Photos Library Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.photos-library)。

实际验证：修复版进程来自本地 1.1.1 构建路径；用户确认图库出现，随后从实时应用状态确认照片加载成功。压缩包解压后校验两种架构的 entitlement 和签名完整性通过。

1.1.1 安装包 SHA-256：`0ebd26d0d8ef8be3d3cf1cbd4ed0aba3c3aa600294fcf20a58f8b0149b4d292b`；主程序 SHA-256：`702d6aaf199ad12aa2351317346aa33c462dba6339363b486b3ebfd7dc91d01f`。这些指纹与下方早期版本不同。

日期：2026-10-13（北京时间）。依据用户提供的 v1.0 静态审查，核对当前工作区后修改。未改动原审查文件，也未发布或更新 GitHub 下载包。

v1.1 发布准备：应用版本 1.1，构建号 2。以下历史校验值对应隐私修复时的本地构建；发布包以本节指纹为准：

- `XingJi-1.1.zip` SHA-256：`493cae59bbea8f4b39dc37d52466be9522b2e733286a7b0ea06c6d817a929da4`。
- v1.1 主程序 SHA-256：`f0fd9cc95ff4678698e7e10474cfe0c2d1c38f8e0fdf152348c73030c4e03954`。

## 已落实到本地源码

1. 主题缓存改为 v4，只持久化主题和置信度；Vision 标签和原始 OCR 文字只保留在当前进程内存。重启后的文字搜索需要重新识别。
2. 首次运行迁移 v2/v3，只保留可用主题、置信度和手动分类，移除旧偏好键。不会恢复旧 OCR，亦不声称清除了系统备份中的历史副本。
3. 星迹菜单增加“删除全部分析数据…”及不可撤销确认，清理主题、手动分类、识别文字、事件名称、SQLite 全部记录和内存缩略图；显示成功/失败结果。原始 Photos 资产不受影响。
4. SQLite 清理执行 secure_delete、VACUUM、WAL 截断；清理代际使旧后台任务不能回写。索引生成暂停，可通过菜单重新建立。
5. 刷新时重新读取权限，剔除不再授权的主题和事件名称；撤权时取消请求和分析、停止实况、关闭大图并清空显示状态。系统层撤权场景尚需隔离账户验证。
6. 本地构建开启 Hardened Runtime，保留下载隔离标记；不再在 README 中建议用 xattr -cr 绕过 Gatekeeper。支持指定已有 Developer ID Application 签名身份。

## 验证范围

- 用独立 UserDefaults 域的虚构文字测试迁移、幂等性、手动分类保留、OCR 不持久化和清除，不读取真实用户偏好内容。
- 通过不注册 PhotoKit 观察器、不枚举真实图库的模型实例测试授权状态下清理和拒绝授权后的状态清空。这是应用逻辑测试，不能替代真实 TCC 撤权测试。
- 临时 SQLite 测试清理、跨连接读取、旧任务回写拒绝及后续新写入。
- arm64/x86_64 编译、签名完整性与 Hardened Runtime 标志检查。
- 未自动打开新版执行真实旧缓存迁移，也未替用户确认删除全部分析数据。

## 仍未完成／不应宣称已完成

- Developer ID 正式身份签名与 Apple 公证：需要发布凭据及公证流程；默认本地包仍为 ad-hoc。
- App Sandbox：尚未启用，需要验证 PhotoKit/iCloud、偏好和数据库容器迁移，再制定最小权限配置。
- 本机仅下载开关、运行时网络抓包、隔离账户的 iCloud 与撤权实测。
- 事件名称/主题仍是本机未加密的派生数据；本次没有实现加密数据库。
- 系统备份、旧发布 ZIP、旧应用副本及已移除功能的其他磁盘目录未自动删除。
- 不宣称应用“绝对安全”“完全离线”或已从运行时证明从不外传。

## 本次构建校验

- 本地工作区基于 `f087a5d902ef0389517fe59ced22f882fdc28462`，包含尚未提交的功能与隐私修复；不将旧提交冒充本次完整源码版本。
- 临时测试输出：`Workflow checks passed: events, browsing, static click, privacy migration, OCR non-persistence, cache reset, denied-access reset, SQLite clearing and stale-write rejection`。
- 通用主程序 SHA-256：`f0925730fdcc2427632a6340c88734153a5d92457700c0941044e3a384861b00`。此值对应本地构建，不对应公开 v1.0 ZIP。
- 签名检查显示 `flags=0x10002(adhoc,runtime)`、`TeamIdentifier=not set`；严格完整性校验通过。仅移除影响校验的 FinderInfo/ResourceFork，未递归清除全部扩展属性。
- 没有启动新版对真实偏好执行迁移，没有点击真实数据删除确认。首次启动会移除旧 OCR 偏好副本并保留手动主题；所有分析数据清除仍需用户在应用中确认。

依据：[Apple UserDefaults 说明](https://developer.apple.com/documentation/Foundation/UserDefaults)、[Apple 公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
