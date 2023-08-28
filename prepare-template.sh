#!/bin/bash

RUNNER_VERSION=$(wget -q -O - https://github.com/actions/runner/raw/main/src/runnerversion)
RUNNER_USER_UID=1001
DOCKER_GROUP_GID=121
YQ_VERSION=v4.33.3


if [ -z "$1" ]; then 
  ARCH=$(uname -m)
else
  ARCH="$1"
fi

CMDINSTALL=""
if ! command -v virt-customize &> /dev/null
then
  echo "virt-customize could not be found"
  CMDINSTALL="guestfs-tools  $CMDINSTALL"
fi

if ! command -v axel &> /dev/null
then
  echo "axel could not be found"
  CMDINSTALL="axel $CMDINSTALL"
fi

if [ -n "${CMDINSTALL}" ]; then
  apt update
  apt install -y ${CMDINSTALL}
fi

TMPDIR=$(mktemp -d)
TMPDIR=test
mkdir -p test

axel -o "${TMPDIR}" https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# resize image to 150Gib
fallocate -l10Gib "${TMPDIR}/jammy-server-cloudimg-amd64-full.img"
sudo virt-resize --expand /dev/sda1 "${TMPDIR}/jammy-server-cloudimg-amd64.img" "${TMPDIR}/jammy-server-cloudimg-amd64-full.img"

# Add standart packages
sudo virt-customize -a "${TMPDIR}/jammy-server-cloudimg-amd64-full.img" --install qemu-guest-agent,software-properties-common,curl,ca-certificates,git,git-lfs,jq,software-properties-common,sudo,unzip,zip,acl,aria2,autoconf,automake,binutils,bison,brotli,build-essential,bzip2,coreutils,curl,dbus,dnsutils,dpkg,fakeroot,file,flex,fonts-noto-color-emoji,ftp,gnupg2,haveged,imagemagick,iproute2,iputils-ping,jq,libc++-dev,libc++abi-dev,libcurl4,libgbm-dev,libgconf-2-4,libgsl-dev,libgtk-3-0,libmagic-dev,libmagickcore-dev,libmagickwand-dev,libsecret-1-dev,libsqlite3-dev,libssl-dev,libtool,libunwind8,libxkbfile-dev,libxss1,libyaml-dev,locales,lz4,m4,mediainfo,mercurial,net-tools,netcat,openssh-client,p7zip-full,p7zip-rar,parallel,pass,patchelf,pkg-config,pollinate,python-is-python3,rpm,rsync,shellcheck,sphinxsearch,sqlite3,ssh,sshpass,subversion,sudo,swig,tar,telnet,texinfo,time,tk,tzdata,unzip,upx,wget,xorriso,xvfb,xz-utils,zip,zsync,libyaml-dev,cgroup-tools,cgroupfs-mount


# ????  add-apt-repository -y ppa:git-core/ppa


# Add yq
case "${ARCH}" in
  "x86_64" | "amd64")
    YQ_ARCH="amd64"
    RUNNER_ARCH="x64"
    ;;
  "armv7l" | "armhf" | "armv7")
    YQ_ARCH="arm"
    RUNNER_ARCH="arm"
    ;;
  "aarch64" | "arm64")
    YQ_ARCH="arm64"
    RUNNER_ARCH="arm64"
    ;;
  "i386")
    YQ_ARCH="386"
    RUNNER_ARCH="x64"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac


sudo virt-customize -a "${TMPDIR}/jammy-server-cloudimg-amd64-full.img"  --memsize 8192 --run-command "wget -q -O /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" && chmod +x /usr/bin/yq"

# Install docker
sudo virt-customize -a "${TMPDIR}/jammy-server-cloudimg-amd64-full.img"  --memsize 8192 --run-command "curl -fsSL https://get.docker.com -o get-docker.sh && sh ./get-docker.sh"


# Runner user
#    && groupadd docker --gid $DOCKER_GROUP_GID \
sudo virt-customize -a "${TMPDIR}/jammy-server-cloudimg-amd64-full.img"  --memsize 8192 --run-command "chpasswd root:12345 && adduser --disabled-password --gecos '' --uid $RUNNER_USER_UID runner \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo '%sudo   ALL=(ALL:ALL) NOPASSWD:ALL' > /etc/sudoers \
    && echo 'Defaults env_keep += \"DEBIAN_FRONTEND\"' >> /etc/sudoers"

#ENV HOME=/home/runner

RUNNER_ASSETS_DIR=/runnertmp

sudo virt-customize -a "${TMPDIR}/jammy-server-cloudimg-amd64-full.img"  --memsize 8192 --run-command 'mkdir -p "'"$RUNNER_ASSETS_DIR"'" && cd "'"$RUNNER_ASSETS_DIR"'" \
    && curl -fLo runner.tar.gz https://github.com/actions/runner/releases/download/v'"${RUNNER_VERSION}"'/actions-runner-linux-'"${RUNNER_ARCH}"'-'"${RUNNER_VERSION}"'.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm -f runner.tar.gz \
    && ./bin/installdependencies.sh'

# Cleanup

#rm -rf "${TMPDIR}"
