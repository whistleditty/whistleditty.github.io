sourcePath="/Users/xiuhao/Library/Mobile Documents/iCloud~md~obsidian/Documents/个人/posts/"  # 定义Obsidian笔记存放博客文章的路径
destinationPath="/Users/xiuhao/blog/hugosite/content/posts"  # 定义Hugo内容文件夹的路径

rsync -av --delete "$sourcePath" "$destinationPath"  # 使用rsync同步文件，删除目标位置中源位置没有的内容

