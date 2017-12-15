#!/usr/bin/env ruby
# encoding: UTF-8

require 'openssl'
require 'open-uri'
require 'fileutils'
require 'net/http'

%w{nokogiri open_uri_redirections}.each do |lib|
  begin
    require lib
  rescue LoadError
    puts "A few gems are missing, install dependencies? [Y/n]: "
    confirm = gets.chomp

    if confirm[/[y]|\r|\n/im]
      system "gem install #{lib}"
      Gem.clear_paths
      retry
    else
      abort "Goodbye."
    end
  end
end

class Integer
  def to_filesize
    {
      'B'  => 1024,
      'KB' => 1024 * 1024,
      'MB' => 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024 * 1024
    }.each_pair { |e, s| return "#{(self.to_f / (s / 1024)).round(2)}#{e}" if self < s }
  end
end

module Kernel
  def silence_warnings
    original_verbosity = $VERBOSE
    $VERBOSE = nil
    result = yield
    $VERBOSE = original_verbosity
    return result
  end
end

ARGS = {}
ARGV.each do |flags|
  case flags
  when '-h', '--help'     then ARGS[:help]    = true
  when '-s', '--sort'     then ARGS[:sort]    = true
  when '-t', '--strict'   then ARGS[:strict]  = true
  end
end

