# Stage 1: Build
FROM nvidia/cuda:12.8.1-devel-ubuntu24.04 AS builder

# Set environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages and dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libfftw3-dev \
    libtiff-dev \
    libgsl-dev \
    libpng-dev \
    ocl-icd-opencl-dev \
    clinfo \
    nvidia-opencl-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone the deconwolf repository
RUN git clone -b dev https://github.com/elgw/deconwolf.git /deconwolf

# Create a build directory
WORKDIR /deconwolf/builddir

# Configure and build deconwolf with OpenCL support
RUN cmake .. && cmake --build .

# Remove unnecessary build dependencies
RUN apt-get purge -y \
    build-essential \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/* 

# Stage 2: Runtime
FROM nvidia/cuda:12.8.1-base-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install necessary runtime libraries
RUN apt-get update && apt-get install -y \
libfftw3-dev \
libtiff-dev \
libgsl-dev \
libpng-dev \
libffi-dev \
libssl-dev \
ocl-icd-libopencl1 \
clinfo \
nvidia-opencl-dev \
python3 \
python3-pip \
python3-venv \
&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------- Python venv ----------
# Create and activate venv, then install requirements in one layer
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt

# Make venv the default Python
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# ---------- deconwolf ----------
COPY --from=builder /deconwolf/builddir/src /usr/local/lib/
RUN find /usr/local/lib -name "*.so*" -exec mv -t /usr/local/lib {} \; \
&& ldconfig

COPY --from=builder /deconwolf/builddir/dw /usr/local/bin/dw
COPY --from=builder /deconwolf/builddir/dw_bw /usr/local/bin/dw_bw

WORKDIR /data/