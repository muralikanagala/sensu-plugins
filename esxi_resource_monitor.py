#!/usr/bin/env python
from __future__ import print_function

# This Check hits the vCenter server to get the status of the ESXi hosts.
# Monitors Disk usage, Memotry usage and CPU usage of ESXi hosts.
# Tested on ESXi 5.5 and vCenter 5.5

"""
Usage: check_vsphere TEST
       check_vsphere [options] dsusage
       check_vsphere --version
Options:
  -T             Test to run (required)
  --version      show version and exit
  -h --help
  -v --verbose   Output more information
  -H --host      vSphere server to interogate
  -E --esxhost   ESX host (vSphere server will be ignored if this argument is passed)
  -U --username  vSphere Username (username@domain if using SSO/AD)
  -P --password  Password
  -W --warning   Warning Threshold
  -C --critical  Critical Threshold
Host, username and password can also be defined using the environment variable:
  VI_SERVER
  VI_USERNAME
  VI_PASSWORD


"""

__author__  = "Murali Krishna Kanagala"
__title__   = "Nagios plugin to check vSphere for vmware metrics"
__version__ = 1.0

from pysphere import VIServer, VIProperty
from pysphere.resources import VimService_services as VI
import argparse
import os
import errno, sys

# Standard Nagios return codes
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

def error(*objs):
  print ("ERROR: ", *objs, file=sys.stderr)

def warning(*objs):
  print ("WARNING: ", *objs, file=sys.stderr)

parser = argparse.ArgumentParser(description=__title__)
parser.add_argument('-H', '--hostname', help='vSphere server to interogate', required=True)
parser.add_argument('-E', '--esxhost', help='ESX server to connect')
parser.add_argument('-U', '--username', help='vSphere Username (username@domain')
parser.add_argument('-P', '--password', help='vSpherePassword')
parser.add_argument('-v', '--verbose', help='Verbose output')
parser.add_argument('-C', '--crit', help='Critical threshold')
parser.add_argument('-W', '--warn', help='Warning threshold')
parser.add_argument('-T', '--test', help='test to run', required=True)
args = parser.parse_args()

# TODO: add suitable stderr messages
if args.hostname != None:
  VI_SERVER = args.hostname
elif "VI_SERVER" in os.environ:
  VI_SERVER = os.getenv("VI_SERVER")
else:
  error("vSphere server not defined")
  sys.exit(UNKNOWN)
if args.username !=None:
  VI_USERNAME = args.username
elif "VI_USERNAME" in os.environ:
  VI_USERNAME = os.getenv("VI_USERNAME")
else:
  error("vSphere username not defined")
  sys.exit(UNKNOWN)

if args.password != None:
  VI_PASSWORD = args.password
elif "VI_PASSWORD" in os.environ:
  VI_PASSWORD = os.getenv("VI_PASSWORD")
else:
  error("vSphere password not defined")
  sys.exit(UNKNOWN)

TEST = args.test

if args.esxhost != None:
  VI_ESXHOST = args.esxhost
else:
  VI_ESXHOST = None

if args.crit != None:
  VI_CRIT = args.crit
else:
  error("Critical threshold not defined")
  sys.exit(UNKNOWN)

if args.warn != None:
  VI_WARN = args.warn
else:
  error("Warning threshold not defined")
  sys.exit(UNKNOWN)

if int(VI_CRIT) <= int(VI_WARN):
  error("Warning threshold can not be less than or equal to Critical threshold")
  sys.exit(UNKNOWN)


server = VIServer()
try:
  server.connect(VI_SERVER, VI_USERNAME, VI_PASSWORD)
except:
  print('Failed to connect to vSphere Server')
  exit(3)

if VI_ESXHOST:
  esxhost = VI_ESXHOST.split('.')
  esxdstag = esxhost[0] + esxhost[1]
else:
  esxdstag =''

