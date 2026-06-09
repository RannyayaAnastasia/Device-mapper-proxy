=========
dmp
=========

Device-Mapper's "dmp" (device mapper proxy) target creates a virtual block
device on top of an existing physical block device. It transparently proxies
all I/O requests to the underlying device while simultaneously collecting
**global** I/O operation statistics (aggregated across all active `dmp` devices)
in real-time via the sysfs interface.

Parameters: <dev path> [physical_offset]
    <dev path>:
        Full pathname to the underlying physical block-device, or a
        "major:minor" device-number.
    <physical_offset>:
        Optional starting sector within the underlying device (defaults to 0).

Statistics
==========
I/O metrics are collected atomically and represent **global** statistics
(aggregated across all active `dmp` devices), available in real time via 
the sysfs interface:

  $ cat /sys/module/dmp/stat/volumes
  read: reqs: 500 avg size: 4096
  write: reqs: 100 avg size: 4096
  total: reqs: 600 avg size: 4096


Example scripts
===============

::

  #!/bin/sh
  # Load the custom kernel module and create a proxy mapping for a device
  sudo insmod dmp.ko
  echo "0 `blockdev --getsz $1` dmp $1" | dmsetup create proxy_$1

  # View the collected global statistics
  cat /sys/module/dmp/stat/volumes

::

  #!/bin/sh
  # Generate a simple workload and check how the proxy counted it

  # Write 100 blocks of 4k
  dd if=/dev/urandom of=/dev/mapper/$1 bs=4k count=100 conv=fsync

  # Read 100 blocks of 4k
  dd if=/dev/mapper/$1 of=/dev/null bs=4k count=100

  # Verify global statistics
  echo "--- Global Proxy Statistics ---"
  cat /sys/module/dmp/stat/volumes
```

