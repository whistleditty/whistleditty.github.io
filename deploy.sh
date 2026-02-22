#!/usr/bin/env bash
#
# 博客部署脚本 - 全量优化版
# 功能：同步 Obsidian 笔记 → Hugo 构建 → Git 提交 → Hostinger 部署
#
# 特性：
# - 模块化设计，单一职责
# - 支持配置文件和环境变量
# - Dry-run 模式预览操作
# - 智能变更检测，避免不必要的构建
# - 完善的错误处理和资源清理
# - 详细的日志系统
# - 向后兼容原有功能
#
# 作者：Claude Code 优化版
# 日期：2025-02-22

set -euo pipefail

# ============================================================================
# 全局变量
# ============================================================================

# 脚本元数据
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="2.0.0"

# 临时分支名称前缀（自动生成以避免冲突）
readonly TEMP_BRANCH_PREFIX="tmp-deploy-"

# 日志级别
readonly LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "SUCCESS")
LOG_LEVEL="INFO"

# 追踪已创建的资源（用于 cleanup）
RESOURCES_TO_CLEAN=()

# ============================================================================
# 配置变量（使用独立变量以兼容 Bash 3.2）
# ============================================================================

# 路径配置
CFG_SOURCE_PATH=""
CFG_DESTINATION_PATH=""
CFG_HUGO_DIR=""
CFG_PUBLIC_DIR=""

# Git 配置
CFG_GIT_REMOTE=""
CFG_MAIN_BRANCH=""
CFG_HOSTINGER_BRANCH=""
CFG_HOSTINGER_DEPLOY_BRANCH=""

# 部署配置
CFG_ENABLE_HOSTINGER=""
CFG_SKIP_IF_NO_CHANGES=""
CFG_DRY_RUN=""
CFG_VERBOSE=""

# Hugo 配置
CFG_HUGO_ENV=""

# ============================================================================
# 日志系统
# ============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # 检查日志级别
    local level_index=-1
    for i in "${!LOG_LEVELS[@]}"; do
        if [[ "${LOG_LEVELS[$i]}" == "$level" ]]; then
            level_index=$i
            break
        fi
    done

    if [[ $level_index -ge 0 ]]; then
        # 根据日志级别输出颜色
        case "$level" in
            "DEBUG")   echo -e "\033[36m[${timestamp}] [${level}] ${message}\033[0m" ;;
            "INFO")    echo -e "\033[32m[${timestamp}] [${level}] ${message}\033[0m" ;;
            "WARN")    echo -e "\033[33m[${timestamp}] [${level}] ${message}\033[0m" ;;
            "ERROR")   echo -e "\033[31m[${timestamp}] [${level}] ${message}\033[0m" >&2 ;;
            "SUCCESS") echo -e "\033[32m[${timestamp}] [${level}] ${message}\033[0m" ;;
            *)         echo "[${timestamp}] [${level}] ${message}" ;;
        esac
    fi
}

log_debug() { [[ "${CFG_VERBOSE}" == "true" ]] && log "DEBUG" "$@" || true; }
log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# ============================================================================
# 工具函数
# ============================================================================

# 打印脚本标题
print_header() {
    echo "========================================================================"
    echo "  ${SCRIPT_NAME} v${VERSION}"
    echo "  博客自动化部署脚本"
    echo "========================================================================"
    echo ""
}

# 打印配置信息
print_config() {
    log_info "当前配置："
    log_debug "  源路径: ${CFG_SOURCE_PATH}"
    log_debug "  目标路径: ${CFG_DESTINATION_PATH}"
    log_debug "  Hugo目录: ${CFG_HUGO_DIR}"
    log_debug "  Git远程仓库: ${CFG_GIT_REMOTE}"
    log_debug "  主分支: ${CFG_MAIN_BRANCH}"
    log_debug "  Hostinger分支: ${CFG_HOSTINGER_BRANCH}"
    log_debug "  启用Hostinger: ${CFG_ENABLE_HOSTINGER}"
    log_debug "  无变更跳过: ${CFG_SKIP_IF_NO_CHANGES}"
    log_debug "  Dry-run: ${CFG_DRY_RUN}"
    echo ""
}

