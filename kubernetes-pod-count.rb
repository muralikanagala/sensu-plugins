#! /usr/bin/env ruby
#
# kubernetes-pod-count
# author: Murali Krishna Kanagala

# DESCRIPTION:
#  Monitors the number of pods in a Kubernetes cluster and alerts if
#  the number drops below the threshold.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: mixlib-shellout
#   gem: json
#   gem: uri

require 'sensu-plugin/check/cli'
require 'mixlib/shellout'
require 'json'
require 'uri'

# rubocop:disable ClassLength
# rubocop:disable CyclomaticComplexity
# rubocop:disable RedundantReturn
# rubocop:disable Next
# rubocop:disable UnusedBlockArgument
# rubocop:disable UselessAssignment
# rubocop:disable PerlBackrefs
# rubocop:disable Eval
# rubocop:disable StringLiterals
# Inherit Sensu check cli
class CheckPodCount < Sensu::Plugin::Check::CLI
  option :server,
    short: '-s server',
    description: 'Kubernetes api url',
    required: true

  option :token_file,
    short: '-t token_file',
    default: '/etc/kubernetes/ssl/auth.token',
    description: 'Kubernetes authentication token'

  option :crit,
    short: '-c crit',
    required: true,
    proc: proc(&:to_i),
    description: 'Critical threshold for the drop in number of the pods'

  option :warn,
    short: '-w warn',
    required: true,
    proc: proc(&:to_i),
    description: 'Warning thresold for the drop in number of the pods'

  option :debug,
    short: '-d',
    boolean: true,
    default: false,
    description: 'Run the check in debug mode. For troubleshooting purposes only'

  def read_file(file, debug)
    # rubocop:disable RescueException
    if File.exist?(file)
      begin
        puts "Reading token file #{file}" if debug
        content = File.read(file)
      rescue Exception => e
        puts "Failed to read the file #{file} #{e}" if debug
        unknown "Failed to read the file  #{file} #{e}"
      end
    else
      puts "File does not exist #{file}" if debug
      unknown "File does not exist #{file}"
    end
    return content
  end

  def run_cmd(cmd, debug)
    puts cmd if debug
    data_cmd = Mixlib::ShellOut.new(cmd)
    data_cmd.run_command
    puts data_cmd.stdout if debug
    if data_cmd.error?
      puts "Failed to run the command #{cmd}, #{data_cmd.stderr}" if debug
      unknown "Failed to run the command #{cmd.gsub(/\"[^)]+\"\s+/, '')}, #{data_cmd.stderr}"
    end
    return data_cmd.stdout
  end

  def cmd_creator(debug)
    token_file = config[:token_file]
    server = config[:server]
    api_path = '/api/v1/pods'
    cmd1 = 'curl -k -H "Accept: application/json" -H "Authorization: Bearer '
    cmd2 = read_file(token_file, debug)
    cmd3 =  "\" #{server}" + api_path
    cmd = cmd1 + cmd2 + cmd3
    puts cmd if debug
    return cmd
  end

  def pod_count_parser(data, debug)
    node_status = {}
    status = ''
    json_data = JSON.parse(data)
    pod_count = json_data['items'].count
    puts "pod count: #{pod_count}" if debug
    return pod_count.to_i
  end

  def run
    debug = config[:debug]
    Dir.mkdir('/tmp/sensu') unless File.directory?('/tmp/sensu')
    previous_pod_count = File.exist?('/tmp/sensu/pod_count') ? File.read('/tmp/sensu/pod_count').to_i : -1
    cluster = config[:server].split('.')[1..-1].join('.')
    cmd = cmd_creator(debug)
    data = run_cmd(cmd, debug)
    pod_count = pod_count_parser(data, debug)
    puts "previous_pod_count: #{previous_pod_count}" if debug
    puts "current_pod_count: #{pod_count}" if debug
    File.write('/tmp/sensu/pod_count', pod_count)

    pod_drop = previous_pod_count - pod_count
    puts "pod_drop: #{pod_drop}" if debug
    pod_drop_percent = (pod_drop * 100 / previous_pod_count).round
    puts "pod_drop_percent: #{pod_drop_percent}" if debug
    info = "previous pod count: #{previous_pod_count} \n current pod count: #{pod_count} \n pod drop percent: #{pod_drop_percent}"
    if pod_drop > 0
      if pod_drop_percent >= config[:crit]
        critical "Number of pods dropped by #{pod_drop_percent.round(2)} percent in #{cluster} \n #{info}"
      elsif pod_drop_percent >= config[:warn]
        warning "Number of pods dropped by #{pod_drop_percent.round(2)} percent in #{cluster} \n #{info}"
      end
    end
    ok "Number of pods dropped is within the threshold \n #{info}"
  end
end
