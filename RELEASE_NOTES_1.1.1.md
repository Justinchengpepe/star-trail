# 星迹 1.1.1

修复 1.1 开启 Hardened Runtime 后遗漏照片库访问声明的问题：部分用户即使在系统设置中允许访问，应用仍显示未授权。

- 签名加入 `com.apple.security.personal-information.photos-library`，保留 Hardened Runtime。
- 不修改动画、实况播放、图片清晰度和相册原图。
- 保留 1.1 的本机隐私缓存修复。

下载 `XingJi-1.1.1.zip`，支持 Apple Silicon 和 Intel，要求 macOS 15 或更高版本。

建议退出旧副本，将新应用放入“应用程序”目录后启动。系统可能将新签名识别为更新的应用，需要用户再次确认照片访问。此声明不绕过 macOS 授权，也不新增修改或删除相册的代码。

本版本仍为 ad-hoc 签名，未正式 Developer ID 签名、未公证、未启用 App Sandbox。不要绕过系统安全警告。详见仓库的隐私处理记录。

验证：两种架构签名均包含照片库声明；压缩包解压后的签名完整性通过。修复版启动后，由用户确认系统授权，并实际观察到图库加载成功。此验证不代替所有 macOS 版本和授权状态的测试。

安装包 SHA-256：`0ebd26d0d8ef8be3d3cf1cbd4ed0aba3c3aa600294fcf20a58f8b0149b4d292b`。
