#!/usr/bin/env ruby

# Sensu check to boot a vm, attach a floating ip and attach a volume.
# This plugin can send metrics to Graphite which can be suppressed by a command line flag.
# Performs cleanup after every check unless told not to.


# rubocop:disable all
require 'sensu-plugin/check/cli'
require 'fog/openstack'
require 'uri'
require 'socket'

### Global variables
$graphite_host = your_graphite_host
$graphite_port = your_graphite_port
$create_items =  {}
$attach_items = {}
$detach_items = {}
$delete_items = {}
$cleanup_items = {}

class RunTest

### Create
  def session(conn_params={})
    start = Time.now
    begin
      compute = Fog::Compute::OpenStack.new(conn_params)
    rescue StandardError => e
      compute = false
      err = "Failed to create api connectionx\n#{conn_params}\n#{e.inspect}"
      status = 2
    end
    finish = Time.now
    duration = (finish - start)
    @compute = compute
    $create_items[:session] = { :status => status||0, :session => @compute||'', :err => err||'', :duration => duration||0 }
  end

  def create_server(instance_params={})
    if @compute
      start = Time.now
      begin
        server = @compute.servers.create(instance_params)
        server.wait_for { ready? }
      rescue StandardError => e
        server = false
        err = "Failed to create instance\n#{instance_params}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      @server = server
      $create_items['server'] = { :status => status||0, :err => err||'', :server => @server.inspect, :duration => duration||0 }
    end
  end

  def pick_fip(fipool)
    if @compute
      start = Time.now
      begin
        fip = @compute.addresses.create(:pool => fipool)
      rescue => e
        fip = false
        err = "Failed to pick floating ip #{fipool}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      @fip = fip
      $create_items['fip'] = { :status => status||0, :err => err||'', :fip => @fip||'', :duration => duration||0 }
    end
  end

  def create_vol(vol_params={})
    if @compute
      start = Time.now
      begin
        volume = @compute.volumes.create(vol_params)
        volume.wait_for { status == 'available' }
      rescue => e
        volume = false
        err = "Failed to create volume #{vol_params}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      @volume = volume
      $create_items['volume'] = { :status => status||0, :err => err||'', :volume => @volume||'', :duration => duration||0 }
    end
  end

### Attach
  def attach_fip()
    if @server && @fip
      start = Time.now
      begin
        attach = @server.associate_address(@fip.ip)
      rescue => e
        err = "Failed to attach floatin ip #{@fip.ip} to #{@server.id}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      $attach_items['fip'] = { :status => status||0, :err => err||'', :attach => attach.inspect, :duration => duration||0 }
    end
  end

  def attach_vol
    if @server && @volume
      start = Time.now
      begin
        attach = @server.attach_volume(@volume.id, '/dev/vdb')
        @volume.wait_for { status == 'in-use' } if @volume
      rescue => e
        err = "Failed to attach volume #{@volume} to #{@server.id}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      $attach_items['volume'] = { :status => status||0, :err => err||'', :attach => attach.inspect, :duration => duration||0 }
    end
  end

### Detach
  def detach_fip
    if @server && @fip
      start = Time.now
      begin
        detach = @compute.disassociate_address(@server.id, @fip.ip)
      rescue => e
        err = "Failed to detach floating ip #{@fip} from #{@server.id}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      $detach_items['fip'] = { :status => status||0, :err => err||'', :detach => detach.inspect, :duration => duration||0 }
    end
  end

  def detach_vol
    if @server && @volume
      start = Time.now
      begin
        detach = @server.detach_volume(@volume.id)
        @volume.wait_for { status == 'available' }
      rescue => e
        err = "Failed to detach volume #{@volume.id} from #{@server.id}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      $detach_items['volume'] = { :status => status||0, :err => err||'', :detach => detach, :duration => duration||0 }
    end
  end

### Delete
  def delete_fip(fip = @fip)
    if @compute && fip
      start = Time.now
      begin
        delete = @compute.release_address(fip.id)
      rescue => e
        err = "Failed to delete floating ip #{fip.ip}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      $delete_items['fip'] = { :status => status||0, :err => err||'', :delete => delete.inspect, :duration => duration||0 }
    end
  end

  def delete_vol(vol = @volume)
    if @compute && vol
      start = Time.now
      begin
        delete = vol.destroy
      rescue => e
        err = "Failed to delete volume #{vol.id}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      $delete_items['volume'] = { :status => status||0, :err => err||'', :delete => delete.inspect, :duration => duration||0 }
    end
  end

  def delete_server(server = @server)
    if server
      start = Time.now
      begin
        delete = server.destroy
        begin
          stat = @compute.get_server_details(server.id).status
        end while stat == 404
      rescue => e
        err = "Failed to delete instance #{server.id}\n#{e.inspect}"
        status = 2
      end
      finish = Time.now
      duration = (finish - start)
      $delete_items['server'] = { :status => status||0, :err => err||'', :delete => delete.inspect, :duration => duration||0 }
    end
  end

