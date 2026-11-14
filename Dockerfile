FROM debian:13-slim

# 与固件项目 README 的 Debian 依赖保持一致（另加 git，用于生成版本号）
RUN apt-get update && apt-get install -y --no-install-recommends \
      make \
      gcc \
      g++ \
      bison \
      flex \
      libboost-dev \
      patch \
      bzip2 \
      curl \
      ca-certificates \
      xxd \
      python3 \
      libjson-c-dev \
      zlib1g-dev \
      git \
    && rm -rf /var/lib/apt/lists/*

# 容器里以 root 挂载宿主机仓库时，避免 git 的 dubious ownership 报错
RUN git config --global --add safe.directory '*'

WORKDIR /work

CMD ["bash"]
