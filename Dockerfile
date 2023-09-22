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

# Download the kernels and RT patch
WORKDIR /rpi-kernel
RUN git clone https://github.com/raspberrypi/linux.git -b ${LINUX_KERNEL_BRANCH} --depth=1
WORKDIR /rpi-kernel/linux
RUN export PATCH=$(curl -s https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/${LINUX_KERNEL_VERSION}/ | sed -n 's:.*<a href="\(.*\).patch.gz">.*:\1:p' | sort -V | tail -1)
RUN echo "Downloading patch ${PATCH}"
RUN curl https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/${LINUX_KERNEL_VERSION}/${PATCH}.patch.gz --output ${PATCH}.patch.gz
RUN gzip -cd /rpi-kernel/linux/${PATCH}.patch.gz | patch -p1 --verbose

# Apply USB patch
ENV USB_DRIVER_SOURCE=usb_driver_patch
ENV USB_DRIVER_PATCH=${USB_DRIVER_SOURCE}/patch
ENV USB_DRIVER_CHECK=${USB_DRIVER_SOURCE}/check
ENV USB_DRIVER_TARGET=/rpi-kernel/linux/drivers/usb/host/dwc_otg/

COPY ${USB_DRIVER_SOURCE} /${USB_DRIVER_SOURCE}
RUN echo "Applying USB patch. Open /usb_diff.patch to see the differences.."
RUN bash /${USB_DRIVER_SOURCE}/patch.sh
# RUN if [ ! -z "$(diff /${USB_DRIVER_CHECK}/ ${USB_DRIVER_TARGET} | grep -v '^Only in')" ]; then echo "Driver versions are not the same!"; echo "$(diff /${USB_DRIVER_CHECK}/ ${USB_DRIVER_TARGET} | grep -v '^Only in')"; exit 1; fi
# RUN diff /${USB_DRIVER_CHECK}/ /${USB_DRIVER_PATCH}/ | cat > /usb_diff.patch
# RUN cp /${USB_DRIVER_PATCH}/. ${USB_DRIVER_TARGET} -f -R

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

RUN [ "$ARCH" = "arm" ] && make bcmrpi_defconfig || make bcm2711_defconfig
RUN ./scripts/config --disable CONFIG_VIRTUALIZATION
RUN ./scripts/config --enable CONFIG_PREEMPT_RT
RUN ./scripts/config --disable CONFIG_RCU_EXPERT
RUN ./scripts/config --enable CONFIG_RCU_BOOST
RUN [ "$ARCH" = "arm" ] && ./scripts/config --enable CONFIG_SMP || true
RUN [ "$ARCH" = "arm" ] && ./scripts/config --disable CONFIG_BROKEN_ON_SMP || true
RUN ./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500

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
