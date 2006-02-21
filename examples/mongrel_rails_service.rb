###############################################
# mongrel_rails_service.rb
#
# Control script for Rails powered by Mongrel
#
# WARNING: stop command still doesn't work with rails!
###############################################
require 'rubygems'
require 'mongrel'
require 'mongrel/command'

require 'win32/service'
include Win32

module GenericCommand
  def configure
    options [
      ['-n', '--name SVC_NAME', "Required name for the service to be registered/installed.", :@svc_name, nil],
    ]
  end
  
  def validate
    valid? @svc_name != nil, "You must specify the service name to be uninstalled."
    
    # We should validate service existance here, right Zed?
    begin
      valid? Service.exists?(@svc_name), "There is no service with that name, cannot proceed."
    rescue
    end
    
    return @valid
  end
end

class InstallCommand < Mongrel::Command::Command

  # Default every option to nil so only the defined ones get passed to service
  # (which will override ServiceCommand defaults).
  def configure
    options [
      ['-n', '--name SVC_NAME', "Required name for the service to be registered/installed.", :@svc_name, nil],
      ['-d', '--display SVC_DISPLAY', "Adjust the display name of the service.", :@svc_display, nil],
      ['-r', '--root PATH', "Set the root path where your rails app resides.", :@rails_root, Dir.pwd],
      ['-e', '--environment ENV', "Rails environment to run as", :@environment, 'production'],
      ['-b', '--binding ADDR', "Address to bind to", :@ip, nil],
      ['-p', '--port PORT', "Which port to bind to", :@port, 3000],
      ['-m', '--mime PATH', "A YAML file that lists additional MIME types", :@mime_map, nil],
      ['-P', '--num-procs INT', "Number of processor threads to use", :@num_procs, nil],
      ['-t', '--timeout SECONDS', "Timeout all requests after SECONDS time", :@timeout, nil],
    ]
  end

  # When we validate the options, we need to make sure the --root is actually RAILS_ROOT
  # of the rails application we wanted to serve, because later "as service" no error 
  # show to trace this.
  def validate
    @rails_root = File.expand_path(@rails_root)
    
    # start with the premise of app really exist.
    app_exist = true
    paths = %w{app config db log public}
    paths.each do |path|
      if !File.directory?(@rails_root + '/' + path)
        app_exist = false
        break
      end
    end
  
    valid? @svc_name != nil, "You must specify a valid service name to install."
    valid? app_exist == true, "The root of rails app isn't valid, please verify."
    valid_exists? @mime_map, "MIME mapping file does not exist: #@mime_map" if @mime_map
    
    # We should validate service existance here, right Zed?
    begin
      valid? !Service.exists?(@svc_name), "The service already exist, please uninstall it first."
    rescue
    end
    
    # Expand to get full path for mime-types file
    @mime_map = File.Expand_path(@mime_map) if @mime_map
    
    # default service display to service name
    @svc_display = @svc_name if !@svc_display
    
    return @valid
  end
  
  def build_params
    # build the parameters that will be used when register/install the service
    @params = ""
    
    # add "service" command
    @params << "service "
    
    # rails_root, must be quoted to support long_names
    @params << "-r \"#{@rails_root}\" "
    
    # environment
    @params << "-e #{@environment} " if @environment
    
    # binding
    @params << "-b #{@ip} " if @ip

    # port
    @params << "-p #{@port.to_i} " if @port

    # mime
    @params << "-m #{@mime_map} " if @mime_map

    # num_procs
    @params << "-P #{@num_procs.to_i} " if @num_procs

    # timeout
    @params << "-t #{@timeout.to_i} " if @timeout
  end
  
  def install_service
    # use rbconfig to get the path to bin ruby.exe
    require 'rbconfig'
    
    # ruby.exe instead of rubyw.exe due a exception raised when stoping the service!
    binary_path = ""
    binary_path << '"' << Config::CONFIG['bindir'] << '/ruby.exe' << '" '
    
    # add service_script
    service_script = File.expand_path(File.dirname(__FILE__) + '/mongrel_rails_svc.rb')
    binary_path << '"' << service_script << '" '
    
    # now add the parameters to it.
    binary_path << @params

    puts "Installing service with these options:"
    puts "service name: " << @svc_name
    puts "service display: " << @svc_display
     
    puts "RAILS_ROOT: " << @rails_root
    puts "RAILS_ENV: " << @environment if @environment
    puts "binding: " << @ip if @ip
    puts "port: " << @port.to_s if @port
    
    puts "mime_map: " << @mime_map if @mime_map
    puts "num_procs: " << @num_procs.to_s if @num_procs
    puts "timeout: " << @timeout.to_s if @timeout
    
    puts "ruby.exe: " << Config::CONFIG['bindir'] << '/ruby.exe'
    puts "service script: " << service_script
    puts

    svc = Service.new
    begin
      svc.create_service{ |s|
        s.service_name     = @svc_name
        s.display_name     = @svc_display
        s.binary_path_name = binary_path
        s.dependencies     = []
      }
      puts "#{@svc_display} service installed."
    rescue ServiceError => err
      puts "There was a problem installing the service:"
      puts err
    end
    svc.close
  end
  
  def run
    build_params
    install_service
  end
end

class DeleteCommand < Mongrel::Command::Command
  include GenericCommand

  def run
    display_name = Service.getdisplayname(@svc_name)
    
    begin
      Service.stop(@svc_name)
    rescue
    end
    begin
      Service.delete(@svc_name)
    rescue
    end
    puts "#{display_name} service deleted."
  end
end

class StartCommand < Mongrel::Command::Command
  include GenericCommand
  
  def run
    display_name = Service.getdisplayname(@svc_name)

    begin
      Service.start(@svc_name)
      started = false
      while started == false
        s = Service.status(@svc_name)
        started = true if s.current_state == "running"
        break if started == true
        puts "One moment, " + s.current_state
        sleep 1
      end
      puts "#{display_name} service started"
    rescue ServiceError => err
      puts "There was a problem starting the service:"
      puts err
    end
  end
end

class StopCommand < Mongrel::Command::Command
  include GenericCommand
  
  def run
    display_name = Service.getdisplayname(@svc_name)

    begin
      Service.stop(@svc_name)
      stopped = false
      while stopped == false
        s = Service.status(@svc_name)
        stopped = true if s.current_state == "stopped"
        break if stopped == true
        puts "One moment, " + s.current_state
        sleep 1
      end
      puts "#{display_name} service stopped"
    rescue ServiceError => err
      puts "There was a problem stopping the service:"
      puts err
    end
  end
end

Mongrel::Command::Registry.instance.run ARGV