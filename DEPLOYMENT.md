# 博客部署脚本 - 使用指南

## 📋 概述

`deploy.sh` 是一个全量优化的博客部署脚本，实现了从 Obsidian 到 Hugo 再到 GitHub Pages 的完整工作流。

### 核心功能

✅ **文件同步**：使用 rsync 将 Obsidian 笔记同步到 Hugo 内容目录
✅ **Git 管理**：自动初始化仓库、配置远程、提交更改
✅ **Hugo 构建**：生成静态网站到 public 目录
✅ **Hostinger 部署**：使用 git subtree 推送到 Hostinger 分支
✅ **智能检测**：自动检测文件变更，避免不必要的构建

---

## 🚀 快速开始

### 1. 初始设置

```bash
# 1. 克隆或复制脚本到你的 Hugo 项目根目录
# 文件已放在：deploy.sh

# 2. 复制配置文件示例
cp deploy-config.toml.example deploy-config.toml

# 3. 根据实际情况修改配置
vim deploy-config.toml
```

### 2. 基本用法

```bash
# 完整部署流程（同步 → 构建 → 部署）
./deploy.sh

# 预览操作（不实际执行）
./deploy.sh --dry-run

# 显示详细日志
./deploy.sh --verbose

# 仅构建（不部署）
./deploy.sh --build-only
```

---

## 📖 详细文档

### 命令行选项

| 选项 | 说明 |
|------|------|
| `-h, --help` | 显示帮助信息 |
| `-v, --version` | 显示版本号 |
| `-n, --dry-run` | 预览模式，不实际执行任何操作 |
| `-V, --verbose` | 显示详细日志（DEBUG 级别） |
| `--skip-hostinger` | 跳过 Hostinger 部署 |
| `--skip-git` | 跳过所有 Git 操作（仅同步和构建） |
| `--build-only` | 仅构建 Hugo，不进行部署 |

### 配置方式

配置支持三层优先级：

1. **脚本默认值**（最低优先级）
2. **配置文件**：`deploy-config.toml`（相对脚本目录）
3. **环境变量**（最高优先级）

#### 环境变量列表

```bash
# 路径配置
DEPLOY_SOURCE_PATH          # 源目录
DEPLOY_DESTINATION_PATH     # 目标目录
DEPLOY_HUGO_DIR            # Hugo 根目录
DEPLOY_PUBLIC_DIR          # 输出目录

# Git 配置
DEPLOY_GIT_REMOTE          # 远程仓库地址
DEPLOY_MAIN_BRANCH         # 主分支名（默认：main）

# 行为控制
DEPLOY_DRY_RUN             # 是否 dry-run (true/false)
DEPLOY_VERBOSE             # 是否详细日志 (true/false)
DEPLOY_ENABLE_HOSTINGER    # 是否启用 Hostinger (true/false)
DEPLOY_SKIP_IF_NO_CHANGES  # 无变更是否跳过 (true/false)
```

### 工作流程

```
┌─────────────────┐
│   Obsidian      │  (源文件)
└────────┬────────┘
         │ rsync
         ▼
┌─────────────────┐
│   Hugo content  │  (content/posts)
└────────┬────────┘
         │ hugo build
         ▼
┌─────────────────┐
│   Git commit    │  (提交到主分支)
└────────┬────────┘
         │ git push
         ▼
┌─────────────────┐
│   public/       │  (Hugo 输出)
└────────┬────────┘
         │ git subtree split
         ▼
┌─────────────────┐
│  Hostinger      │  (强制推送到 hostinger 分支)
└─────────────────┘
```

1. **同步文件**：`rsync -av --delete` 同步 Obsidian 笔记
2. **Git 提交**：自动提交更改（如果启用）
3. **Hugo 构建**：生成静态站点
4. **部署**：使用 `git subtree split` 分离 public 目录并推送到 hostinger 分支

---

## 🔧 配置详解

### 路径配置

```toml
# 源目录：Obsidian 笔记存放位置
source = "/Users/xiuhao/Library/Mobile Documents/iCloud~md~obsidian/Documents/个人/posts"

# 目标目录：Hugo content 目录下的 posts 子目录
destination = "content/posts"

# Hugo 项目根目录（包含 hugo.toml 的目录）
hugo_dir = "."

# 构建输出目录（通常是 public）
public_dir = "public"
```

**注意**：destination 是相对于 `hugo_dir` 的路径，也可以是绝对路径。

### Git 配置

```toml
# GitHub 远程仓库地址（SSH 格式）
git_remote = "git@github.com:whistleditty/whistleditty.github.io.git"

# 主分支名称（建议使用 main，不是 master）
main_branch = "main"

# Hostinger 部署分支名称（在 GitHub Actions 或其他服务中配置）
hostinger_branch = "hostinger"
```

### 部署选项

```toml
# 是否启用 Hostinger 部署（如果只用 GitHub Pages 可以设为 false）
enable_hostinger = true

# 如果文件未变更，是否跳过 Hugo 构建（提升性能）
skip_if_no_changes = true
```

---

## 🛡️ 安全特性

### 1. 错误处理

