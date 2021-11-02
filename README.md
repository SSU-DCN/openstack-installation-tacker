# openstack-installation-tacker
It should be connected by 2 LAN lines.

```
$ ifconfig
```

```
$ chmod 700 openstack.sh
```

After checking the interface, copy the INTERFACE_ID that inet is not set (ex. eno2 or enx~~)

```
$ ./openstack_install.sh ${INTERFACE_ID}
```

Set Openstack Dashboard Password
