#!/usr/bin/env ruby

# rubocop:disable all
# Sensu check to monitor "Media_Wearout_Indicator" of Intel solid state drives.
# Looks for the "VALUE" field (not RAW_VALUE) in smartctl output.
# Requires "smartmontools" installed.
# Works only with Intel SSD drives. Tested only on "INTEL SSDSC2BB240G4".
# Intel strongly suggests to replace the disk when
# the value of "Media_Wearout_Indicator" is 1.

require 'sensu-plugin/check/cli'

$legend = 'Wearout Indicator values
 New disk :100
 Worn out: 1
 1 is the lowest number we can see.'

class Disk
  def get_cmd(mode)
    @debug = true if mode
    @cmd = `/usr/bin/which smartctl`.strip
    if @cmd.length > 1
      puts "Using binary: #{@cmd}" if @debug
      return true
    else
      return false
    end
  end

  def disk_list
    list = []
    full_list = `#{@cmd} --scan`.split("\n")
    puts "Disks on this host:\n #{full_list}\n" if @debug
    full_list.each do |line|
      list << line.split(" ").first
    end
    return list
  end

  def find_intel_ssd(list)
    ssd_disks = []
    puts "Disk information: " if @debug
    list.each do |disk|
      info = `#{@cmd} -i #{disk}`
      puts info if @debug
      if info.include? 'INTEL SSD'
        ssd_disks << disk
      end
    end
    puts "SSDs on this host: #{ssd_disks.inspect}" if @debug
    return ssd_disks
  end

  def wearout(ssd_disks)
    wear_status = {}
    ssd_disks.each do |ssd|
      wear_ind = `#{@cmd} -A #{ssd}|grep 'Media_Wearout_Indicator'|awk '{print $4}'`
      wear_status[ssd] = wear_ind.to_i
    end
    puts "Wear status: #{wear_status.inspect}\n" if @debug
    return wear_status
  end

end


class SMART < Sensu::Plugin::Check::CLI

  option :warn,
    :short => '-w warn',
    :default => 10,
    :proc => proc {|a| a.to_i },
    :description => 'Warning threshold'

  option :crit,
    :short => '-c crit',
    :default => 5,
    :proc => proc {|a| a.to_i },
    :description => "Critical threshold"

  option :debug,
    :short => '-d',
    :description => "Debug mode"

  def run
    wear_crit = ''
    wear_warn = ''
    wear_ok = ''

    d = Disk.new
    c = d.get_cmd(config[:debug])
    if c
      list = d.disk_list
      ssd_disks = d.find_intel_ssd(list)
      wearout_status = d.wearout(ssd_disks)
      wearout_status.each do |k ,v|
        status = ' (disk:' + k + ', wearout_indicator:' + v.to_s + ')'
        if v <= config[:crit]
          wear_crit = wear_crit + status
        elsif v <= config[:warn]
          wear_warn = wear_warn + status
        else
          wear_ok = wear_ok + status
        end
      end

      critical "#{wear_crit} worn out. Replace it asap.\n#{$legend}" if wear_crit.length > 4
      warning "#{wear_warn} approaching wearout limit.\n#{$legend}"  if wear_warn.length > 4
      if wear_ok.length > 4
        ok "All Intel SSDs are looking good #{wear_ok}. \n#{$legend}"
      else
        ok "No Intel SSDs installed on this host."
      end
    else
      unknown "Command smartctl not found, smartmontools not installed on this host"
    end
  end
end