# 添加清理资源
add_cleanup() {
    local resource_type=$1
    local resource_name=$2
    RESOURCES_TO_CLEAN+=("$resource_type:$resource_name")
}

# 清理资源（trap调用）
cleanup() {
    local exit_code=$?
    if [[ ${#RESOURCES_TO_CLEAN[@]} -gt 0 ]]; then
        log_info "清理临时资源..."
        for resource in "${RESOURCES_TO_CLEAN[@]}"; do
            IFS=':' read -r type name <<<"$resource"
            case "$type" in
                "branch")
                    log_debug "删除临时分支: $name"
                    git branch -D "$name" 2>/dev/null || true
                    ;;
                "temp_dir")
                    log_debug "删除临时目录: $name"
                    rm -rf "$name" 2>/dev/null || true
                    ;;
            esac
        done
    fi

    if [[ $exit_code -eq 0 ]]; then
        log_success "脚本执行完成"
    else
        log_error "脚本执行失败，退出码: $exit_code"
    fi
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        log_error "命令未找到: $cmd"
        log_error "请安装后再试："
        case "$cmd" in
            "hugo")   log_error "  - Hugo: https://gohugo.io/installation/" ;;
            "git")    log_error "  - Git: https://git-scm.com/downloads" ;;
            "rsync")  log_error "  - rsync: 通常系统自带，或使用包管理器安装" ;;
            "python3") log_error "  - Python3: https://www.python.org/downloads/" ;;
        esac
        return 1
    fi
    log_debug "✓ 命令检查通过: $cmd"
    return 0
}

# ============================================================================
# 配置加载
# ============================================================================

