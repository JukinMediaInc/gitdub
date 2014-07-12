#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'logger'
require 'sinatra/base'
require 'yaml'
require 'open3'

def which(cmd)
  ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
    exe = "#{path}/#{cmd}"
    return exe if File.executable?(exe)
  end
  nil
end

raise 'could not find git-notifier in $PATH' unless which('git-notifier')

if ARGV.size != 1
  STDERR.puts "usage: #{$0} <config.yml>"
  exit 1
end

CONFIG = YAML.load_file(ARGV[0])

class GitNotifier
  STATE_FILE = '.git-notifier.dat'

  private

  MAPPINGS = {
      :from => 'sender',
      :to => 'mailinglist',
      :subject => 'emailprefix'
  }

  public

  def self.run(path, opts)
    success = execute(path, Hash[opts.map { |k, v| [MAPPINGS[k] || k, v] }])
    $logger.error('git-notifier failed') unless success
    success
  end

  private

  def self.execute(path, args = [])
    args = args.map do |k, v|
      v = v * ',' if k == 'mailinglist'
      next unless v
      ["--#{k}"] + (!!v == v ? [] : ["#{v}"]) # Ignore non-boolean values.
    end
    args << '--log'
    args << '/var/log/git-notifier.log'
    $logger.debug("args='#{args}'")
    current = Dir.pwd()
    success = true
    Dir.chdir(path)
    begin
      $logger.debug('> git fetch origin +refs/heads/*:refs/heads/*')
      success = system('git', 'fetch', 'origin', '+refs/heads/*:refs/heads/*')
      raise "git fetch failed in #{path}" unless success
      args = args.flatten.delete_if { |x| x.nil? }
      $logger.debug("> git-notifier #{args}")
      success = system('git-notifier', *args)
      raise "git-notifier failed in #{path} with args: #{args}" unless success
    rescue Exception => e
      $logger.error(e)
    end
    Dir.chdir(current)
    success
  end
end

class GitCommitNotifier
  STATE_FILE = '.git-commit-notifier.dat'

  private

  MAPPINGS = {
      :from => 'sender',
      :to => 'mailinglist',
      :subject => 'emailprefix'
  }

  public

  def self.run(path, opts)
    args = []
    args << "#{opts['checkout_dir']}/#{opts['repo']}"
    args << opts['before']
    args << opts['after']
    args << opts['ref']
    success = execute(path, args)
    $logger.error('git-commit-notifier failed') unless success
    success
  end

  private

  def self.execute(path, args = [])
    $logger.debug("args='#{args}'")
    current = Dir.pwd()
    success = true
    Dir.chdir(path)
    begin
      $logger.debug('> git fetch origin +refs/heads/*:refs/heads/*')
      success = system('git', 'fetch', 'origin', '+refs/heads/*:refs/heads/*')
      raise "git fetch failed in #{path}" unless success
      $logger.debug("> bundle exec ./change-notify.sh #{args.join(' ')}")

      captured_stdout = ''
      captured_stderr = ''
      gitdub_home = '/home/jerry/git/JukinMediaInc/gitdub' # TODO fix
      Dir.chdir(gitdub_home)
      ENV['GITDUB_HOME'] = gitdub_home
      exit_status = Open3.popen3(ENV, 'bundle', 'exec', './change-notify.sh', *args){ |stdin, stdout, stderr, wait_thr|
        pid = wait_thr.pid # pid of the started process.
        stdin.close
        captured_stdout = stdout.read
        captured_stderr = stderr.read
        wait_thr.value # Process::Status object returned.
      }

      $logger.debug("STDOUT: #{captured_stdout}")
      $logger.debug("STDERR: #{captured_stderr}")
      $logger.debug("EXIT STATUS: #{exit_status.success? ? 'succeeded' : 'failed'}")

      # Bundler.with_clean_env do
      # end
      raise "git-commit-notifier failed (#{exit_status.success?}) in #{path} with args: #{args}" unless exit_status.success?
    rescue Exception => e
      $logger.error(e)
    end
    Dir.chdir(current)
    success
  end
end

