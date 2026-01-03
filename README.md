# MS-S1-setup-4-llama-cpp-on-ubuntu-25-10
Documentation of the setup steps for the minisforum ms-s1 to use as local ai server for document processing with ubuntu, rocm, docker, llama.cpp, docling. Maybe it helps also someone else.

## Hardware
[minisforum MS-S1 MAX](https://www.minisforum.com/de/pages/product-info)

## goods receipt
* finalize windows setup
* performance test
* firmware update
* load new defaults
* performance & burn-in test
* download [ubuntu server](https://ubuntu.com/download/server) (important kernel >= 6.17)
* to create usb [rufus](https://www.heise.de/download/product/rufus)

## install ubuntu
* follow standard ubuntu server setup (destroy win11 installation)
* improve boot time (1) systemd-networkd-wait-online.service

```
sudo systemctl edit systemd-networkd-wait-online.service

### Editing /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
### Anything between here and the comment below will become the contents of the drop-in file

[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-networkd-wait-online -i enp98s0

### Edits below this comment will be discarded

```

* adapt grub to ensure 124 GB of shared memory for the GPU and optimize boot time (2)
```
sudo nano /etc/default/grub

GRUB_TIMEOUT_STYLE=menu  
GRUB_TIMEOUT=1

GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=off amdgpu.gttsize=126976 ttm.pages_limit=32505856"

sudo update-grub
```

* increase lvm space for / the standard 98G are to less for the next steps.
```
df -h
sudo lvextend --resizefs -L +410G /dev/mapper/ubuntu--vg-ubuntu--lv
df -h
```

* update and clean the os
```
sudo apt update
sudo apt upgrade
sudo apt autoremove
```

## install rocm
[Ubuntu native installation](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/install-methods/package-manager/package-manager-ubuntu.html)
only 24.04 description is available

* First check and uninstall (should be clean but who knows)
```
sudo apt autoremove rocm
sudo apt autoremove rocm-core

# Remove the repositories
sudo rm /etc/apt/sources.list.d/rocm.list

# Clear the cache and clean the system
sudo rm -rf /var/cache/apt/*
sudo apt clean all
sudo apt update

# Make the directory if it doesn't exist yet.
# This location is recommended by the distribution maintainers.
sudo mkdir --parents --mode=0755 /etc/apt/keyrings

# Download the key, convert the signing-key to a full
# keyring required by apt and store in the keyring directory
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

sudo tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.1.1 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.1.1/ubuntu noble main
EOF

sudo tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

sudo apt update

sudo apt install rocm

sudo tee --append /etc/ld.so.conf.d/rocm.conf <<EOF
/opt/rocm/lib
/opt/rocm/lib64
EOF
sudo ldconfig

sudo update-alternatives --display rocm
#should be only one. if multi then
sudo update-alternatives --config rocm

# Add the current user to the render and video groups
sudo usermod -aG render,video $LOGNAME
# reconnect to ssh

#checks
apt list --installed | grep rocm
rocminfo | grep -i "Marketing Name:"
```

## Install docker  
[Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)


* First check and uninstall (should be clean but who knows)
```
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1)
```
* then add repositories
```
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# issue https://github.com/containerd/containerd/issues/12741

# Add the current user to the docker group
sudo usermod -aG docker $LOGNAME
# reconnect to ssh

#checks
apt list --installed | grep docker
docker ps

```
## monitoring
```
wget https://github.com/Umio-Yasuno/amdgpu_top/releases/download/v0.11.0/amdgpu-top_without_gui_0.11.0-1_amd64.deb
sudo apt install ./amdgpu-top_without_gui_0.11.0-1_amd64.deb
amdgpu_top
```



## llama.cpp Docker
[llama cpp docker.md](https://github.com/ggml-org/llama.cpp/blob/master/docs/docker.md)
see Dockerfile (is all you can eat, basic version, no optimisation)

```
mkdir ~/docker
# copy Dockerfile
docker build -t rocm-base:0.1 .
docker run -it --device=/dev/kfd --device=/dev/dri --security-opt seccomp=unconfined --group-add video --volume ~/.cache/llama.cpp/:/root/.cache/llama.cpp/ -p 8033:8033 rocm-base:0.1 
```

check if devices are identified correct
```
cd /app/full
llama-cli --list-devices
```

```
/app/full/llama-server -hf unsloth/gpt-oss-120b-GGUF:F16 --ctx-size 120000 -ngl 999 -fa 1 --no-mmap --host 0.0.0.0 --port 8033
```

## docling 4 rocm
[docling serve documentation](https://github.com/docling-project/docling-serve/blob/main/docs/deployment.md#local-gpu-amd)

```
cd ~/docker/

git clone https://github.com/docling-project/docling-serve
cd docling-serve/
make docling-serve-rocm-image

docker compose -f docs/deploy-examples/compose-amd.yaml up -d

# Make a test query
curl -X 'POST' \
  "localhost:5001/v1/convert/source/async" \
  -H "accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "sources": [{"kind": "http", "url": "https://arxiv.org/pdf/2501.17887"}]
  }'
```
