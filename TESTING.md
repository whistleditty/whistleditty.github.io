# 博客部署脚本测试指南

## 📋 目录

1. [快速测试流程](#快速测试流程)
2. [详细测试场景](#详细测试场景)
3. [错误注入测试](#错误注入测试)
4. [性能测试](#性能测试)
5. [自动化测试脚本](#自动化测试脚本)

---

## 🚀 快速测试流程（5分钟）

### 步骤 1：语法检查（必做）

```bash
# 检查 Bash 语法
bash -n deploy.sh && echo "✓ 语法检查通过"

# 或使用 Make
make check
```

**预期**：无输出或 "✓ 语法检查通过"

---

### 步骤 2：基本功能测试

```bash
# 1. 查看版本
./deploy.sh --version

# 2. 查看帮助
./deploy.sh --help

# 3. Dry-run 预览（最安全）
./deploy.sh --dry-run --verbose 2>&1 | head -50
```

**预期**：
- 版本显示 `deploy.sh v2.0.0`
- 帮助信息正常显示
- Dry-run 显示将要执行的操作，但不实际执行

---

### 步骤 3：完整流程测试（谨慎）

```bash
# 第一次务必在非工作时间或备份后执行
./deploy.sh --verbose
```

**观察点**：
1. ✅ 同步文件：从 Obsidian 同步 `.md` 文件
2. ✅ Hugo 构建：生成 `public/` 目录
3. ✅ Git 提交：提交到主分支
4. ✅ 推送到 GitHub：`main` 分支
5. ✅ Hostinger 部署：`hostinger` 分支更新

---

## 📊 详细测试场景

### 场景 1：首次部署（全新仓库）

**条件**：新克隆的仓库或未部署过的环境

```bash
# 备份当前状态
git status
# 确保 working directory 干净

# 执行完整部署
./deploy.sh --verbose
```

**预期**：
- 检测到 Git 未初始化 → 初始化并配置 origin
- 同步 Obsidian 文件到 `content/posts/`
- Hugo 构建生成 `public/`
- 首次提交所有文件
- 推送到 `main` 和 `hostinger` 分支

**验证**：
```bash
git log --oneline -3
ls public/ | head -10
git remote -v
```

---

### 场景 2：无变更部署（测试智能检测）

**条件**：两次连续执行，中间没有修改笔记

```bash
# 第一次部署（有变更）
./deploy.sh --verbose 2>&1 | grep -E "(Hugo|变更|跳过)"

# 等待 10 秒
sleep 10

# 第二次部署（应跳过构建）
./deploy.sh --verbose 2>&1 | grep -E "(Hugo|变更|跳过)"
```

**预期输出**：
```
第一次：检测到文件变更 → 执行 Hugo 构建
第二次：文件未变更，跳过 Hugo 构建
```

**性能对比**：
```bash
time ./deploy.sh --skip-hostinger  # 有变更
time ./deploy.sh --skip-hostinger  # 无变更
```

---

### 场景 3：仅新增博客文章

**条件**：在 Obsidian 新建 1 篇 Markdown 文件

```bash
# 1. 在 Obsidian 中添加测试文章
#    例如：测试文章 2025-02-22-test.md

# 2. 执行部署（使用 --build-only 先测试）
./deploy.sh --build-only --verbose

# 3. 验证文章已同步
ls content/posts/ | grep test

# 4. 验证 Hugo 生成
ls public/posts/ | grep test

# 5. 完整部署
./deploy.sh --verbose
```

**预期**：
- 新文件被同步到 `content/posts/`
- Hugo 生成对应的 HTML 到 `public/posts/`
- Git 提交包含新文件
- 部署成功

---

### 场景 4：修改已有文章

**条件**：修改一篇已发布的博客内容

```bash
# 1. 修改一篇旧文章（例如修改标题或内容）

# 2. 部署（仅构建模式测试）
./deploy.sh --build-only --verbose 2>&1 | grep -A 5 "Hugo"

# 3. 检查 Git diff
git diff --name-only HEAD~1 HEAD
```

**预期**：
- 修改的文件被同步
- Hugo 重新构建该页面
- Git 记录修改

---

### 场景 5：删除文章

**条件**：在 Obsidian 中删除一篇博客

```bash
# 1. 在 Obsidian 中删除文件（或移动到其他位置）

# 2. 执行完整部署
./deploy.sh --dry-run --verbose 2>&1 | grep "deleting"

# 3. 确认后执行真实部署
./deploy.sh --verbose
```

**预期**：
- rsync 使用 `--delete` 同步删除
- Hugo 重新构建时删除对应页面
- Git 记录删除

---

### 场景 6：跳过特定阶段

**测试每个跳过选项**：

```bash
# 跳过 Hostinger 部署（仅同步+构建+Git）
./deploy.sh --skip-hostinger --verbose

# 跳过 Git 操作（仅同步+构建）
./deploy.sh --skip-git --verbose

# 仅构建（不部署）
./deploy.sh --build-only --verbose

# 完全只预览
./deploy.sh --dry-run --verbose
```

**验证**：
```bash
# 检查 Git 状态（skip-git 应无变化）
git status

# 检查 public 是否生成（build-only 应生成）
ls public/

# 检查 hostinger 分支未更新
git ls-remote origin hostinger
```

---

### 场景 7：配置文件测试

```bash
# 1. 创建自定义配置
cat > test-config.toml << 'EOF'
source = "/tmp/test-notes"
destination = "content/test"
git_remote = "git@github.com:test/test.git"
main_branch = "master"
enable_hostinger = false
EOF

# 2. 使用环境变量指定配置
DEPLOY_SOURCE_PATH="/tmp/test-notes" ./deploy.sh --dry-run

# 3. 验证配置加载
DEPLOY_VERBOSE=true ./deploy.sh --help 2>&1 | grep "源路径"
```

**预期**：环境变量覆盖配置文件

---

## 🐛 错误注入测试

### 测试 1：源目录不存在

```bash
# 临时修改配置指向不存在的目录
DEPLOY_SOURCE_PATH="/tmp/does-not-exist-12345" ./deploy.sh --dry-run

# 或修改配置文件
vim deploy-config.toml  # 设置错误的 source 路径
./deploy.sh --dry-run
```

**预期输出**：
```
[ERROR] 源目录不存在: /tmp/does-not-exist-12345
[ERROR] 脚本执行失败，退出码: 1
```

---

### 测试 2：Hugo 命令不存在

```bash
# 临时从 PATH 移除 hugo
PATH=/tmp ./deploy.sh --dry-run
```

**预期**：
```
[ERROR] 命令未找到: hugo
[ERROR] 请安装后再试：
[ERROR]   - Hugo: https://gohugo.io/installation/
```

---

### 测试 3：Git 推送失败

```bash
# 方法 1：配置错误的 Git 远程
DEPLOY_GIT_REMOTE="git@github.com:invalid/repo.git" ./deploy.sh --verbose

# 方法 2：断开网络后测试
# (拔网线或关闭 WiFi，然后快速执行)
./deploy.sh --verbose
```

**预期**：
```
[ERROR] 推送到 main 失败
[ERROR] 脚本执行失败，退出码: 1
```

**恢复后**：重试应能成功

---

### 测试 4：文件权限问题

```bash
# 1. 使目标目录只读
chmod -w content/posts/

# 2. 尝试同步
./deploy.sh --dry-run
```

**预期**：
```
[ERROR] 文件同步失败
[ERROR] 脚本执行失败，退出码: 1
```

**恢复**：
```bash
chmod -R u+w content/posts/
```

---

### 测试 5：中断测试（Ctrl+C）

```bash
# 1. 在长时间运行的步骤中按下 Ctrl+C
#    建议执行完整部署时，在 "Hugo 构建中" 中断

# 2. 观察清理行为
#    预期：临时分支被删除
git branch | grep tmp-deploy
```

**预期**：
```
[INFO] 清理临时资源...
[DEBUG] 删除临时分支: tmp-deploy-...
[SUCCESS] 脚本执行完成  # 即使中断也会清理
```

---

### 测试 6：配置文件语法错误

```bash
# 创建有错误的配置文件
cat > deploy-config.toml << 'EOF'
source = "/path/to/source
destination = "content/posts"  # 缺少引号
EOF

./deploy.sh --dry-run
```

**预期**：脚本应能容忍某些错误，使用默认值继续

---

## ⚡ 性能测试

### 基准测试：有变更 vs 无变更

```bash
# 准备环境
./deploy.sh --skip-hostinger  # 确保 baseline

# 测试 1：有变更（新建或修改文件）
time ./deploy.sh --skip-hostinger 2>&1 | tail -1

# 测试 2：无变更（立即重复）
time ./deploy.sh --skip-hostinger 2>&1 | tail -1

# 测试 3：仅同步（skip-git + build-only）
time ./deploy.sh --skip-git --build-only 2>&1 | tail -1
```

**预期结果示例**：
```
有变更：real 0m15.23s  (完整流程)
无变更：real 0m1.05s   (跳过 Hugo)
仅同步：real 0m0.35s   (最快)
```

---

### 文件数量影响测试

```bash
# 创建大量测试文件
for i in {1..100}; do
    cp content/posts/example.md "content/posts/test-$i.md"
done

# 测试同步时间
time ./deploy.sh --skip-git --build-only 2>&1 | grep "文件同步完成"

# 清理测试文件
rm content/posts/test-*.md
```

**预期**：线性增长，rsync 效率高

---

## 🔍 日志验证

### 验证日志级别

```bash
# 默认级别（INFO）
./deploy.sh --dry-run 2>&1 | grep "\[INFO\]" | wc -l

# 详细级别（DEBUG）
./deploy.sh --dry-run --verbose 2>&1 | grep "\[DEBUG\]" | wc -l
# 应该比默认多很多 DEBUG 行
```

---

### 验证彩色输出

```bash
# 保存带颜色的输出
./deploy.sh --dry-run --verbose > /tmp/output.txt 2>&1

# 检查是否包含 ANSI 颜色码
cat /tmp/output.txt | grep -o "\033\[[0-9;]*m" | sort -u
```

**预期**：能看到 `\033[32m` (绿色)、`\033[36m` (青色) 等

---

## 📈 Makefile 测试

```bash
# 测试所有 make 目标
make help          # 查看帮助
make config        # 创建配置
make check         # 环境检查
make preview       # 预览模式
make sync          # 仅同步
make build         # 仅构建
make test          # 测试运行
make deploy        # 完整部署（谨慎！）

# 测试别名
make d    # 同 make deploy
make p    # 同 make preview
make s    # 同 make sync
```

---

## 🧪 自动化测试脚本

创建一个自动化测试脚本 `test-deploy.sh`：

```bash
#!/bin/bash
# test-deploy.sh - 自动化测试脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOG="/tmp/deploy-test-$(date +%Y%m%d-%H%M%S).log"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

test_count=0
pass_count=0
fail_count=0

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected="$3"

    test_count=$((test_count + 1))
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "测试 #$test_count: $test_name"
    echo "命令: $test_cmd"

    if eval "$test_cmd" 2>&1 | tee -a "$TEST_LOG" | grep -q "$expected"; then
        echo -e "${GREEN}✓ 通过${NC}"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "${RED}✗ 失败${NC}"
        fail_count=$((fail_count + 1))
        return 1
    fi
}

# 主测试流程
{
    echo "测试开始: $(date)"
    echo "测试日志: $TEST_LOG"
    echo ""

    cd "$SCRIPT_DIR"

    # 测试组 1：基础功能
    run_test "版本号输出" "./deploy.sh --version" "v2.0.0"
    run_test "帮助信息" "./deploy.sh --help" "用法:"
    run_test "语法检查" "bash -n deploy.sh" ""

    # 测试组 2：配置加载
    run_test "配置文件存在" "test -f deploy-config.toml || echo 'using defaults'" "deploy-config.toml"
    run_test "环境变量覆盖" "DEPLOY_DRY_RUN=true ./deploy.sh --version 2>&1" "v2.0.0"

    # 测试组 3：命令检查
    run_test "Git 可用" "command -v git" "git"
    run_test "rsync 可用" "command -v rsync" "rsync"
    run_test "bash 版本" "bash --version | head -1" "bash"

    # 测试组 4：目录验证
    run_test "脚本目录存在" "test -d '$SCRIPT_DIR'" "true"
    run_test "源目录检查" "DEPLOY_SOURCE_PATH='/nonexistent' ./deploy.sh --dry-run 2>&1" "源目录不存在"

    # 测试组 5：Dry-run 模式
    run_test "Dry-run 预览" "./deploy.sh --dry-run --verbose 2>&1" "DRY-RUN"
    run_test "无错误退出" "./deploy.sh --dry-run" "脚本执行完成"

    # 测试组 6：实际部署（谨慎！）
    read -p "是否进行实际部署测试？这将修改 Git 和文件系统 (y/N): " confirm
    if [[ "$confirm" == "y" ]]; then
        run_test "完整部署流程" "./deploy.sh --verbose" "所有任务完成"
    fi

} | tee -a "$TEST_LOG"

# 测试报告
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试报告"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "总计: $test_count"
echo -e "通过: ${GREEN}$pass_count${NC}"
echo -e "失败: ${RED}$fail_count${NC}"
echo ""
echo "详细日志: $TEST_LOG"

if [[ $fail_count -eq 0 ]]; then
    echo -e "${GREEN}所有测试通过！✓${NC}"
    exit 0
else
    echo -e "${RED}有 $fail_count 个测试失败${NC}"
    exit 1
fi
```

**使用方法**：
```bash
chmod +x test-deploy.sh
./test-deploy.sh
```

---

## 🔬 边界情况测试

### 测试 1：路径包含空格

你的源路径包含空格：
```
/Users/xiuhao/Library/Mobile Documents/iCloud~md~obsidian/...
```

**验证**：
```bash
# 脚本应该正确处理
./deploy.sh --dry-run --verbose 2>&1 | grep "Mobile Documents"
```

**预期**：正常处理，无引号错误

---

### 测试 2：文件名包含特殊字符

```bash
# 创建带特殊字符的文件名（如果 Obsidian 中有）
ls "content/posts/" | grep -E "[\#\$\%\&\*]"

# 同步应保留原文件名
./deploy.sh --dry-run --verbose 2>&1 | grep "特殊字符"
```

---

### 测试 3：空文件处理

```bash
# 创建空 Markdown 文件
touch content/posts/empty-test.md

# 部署
./deploy.sh --dry-run --verbose

# 验证 rsync 处理空文件
./deploy.sh --verbose 2>&1 | grep "empty-test"
```

---

### 测试 4：大文件处理

```bash
# 创建一个大文件（例如 100MB）
dd if=/dev/zero of=content/posts/large-test.md bs=1M count=100

# 测试同步
time ./deploy.sh --skip-git --build-only

# 清理
rm content/posts/large-test.md
```

---

## 🎯 测试检查清单

### 必测项（每次改代码都要测）

- [ ] 语法检查通过 `bash -n deploy.sh`
- [ ] 版本显示正确 `./deploy.sh --version`
- [ ] Dry-run 无错误 `./deploy.sh --dry-run`
- [ ] 配置文件加载正常
- [ ] 同步文件功能正常
- [ ] Hugo 构建成功
- [ ] Git 提交成功
- [ ] Hostinger 部署成功

### 功能项（新功能需测）

- [ ] `--skip-hostinger` 跳过部署
- [ ] `--skip-git` 跳过 Git
- [ ] `--build-only` 仅构建
- [ ] `--verbose` 显示 DEBUG 日志
- [ ] Dry-run 真的不执行操作
- [ ] 环境变量覆盖配置
- [ ] 独立仓库模式（public/.git 存在）
- [ ] 传统模式（git subtree split）
- [ ] 无变更时跳过构建

### 边界项（特殊场景）

- [ ] 源目录不存在 → 正确报错
- [ ] 目标目录不存在 → 自动创建
- [ ] 首次部署（无 Git 仓库）
- [ ] 分支不存在 → 自动创建
- [ ] Ctrl+C 中断 → 清理临时资源
- [ ] 路径包含空格 → 正确处理
- [ ] 文件名含特殊字符 → 正确处理

---

## 📊 测试报告模板

```
测试日期: 2025-02-22
测试环境: macOS 14.0 / Bash 3.2.57
脚本版本: v2.0.0

基础功能:
✓ 语法检查
✓ 版本输出
✓ 帮助信息
✓ Dry-run 预览
✓ 完整流程部署

性能测试:
- 有变更部署: 14.32s
- 无变更部署: 1.05s
- 仅同步: 0.35s

错误处理:
✓ 源路径不存在检测
✓ 命令不存在提示
✓ 中断资源清理

部署模式:
✓ 独立仓库模式（public/.git）
✓ 传统模式（git subtree）

得分: 15/15 (100%)
```

---

## 🐛 已知问题

1. **public/.git 状态**：
   - 如果 `public/` 已经是独立仓库，脚本会进入独立部署模式
   - 确保 `public/.git/config` 有正确的远程地址

2. **中文路径**：
   - 源路径含中文字符已验证通过
   - 如果遇到编码问题，设置 `export LANG=zh_CN.UTF-8`

3. **rsync 权限**：
   - 确保源目录可读
   - 确保目标目录可写

4. **Git 分支**：
   - 远程默认分支建议为 `main`（通过 `main_branch` 配置可覆盖）
   - 如果使用 `master`，需修改配置

---

## 📞 问题反馈

如遇到测试未覆盖的场景：

1. 记录完整错误输出：`./deploy.sh --verbose 2>&1 | tee error.log`
2. 记录环境信息：`bash --version && hugo version && git --version`
3. 检查配置：`cat deploy-config.toml`
4. 提交 Issue 时附上以上信息

---

## ✅ 测试确认清单

在正式使用前，请确认：

- [ ] 已阅读 `DEPLOYMENT.md`
- [ ] 已复制 `deploy-config.toml.example` 为 `deploy-config.toml`
- [ ] 已编辑配置（如需修改路径）
- [ ] 已执行 `./deploy.sh --dry-run --verbose` 验证
- [ ] 已了解 `Makefile` 快捷命令
- [ ] 已备份原脚本 `sys.sh` 和 `postsys.sh`
- [ ] 已了解如何回滚（Git 历史）

---

**开始测试**：从快速测试流程的步骤 1 开始！