class GitDub
  def initialize(config)
    @notifier = config['notifier']
    @github = config['github']
    @silent_init = config['gitdub']['silent_init']

    @dir = config['gitdub']['directory']
    if @dir != '.'
      $logger.info("switching into working directory #{@dir}")
      Dir.mkdir(@dir) unless Dir.exists?(@dir)
      Dir.chdir(@dir)
    end
  end

  def process(push)
    opts = @notifier
    url = push['repository']['url']
    user = push['repository']['owner']['name']
    repo = push['repository']['name']
    before = push['before']
    after = push['after']
    ref = push['ref']

    opts['link'] = "#{url}/compare/#{before}...#{after}"
    $logger.info("received push from #{user}/#{repo} for commits "\
                 "#{before[0..5]}...#{after[0..5]}")

    @github.each do |entry|
      if "#{user}\/#{repo}" =~ Regexp.new(entry['id'])
        opts.merge!(entry.reject { |k, v| k == 'id' })

        dir = File.join(user, repo)
        bare_dir = "#{dir}_bare"
        unless Dir.exists?(dir)
          remote = "ssh://git@github.com/#{user}/#{repo}.git"

          $logger.debug("> git clone --bare #{remote} #{bare_dir}")
          unless system('git', 'clone', '--bare', remote, bare_dir)
            $logger.error("git failed to clone repository #{user}/#{repo}")
            FileUtils.rm_rf(bare_dir) if File.exists?(bare_dir)
            return
          end

          $logger.debug("> git clone #{remote} #{dir}")
          unless system('git', 'clone', remote, dir)
            $logger.error("git failed to clone repository #{user}/#{repo}")
            FileUtils.rm_rf(dir) if File.exists?(dir)
            return
          end

          # Do not keep empty user directories.
          if Dir[File.join(user, '*')].empty?
            Dir.rmdir(user)
          end
        end

        type = opts['impl'] ||= 'git-notifier'
        case type
          when 'git-notifier'
            state_file = File.join(bare_dir, GitNotifier::STATE_FILE)
          when 'git-commit-notifier'
            state_file = File.join(bare_dir, GitCommitNotifier::STATE_FILE)
          else
            $logger.error("unknown notifier #{type}")
            return
        end
        if @silent_init and not File.exists?(state_file)
          $logger.info("configuring #{type} for silent update")
          opts = opts.merge({updateonly: true}) unless File.exists?(state_file)
        end

        case type
          when 'git-notifier'
            return GitNotifier.run(bare_dir, opts)
          when 'git-commit-notifier'
            opts['repo'] = "#{entry['id']}_bare"
            opts['before'] = before
            opts['after'] = after
            opts['ref'] = ref
            opts['checkout_dir'] = @dir
            return GitCommitNotifier.run(dir, opts)
          else
            $logger.error("unknown notifier #{type}")
            return
        end

      end
    end
    $logger.warn("no matching repository found for #{user}/#{repo}")
  end
end

class GitDubServer < Sinatra::Base
  configure do
    set(:environment, :production)
    set(:bind, CONFIG['gitdub']['bind'])
    set(:port, CONFIG['gitdub']['port'])
  end

  get '/' do
    "Use #{request.url} as WebHook URL in your github repository settings."
  end

  post '/' do
    directory = CONFIG['gitdub']['directory']
    sources = CONFIG['gitdub']['allowed_sources']
    if not sources.empty? and not sources.include?(request.ip)
      $logger.info("discarding request from disallowed address #{request.ip}")
    else
      event = request.env['HTTP_X_GITHUB_EVENT']
      if event && event == 'ping'
        payload = JSON.parse(params[:payload])
        zen = payload['zen']
        hook_id = payload['hook_id']
        $logger.info("received ping for hook_id=#{hook_id} with zen='#{zen}'")
      else
        if params[:payload]
          $logger.info('processing push request')
          $gitdub.process(JSON.parse(params[:payload]))
        else
          $logger.error('no payload')
        end
      end
    end
  end
end

if __FILE__ == $0
  $logger = Logger.new(STDERR)
  $logger.formatter = proc do |severity, datetime, progname, msg|
    time = datetime.strftime('%Y-%m-%d %H:%M:%S')
    "[#{time}] #{severity}#{' ' * (5 - severity.size + 1)}gitdub | #{msg}\n"
  end

  $gitdub = GitDub.new(CONFIG)

  if CONFIG['gitdub']['ssl']['enable']
    require 'webrick/https'
    require 'openssl'
    cert = File.open(CONFIG['gitdub']['ssl']['cert']).read
    key = File.open(CONFIG['gitdub']['ssl']['key']).read
    webrick_options = {
        app: GitDubServer,
        BindAddress: CONFIG['gitdub']['bind'],
        Port: CONFIG['gitdub']['port'],
        Logger: $logger,
        SSLEnable: true,
        SSLCertificate: OpenSSL::X509::Certificate.new(cert),
        SSLPrivateKey: OpenSSL::PKey::RSA.new(key),
        SSLCertName: [['CN', WEBrick::Utils::getservername]]
    }
    Rack::Server.start(webrick_options)
  else
    Sinatra.new(GitDubServer).run!
  end
end
