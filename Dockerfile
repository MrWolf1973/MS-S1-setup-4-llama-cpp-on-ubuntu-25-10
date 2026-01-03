FROM ubuntu:25.10

#OS basic
RUN apt update
RUN apt -y upgrade
RUN apt -y install wget gpg

#Rocm
RUN mkdir --parents --mode=0755 /etc/apt/keyrings
RUN wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null

RUN <<'ENDRUN'
tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.1.1 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.1.1/ubuntu noble main
EOF
ENDRUN

RUN <<'ENDRUN'
tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF
ENDRUN

RUN apt update
RUN apt -y install rocm
#rocm-dev rocm-libs

RUN <<'ENDRUN'
tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
ENDRUN
RUN ldconfig

#llama.cpp compile
ENV ROCM_DOCKER_ARCH='gfx1151'
RUN apt install -y build-essential cmake git libcurl4-openssl-dev curl libgomp1

#workaround for 25.10
RUN ln -s /lib/x86_64-linux-gnu/libxml2.so.16 /lib/x86_64-linux-gnu/libxml2.so.2
RUN ldconfig

WORKDIR /app
RUN git clone https://github.com/ggml-org/llama.cpp

WORKDIR /app/llama.cpp
RUN HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build \
        -DGGML_HIP=ON \
        -DGGML_HIP_ROCWMMA_FATTN=ON \
        -DAMDGPU_TARGETS="$ROCM_DOCKER_ARCH" \
        -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
        -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TESTS=OFF \
    && cmake --build build --config Release -j$(nproc)

RUN mkdir -p /app/lib \
    && find build -name "*.so*" -exec cp -P {} /app/lib \;

RUN mkdir -p /app/full \
    && cp build/bin/* /app/full \
    && cp *.py /app/full \
    && cp -r gguf-py /app/full \
    && cp -r requirements /app/full \
    && cp requirements.txt /app/full \
    && cp .devops/tools.sh /app/full/tools.sh
