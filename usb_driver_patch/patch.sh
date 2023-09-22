#!/bin/bash

# Check if driver version is the same
touch /check_diff.patch
if [ -z "$(diff /${USB_DRIVER_CHECK}/v6 ${USB_DRIVER_TARGET} | grep -v '^Only in')" ]
then 
    DRIVER_VERSION="v6"
elif [[ -z "$(diff /${USB_DRIVER_CHECK}/v5 ${USB_DRIVER_TARGET} | grep -v '^Only in')" ]] 
then
    DRIVER_VERSION="v5"
else
    echo "Driver version is not supported!";
    exit 1;
fi

echo ${DRIVER_VERSION}

rm /check_diff.patch

touch /usb_diff.patch
diff /${USB_DRIVER_CHECK}/${DRIVER_VERSION}/ /${USB_DRIVER_PATCH}/${DRIVER_VERSION} | cat > /usb_diff.patch
cp /${USB_DRIVER_PATCH}/${DRIVER_VERSION}/. ${USB_DRIVER_TARGET} -f -R