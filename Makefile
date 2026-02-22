# ============================================================================
# 博客部署 Makefile
# ============================================================================
#
# 提供便捷的命令别名，简化日常操作
#
# 使用方法：
#   make deploy           # 完整部署（同步+构建+部署）
#   make sync            # 仅同步文件
#   make build           # 仅构建 Hugo
#   make preview         # 预览模式（dry-run）
#   make test            # 测试部署流程

.PHONY: help deploy sync build preview test clean check install

# 默认目标
.DEFAULT_GOAL := help

# 脚本路径
DEPLOY_SCRIPT := ./deploy.sh

# ============================================================================
# 主要命令
# ============================================================================

## help: 显示此帮助信息
help:
	@echo "博客部署 Makefile"
	@echo ""
	@echo "用法: make <目标>"
	@echo ""
	@echo "主要目标："
	@echo "  deploy       完整部署流程（同步→构建→部署）"
	@echo "  preview      Dry-run 预览模式"
	@echo "  sync        仅同步 Obsidian 文件"
	@echo "  build       仅构建 Hugo 站点"
	@echo "  test        测试部署（dry-run + verbose）"
	@echo ""
	@echo "配置管理："
	@echo "  config      创建配置文件（如果不存在）"
	@echo "  check       检查环境配置"
	@echo ""
	@echo "维护："
	@echo "  clean       清理发布目录（public/）"
	@echo "  install     安装/配置部署脚本"
	@echo ""
	@echo "示例："
	@echo "  make deploy --dry-run --verbose"
	@echo "  make sync DEPLOY_VERBOSE=true"

# ============================================================================
# 部署相关
# ============================================================================

## deploy: 完整部署流程（默认使用 deploy.sh）
deploy:
	@$(DEPLOY_SCRIPT) $(ARGS)

## preview: 预览模式（dry-run）
preview:
	@$(DEPLOY_SCRIPT) --dry-run --verbose $(ARGS)

## sync: 仅同步文件（跳过构建和部署）
sync:
	@$(DEPLOY_SCRIPT) --skip-git --build-only $(ARGS)

## build: 仅构建 Hugo（依赖已同步的文件）
build:
	@$(DEPLOY_SCRIPT) --skip-git --build-only $(ARGS)

## test: 测试部署流程（dry-run + verbose）
test:
	@$(DEPLOY_SCRIPT) --dry-run --verbose $(ARGS)

# ============================================================================
# 配置管理
# ============================================================================

## config: 创建配置文件（如果不存在）
config:
	@if [ ! -f deploy-config.toml ]; then \
		cp deploy-config.toml.example deploy-config.toml; \
		echo "✓ 配置文件已创建: deploy-config.toml"; \
		echo "  请根据需要编辑此文件"; \
	else \
		echo "⚠ 配置文件已存在，跳过创建"; \
	fi

## check: 检查环境和配置
check:
	@echo "=== 环境检查 ==="
	@echo ""
	@echo "1. 检查必要命令："
	@for cmd in git rsync hugo bash; do \
		if command -v $$cmd &>/dev/null; then \
			echo "  ✓ $$cmd"; \
		else \
			echo "  ✗ $$cmd (未安装)"; \
		fi \
	done
	@echo ""
	@echo "2. 检查配置文件："
	@if [ -f deploy-config.toml ]; then \
		echo "  ✓ deploy-config.toml 存在"; \
	else \
		echo "  ⚠ deploy-config.toml 不存在，使用默认配置"; \
		echo "   运行 'make config' 创建配置文件"; \
	fi
	@echo ""
	@echo "3. 检查目录："
	@if [ -d "/Users/xiuhao/Library/Mobile Documents/iCloud~md~obsidian/Documents/个人/posts" ]; then \
		echo "  ✓ 源目录存在"; \
	else \
		echo "  ✗ 源目录不存在"; \
	fi
	@if [ -d "content/posts" ]; then \
		echo "  ✓ 目标目录存在"; \
	else \
		echo "  ⚠ 目标目录不存在，将在首次同步时创建"; \
	fi
	@if [ -d "public" ]; then \
		echo "  ✓ public 目录存在"; \
	else \
		echo "  ⚠ public 目录不存在（首次构建将创建）"; \
	fi

# ============================================================================
# 维护命令
# ============================================================================

## clean: 清理发布目录
clean:
	@echo "清理 public 目录..."
	@rm -rf public/*
	@echo "✓ 清理完成"

## install: 安装和配置部署脚本
install:
	@echo "=== 部署脚本安装 ==="
	@echo ""
	@chmod +x deploy.sh && echo "✓ 设置执行权限"
	@$(MAKE) config
	@echo ""
	@echo "安装完成！"
	@echo ""
	@echo "下一步："
	@echo "  1. 编辑 deploy-config.toml 配置路径"
	@echo "  2. 运行 'make preview' 预览"
	@echo "  3. 运行 'make deploy' 部署"

# ============================================================================
# 开发辅助
# ============================================================================

## logs: 查看最近的部署日志（需要先配置日志重定向）
logs:
	@if [ -f /tmp/deploy.log ]; then \
		tail -f /tmp/deploy.log; \
	else \
		echo "未找到日志文件。建议使用重定向："; \
		echo "  make deploy >> /tmp/deploy.log 2>&1"; \
	fi

## watch: 监控笔记目录，文件变更时自动部署（需要 entr 工具）
watch:
	@which entr >/dev/null 2>&1 || { \
		echo "错误: 需要 entr 工具"; \
		echo "安装: brew install entr (macOS) 或 apt install entr (Linux)"; \
		exit 1; \
	}
	@echo "监控笔记目录，变更时自动部署..."
	@find "$(shell echo $$DEPLOY_SOURCE_PATH | sed 's/\//\\\//g')" -name "*.md" 2>/dev/null | entr -s $(DEPLOY_SCRIPT) $(ARGS)

# ============================================================================
# 便利别名
# ============================================================================

d: deploy        # 简写
p: preview       # 简写
s: sync          # 简写
b: build         # 简写
t: test          # 简写
