# 使用带有 uv 的官方轻量级 Python 镜像
FROM python:3.11-slim

# 安装 uv（使用官方推荐的安装方式，直接拷入二进制文件，极快）
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# 设置工作目录
WORKDIR /app

# 把依赖清单拷进去
COPY pyproject.toml uv.lock ./

# 用 uv 同步依赖（生成虚拟环境并安装，--no-dev 表示不安装开发测试用的包）
RUN uv sync --no-dev

# 把你的业务代码拷进去
COPY main.py ./

# 暴露端口，并告诉 Docker 怎么启动这个服务
# 注意：必须要写 --host 0.0.0.0，不能是 127.0.0.1，否则盒子外面访问不到！
CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]