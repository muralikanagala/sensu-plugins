#!/usr/bin/env ruby

#  author: Murali Kanagala
#  ESXi health monitoring script
#  Uses ssh to check whether and ESXi host is up and runs vm listing command
#  Written for VMWare ESXi 5.5
#  Compatible with Nagios and Sensu

require 'optparse'
require 'net/ssh'
require 'ostruct'

def parse(args)
  options = OpenStruct.new

  opt_parser = OptionParser.new do |opts|
    opts.banner = 'Usage: esxi-ssh-check.rb [options]'
    opts.separator ''

    opts.on('-H', '--esxi_host esxi_host') do |esxi_host|
      options.esxi_host = esxi_host
    end
    opts.on('-u', '--user user') do |user|
      options.user = user
    end
    opts.on('-p', '--password password') do |password|
      options.password = password
    end
    opts.on('-h', '--help') do
      puts opts
      exit
    end
  end
  opt_parser.parse!(args)
  options
end

options = parse(ARGV)
esxi_host = options.esxi_host
ssh_user = options.user
ssh_password = options.password

if !options.esxi_host || !options.user || !options.password
  puts 'UNKNOWN: Insufficient arguments. Use -h option for help'
  exit 3
end

begin
  esxi_session = Net::SSH.start(esxi_host, ssh_user, :password => ssh_password)
  list = esxi_session.exec!('vim-cmd vmsvc/getallvms')
  esxi_session.close

  if list.match(/sh:.*not found/) || list.match(/Invalid command.*/)
    message = "CRITICAL: Failed to list VMs on ESXi host #{options.esxi_host}"
    return_code = 2
  else
    message = "OK: ESXi ssh test successful for #{options.esxi_host}"
    return_code = 0
  end
rescue
  message = "CRITICAL: Failed to ssh #{options.esxi_host}"
  return_code = 2
end

puts message
exit return_code