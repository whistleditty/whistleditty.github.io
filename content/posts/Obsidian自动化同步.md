+++
title = 'Obsidian自动化同步'
date = 2024-12-21T17:10:58+08:00
draft = false
+++

`你好你好你好 2024-12-21 20:30:57`

<!--more-->
成功了吗？
再试一次  
成功了！  

把代码贴上来好了：
```sh
#!/bin/bash
set -euo pipefail  # 设置严格的错误处理模式，遇到任何错误都会退出脚本

# Change to the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 获取并切换到脚本所在的目录
cd "$SCRIPT_DIR"

# Set variables for Obsidian to Hugo copy
sourcePath="/Users/xiuhao/Library/Mobile Documents/iCloud~md~obsidian/Documents/个人/posts/"  # 定义Obsidian笔记存放博客文章的路径
destinationPath="/Users/xiuhao/blog/hugosite/content/posts"  # 定义Hugo内容文件夹的路径

# Set GitHub Repo
myrepo="git@github.com:whistleditty/whistleditty.github.io.git"  # 定义GitHub上的远程仓库地址

# Set Hugo build and public directory
hugo_dir="/Users/xiuhao/blog/hugosite"  # Hugo 项目根目录
public_dir="$hugo_dir/public"  # Hugo 构建后生成的 public 目录

# Check for required commands
for cmd in git rsync python3 hugo; do  # 检查必要的命令是否存在
    if ! command -v $cmd &> /dev/null; then  # 如果命令不存在
        echo "$cmd is not installed or not in PATH."  # 输出错误信息
        exit 1  # 退出脚本
    fi
done

# Step 1: Check if Git is initialized, and initialize if necessary
if [ ! -d ".git" ]; then  # 如果当前目录下没有.git文件夹
    echo "Initializing Git repository..."  # 输出初始化Git仓库的信息
    git init  # 初始化一个新的Git仓库
    git remote add origin $myrepo  # 添加远程仓库为origin
else
    echo "Git repository already initialized."  # 输出Git仓库已经初始化的信息
    if ! git remote | grep -q 'origin'; then  # 如果远程仓库列表中没有origin
        echo "Adding remote origin..."  # 输出添加远程仓库的信息
        git remote add origin $myrepo  # 添加远程仓库为origin
    fi
fi

# Step 2: Sync posts from Obsidian to Hugo content folder using rsync
echo "Syncing posts from Obsidian..."  # 输出同步博客文章的信息

if [ ! -d "$sourcePath" ]; then  # 如果源路径不存在
    echo "Source path does not exist: $sourcePath"  # 输出错误信息
    exit 1  # 退出脚本
fi

if [ ! -d "$destinationPath" ]; then  # 如果目标路径不存在
    echo "Destination path does not exist: $destinationPath"  # 输出错误信息
    exit 1  # 退出脚本
fi

rsync -av --delete "$sourcePath" "$destinationPath"  # 使用rsync同步文件，删除目标位置中源位置没有的内容


## Step 3: Process Markdown files with Python script to handle image links
#echo "Processing image links in Markdown files..."  # 输出处理Markdown文件中的图片链接的信息
#
#if [ ! -f "images.py" ]; then  # 如果Python脚本不存在
#    echo "Python script images.py not found."  # 输出错误信息
#    exit 1  # 退出脚本
#fi
#
#if ! python3 images.py; then  # 运行Python脚本
#    echo "Failed to process image links."  # 如果运行失败，输出错误信息
#    exit 1  # 退出脚本
#fi
#
# Step 4: Build the Hugo site
echo "Building the Hugo site..."  # 输出构建Hugo站点的信息
cd "$hugo_dir"  # 切换到 Hugo 项目目录

if ! hugo; then  # 调用Hugo命令生成静态网站
    echo "Hugo build failed."  # 如果构建失败，输出错误信息
    exit 1  # 退出脚本
fi

# Step 5: Add changes to Git
echo "Staging changes for Git..."  # 输出将更改添加到Git暂存区的信息
cd "$public_dir"
if git diff --quiet && git diff --cached --quiet; then  # 如果没有新的更改
    echo "No changes to stage."  # 输出没有新更改的信息
else
    git add .  # 将所有更改添加到暂存区
fi

# Step 6: Commit changes with a dynamic message
commit_message="New Blog Post on $(date +'%Y-%m-%d %H:%M:%S')"  # 生成提交信息，包含当前日期和时间
if git diff --cached --quiet; then  # 如果没有新的更改需要提交
    echo "No changes to commit."  # 输出没有新更改的信息
else
    echo "Committing changes..."  # 输出正在提交更改的信息
    git commit -m "$commit_message"  # 提交更改
fi

# Step 7: Push all changes to the main branch
echo "Deploying to GitHub Main..."  # 输出推送到主分支的信息

if ! git push origin master; then  # 推送本地更改到GitHub仓库的main分支
    echo "Failed to push to main branch."  # 如果推送失败，输出错误信息
    exit 1  # 退出脚本
fi

# Step 8: Push the public folder to the hostinger branch using subtree split and force push
echo "Deploying to GitHub Hostinger..."  # 输出推送到Hostinger分支的信息

if git branch --list | grep -q 'hostinger-deploy'; then  # 如果存在名为hostinger-deploy的分支
    git branch -D hostinger-deploy  # 删除该分支
fi

if ! git subtree split --prefix public -b hostinger-deploy; then  # 创建一个只包含public文件夹的新分支
    echo "Subtree split failed."  # 如果创建失败，输出错误信息
    exit 1  # 退出脚本
fi

if ! git push origin hostinger-deploy:hostinger --force; then  # 强制推送新分支到远程仓库的hostinger分支
    echo "Failed to push to hostinger branch."  # 如果推送失败，输出错误信息
    git branch -D hostinger-deploy  # 删除临时分支
    exit 1  # 退出脚本
fi

git branch -D hostinger-deploy  # 删除临时分支

echo "All done! Site synced, processed, committed, built, and deployed."  # 输出完成所有操作的信息
```

整个方案是从[NetworkChuck](https://www.youtube.com/@NetworkChuck)的代码改来的。  
他直接上传了hugo整个文件夹，但似乎只要上传public文件夹就够了，他的部署方式似乎有点区别所以不能直接用？  
虽然脚本还在报错`'public' does not exist; use 'git subtree add'
Subtree split failed.` 但能用就行了，不管啦。
😄