def dsSpaceCheck():
  perfdataarray = []
  status = OK
  for ds, name in server.get_datastores().items():
    if esxdstag and esxdstag not in name:
      continue
    props = VIProperty(server, ds)
    capacity = props.summary.capacity
    capacityGB = capacity / (1024 ^ 3)
    freeSpace = props.summary.freeSpace
    freeSpaceGB = freeSpace / 1024 / 1024 / 1024
    usedSpace = capacity - freeSpace
    usedSpaceGB = capacityGB - freeSpaceGB
    try:
      uncommited = props.summary.uncommited
      overprov = used + uncommited
      overprovPercent = (overprov / capacity) * 100
      if overprovPercent > 100:
        message = "WARNING: A datastore is over-commited"
        status = WARNING
        break
      elif overprovPercent > 150:
        message = "CRITICAL: A datastore is REALLY over-commited"
        status = CRITICAL
        break
      else:
        pass
    except AttributeError:
      pass
    usedPercent = round(abs(float(usedSpace) / float(capacity) * 100),1)
    perfdataarray.append (name + ': ' + str(usedPercent) + '%')
    if usedPercent >= int(VI_CRIT):
      message = "CRITICAL: High disk usage on datastore"
      status = CRITICAL
    elif int(VI_WARN) <= usedPercent < int(VI_CRIT):
      if status != CRITICAL:
        message = "WARNING: High disk usage on datastore"
        status = WARNING
    else:
      pass
  if status == OK:
    message = "OK: Datastore disk usages are normal"
  perfdata = ""
  for dsdata in perfdataarray:
    perfdata = perfdata + dsdata + " "
  message = message + " | " + perfdata
  print (message)
  return status


def cpuUsage():
  status = OK
  cpuusage = {}
  message = ''
  cpu_usages = ""
  pm = server.get_performance_manager()
  hosts = server.get_hosts()
  for host, host_name in hosts.items():
    if VI_ESXHOST and VI_ESXHOST != host_name:
      continue
    cpu_stats = pm.get_entity_statistic(host, [2])
    for stat in cpu_stats:
      if stat.instance == '0':
        cpuusage[host_name] = int(stat.value) / 100.0

  for host, cpu_usage in cpuusage.items():
    cpu_usages = cpu_usages + "|" + host + ": " + str(cpu_usage) + '%'
    if cpu_usage >= int(VI_CRIT):
      message = "CRITICAL: CPU usage"
      status = CRITICAL
    elif int(VI_WARN) <= cpu_usage < int(VI_CRIT):
      if 'CRITICAL' not in message:
        message = "WARNING: High CPU usage"
      if status != CRITICAL:
        status = WARNING
  if status == OK:
    message = "OK: CPU usages are normal"
  message = message + cpu_usages
  print (message)
  return status


def memUsage():
  memusage = {}
  mem_usages = ''
  message = ''
  status = OK
  pm = server.get_performance_manager()
  hosts = server.get_hosts()
  for host, host_name in hosts.items():
    if VI_ESXHOST and VI_ESXHOST != host_name:
      continue
    memstats = pm.get_entity_statistic(host, [24])
    mem =  memstats[0]
    memusage[host_name] = int(mem.value) / 100.0

  for host, mem_usage in memusage.items():
    mem_usages = mem_usages + "|" + host + ": " + str(mem_usage) + '%'
    if mem_usage >= int(VI_CRIT):
      message = "CRITICAL: Memory usage"
      status = CRITICAL
    elif int(VI_WARN) <= mem_usage < int(VI_CRIT):
        if 'CRITICAL' not in message:
          message = "WARNING: High memory usage"
        if status != CRITICAL:
          status = WARNING
  if status == OK:
     message = "OK: Memory usages are normal"
  message = message + mem_usages
  print (message)
  return status


def dsIOCheck():
  status = OK
  vmlist = server.get_registered_vms(status='poweredOn')
  for vmpath in vmlist:
    print (vmpath)
    pm = server.get_performance_manager()
    vm = server.get_vm_by_path(vmpath)
    mor = vm._mor
    counterValues = pm.get_entity_counters(mor)
    #print (counterValues) #virtualDisk.readLatencyUS
#    readIOPS = counterValues['virtualDisk.numberReadAveraged']
#    writeIOPS = counterValues['virtualDisk.numberWriteAveraged']
    readLatency = counterValues['virtualDisk.readLatencyUS']
    writeLatency = counterValues['virtualDisk.writeLatencyUS']
#    IOPS = readIOPS + writeIOPS
    print(readLatency, writeLatency)
  return status

if __name__ == '__main__':
  if TEST == 'dsusage':
    status = dsSpaceCheck()
    exit(status)
  elif TEST == 'testrun':
    testRun()
  elif TEST == 'cpuusage':
    status = cpuUsage()
    exit(status)
  elif TEST == 'memusage':
    status = memUsage()
    exit(status)
  else:
    print ('UNKNOWN: incorrect test defined (dsusage|memusage|cpuusage are accepted)')
    exit(UNKNOWN)
