# set PLATFORM32 to something not null if you're building for older platforms, i.e. Pi 1, Pi Zero, Pi Zero W and Pi CM1
# do not define PLATFORM32 or set it to null if you're building for newer platforms, i.e. Pi 3, Pi 3+, Pi 4, Pi 400, Pi Zero 2 W, Pi CM3, Pi CM3+, Pi CM4
FROM ubuntu:latest

# Timezone. You may change if you want
ENV TZ=Europe/Amsterdam
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Installing dependencies
RUN apt update
RUN apt upgrade -y
RUN apt install -y git make gcc bison flex libssl-dev bc ncurses-dev kmod
RUN apt install -y crossbuild-essential-arm64 crossbuild-essential-armhf
RUN apt install -y wget zip unzip fdisk nano curl xz-utils

# Linux version. Only works if the usb driver is the same as in the patch. Will check.
ENV LINUX_KERNEL_VERSION=6.6
ENV LINUX_KERNEL_BRANCH=rpi-${LINUX_KERNEL_VERSION}.y

# Download the kernels


WORKDIR /rpi-kernel
RUN git clone https://github.com/raspberrypi/linux.git -b ${LINUX_KERNEL_BRANCH} --depth=1
WORKDIR /rpi-kernel/linux
RUN export PATCH=$(curl -s https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/${LINUX_KERNEL_VERSION}/ | sed -n 's:.*<a href="\(.*\).patch.gz">.*:\1:p' | sort -V | tail -1)

ARG NO_RT
# Download and apply RT patch (unless NO_RT is defined)
RUN [ -z "$NO_RT"] && echo "Downloading patch ${PATCH}" || true
RUN [ -z "$NO_RT"] && curl https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/${LINUX_KERNEL_VERSION}/${PATCH}.patch.gz --output ${PATCH}.patch.gz || true
RUN [ -z "$NO_RT"] && gzip -cd /rpi-kernel/linux/${PATCH}.patch.gz | patch -p1 --verbose || true

# Apply USB patch (unless NO_RT is defined)
ENV USB_DRIVER_SOURCE=usb_driver_patch
ENV USB_DRIVER_PATCH=${USB_DRIVER_SOURCE}/patch
ENV USB_DRIVER_CHECK=${USB_DRIVER_SOURCE}/check
ENV USB_DRIVER_TARGET=/rpi-kernel/linux/drivers/usb/host/dwc_otg/

COPY ${USB_DRIVER_SOURCE} /${USB_DRIVER_SOURCE}
RUN [ -z "$NO_RT"] && echo "Applying USB patch. Open /usb_diff.patch to see the differences.." || true
RUN [ -z "$NO_RT"] && bash /${USB_DRIVER_SOURCE}/patch.sh || true

ARG PLATFORM32

# if PLATFORM32 has been defined then set KERNEL=kernel else set KERNEL=kernel8 (arm64)
ENV KERNEL=${PLATFORM32:+kernel}
ENV KERNEL=${KERNEL:-kernel8}

# if PLATFORM32 has been defined then set ARCH=arm else set ARCH=arm64
ENV ARCH=${PLATFORM32:+arm}
ENV ARCH=${ARCH:-arm64}

# if PLATFORM32 has been defined then set CROSS_COMPILE=arm-linux-gnueabihf- else set CROSS_COMPILE=aarch64-linux-gnu-
ENV CROSS_COMPILE=${PLATFORM32:+arm-linux-gnueabihf-}
ENV CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}

# print the above env variables
RUN echo ${KERNEL} ${ARCH} ${CROSS_COMPILE}

# set the kernel config (leave default if NO_RT is defined)
RUN [ "$ARCH" = "arm" ] && make bcmrpi_defconfig || make bcm2711_defconfig
RUN [ -z "$NO_RT"] ./scripts/config --disable CONFIG_VIRTUALIZATION || true
RUN [ -z "$NO_RT"] && ./scripts/config --enable CONFIG_PREEMPT_RT || true
RUN [ -z "$NO_RT"] && ./scripts/config --disable CONFIG_RCU_EXPERT || true
RUN [ -z "$NO_RT"] && ./scripts/config --enable CONFIG_RCU_BOOST || true
RUN [ "$ARCH" = "arm" ] && [ -z "$NO_RT"] && ./scripts/config --enable CONFIG_SMP || true
RUN [ "$ARCH" = "arm" ] &&[ -z "$NO_RT"] &&  ./scripts/config --disable CONFIG_BROKEN_ON_SMP || true
RUN [ -z "$NO_RT"] && ./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500 || true

RUN make -j4 Image modules dtbs

ARG RASPIOS_IMAGE_NAME
RUN echo "Using Raspberry Pi image ${RASPIOS_IMAGE_NAME}"
WORKDIR /raspios
RUN apt -y install
RUN export DATE=$(curl -s https://downloads.raspberrypi.org/${RASPIOS_IMAGE_NAME}/images/ | sed -n "s:.*${RASPIOS_IMAGE_NAME}-\(.*\)/</a>.*:\1:p" | tail -1) && \
    export RASPIOS=$(curl -s https://downloads.raspberrypi.org/${RASPIOS_IMAGE_NAME}/images/${RASPIOS_IMAGE_NAME}-${DATE}/ | sed -n "s:.*<a href=\"\(.*\).xz\">.*:\1:p" | tail -1) && \
    echo "Downloading ${RASPIOS}.xz" && \
    curl https://downloads.raspberrypi.org/${RASPIOS_IMAGE_NAME}/images/${RASPIOS_IMAGE_NAME}-${DATE}/${RASPIOS}.xz --output ${RASPIOS}.xz && \
    xz -d ${RASPIOS}.xz

RUN mkdir /raspios/mnt && mkdir /raspios/mnt/disk && mkdir /raspios/mnt/boot
COPY build.sh ./build.sh
COPY config.txt ./
