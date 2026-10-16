FROM ubuntu:22.04 as uta

# list and install dependencies
# build-essential is needed to compile uta-align, which has no wheels
ARG dependencies="build-essential curl ca-certificates rsync git postgresql-client-14 tabix"

RUN apt-get update && apt-get install -y $dependencies && apt-get clean

# install uv; it downloads the Python version in .python-version and installs
# the locked dependencies into /opt/venv, which is put first on PATH so that
# `python`, `uta`, `alembic`, and `seqrepo` resolve to it
COPY --from=ghcr.io/astral-sh/uv:0.12.19 /uv /uvx /bin/
ENV UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    PATH="/opt/venv/bin:${PATH}"

WORKDIR /opt/repos/uta/
COPY .python-version pyproject.toml uv.lock README.md ./
COPY etc ./etc
COPY misc ./misc
COPY sbin ./sbin
COPY src ./src
RUN uv sync --frozen


# UTA test image
FROM uta as uta-test
RUN DEBIAN_FRONTEND=noninteractive apt-get -yq install postgresql
COPY tests ./tests
RUN uv sync --frozen --extra test
RUN useradd uta-tester
RUN chown -R uta-tester .
USER uta-tester
