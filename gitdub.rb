#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'logger'
require 'sinatra/base'
require 'yaml'

def which(cmd)
  ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
    exe = "#{path}/#{cmd}"
    return exe if File.executable?(exe)
  end
  nil
end

raise 'could not find git-notifier in $PATH' unless which('git-notifier')

if ARGV.size() != 1
  STDERR.puts "usage: #{$0} <config.yml>"
  exit 1
end

CONFIG = YAML.load_file(ARGV[0])

class GitNotifier
  STATE_FILE = '.git-notifier.dat'

  private

  MAPPINGS = {
    'from' => 'sender',
    'to' => 'mailinglist',
    'subject' => 'emailprefix'
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

class GitDub
  def initialize(config)
    @notifier = config['notifier']
    @github = config['github']
    @silent_init = config['gitdub']['silent_init']

    dir = config['gitdub']['directory']
    if dir != '.'
      $logger.info("switching into working directory #{dir}")
      Dir.mkdir(dir) unless Dir.exists?(dir)
      Dir.chdir(dir)
    end
  end

  def process(push)
    opts = @notifier
    url = push['repository']['url']
    user = push['repository']['owner']['name']
    repo = push['repository']['name']
    opts['link'] = "#{url}/compare/#{push['before']}...#{push['after']}"
    $logger.info("received push from #{user}/#{repo} for commits "\
                 "#{push['before'][0..5]}...#{push['after'][0..5]}")

    @github.each do |entry|
      if "#{user}\/#{repo}" =~ Regexp.new(entry['id'])
        opts.merge!(entry.reject { |k, v| k == 'id' })

        dir = File.join(user, repo)
        if not Dir.exists?(dir)
          remote = "ssh://git@github.com/#{user}/#{repo}.git"
          $logger.debug("> git clone --bare #{remote} #{dir}")
          if not system('git', 'clone', '--bare', remote, dir)
            $logger.error("git failed to clone repository #{user}/#{repo}")
            FileUtils.rm_rf(dir) if File.exists?(dir)
            return
          end
          # Do not keep empty user directories.
          if Dir[File.join(user, '*')].empty?
            Dir.rmdir(user)
          end
        end

        state_file = File.join(dir, GitNotifier::STATE_FILE)
        if @silent_init and not File.exists?(state_file)
          $logger.info("configuring git-notifer for silent update")
          opts = opts.merge({updateonly: true}) unless File.exists?(state_file)
        end
        return GitNotifier.run(dir, opts)
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
    sources = CONFIG['gitdub']['allowed_sources']
    if not sources.empty? and not sources.include?(request.ip)
      $logger.info("discarding request from disallowed address #{request.ip}")
      return
    end

    event = request.env['HTTP_X_GITHUB_EVENT']
    if event && event == 'ping'
      payload = JSON.parse(params[:payload])
      zen = payload['zen']
      hook_id = payload['hook_id']
      $logger.info("received ping for hook_id=#{hook_id} with zen='#{zen}'")
    else
      $logger.info("processing non-ping request")
      $gitdub.process(JSON.parse(params[:payload]))
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

  if not CONFIG['gitdub']['ssl']['enable']
    Sinatra.new(GitDubServer).run!
  else
    require 'webrick/https'
    require 'openssl'

    cert = File.open(CONFIG['gitdub']['ssl']['cert']).read
    key = File.open(CONFIG['gitdub']['ssl']['key']).read
    webrick_options = {
      app:            GitDubServer,
      BindAddress:    CONFIG['gitdub']['bind'],
      Port:           CONFIG['gitdub']['port'],
      Logger:         $logger,
      SSLEnable:      true,
      SSLCertificate: OpenSSL::X509::Certificate.new(cert),
      SSLPrivateKey:  OpenSSL::PKey::RSA.new(key),
      SSLCertName:    [['CN', WEBrick::Utils::getservername]]
    }

    Rack::Server.start(webrick_options)
  end
end