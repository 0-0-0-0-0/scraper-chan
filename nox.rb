#!/usr/bin/env ruby
# encoding: UTF-8

require 'openssl'
require 'open-uri'
require 'net/http'
require 'timeout'

%w{nokogiri open_uri_redirections progressbar}.each do |lib|
    begin
        require lib
    rescue LoadError
        system "gem install #{lib}"
        Gem.clear_paths
        retry
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
        when '-i', '--ignore'   then ARGS[:exlude]  = true
    end
end

BEGIN {
    require 'fileutils'

    system "title nox"

    class String
        def red;            "\e[31m#{self}\e[0m" end
        def blue;           "\e[34m#{self}\e[0m" end
        def green;          "\e[32m#{self}\e[0m" end
        def purple;         "\e[35m#{self}\e[0m" end
    end

    puts %{
            ███╗   ██╗ ██████╗ ██╗  ██╗
            ████╗  ██║██╔═══██╗╚██╗██╔╝
            ██╔██╗ ██║██║   ██║ ╚███╔╝ 
            ██║╚██╗██║██║   ██║ ██╔██╗ 
            ██║ ╚████║╚██████╔╝██╔╝ ██╗
            ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
    }.purple

    # get input, create folder 'data' if not specified
    (FileUtils::mkdir_p ENV['folder'] = (ARGV[1].nil? ? 'data' : ARGV[1].to_s)) &&
    (ARGV[0].nil? ? (print "URL => "; URL = gets.chop.split(',')) : (URL = ARGV[0].split(','))) &&
    (URL =~ /^(?<http>!.*http|https:\/\/).*$/i ? $~[:http] += $` : nil) if ARGV[0] !~ /^\-+/ }

# --sort, -p: files numerically in increasing order
at_exit { ->(i) {->(_) {Dir[$_=(_.nil? ? '.' : _) + '/*'].each_with_index {|f,i| f.to_enum(:scan, /(?<type>\.(png|jpg|jpeg|gif|webm|mp4|pdf))$/im). \
    map {p "Sorting - [#{-~i}/#{Dir["#{_}/*"].length}] "+f;$_=f; test(?e, ($_) + i.to_s + $1) ? next : \
    File.rename(f, File.dirname(f) + File::SEPARATOR + (-~i).to_s + $~[:type])}}}::(ENV['folder'])}.(0) && (puts 'Done!') \
    rescue Errno::EACCES abort "NO ACCESS - Can't sort this folder :(" } if ARGS[:sort]

def help
    abort %{
            ruby nox.rb <url>,<url> <folder> <options>

            OPTIONS: 
            -h, --help          Shows this help
            -s, --sort          Sort files in inscreasing order
            -i, --ignore        Ignore specific file extension
    }
end

# -- ignore: file extensions
def ignore(*ext); end

help   if ARGS[:help]
ignore if ARGS[:ignore]

# nonconstant variables
time       = Time.now
dl_size    = []
total_size = 
retries    =
downloaded = 0
connected  = false

trap("SIGINT") { throw :ctrl_c }

catch :ctrl_c do
    puts "Connecting to URL.. ".green
    puts "Press ctrl-c to stop".green
    puts "\n\n"

    begin
        URL.map do |url|
            Thread.new do
                document = Nokogiri::HTML(open(URI.encode(url),
                    "User-Agent" => "Ruby/#{RUBY_VERSION}",
                    :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE,
                    :allow_redirections => :all)).xpath(
                        "//a[@class='fileThumb']",
                        "//p[@class='fileinfo']/a",
                        "//a[@class='imgLink']",
                        "//div[@class='post']//a[@target='_blank']",
                        "//td[@class='reply']/a[3]",
                        "//div[@class='post_content_inner']/div",
                        "//div[@class='post-image']/a")

                document.each_with_index do |data, i|
                    uri         = URI.join(url, URI.escape((data['href'] || data['src']))).to_s
                    response    = Net::HTTP.get_response(URI.parse(uri))
                    connected   = true
                    downloaded += 1
                    dl_size    << response['content-length'].to_i

                    puts "[%s/%s%s] [%s/%s] [%s] -> %s" % [(-~i).to_s.blue, document.length.to_s.blue, (" - " + (URI.parse(url).path.split('/')[-3..-1]*?/) if URL.size > 1).to_s,
                        (response['content-length'].to_i.to_filesize).to_s.green, response['content-type'], File.basename(uri).to_s.blue, (__dir__ + "/" + (ENV['folder']).to_s.blue)]

                    begin
                        Timeout::timeout(120) do
                            test(?e, ENV['folder'] + "/" + File.basename(uri).to_s) == false ?
                                File.open(ENV['folder'] + File::SEPARATOR + File.basename(uri), 'wb') { |f| f << open(uri).read }
                            : next
                        end
                    rescue TimeoutError
                        puts "¯\\_(ツ)_/¯ shitty internet speed or very large file".red
                    end
                end
            end
        end.each(&:join)
    rescue OpenURI::HTTPError => e # fetching real domain address
        res = e.io

        (res.status[0] == '403') ?
            (warn "Attempt to bypass Cloudflare..") &&

            (fetch = /(?:\d+\.){3}(?:\d+)(?::\d*)/.match(
                Net::HTTP.post_form(URI("http://www.crimeflare.com/cgi-bin/cfsearch.cgi"), 
                'cfS' => URL).body)) &&

            (fetch.nil? || fetch.empty?) ?
                (puts "Could not bypass protection :(")
            : (URL = fetch && (retry))
        : nil
    rescue OpenSSL::SSL::SSLError # bypassing invalid ssl certificate
        warn "Bypassing SSL verification...".blue

        silence_warnings { OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE }

        retries += 1
        retry if retries <= 2
    end
    abort "Couldn't connect to the URL :(".red unless connected
end

at_exit do
    if $!
        warn "Oops, something happened :("
    else
        Dir["#{ENV['folder']}/*"].each { |f| total_size += File.size(f) }

        if connected
            puts "\n=TOTAL=\n"
            puts "Downloaded: %s (%s files)" % [(dl_size.inject(:+).to_filesize).to_s.green, downloaded]
            puts "Folder (%s) now has: %s (%s files)" % [ENV['folder'], total_size.to_filesize.to_s.green, Dir[ENV['folder'] + "/*"].length] unless dl_size.inject(:+) == total_size
        else
            abort "Unkown error, type --help."        
        end
    end
end