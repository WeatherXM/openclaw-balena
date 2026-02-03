# Build llama.cpp from source for multi-arch support (ARM64 + AMD64)
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    ca-certificates \
    libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/*

# Clone and build llama.cpp (static build to avoid shared library issues)
ARG LLAMA_CPP_VERSION=master
RUN git clone --depth 1 --branch ${LLAMA_CPP_VERSION} https://github.com/ggerganov/llama.cpp.git /llama.cpp

WORKDIR /llama.cpp
RUN cmake -B build \
    -DGGML_NATIVE=OFF \
    -DLLAMA_CURL=ON \
    -DBUILD_SHARED_LIBS=OFF \
    && cmake --build build --config Release -j$(nproc) --target llama-server

# Runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libgomp1 \
    libcurl4 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /llama.cpp/build/bin/llama-server /app/llama-server

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8080
ENTRYPOINT ["/start.sh"]