### Cleanup
  def cleanup_items
    if @compute
      cleanup_servers = []
      cleanup_volumes = []
      cleanup_fips = []

      servers = @compute.servers.all
      volumes = @compute.volumes.all
      fips = @compute.addresses

      servers.each do |ser|
        if ser.name == 'sensu-check-instance'
          cleanup_servers << ser.id
        end
      end

      volumes.each do |vol|
        if vol.name == 'sensu-check-volume' && vol.status != 'deleting'
          cleanup_volumes << vol.id
        end
      end

      fips.each do |fip|
        cleanup_fips << fip
      end
      { :servers => cleanup_servers, :volumes => cleanup_volumes, :fips => cleanup_fips }
    end
  end

  def cleanup
    if @compute
      items = cleanup_items

      items[:servers].each do |ser|
         vm = @compute.servers.get(ser)
         delete_server(vm)
      end

      items[:fips].each do |fip|
         delete_fip(fip)
      end

      items[:volumes].each do |v|
        vol = @compute.volumes.get(v)
        delete_vol(vol)
      end

      sleep 5
      stat = 0
      items_after_cleanup = cleanup_items
      items_after_cleanup.each do |k, v|
        if v.count > 1
          stat = 1
        end
      end

      $cleanup_items = { :servers => items[:servers], :volumes => items[:volumes], :fips => items[:fips], :status => stat||0, :err => items_after_cleanup }
    end
  end

### Graphite
  def cloud_name(url)
    uri = URI.parse(url)
    return uri.host.split('.').first
  end

  def graphite_data(data)
    begin
      connect = TCPSocket.new($graphite_host, $graphite_port)
      data.each do |k, entry|
        connect.puts(entry)
      end
      connect.close
    rescue => e
      status = 2
      err = "Failed to send data #{e.inspect}"
    end
    return { :status => status||0, :err => err||''}
  end
end


class BootAttachFloatipVolume < Sensu::Plugin::Check::CLI
  option :auth_url,
    :short => '-a auth_url',
    :required => true,
    :proc => proc {|a| a.to_s },
    :description => 'Keystone auth url'

  option :user_name,
    :short => '-u user_name',
    :required => true,
    :proc => proc {|a| a.to_s },
    :description => "Openstack user name"

  option :password,
    :short => '-p password',
    :required => true,
    :proc => proc {|a| a.to_s },
    :description => "Openstack password"

  option :tenant_name,
    :short => '-t tenant_name',
    :required => true,
    :proc => proc {|a| a.to_s },
    :description => "Tenant name to use for the check"

  option :connect_timeout,
    :short => '-st connect_timeout',
    :proc => proc {|a| a.to_i },
    :default => 300,
    :description => 'Timeout to create a session in seconds (default: 300)'

  option :read_timeout,
    :short => '-rt read_timeout',
    :default => 300,
    :proc => proc {|a| a.to_s },
    :description => 'Timeout to read over the session in seconds (default: 300)'

  option :write_timeout,
    :short => '-wt write_timeout',
    :default => 300,
    :proc => proc {|a| a.to_s },
    :description => 'Timeout to write over the session in seconds (default: 300)'

  option :ssl_ca_file,
    :short => '-c ssl_ca_file',
    :default => '/etc/ssl/certs/ca-certificates.crt',
    :proc => proc {|a| a.to_s },
    :description => 'SSL CA certificate path (default: /etc/ssl/certs/ca-certificates.crt)'

  option :image,
    :short => '-i image',
    :proc => proc {|a| a.to_s },
    :description => 'Image to use to run the check'

  option :flavor,
    :short => '-f flavor',
    :default => 'sbc.tiny',
    :proc => proc {|a| a.to_s },
    :description => 'Flavor name to run the check (default: sbc.tiny)'

  option :network,
    :short => '-n network',
    :default => false,
    :proc => proc {|a| a.to_s },
    :description => 'Network id to attach to the instance (default: none)'

  option :sec_group,
    :short => '-g sec_group',
    :default => 'default',
    :proc => proc {|a| a.to_s },
    :description => 'Security group to use with the instance (default: default)'

  option :key_name,
    :short => '-k key_name',
    :default => 'sensu-check',
    :proc => proc {|a| a.to_s },
    :description => 'Key to use to access the instance (default: sensu-check)'

  option :volume_size,
    :short => '-v volume_size',
    :default => '1',
    :proc => proc {|a| a.to_i },
    :description => 'Size of the cinder volume to create for the check (default: 1GB)'

  option :floating_ip_pool,
    :short => '-o floating_ip_pool',
    :required => true,
    :proc => proc {|a| a.to_s },
    :description => 'Floating IP pool name to pick a floating IP for the check'

  option :metrics,
    :short => '-m',
    :default => false,
    :boolean => true,
    :description => 'Do not send metrics to Graphite'

  option :cleanup,
    :short => '-C',
    :default => false,
    :boolean => true,
    :description => 'Suppress cleanup activity after running the check'

  option :debug,
    :short => '-d item',
    :in => ['request', 'response', 'all'],
    :description => 'Set debug option (request, response, all)'


  def run

