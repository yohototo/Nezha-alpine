# 哪吒面板安装脚本
在哪吒原安装脚本上进行了一些修改，使其直接安装在宿主机上（为什么？因为有些lxc，openvz小鸡不能用docker）
建议非必要不要使用此安装方法！
运行（如sudo无法正常使用且已经有root权限，请去掉sudo运行）：

```
curl -L https://raw.githubusercontent.com/applexad/nezhascript/main/install.sh  -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
```

大陆加速代理：
```
curl -L https://raw.fgit.cf/applexad/nezhascript/main/install.sh  -o nezha.sh && chmod +x nezha.sh && sudo ./nezha.sh
```

具体用法可参考[官方教程](https://nezha.wiki/guide/dashboard.html)
