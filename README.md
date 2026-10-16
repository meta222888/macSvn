# SVN 访达菜单

在 macOS 访达右键中提供 **SVN 更新** 与 **SVN 提交**。菜单弹出时不访问版本库；点中菜单项后才调用本机 `svn`。

方案全文：[docs/需求方案书.md](docs/需求方案书.md)

## 要求

- macOS 13 及以上
- 本机已安装官方 `svn`（例如 `brew install svn`）
- Xcode（仅构建时需要）

## 构建并安装

```bash
./Scripts/build_and_install.sh
```

安装位置：`/Applications/SVN访达菜单.app`

## 使用

1. 打开「SVN 访达菜单」，确认已检测到 `svn`。
2. 添加工作副本目录。
3. 打开：系统设置 → 通用 → 登录项与扩展 → 访达扩展 → 打开「SVN 访达菜单」。
4. 如菜单未出现，在应用内点击「重新启动访达」。
5. 在已登记的工作副本内右键，选择「SVN 更新」或「SVN 提交」。

## 工程结构

| 路径 | 说明 |
| --- | --- |
| `App/` | 主应用：设置、提交窗口、结果窗口、`svn` 进程 |
| `FinderSync/` | 访达扩展：右键菜单 |
| `Shared/` | 设置读写、路径解析、待处理请求 |
| `Scripts/build_and_install.sh` | 生成工程、编译、签名、安装 |
