# sensu_plugins
Sensu CLI Plugins and Scripts

1) esxi_resource_monitor:  
  This plugin hits the vCenter server to get the status of the ESXi hosts.
  Monitors Disk usage, Memotry usage and CPU usage of ESXi hosts.
  Tested on ESXi 5.5 and vCenter 5.5

2) esxi_host:  
  ESXi health monitoring script
  Uses ssh to check whether and ESXi host is up and runs vm listing command
  Written for VMWare ESXi 5.5

3) kubernetes-pod-count:  
  Monitors the number of pods in a Kubernetes cluster and alerts if
  the number drops below the threshold.

4) kubernetes-pod-restarts:  
  Monitors the pod restart count by hitting the Kubernetes API.
  Dumps pod restart count to /tmp/sensu and compares the counts in the next run.
  Sensu check definition that runs this plugin should use autoresolve: false to
  avoid the check resolving itself if it does not see any change in restart counts
  in subsequent runs.

5) kubernetes-pods-pending:  
 Monitors the pod status hitting the kubernetes API.
 Dumps pending pod list to /tmp/sensu and comapres them in the next run.
 Sensu check definition that runs this plugin should use autoresolve: false to
 avoid the check resolving itself if it does not see any change in restart counts
 in subsequent runs.

6) network_interface_monitor:  
 Sensu plugin to check the status of network interfaces on a Ubuntu host.
 Tested on Ubuntu 14.04 LTS.
 Can check whether an interface is up, its physical link state and mtu.
 Accepts command line arguments with wildcards.

7) openshift_node_status:  
 Compares the nodes list from Openshift API and from the
 Ansible hosts file and alerts if they don't match
 Checks whether the nodes are 'Ready' in Openshift by hitting the API.

8) openstack-boot_attach_floatip_volume:  
 Sensu check to boot a vm, attach a floating ip and attach a volume.
 This plugin can send metrics to Graphite which can be suppressed by a command line flag.
 Performs cleanup after every check unless told not to.

9) smart_ssd_check:  
 Sensu check to monitor "Media_Wearout_Indicator" of Intel solid state drives.
 Looks for the "VALUE" field (not RAW_VALUE) in smartctl output.
 Requires "smartmontools" installed.
 Works only with Intel SSD drives. Tested only on "INTEL SSDSC2BB240G4".
 Intel strongly suggests to replace the disk when
 the value of "Media_Wearout_Indicator" is 1.


 Tags: Sensu Plugins, Kubernetes, Openshift, Smart ssd, network interface monitor, nagios