- 使用 `set -euo pipefail` 确保任何错误都会退出
- 所有关键步骤都有错误检查
- 自动生成唯一临时分支名，避免冲突

### 2. 资源清理

使用 `trap` 确保即使脚本中断也会：
- 删除临时分支
- 清理临时目录

### 3. 命令存在性检查

自动验证以下命令是否存在：
- `git`
- `rsync`
- `hugo`

缺失时会提供安装提示。

### 4. Dry-run 模式

使用 `--dry-run` 可以预览所有将要执行的操作，而不会实际修改任何文件或推送。

---

## 📊 与原版脚本对比

| 特性 | 原版 (sys.sh) | 新版 (deploy.sh) |
|------|-------------|-----------------|
| 模块化 | ❌ 单文件扁平 | ✅ 函数式模块 |
| 配置管理 | ❌ 硬编码 | ✅ 配置文件 + 环境变量 |
| 错误处理 | ⚠️ 基础 | ✅ 完善（trap、检查、回滚） |
| Dry-run | ❌ 不支持 | ✅ 完整支持 |
| 变更检测 | ❌ 总是构建 | ✅ 智能检测 |
| 日志系统 | ❌ echo 直接输出 | ✅ 分级彩色日志 |
| 资源清理 | ❌ 手动 | ✅ 自动 trap 清理 |
| 分支管理 | ⚠️ 可能冲突 | ✅ 唯一临时分支 |
| 向后兼容 | - | ✅ 保持原有功能 |
| 可维护性 | ⚠️ 低 | ✅ 高 |

---

## 🐛 故障排除

### 问题：rsync 同步失败

```bash
# 检查源目录是否存在
ls -la "$DEPLOY_SOURCE_PATH"

# 检查权限
chmod -R u+rw "$DEPLOY_SOURCE_PATH"
```

### 问题：Git push 失败

```bash
# 1. 检查 SSH 密钥是否正确配置
ssh -T git@github.com

# 2. 检查是否有推送权限
git remote -v

# 3. 强制推送会失败？检查分支保护规则
# 可能需要先拉取
git pull origin main --rebase
```

### 问题：Hugo 构建失败

```bash
# 检查 Hugo 版本
hugo version

# 检查配置文件语法
hugo config

# 尝试单独构建看错误信息
cd /Users/xiuhao/blog/hugosite
hugo --cleanDestinationDir
```

### 问题：Hostinger 部署失败

```bash
# 1. 确认 remote 配置正确
git remote -v

# 2. 检查是否有权限推送到 hostinger 分支
# 通常需要仓库配置允许 force push

# 3. 查看详细日志
DEPLOY_VERBOSE=true ./deploy.sh
```

### 启用详细日志

```bash
# 方法1：使用命令行参数
./deploy.sh --verbose

# 方法2：使用环境变量
DEPLOY_VERBOSE=true ./deploy.sh

# 方法3：临时修改脚本
# 在脚本中设置 LOG_LEVEL="DEBUG"
```

---

## 📝 迁移指南

如果原来使用 `sys.sh`，迁移步骤：

1. **备份原脚本**（推荐）
   ```bash
   mv sys.sh sys.sh.backup
   ```

2. **使用新脚本**
   ```bash
   # 首次需要复制配置
   cp deploy-config.toml.example deploy-config.toml
   # 修改部署配置

   # 测试 dry-run
   ./deploy.sh --dry-run --verbose

   # 确认无误后实际部署
   ./deploy.sh
   ```

3. **替代原脚本**
   ```bash
   # 如果想保留原名
   mv deploy.sh sys.sh.new
   # 然后使用 sys.sh.new 代替 sys.sh
   ```

---

## 🔧 高级用法

### 与 CI/CD 集成

```bash
#!/bin/bash
# .github/workflows/deploy.yml 中的步骤

- name: Deploy Blog
  env:
    DEPLOY_DRY_RUN: false
    DEPLOY_VERBOSE: true
    DEPLOY_GIT_REMOTE: ${{ secrets.GIT_REMOTE }}
  run: |
    chmod +x deploy.sh
    ./deploy.sh --build-only
```

### 定时自动部署

```bash
# crontab -e
0 */6 * * * /Users/xiuhao/blog/hugosite/deploy.sh --skip-hostinger >> /tmp/deploy.log 2>&1
```

### 自定义部署流程

```bash
# 只同步文件（最快）
./deploy.sh --skip-git --build-only

# 只部署不构建（构建步骤已手动完成）
./deploy.sh --skip-git
```

---

## 📄 文件清单

```
hugosite/
├── deploy.sh              # 主部署脚本（新）
├── deploy-config.toml     # 配置文件（需创建）
├── deploy-config.toml.example  # 配置示例
├── sys.sh                 # 原脚本（可保留为备份）
├── postsys.sh             # 原简化脚本
└── DEPLOYMENT.md          # 本文档
```

---

## 📜 许可证

本脚本基于原脚本优化，遵循 MIT 许可证。

---

## 🤝 贡献

如有问题或建议，欢迎提交 Issue 或 PR。

---

**最后更新**: 2025-02-22
**版本**: 2.0.0
