#! /usr/bin/env ruby
#
#   openshift-node-status
# author: Murali Krishna Kanagala
#
# DESCRIPTION:
#   Compares the nodes list from Openshift API and from the
#   Ansible hosts file and alerts if they dont match
#   Checks whether the nodes are 'Ready' in Openshift by hitting the API.
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
# rubocop:disable UnusedBlockArgument
# rubocop:disable UselessAssignment
# rubocop:disable PerlBackrefs
class OpenShiftNodeStatus < Sensu::Plugin::Check::CLI
  option :server,
    short: '-s server',
    description: 'Openshift api url',
    required: true

  option :token_file,
    short: '-t token_file',
    default: '/etc/openshift/ssl/auth.token',
    description: 'Openshift authentication token, default: /etc/openshift/ssl/auth.token'

  option :hosts_file,
    short: '-a hosts_file',
    default: '/etc/ansible/hosts',
    description: 'Openshift Ansible hosts file, default: /etc/ansible/hosts'

  option :debug,
    short: '-d',
    boolean: true,
    default: false,
    description: 'Run the check in debug mode, do not use this flag with actual check'

  def read_token(token_file, debug)
    # rubocop:disable RescueException
    if File.exist?(token_file)
      begin
        puts "DEBUG - Reading token file #{token_file}" if debug
        token = File.read(token_file)
      rescue Exception => e
        puts "DEBUG - Failed to read the file #{token_file} #{e}" if debug
        unknown "Failed to read the file  #{token_file} #{e}"
      end
    else
      puts "DEBUG - File does not exist #{token_file}" if debug
      unknown "File does not exist #{token_file}"
    end
    puts "DEBUG - token: \n#{token}" if debug
    return token
  end

  def run_cmd(cmd, debug)
    puts "DEBUG - running command #{cmd}" if debug
    puts cmd if debug
    data_cmd = Mixlib::ShellOut.new(cmd)
    data_cmd.run_command
    puts data_cmd.stdout if debug
    if data_cmd.error?
      puts "DEBUG - Failed to run the command #{cmd}, #{data_cmd.stderr}" if debug
      unknown "Failed to run the command #{cmd.gsub(/\"[^)]+\"\s+/, '')}, #{data_cmd.stderr}"
    end
    return data_cmd.stdout
  end

  def cmd_creator(debug)
    token_file = config[:token_file]
    server = config[:server]
    api_path = '/api/v1/nodes'
    cmd1 = 'curl -k -H "Accept: application/json" -H "Authorization: Bearer '
    cmd2 = read_token(token_file, debug)
    cmd3 =  "\" #{server}" + api_path
    cmd = cmd1 + cmd2 + cmd3
    puts "DEBUG - created command #{cmd}" if debug
    return cmd
  end

  def node_status_parser(data, debug)
    node_status = {}
    status = ''
    json_data = JSON.parse(data)
    json_data['items'].each do |item|
      node_name =  item['metadata']['name']
      item['status']['conditions'].each do |cond|
        status =  cond['status'] if cond['type'] == 'Ready'
      end
      node_status[node_name] = status
    end
    puts  "DEBUG - node status from api:\n #{node_status}" if debug
    return node_status
  end

  def hosts_file_parser(hosts_file, debug)
    ini = {}
    node_list = []
    cur_section = nil
    File.open(hosts_file).each do |line|
      if line.strip.split(';').first =~ /^\[(.*)\]$/
        cur_section = $1
        ini[cur_section] = Hash.new
        next
      end
      if line.strip.split(';').first =~ /\=/
        key = line.strip.split(';').first.split('=')
        ini[cur_section].merge!(key[0] => key[1].nil? ? '' : key[1])
      end
    end
    ini['nodes'].each do |node, data|
      node_list << node.split(' ').first
    end
    puts "DEBUG - node list from ansible hosts file: \n #{node_list}" if debug
    return node_list
  end

  def run
    crit_stat = ''
    node_list_from_api = []
    Dir.mkdir('/tmp/sensu') unless File.directory?('/tmp/sensu')
    debug = config[:debug]
    cluster = config[:server].split('.')[1..-1].join('.')
    cmd = cmd_creator(debug)
    data = run_cmd(cmd, debug)
    node_status = node_status_parser(data, debug)
    node_list = hosts_file_parser(config[:hosts_file], debug)
    if node_status.count != node_list.count
      node_status.each do |st, ts|
        node_list_from_api << st
      end
      missing_nodes = node_list_from_api - node_list | node_list - node_list_from_api
      missing = node_list.count - node_status.count
      if missing < 0
        crit_stat = "unexpected node(s) in the cluster #{cluster} \n #{missing_nodes}"
      elsif missing > 0
        crit_stat = "#{missing} node(s) are missing from the cluster #{cluster} \n #{missing_nodes}"
      end
    end

    node_status.each do |name, stat|
      if stat != 'True'
        crit_stat = crit_stat + 'Node is not Ready: ' + name + "\n"
      end
    end

    critical crit_stat if crit_stat.length > 0
    ok 'All nodes are ready'
  end
end
