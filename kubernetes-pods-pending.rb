#! /usr/bin/env ruby
#
# kubernetes-pods-pending.eb
# author: Murali Krishna Kanagala

#
# DESCRIPTION:
#   Monitors the pod status hitting the kubernetes API.
#   Dumps pending pod list to /tmp/sensu and comapres them in the next run.
#   Sensu check definition that runs this plugin should use autoresolve: false to
#   avoid the check resolving itself if it does not see any change in restart counts
#   in subsequesnt runs.
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

require 'sensu-plugin/check/cli'
require 'mixlib/shellout'
require 'json'

# rubocop:disable ClassLength
# rubocop:disable CyclomaticComplexity
# rubocop:disable RedundantReturn
# rubocop:disable Next
# rubocop:disable UselessAssignment
# rubocop:disable Eval
# rubocop:disable StringLiterals
# rubocop:disable PerceivedComplexity
# rubocop:disable AbcSize

# Inherit Sensu check cli
class PodsPending < Sensu::Plugin::Check::CLI
  option :server,
    short: '-s server',
    description: 'kubernetes api url',
    required: true

  option :token_file,
    short: '-t token_file',
    default: '/etc/kubernetes/ssl/auth.token',
    description: 'kubernetes authentication token'

  option :debug,
    short: '-d',
    boolean: true,
    default: false,
    description: 'Run the check in debug mode. For troubleshooting purposes only'

  def read_token(token_file, debug)
    # rubocop:disable RescueException
    if File.exist?(token_file)
      begin
        puts "Reading token file #{token_file}" if debug
        token = File.read(token_file)
      rescue Exception => e
        puts "Failed to read the file #{token_file} #{e}" if debug
        unknown "Failed to read the file #{token_file}\n#{e}"
      end
    else
      puts "File does not exist #{token_file}" if debug
      unknown "File does not exist #{token_file}"
    end
    return token
  end

  def run_cmd(cmd, debug)
    puts cmd if debug
    data_cmd = Mixlib::ShellOut.new(cmd)
    data_cmd.run_command
    puts data_cmd.stdout if debug
    if data_cmd.error?
      puts "Failed to run the command #{cmd}, #{data_cmd.stderr}" if debug
      unknown "Failed to run the command #{cmd.gsub(/\"[^)]+\"\s+/, '')}\n#{data_cmd.stderr}"
    end
    return data_cmd.stdout
  end

  def cmd_creator(debug)
    token_file = config[:token_file]
    server = config[:server]
    api_path = '/api/v1/pods'
    cmd1 = 'curl -k -H "Accept: application/json" -H "Authorization: Bearer '
    cmd2 = read_token(token_file, debug)
    cmd3 = "\" #{server}" + api_path
    cmd = cmd1 + cmd2 + cmd3
    puts cmd if debug
    return cmd
  end

  def pod_status_parser(data, debug)
    pod_status = []
    json_data = JSON.parse(data)
    json_data['items'].each do |item|
      cont_count = 0
      project = item['metadata']['namespace']
      pod_name = item['metadata']['name']
      status = item['status']['phase']
      if status == 'Pending'
        pod_status << { 'pod_name' => pod_name, 'project' => project, 'status' => status }
      end
    end
    puts pod_status if debug
    return pod_status
  end

  def time_diff(file)
    a = File.mtime(file).to_i
    b = Time.now.to_i
    c = b - a
    diff = Time.at(c).utc.strftime "%k hours %M minutes %S seconds"
    return diff
  end

  def run
    crit_pending = []
    debug = config[:debug]
    cmd = cmd_creator(debug)
    data = run_cmd(cmd, debug)

    Dir.mkdir('/tmp/sensu') unless File.directory?('/tmp/sensu')
    if File.exist?('/tmp/sensu/pod_status')
      previous_stats = File.read('/tmp/sensu/pod_status')
      previous_pod_stats = eval(previous_stats)
      interval = time_diff('/tmp/sensu/pod_status')
    else
      previous_pod_stats = {}
    end

    current_pod_stats = pod_status_parser(data, debug)

    previous_pod_stats.each do |prev_stat|
      pod_name = prev_stat['pod_name']
      proj_name = prev_stat['project']
      current_pod_stats.each do |cur_stat|
        if (pod_name == cur_stat['pod_name']) && (proj_name == cur_stat['project'])
          puts "comparing #{prev_stat} with #{cur_stat}" if debug
          if cur_stat['status'] == prev_stat['status']
            crit_pending << "#{proj_name}: #{pod_name}"
          end
        end
      end
    end

    File.open('/tmp/sensu/pod_status', 'w') { |f| f.write(current_pod_stats) }

    if crit_pending.length > 0
      critical "Pods in pending status from last #{interval}:\n#{crit_pending.join("\n")}"
    end
    ok "No pods are in pending status"
  end
end
