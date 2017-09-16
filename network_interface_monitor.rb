#!/opt/sensu/embedded/bin/ruby

# Sensu plugin to check the status of network intefaces on a Ubuntu host.
# Tested on Ubuntu 14.04 LTS.
# Can check whether an interface is up, its physical link state and mtu.
# Accepts command line arguments with wildcards.

# rubocop:disable all
require 'sensu-plugin/check/cli'

class InterfaceStats

  # Find all the interfaces on this host by looking for directories /sys/class/net directory.
  # Ignores dummy interfaces.
  # Creates empty arrays and hashes.
  def initialize(debug)
    @debug = true if debug
    @stats = {}
    @all_interfaces = Dir["/sys/class/net/*"].select { |i| File.symlink?(i) }.map { |i| File.basename(i) }.reject { |i| i =~ /^dummy/ }
    puts "\nInterfaces in this host: #{@all_interfaces.inspect}" if @debug

    @picked_interfaces = []
    @picked_mtu_interfaces = []
  end
  
  # Interface files are not readable if the interface is down. 
  # So we need a method with resue from the file read failures.
  def file_read(file)
    begin
      content = File.read(file).strip
      puts "\nContent of #{file}: #{content}" if @debug
    rescue => e  
      puts "\nFailed to read #{file}" if @debug
      content = 'down'
      content = 0 if file.include? 'mtu'
      content = 0 if file.include? 'carrier' # 0 indicates carrier is down
    end
    return content
  end

  # Selects the interfaces passed in command line arguments.
  def pick_interfaces(incl, excl)
    @picked_interfaces = []
    if incl.size > 0
      @all_interfaces.each do |intf|
        incl.each do |inc_interface|
          if intf.match(/#{inc_interface}/)
            @picked_interfaces << intf
          end
        end
      end
    else
      @picked_interfaces = [] + @all_interfaces
    end

  # Excludes the interfaces passed in command line arguments.
    if excl.size > 0
      p_int = [] + @picked_interfaces
      p_int.each do |pint|
        excl.each do |exc_interface|
          if pint.match(/#{exc_interface}/)
            @picked_interfaces.delete(pint)
          end
        end
      end
    end
    puts "\nSelected interfaces to monitor: #{@picked_interfaces.inspect}" if @debug
  end

  # Selects the interfaces passed in command line arguments to check mtu.
  def pick_mtu_interfaces(mincl, mexcl)
    if mincl.size > 0
      @picked_interfaces.each do |mintf|
        mincl.each do |minc_interface|
          if mintf.match(/#{minc_interface}/)
            @picked_mtu_interfaces << mintf
          end
        end
      end
    else
      @picked_mtu_interfaces = [] + @picked_interfaces
    end

  # Excludes the interfaces passed in command line arguments to check mtu.
    if mexcl.size > 0
      # Creating a new array object with same content as a = b approah creates only a pointer in ruby.  
      p_m_int = [] + @picked_mtu_interfaces
      p_m_int.each do |pmint|
        mexcl.each do |mexc_interface|
          if pmint.match(/#{mexc_interface}/)
            @picked_mtu_interfaces.delete(pmint)
          end
        end
      end
      puts "\nPicked_mtu_interfaces after exlusion: #{@picked_mtu_interfaces}" if @debug
    end
    puts "\nSelected interfaces to monitor mtu: #{@picked_mtu_interfaces.inspect}" if @debug
  end

  # Loopback interfaces does not say 'up' in the files under /sys/class/net/lo/, eventhough
  # they are up and running. Reading the output from ip command to check the status of 
  # loopback interfaces.
  def lo_interface(lintf)
    puts "\nGetting loopback interface status #{lintf}" if @debug
    lo_state = `/sbin/ip addr show #{lintf}|grep -oF 'LOOPBACK,UP,LOWER_UP'`
    if lo_state.include? 'LOOPBACK,UP,LOWER_UP'
      operstate = 'up' 
    else
      operstate = 'down' 
    end
    puts "\nLoopback interface status: #{operstate}" if @debug
    return operstate
  end 

  # Creating an empty hash to store interface information.
  # Default mtu value of -1 indicates that we dont want to read mtu of that interface.
  def data_template
    @picked_interfaces.each do |int|
      @stats[int] = { :operstate => 'down', :carrier => 'down', :mtu => -1 }
    end
    puts "\nDefault stat template: #{@stats.inspect}" if @debug
  end

  # Getting operstate of interfaces and saving it to '@stats' hash.
  def operstate
    @picked_interfaces.each do |int|
      if int.include? 'lo'
        operstate = lo_interface(int)
      else
        operstate = file_read("/sys/class/net/#{int}/operstate")
      end
      @stats[int][:operstate] = operstate
    end 
    puts "\nOperstate stats: #{@stats.inspect}" if @debug
  end
 
  # Getting carrier staus of interfces and saving it to '@stats' hash. 
  def carrier
    @picked_interfaces.each do |int|
      carrier = file_read("/sys/class/net/#{int}/carrier")
      carrier.to_i == 1 ? carrier = 'up' : carrier = 'down'
      @stats[int][:carrier] = carrier
    end
    puts "\nCarrier stats: #{@stats.inspect}" if @debug
  end    

  # Getting mtu number of interfaces and saving it to '@stats' hash.
  def mtu
    @picked_mtu_interfaces.each do |int|
      mtu = file_read("/sys/class/net/#{int}/mtu")
      @stats[int][:mtu] = mtu.to_i
    end
    puts "\nMTU stats: #{@stats.inspect}" if @debug
  end 

  # Method to make use of all the methods above. 
  def get_stats(incl, excl, mincl, mexcl)
    pick_interfaces(incl, excl) 
    pick_mtu_interfaces(mincl, mexcl)
    data_template
    operstate
    carrier
    mtu
    puts "\nAll stats: #{@stats.inspect}" if @debug
    return @stats
 end
end

class CheckInterfaces < Sensu::Plugin::Check::CLI
  option :include,
    :short => '-i include',
    :long => '--include include',
    :description => 'Interfaces to check, default is none. Accepts comma sepratetd values(no space) and wildcards.',
    :default => [],
    :proc => Proc.new { |l| l.split(',') }

  option :exclude,
    :short => '-x exclude',
    :long => '--exclude exclude',
    :description => 'Interfaces to ignore, default is none. Accepts comma sepratetd values(no space) and wildcards.',
    :default => [],
    :proc => Proc.new { |l| l.split(',') }

  option :operstate,
    :short => '-o',
    :long => '--operstate',
    :description => 'Check interface operational state, default is false.',
    :boolean => true,
    :default => false

  option :carrier,
    :short => '-l',
    :long => '--link',
    :description => 'Check carrier status (physical link state), default is false.',
    :boolean => true,
    :default => false

  option :mtu,
    :short => '-m mtu',
    :long => '--mtu mtu',
    :description => 'MTU value to look for. MTU values are not checked if this value is not provided.',
    :proc=> Proc.new { |l| l.to_i },
    :default => 0
 
  option :check_mtu,
    :short => '-c check_mtu',
    :long => '--check_mtu check_mtu',
    :description => 'Check mtu values on these interfaces, default is none. Accepts comma sepratetd values(no space) and wildcards.',
    :default => [],
    :proc => Proc.new { |l| l.split(',') }

  option :exclude_mtu,
    :short => '-e exclude_mtu',
    :long => '--exclude_mtu exclude_mtu',
    :description => 'Exclude these interfaces from mtu checks, default is none.  Accepts comma sepratetd values(no space) and wildcards.',
    :default => [],
    :proc => Proc.new { |l| l.split(',') }

  option :warn_only,
    :short => '-w',
    :long => '--warn_only',
    :description => 'Send only warnings in case of failures.',
    :boolean => true,
    :default => false

  option :debug,
    :short => '-d',
    :long => '--debug',
    :description => 'Enable debugging.',
    :boolean => true,
    :default => false

  option :help,
    :short => '-h',
    :long => '--help',
    :description => "Show this message",
    :boolean => true,
    :show_options => true,
    :exit => 0

  def run
    debug = config[:debug]
    puts "\nArguments: #{config.inspect}" if debug

    incl = config[:include]
    excl = config[:exclude]
    mincl = config[:check_mtu]
    mexcl = config[:exclude_mtu]
    mtu = config[:mtu]
    operstate = config[:operstate]
    carrier = config[:carrier]
    warn_only = config[:warn_only]

    # Initialize in debug mode if specified.
    stats = InterfaceStats.new(debug)
    get_stats = stats.get_stats(incl, excl, mincl, mexcl)

    status = 0
    message = ''

    get_stats.each do |intf, stat|
      if (stat[:operstate] != 'up') && operstate
        status = 2
        message = message + 'Interface ' + intf + ' is down'  + "\n"
      end

      if (stat[:carrier] == 'down') && carrier
        status = 2
        message = message + 'Interface ' + intf + ' link status is down (cable damaged/unplugged)' + "\n"
      end

      if (mtu > 0) && (stat[:mtu] >= 0) && (stat[:mtu].to_i != mtu)
        status = 2
        message = message + 'Wrong mtu set on interface ' + intf + ': ' +  stat[:mtu].to_s + "\n"
      end
      puts "\nInterface: #{intf}, Stats: #{stat.inspect}, Check_status: #{status}, Message: #{message}" if debug
    end
   
    if status != 0 
      puts "\nCheck failed #{message}" if debug
      if warn_only
        warning(message)
      else
        critical(message)
      end
    else
      ok
    end
  end
end