### If asked for Debug
    if config[:debug] == 'all'
      config[:debug_request] = true
      config[:debug_response] = true
    else
      config[:debug_request] = false
      config[:debug_response] = false
      item = config[:debug]
      config["debug_#{item}"] = true
    end

### Connection, Instance, FIP and Volume Parameters
    conn_opts = {
      :ssl_ca_file => config[:ssl_ca_file],
      :debug_request => config[:debug_request],
      :debug_response => config[:debug_response],
      :connect_timeout => config[:connect_timeout],
      :read_timeout => config[:read_timeout],
      :write_timeout => config[:write_timeout]
    }

    conn_params = {
      :openstack_auth_url => config[:auth_url],
      :openstack_username => config[:user_name],
      :openstack_api_key => config[:password],
      :openstack_tenant => config[:tenant_name],
      :connection_options  => conn_opts
    }

    instance_params = {
      :image_ref => config[:image],
      :flavor_ref => config[:flavor],
      :security_groups => config[:sec_group],
      :key_name => config[:key_name],
      :name => 'sensu-check-instance'
    }

    fip_params = {
      :fipool => config[:floating_ip_pool]
    }

    volume_params = {
      :size => config[:volume_size],
      :name => 'sensu-check-volume',
      :description => 'Sensu check volume'
    }

### To Attach provided network
    if config[:network]
      nics = [ { :net_id => config[:network] } ]
      instance_params[:nics] = nics
    end

### Debug output
    if config[:debug]
      puts 'PARAMETERS ' + '=' * 30
      p conn_params
      p instance_params
      p volume_params
      p fip_params
      p config[:metrics]
    end

### Initialize new check
    check = RunTest.new

### Metric Prefix and Variables
    cloud_prefix = check.cloud_name(config[:auth_url])
    prefix = "#{cloud_prefix}.openstack.boot_attach_fip_volume"
    timestamp = Time.now.to_i.to_s
    metrics = {  ### Default metrics
      'create_session' => "#{prefix}.create_session 0 #{timestamp}",
      'create_server' => "#{prefix}.create_server 0 #{timestamp}",
      'create_fip' => "#{prefix}.create_fip 0 #{timestamp}",
      'create_volume' => "#{prefix}.create_volume 0 #{timestamp}",
      'attach_fip' => "#{prefix}.attach_fip 0 #{timestamp}",
      'attach_volume' => "#{prefix}.attach_volume 0 #{timestamp}",
      'detach_fip' => "#{prefix}.detach_fip 0 #{timestamp}",
      'detach_volume' => "#{prefix}.detach_volume 0 #{timestamp}",
      'delete_server' => "#{prefix}.delete_server 0 #{timestamp}",
      'delete_fip' => "#{prefix}.delete_fip 0 #{timestamp}",
      'delete_volume' => "#{prefix}.delete_volume 0 #{timestamp}"
    }
    err = ''
    message = ''

### Create
    check.session(conn_params)
    check.create_server(instance_params)
    check.pick_fip(fip_params[:fipool])
    check.create_vol(volume_params)

#### Attach
    check.attach_fip
    check.attach_vol

#### Detach
    check.detach_fip
    check.detach_vol

#### Delete
    check.delete_fip
    check.delete_vol
    check.delete_server
    sleep 10

### Cleanup
    if !config[:cleanup]
      check.cleanup
    end

### Debug output
    if config[:debug]
      puts 'CREATE ACTIONS ' + '=' * 30
      p $create_items
      puts 'ATTACH ACTIONS ' + '=' * 30
      p $attach_items
      puts 'DETACH ACTIONS ' + '=' * 30
      p $detach_items
      puts 'DELETE ACTIONS ' + '=' * 30
      p $delete_items
      puts 'CLEANUP ACTIONS ' + '=' * 30
      p $cleanup_items
    end

### Stats and Alert content
    $create_items.each do |k, v|
      if v[:status] != 0
        message = message + "Failed to create #{k}.\n #{v[:err]}\n"
        st = 2
      else
        item = "create_#{k}"
        metrics[item] = "#{prefix}.create_#{k} #{v[:duration]} #{timestamp}"
      end
    end

    $attach_items.each do |k, v|
      if v[:status] != 0
        message = message + "Failed to attach #{k}.\n #{v[:err]}\n"
        st = 2
      else
        item = "attach_#{k}"
        metrics[item] = "#{prefix}.attach_#{k} #{v[:duration]} #{timestamp}"
      end
    end

    $delete_items.each do |k, v|
      if v[:status] != 0
        message = message + "Failed to delete #{k}.\n #{v[:err]}\n"
        st = 2
      else
        item = "delete_#{k}"
        metrics[item] = "#{prefix}.delete_#{k} #{v[:duration]} #{timestamp}"
      end
    end

    if !$cleanup_items.empty? && $cleanup_items[:status] != 0
      st = 1 if st != 2
      message = message + "Failed to perform cleanup.\n #{$cleanup_items[:err]}"
    end

### Graphite Data
    if !config[:metrics]
      check.graphite_data(metrics)
    end

### Sensu Alert
    if st == 2
      critical message
    elsif st == 1
      warning message
    else
      ok message
    end
  end
end