# 加载配置文件（如果存在）
load_config() {
    local config_file="${SCRIPT_DIR}/deploy-config.toml"

    # 设置默认值
    CFG_SOURCE_PATH="/Users/xiuhao/Library/Mobile Documents/iCloud~md~obsidian/Documents/个人/posts"
    CFG_DESTINATION_PATH="${SCRIPT_DIR}/content/posts"
    CFG_HUGO_DIR="${SCRIPT_DIR}"
    CFG_PUBLIC_DIR="${SCRIPT_DIR}/public"
    CFG_GIT_REMOTE="git@github.com:whistleditty/whistleditty.github.io.git"
    CFG_MAIN_BRANCH="master"
    CFG_HOSTINGER_BRANCH="hostinger"
    CFG_HOSTINGER_DEPLOY_BRANCH="hostinger-deploy"
    CFG_ENABLE_HOSTINGER="false"
    CFG_SKIP_IF_NO_CHANGES="true"
    CFG_DRY_RUN="false"
    CFG_VERBOSE="false"
    CFG_HUGO_ENV="production"

    if [[ -f "$config_file" ]]; then
        log_info "加载配置文件: $config_file"

        # 简单的 TOML 解析（避免依赖外部工具）
        while IFS='=' read -r key value; do
            # 跳过注释和空行
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue

            # 去除空格和引号
            key="$(echo "$key" | xargs)"
            value="$(echo "$value" | xargs | sed "s/^[\"']//;s/[\"']$//")"

            # 只处理我们关心的配置
            case "$key" in
                "source"|"source_path") CFG_SOURCE_PATH="$value" ;;
                "destination"|"destination_path") CFG_DESTINATION_PATH="$value" ;;
                "hugo_dir") CFG_HUGO_DIR="$value" ;;
                "public_dir") CFG_PUBLIC_DIR="$value" ;;
                "git_remote") CFG_GIT_REMOTE="$value" ;;
                "main_branch") CFG_MAIN_BRANCH="$value" ;;
                "hostinger_branch") CFG_HOSTINGER_BRANCH="$value" ;;
                "enable_hostinger") CFG_ENABLE_HOSTINGER="$value" ;;
                "skip_if_no_changes") CFG_SKIP_IF_NO_CHANGES="$value" ;;
                "hugo_env") CFG_HUGO_ENV="$value" ;;
            esac
        done < <(grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=' "$config_file" 2>/dev/null || true)
    fi

    # 环境变量覆盖（优先级最高）
    [[ -n "${DEPLOY_SOURCE_PATH:-}" ]] && CFG_SOURCE_PATH="$DEPLOY_SOURCE_PATH"
    [[ -n "${DEPLOY_DESTINATION_PATH:-}" ]] && CFG_DESTINATION_PATH="$DEPLOY_DESTINATION_PATH"
    [[ -n "${DEPLOY_GIT_REMOTE:-}" ]] && CFG_GIT_REMOTE="$DEPLOY_GIT_REMOTE"
    [[ -n "${DEPLOY_MAIN_BRANCH:-}" ]] && CFG_MAIN_BRANCH="$DEPLOY_MAIN_BRANCH"
    [[ -n "${DEPLOY_ENABLE_HOSTINGER:-}" ]] && CFG_ENABLE_HOSTINGER="$DEPLOY_ENABLE_HOSTINGER"
    [[ -n "${DEPLOY_SKIP_IF_NO_CHANGES:-}" ]] && CFG_SKIP_IF_NO_CHANGES="$DEPLOY_SKIP_IF_NO_CHANGES"
    [[ -n "${DEPLOY_HUGO_ENV:-}" ]] && CFG_HUGO_ENV="$DEPLOY_HUGO_ENV"
    [[ -n "${DEPLOY_DRY_RUN:-}" ]] && CFG_DRY_RUN="$DEPLOY_DRY_RUN"
    [[ -n "${DEPLOY_VERBOSE:-}" ]] && CFG_VERBOSE="$DEPLOY_VERBOSE"

    # 路径规范化：如果 Hugo 目录没有绝对路径，将其转换为绝对路径
    if [[ "${CFG_HUGO_DIR}" != /* ]]; then
        CFG_HUGO_DIR="${SCRIPT_DIR}/${CFG_HUGO_DIR}"
    fi

    # 同样处理 destination 路径
    if [[ "${CFG_DESTINATION_PATH}" != /* ]]; then
        CFG_DESTINATION_PATH="${CFG_HUGO_DIR}/${CFG_DESTINATION_PATH}"
    fi

    # 同样处理 public 目录
    if [[ "${CFG_PUBLIC_DIR}" != /* ]]; then
        CFG_PUBLIC_DIR="${CFG_HUGO_DIR}/${CFG_PUBLIC_DIR}"
    fi
}

# ============================================================================
# 验证函数
# ============================================================================

# 验证目录存在
validate_directories() {
    log_info "验证目录..."

    # 检查源目录
    if [[ ! -d "${CFG_SOURCE_PATH}" ]]; then
        log_error "源目录不存在: ${CFG_SOURCE_PATH}"
        return 1
    fi
    log_debug "✓ 源目录存在: ${CFG_SOURCE_PATH}"

    # 检查目标父目录
    local dest_parent="$(dirname "${CFG_DESTINATION_PATH}")"
    if [[ ! -d "$dest_parent" ]]; then
        log_warn "目标父目录不存在，尝试创建: $dest_parent"
        if [[ "${CFG_DRY_RUN}" != "true" ]]; then
            mkdir -p "$dest_parent"
        fi
    fi

    # 确保 Hugo 目录存在
    if [[ ! -d "${CFG_HUGO_DIR}" ]]; then
        log_error "Hugo 目录不存在: ${CFG_HUGO_DIR}"
        return 1
    fi
    log_debug "✓ Hugo 目录存在: ${CFG_HUGO_DIR}"

    return 0
}

# 验证必要的命令
validate_commands() {
    log_info "验证必要的命令..."

    local required_cmds=("git" "rsync" "hugo")
    for cmd in "${required_cmds[@]}"; do
        if ! check_command "$cmd"; then
            return 1
        fi
    done

    # 检查 Hugo 版本
    local hugo_version
    hugo_version="$(hugo version | head -n1 || echo "unknown")"
    log_debug "Hugo 版本: $hugo_version"

    return 0
}

# ============================================================================
# 文件同步模块
# ============================================================================

# 计算文件的 MD5 哈希（用于检测变更）
calculate_file_hash() {
    local file=$1
    if command -v md5 &>/dev/null; then
        md5 -q "$file" 2>/dev/null
    elif command -v md5sum &>/dev/null; then
        md5sum "$file" | awk '{print $1}'
    else
        # 回退到 stat
        stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo "0"
    fi
}

# 检测是否有文件变更
has_file_changes() {
    log_info "检测文件变更..."

    # 使用 rsync dry-run 来检测变更
    local dry_run_output
    if [[ "${CFG_DRY_RUN}" == "true" ]]; then
        log_debug "Dry-run 模式：跳过变更检测"
        return 0
    fi

    # 确保目标目录存在
    if [[ ! -d "${CFG_DESTINATION_PATH}" ]]; then
        log_debug "目标目录不存在，需要同步"
        return 0
    fi

    # rsync dry-run 检查是否有文件需要同步
    dry_run_output=$(rsync -avn --delete "${CFG_SOURCE_PATH}/" "${CFG_DESTINATION_PATH}/" 2>&1)

    if [[ -n "$dry_run_output" ]]; then
        log_info "检测到文件变更"
        log_debug "变更详情："
        echo "$dry_run_output" | while IFS= read -r line; do
            log_debug "  $line"
        done
        return 0
    else
        log_info "未检测到文件变更"
        return 1
    fi
}

# 同步文件
sync_files() {
    log_info "开始同步文件..."
    log_info "  从: ${CFG_SOURCE_PATH}"
    log_info "  到: ${CFG_DESTINATION_PATH}"

    if [[ "${CFG_DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN 模式：不执行实际同步"
        log_info "执行的命令: rsync -avn --delete ${CFG_SOURCE_PATH}/ ${CFG_DESTINATION_PATH}/"
        rsync -avn --delete "${CFG_SOURCE_PATH}/" "${CFG_DESTINATION_PATH}/" || true
        return 0
    fi

    # 执行同步
    if rsync -av --delete "${CFG_SOURCE_PATH}/" "${CFG_DESTINATION_PATH}/"; then
        local sync_count
        sync_count=$(rsync -av --dry-run --delete "${CFG_SOURCE_PATH}/" "${CFG_DESTINATION_PATH}/" 2>&1 | grep -c '^[<>]' || echo "0")
        log_success "文件同步完成（$sync_count 个文件）"
        return 0
    else
        log_error "文件同步失败"
        return 1
    fi
}

# ============================================================================
# Git 操作模块
# ============================================================================

# 初始化 Git 仓库
init_git_repo() {
    log_info "检查 Git 仓库状态..."

    if [[ ! -d "${CFG_HUGO_DIR}/.git" ]]; then
        log_info "初始化 Git 仓库..."
        if [[ "${CFG_DRY_RUN}" == "true" ]]; then
            log_warn "DRY-RUN: 跳过 Git 初始化"
            return 0
        fi

        cd "${CFG_HUGO_DIR}"
        if git init; then
            log_success "Git 仓库初始化完成"
            add_cleanup "branch" "$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"
        else
            log_error "Git 初始化失败"
            return 1
        fi
    fi

    # 检查并添加远程仓库
    cd "${CFG_HUGO_DIR}"
    if ! git remote | grep -q '^origin$'; then
        log_info "添加远程仓库: ${CFG_GIT_REMOTE}"
        if [[ "${CFG_DRY_RUN}" != "true" ]]; then
            git remote add origin "${CFG_GIT_REMOTE}"
        fi
    fi

    return 0
}

# 检查是否有 Git 变更
has_git_changes() {
    local dir=$1

    if [[ "${CFG_DRY_RUN}" == "true" ]]; then
        return 0
    fi

    cd "$dir"
    if git diff --quiet && git diff --cached --quiet; then
        return 1
    else
        return 0
    fi
}

# 提交 Git 更改
commit_changes() {
    local dir=$1
    local commit_message=$2

    log_info "提交更改..."
    cd "$dir"

    if [[ "${CFG_DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN: 跳过 Git 提交"
        return 0
    fi

    # 显示状态
    git status --short || return 1

    # 添加所有更改
    if ! git add -A; then
        log_error "Git add 失败"
        return 1
    fi

    # 检查是否有更改需要提交
    if git diff --cached --quiet; then
        log_info "没有需要提交的更改"
        return 0
    fi

    # 提交
    if git commit -m "$commit_message"; then
        log_success "提交成功"
        return 0
    else
        log_error "提交失败"
        return 1
    fi
}

# 推送到主分支
push_main_branch() {
    log_info "推送到 ${CFG_MAIN_BRANCH} 分支..."

    cd "${CFG_HUGO_DIR}"

    if [[ "${CFG_DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN: 跳过推送到主分支"
        return 0
    fi

    # 确保在正确的分支上
    local current_branch
    current_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"
    if [[ "$current_branch" != "${CFG_MAIN_BRANCH}" ]] && [[ -n "$current_branch" ]]; then
        log_info "切换到分支: ${CFG_MAIN_BRANCH}"
        git checkout "${CFG_MAIN_BRANCH}" 2>/dev/null || {
            log_warn "分支 ${CFG_MAIN_BRANCH} 不存在，创建新分支"
            git checkout -b "${CFG_MAIN_BRANCH}"
        }
    fi

    # 拉取最新更改
    if git remote | grep -q 'origin'; then
        log_debug "拉取远程更改..."
        git pull origin "${CFG_MAIN_BRANCH}" --rebase || {
            log_warn "拉取失败，可能是远程有新提交，尝试推送..."
        }
    fi

    # 推送
    if git push origin "${CFG_MAIN_BRANCH}"; then
        log_success "推送到 ${CFG_MAIN_BRANCH} 成功"
        return 0
    else
        log_error "推送到 ${CFG_MAIN_BRANCH} 失败"
        return 1
    fi
}

# ============================================================================
# Hugo 构建模块
# ============================================================================

# 构建 Hugo 站点
build_hugo() {
    log_info "构建 Hugo 站点..."

    # 检查是否需要构建（跳过未变更的情况）
    if [[ "${CFG_SKIP_IF_NO_CHANGES}" == "true" ]]; then
        if ! has_file_changes; then
            log_info "文件未变更，跳过 Hugo 构建"
            return 0
        fi
    fi

    cd "${CFG_HUGO_DIR}"

    # 设置环境变量
    export HUGO_ENV="${CFG_HUGO_ENV}"
    export HUGO_TITLE="${CFG_HUGO_TITLE:-我的数字花园}"

    log_info "执行 Hugo 构建（环境: $HUGO_ENV）..."

    if [[ "${CFG_DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN: 跳过 Hugo 构建"
        log_info "执行的命令: HUGO_ENV=$HUGO_ENV hugo"
        return 0
    fi

    # 清理 public 目录（可选，Hugo 默认会清理）
    if [[ -d "${CFG_PUBLIC_DIR}" ]]; then
        log_debug "清理 public 目录..."
        rm -rf "${CFG_PUBLIC_DIR}"/*
    fi

    if hugo --cleanDestinationDir; then
        log_success "Hugo 构建完成，输出到: ${CFG_PUBLIC_DIR}"
        return 0
    else
        log_error "Hugo 构建失败"
        return 1
    fi
}

# ============================================================================
# Hostinger 部署模块
# ============================================================================

# 部署到 Hostinger 分支
deploy_to_hostinger() {
    if [[ "${CFG_ENABLE_HOSTINGER}" != "true" ]]; then
        log_info "Hostinger 部署已禁用"
        return 0
    fi

    log_info "开始部署到 Hostinger..."

    cd "${CFG_HUGO_DIR}"

    if [[ "${CFG_DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN: 跳过 Hostinger 部署"
        if [[ -d "${CFG_PUBLIC_DIR}/.git" ]]; then
            log_info "检测到 public 是独立 Git 仓库，将执行: (cd public && git add -A && git commit -m 'Deploy' && git push origin ${CFG_HOSTINGER_BRANCH})"
        else
            log_info "将执行: git subtree split --prefix public -b <branch>"
            log_info "将执行: git push origin <branch>:${CFG_HOSTINGER_BRANCH} --force"
        fi
        return 0
    fi

    # 检测 public 是否为独立的 Git 仓库（常见配置）
    if [[ -d "${CFG_PUBLIC_DIR}/.git" ]]; then
        log_debug "检测到 public 是独立 Git 仓库，使用独立仓库部署方式"

        cd "${CFG_PUBLIC_DIR}"

        # 检查是否有更改
        if git diff --quiet && git diff --cached --quiet; then
            log_info "public 仓库无更改，跳过部署"
            return 0
        fi

        # 添加所有更改
        git add -A || {
            log_error "public git add 失败"
            return 1
        }

        # 提交
        if git diff --cached --quiet; then
            log_info "public 仓库无需要提交的更改"
        else
            if ! git commit -m "自动化部署: ${SCRIPT_NAME} on $(date +'%Y-%m-%d %H:%M:%S')"; then
                log_error "public 仓库提交失败"
                return 1
            fi
            log_success "public 仓库提交成功"
        fi

        # 确保在正确的分支上
        local current_branch
        current_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"
        if [[ "$current_branch" != "${CFG_HOSTINGER_BRANCH}" ]] && [[ -n "$current_branch" ]]; then
            log_info "切换到分支: ${CFG_HOSTINGER_BRANCH}"
            git checkout "${CFG_HOSTINGER_BRANCH}" 2>/dev/null || {
                log_warn "分支 ${CFG_HOSTINGER_BRANCH} 不存在，创建新分支"
                git checkout -b "${CFG_HOSTINGER_BRANCH}"
            }
        fi

        # 推送到远程
        log_info "推送到 ${CFG_HOSTINGER_BRANCH} 分支..."
        if git push origin "${CFG_HOSTINGER_BRANCH}"; then
            log_success "Hostinger 部署成功（独立仓库模式）"
            return 0
        else
            log_error "Hostinger 部署失败（独立仓库模式）"
            return 1
        fi
    else
        log_debug "使用 git subtree split 传统方式"

        # 生成唯一的临时分支名
        local timestamp
        timestamp="$(date +%Y%m%d-%H%M%S)"
        local temp_branch="${TEMP_BRANCH_PREFIX}${timestamp}"
        add_cleanup "branch" "$temp_branch"

        # 删除可能存在的旧临时分支
        if git branch --list | grep -q "^  ${temp_branch}$"; then
            git branch -D "$temp_branch" 2>/dev/null || true
        fi

        # 使用 git subtree split 从 public 目录创建分支
        log_debug "创建 subtree 分支: $temp_branch"
        if ! git subtree split --prefix public -b "$temp_branch"; then
            log_error "Subtree split 失败"
            return 1
        fi

        # 强制推送到 hostinger 分支
        log_info "推送到 ${CFG_HOSTINGER_BRANCH} 分支..."
        if git push origin "$temp_branch:${CFG_HOSTINGER_BRANCH}" --force; then
            log_success "Hostinger 部署成功"
        else
            log_error "Hostinger 部署失败"
            git branch -D "$temp_branch" 2>/dev/null || true
            return 1
        fi

        # 清理临时分支
        git branch -D "$temp_branch" 2>/dev/null || true
        RESOURCES_TO_CLEAN=("${RESOURCES_TO_CLEAN[@]/"branch:$temp_branch"/}")

        return 0
    fi
}

# ============================================================================
# 主流程
# ============================================================================

# 显示用法
show_usage() {
    cat << EOF
用法: $SCRIPT_NAME [选项]

博客自动化部署脚本 - 将 Obsidian 笔记同步并部署到 GitHub Pages

选项:
  -h, --help          显示此帮助信息
  -v, --version       显示版本信息
  -n, --dry-run       预览操作，不实际执行
  -V, --verbose       显示详细日志
  --skip-hostinger    跳过 Hostinger 部署
  --skip-git          跳过 Git 操作（仅同步和构建）
  --build-only        仅构建，不进行部署

示例:
  $SCRIPT_NAME              # 完整部署流程
  $SCRIPT_NAME --dry-run    # 预览将要执行的操作
  $SCRIPT_NAME --build-only # 仅构建 Hugo 站点

配置文件:
  在脚本目录创建 deploy-config.toml 可以自定义配置：
    source = "/路径/到/笔记"
    destination = "content/posts"
    git_remote = "git@github.com:用户/仓库.git"
    main_branch = "main"

环境变量:
  DEPLOY_SOURCE_PATH       覆盖源路径
  DEPLOY_GIT_REMOTE        覆盖 Git 远程仓库
  DEPLOY_DRY_RUN           设置为 true 启用 dry-run
  DEPLOY_VERBOSE           设置为 true 启用详细日志

EOF
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME v${VERSION}"
                exit 0
                ;;
            -n|--dry-run)
                CFG_DRY_RUN="true"
                shift
                ;;
            -V|--verbose)
                CFG_VERBOSE="true"
                LOG_LEVEL="DEBUG"
                shift
                ;;
            --skip-hostinger)
                CFG_ENABLE_HOSTINGER="false"
                shift
                ;;
            --skip-git)
                CFG_SKIP_GIT="true"
                shift
                ;;
            --build-only)
                CFG_BUILD_ONLY="true"
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 主函数
main() {
    # 设置 trap 确保清理
    trap cleanup EXIT INT TERM

    # 打印标题
    print_header

    # 解析参数
    parse_args "$@"

    # 加载配置
    load_config

    # 打印配置
    print_config

    # 验证
    if ! validate_commands; then
        exit 1
    fi

    if ! validate_directories; then
        exit 1
    fi

    # 步骤 1: Git 初始化（如果启用）
    if [[ "${CFG_SKIP_GIT:-false}" != "true" ]]; then
        if ! init_git_repo; then
            log_error "Git 初始化失败"
            exit 1
        fi

        # 步骤 2: 提交到主分支
        if commit_changes "${CFG_HUGO_DIR}" "自动化部署: ${SCRIPT_NAME} on $(date +'%Y-%m-%d %H:%M:%S')"; then
            push_main_branch || log_warn "推送到主分支失败，继续后续流程..."
        fi
    else
        log_info "跳过 Git 操作"
    fi

    # 步骤 3: 同步文件
    if ! sync_files; then
        log_error "文件同步失败"
        exit 1
    fi

    # 步骤 4: 构建 Hugo
    if ! build_hugo; then
        log_error "Hugo 构建失败"
        exit 1
    fi

    # 步骤 5: 部署到 Hostinger（如果启用且不是仅构建模式）
    if [[ "${CFG_BUILD_ONLY:-false}" != "true" ]]; then
        if ! deploy_to_hostinger; then
            log_error "Hostinger 部署失败"
            exit 1
        fi
    else
        log_info "仅构建模式，跳过部署"
    fi

    log_success "所有任务完成！"
    exit 0
}

# 运行主函数
main "$@"
