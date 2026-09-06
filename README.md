# container-escape-lab

GitHub Actions 容器逃逸测试靶场。矩阵：`ubuntu-22.04 / ubuntu-24.04` × `privileged / sock / plain` 三种容器变体。

每个变体在一次性 runner VM 内执行：
- 宿主基线（内核/Docker 版本/默认容器 caps）
- 容器内探针：caps、seccomp/apparmor、挂载、/host 可见性、docker.sock 存在性
- **CDK `evaluate`**（neargle/CDK）自动评估可逃逸项
- **deepce** Docker 逃逸枚举

## 合规边界

- 仅在本次 job 的一次性 GitHub-hosted runner VM 内做探测，无持久化、无横向、无破坏性操作。
- 不触碰 GitHub 生产基础设施；对 GitHub 自身的逃逸类研究须走官方 Bounty 授权。
- sock 变体仅做非破坏性 daemon 查询（`docker version`），不实际起逃逸容器。

报告在 Actions artifacts：`escape-report-<os>-<variant>`。
