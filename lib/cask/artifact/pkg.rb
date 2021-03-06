class Cask::Artifact::Pkg < Cask::Artifact::Base
  # this class actually covers two keys, :install and :uninstall
  def self.artifact_dsl_key
    :install
  end

  def self.read_script_arguments(uninstall_options, key)
    script_arguments = uninstall_options[key]

    # backwards-compatible string value
    if script_arguments.kind_of?(String)
      script_arguments = { :executable => script_arguments }
    end

    # key sanity
    permitted_keys = [:args, :input, :executable]
    unknown_keys = script_arguments.keys - permitted_keys
    unless unknown_keys.empty?
      opoo "Unknown arguments to uninstall :#{key} -- :#{unknown_keys.join(", :")} (ignored). Running `brew update; brew upgrade brew-cask` will likely fix it.'"
    end
    script_arguments.reject! {|k,v| ! permitted_keys.include?(k)}

    # extract executable
    if script_arguments.key?(:executable)
      executable = script_arguments.delete(:executable)
    else
      executable = nil
    end

    script_arguments.merge!(:sudo => true, :print => true)
    return executable, script_arguments
  end

  def install
    @cask.artifacts[:install].each { |pkg| run_installer(pkg) }
  end

  def uninstall
    @cask.artifacts[:uninstall].each { |opts| manually_uninstall(opts) }
  end

  def run_installer(pkg_relative_path)
    ohai "Running installer for #{@cask}; your password may be necessary."
    args = [
      '-pkg',    @cask.destination_path.join(pkg_relative_path),
      '-target', '/'
    ]
    args << '-verboseR' if ARGV.verbose?
    @command.run!('/usr/sbin/installer', {:sudo => true, :args => args, :print => true})
  end

  def manually_uninstall(uninstall_options)
    ohai "Running uninstall process for #{@cask}; your password may be necessary"

    unknown_keys = uninstall_options.keys - [:script, :quit, :kext, :pkgutil, :launchctl, :files]
    unless unknown_keys.empty?
      opoo "Unknown arguments to uninstall: #{unknown_keys.join(", ")}. Running `brew update; brew upgrade brew-cask` will likely fix it.'"
    end

    if uninstall_options.key? :script
      executable, script_arguments = self.class.read_script_arguments(uninstall_options, :script)
      ohai "Running uninstall script #{executable}"
      raise "Error in Cask #{@cask}: uninstall :script without :executable." if executable.nil?
      @command.run!(@cask.destination_path.join(executable), script_arguments)
    end

    if uninstall_options.key? :launchctl
      [*uninstall_options[:launchctl]].each do |service|
        ohai "Removing launchctl service #{service}"
        @command.run!('/bin/launchctl', :args => ['remove', service], :sudo => true)
      end
    end

    if uninstall_options.key? :quit
      [*uninstall_options[:quit]].each do |id|
        ohai "Quitting application ID #{id}"
        num_running = @command.run!('/usr/bin/osascript', :args => ['-e', "tell application \"System Events\" to count processes whose bundle identifier is \"#{id}\""], :sudo => true).to_i
        if num_running > 0
          @command.run!('/usr/bin/osascript', :args => ['-e', "tell application id \"#{id}\" to quit"], :sudo => true)
        end
      end
    end

    if uninstall_options.key? :kext
      [*uninstall_options[:kext]].each do |kext|
        ohai "Unloading kernel extension #{kext}"
        is_loaded = @command.run!('/usr/sbin/kextstat', :args => ['-l', '-b', kext], :sudo => true)
        if is_loaded.length > 1
          @command.run!('/sbin/kextunload', :args => ['-b', kext], :sudo => true)
        end
      end
    end

    if uninstall_options.key? :pkgutil
      ohai "Removing files from pkgutil Bill-of-Materials"
      pkgs = Cask::Pkg.all_matching(uninstall_options[:pkgutil], @command)
      pkgs.each(&:uninstall)
    end

    if uninstall_options.key? :files
      uninstall_options[:files].each do |file|
        ohai "Removing file #{file}"
        @command.run!('/bin/rm', :args => ['-rf', file], :sudo => true)
      end
    end
  end
end

