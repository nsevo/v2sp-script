# v2sp-script

用于部署和维护 v2sp 节点端的 Shell 脚本集合，包括：
- `install.sh`：一键安装、更新、初始化配置
- `v2sp.sh`：管理脚本（启动/停止/日志/限速工具等）
- `initconfig.sh`：交互式配置生成器
- `v2sp.service`：systemd 单元示例

核心代码仓库：[nsevo/v2sp](https://github.com/nsevo/v2sp)

## 快速开始

```bash
wget -N https://raw.githubusercontent.com/nsevo/v2sp-script/master/install.sh && bash install.sh
```