BEGIN {
  require 'fileutils'

  system "title scraper-chan"

  class String
    def red;            "\e[31m#{self}\e[0m" end
    def blue;           "\e[34m#{self}\e[0m" end
    def green;          "\e[32m#{self}\e[0m" end
    def purple;         "\e[35m#{self}\e[0m" end
    def bg_magenta;     "\e[45m#{self}\e[0m" end
  end

  %{
      ███████╗ ██████╗██████╗  █████╗ ██████╗ ███████╗██████╗
      ██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗
      ███████╗██║     ██████╔╝███████║██████╔╝█████╗  ██████╔╝
      ╚════██║██║     ██╔══██╗██╔══██║██╔═══╝ ██╔══╝  ██╔══██╗
      ███████║╚██████╗██║  ██║██║  ██║██║     ███████╗██║  ██║
      ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝
  }.chars.map { |line| print "\e[#{rand(31..35)}m#{line}\e[0m"; $stdout.flush; sleep 0.003 }

  exit if defined? Ocra
  abort "Usage: ruby scraper.rb <urls> <folder> <options>".red if ARGV[0].nil?

  FileUtils::mkdir_p ENV['folder'] = ARGV[1] || ARGV[0].split('/')[-1]
  URL = ARGV[0].split(',')
  URL =~ /^(?<http>!.*http|https:\/\/).*$/i ? $~[:http] += $` : nil if ARGV[0] !~ /^\-+/
}

at_exit {
  ->i {
    ->_ {
      Dir[$_=(_.nil? ? '.' : _) + '/*'].each_with_index { |f, i|
        f.to_enum(:scan, /(?<type>\.(png|jpg|jpeg|gif|webm|mp4|pdf))$/im).map {
          p "Sorting - [#{-~i}/#{Dir["#{_}/*"].length}] " + f; $_=f;
          test(?e, ($_) + i.to_s + $1) ? next : \

          File.rename(f, File.dirname(f) + File::SEPARATOR + (-~i).to_s + $~[:type])
        }
      }
    }::(ENV['folder'])
  }.(0) && (puts 'Done!') rescue Errno::EACCES abort "NO ACCESS - Can't sort this folder :("
} if ARGS[:sort]

def help
  abort %{
      ruby scraper.rb <url>,<url> <folder> <options>

      OPTIONS:
      -h, --help          Shows this help
      -s, --sort          Sort files in inscreasing order
      -t, --strict        Ensures well-formed markup
  }
end

def warning(str)
  warn "#{"[!]".red} #{str}"
end

help   if ARGS[:help]
ignore if ARGS[:ignore]

dl_size    = []
total_size =
retries    =
count      =
downloaded = 0
connected  = false
started    = Time.now

trap("SIGINT") { throw :ctrl_c }

catch :ctrl_c do
  begin
    URL.map do |url|
      puts "\nConnecting to (#{url.green})\n"
      Thread.new do
        document = Nokogiri::HTML(open(URI(URI.encode(url)),
          "User-Agent"        => "Ruby/#{RUBY_VERSION}",
          :ssl_verify_mode    => OpenSSL::SSL::VERIFY_NONE,
          :allow_redirections => :all)).xpath(
          "//a[@class='imgLink']",
          "//a[@class='fileThumb']",
          "//p[@class='fileinfo']/a",
          "//td[@class='reply']/a[3]",
          "//div[@class='post-image']/a",
          "//div[@class='main-body']//a",
          "//div[@class='post-body']//p/img",
          "//a[@class='thread_image_link']",
          "//a[@class='prettyPhoto_gall']",
          "//div[@class='post_content_inner']/div",
          "//div[@id='postcontent']//a[starts-with(@href, '//images.')]",
          "//div[@class='entry-content']//p/a",
          "//div[@class='ngg-gallery-thumbnail']/a",
          "//div[@class='icon-overlay']/a/img",
          "//div[@class='entry']//p/a",
          "//div[@id='post-content']//p/img",
          "//div[@class='post']//a[@target='_blank']") { |config| config.strict if ARGS[:strict] }

          document.map.with_index do |data, i|
            Thread.new do
              uri         = URI.join(url, URI.escape((data['href'] || data['src']))).to_s
              response    = Net::HTTP.get_response(URI.parse(uri))
              doc_path    = ENV['folder'] + File::SEPARATOR + File.basename(uri).to_s
              connected   = true
              downloaded += 1
              is_html     = response['content-type'][/\/text\/html/i]
              dl_size    << response['content-length'].to_i

              $> << "(%s) [%s/%s%s] [%s/%s] [%s] » %s\n" % [
                (((is_html || response['content-length'] == 0) ? '- '.red : '+ '.green) + (count+=1).to_s),
                (-~i).to_s.blue, document.length.to_s.blue,
                (" - " + (URI.parse(url).path.split('/')[-1]) if URL.size > 1).to_s,
                (response['content-length'].to_i.to_filesize).to_s.green,
                response['content-type'],
                File.basename(uri).to_s.bg_magenta,
                ((ENV['folder']).to_s.blue)
              ]

              next if is_html

              !test(?e, doc_path) \
              ? File.open(doc_path, 'wb') { |f| f << open(uri).read }
              : Thread.exit
            end
          end.each(&:join)
        end
      end.each(&:join)
    rescue OpenURI::HTTPError => e
      res = e.io
      if res.status[0] == '403'
        warning "Attempt to bypass Cloudflare"

        fetch = /(?:\d+\.){3}(?:\d+)(?::\d*)/.match(Net::HTTP.post_form(URI("http://www.crimeflare.com/cgi-bin/cfsearch.cgi"), 'cfS' => URL).body)

        if fetch.nil? || fetch.empty?
          warning "Could not bypass protection :("
          URL = fetch
          retry
        end
      end
    rescue SocketError, Errno::EINVAL, Errno::ECONNRESET, Errno::ETIMEDOUT, Net::ReadTimeout
      next
    rescue OpenSSL::SSL::SSLError
      warning "Bypassing SSL verification..."
      silence_warnings { OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE }
      retries += 1
      retry if retries <= 2
  end
  abort "Couldn't connect to the URL :(".red unless connected
end

at_exit do
  empty_files = 0
  if $!
    warning "Oops, something happened :("
  else
    Dir["#{ENV['folder']}/*"].each do |f|
      if !File.zero?(f)
        total_size += File.size(f)
      else
        begin
          puts "#{"[-] DEL".red} #{(f.to_s).blue} [#{File.size(f).to_filesize.to_s.green}]"
          FileUtils::rm(f)
          empty_files += 1
        rescue Errno::EACCES
          next
        end
      end
    end
    download_size = dl_size.inject(:+)
    warning "Removed #{empty_files} empty files." unless empty_files == 0

    FileUtils::mkdir_p('logs') if !Dir.exists?('logs')
    File.open("logs/log #{Time.now.strftime("(%Y-%m-%d) [%Hh-%Mmin]")}.txt", 'w+') { |log|
      URL.map { |site| log << "WEBSITE: #{site}\n" }
      log << "TOTAL: #{downloaded} files [#{download_size.to_filesize}] >> #{ENV['folder']}"
    }

    duration = (started - Time.now)
    if connected
      puts "\nTook: #{(Time.at(duration.round.abs).utc.strftime("%H:%M:%S")).blue} to finish"
      puts "Downloaded: %s (%s files)" % [(download_size.to_filesize).to_s.green, downloaded]
      puts "Folder (%s) now has: %s (%s files)" % [ENV['folder'], total_size.to_filesize.to_s.green, Dir[ENV['folder'] + "/*"].length] unless download_size == total_size
    else
      abort "Unknown error, type --help."
    end
  end
end
