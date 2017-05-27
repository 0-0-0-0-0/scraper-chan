#!/usr/bin/env ruby
# encoding: UTF-8

require 'nokogiri'
require 'openssl'
require 'open-uri'
require 'open_uri_redirections'

=begin
My own personal web scraper, for the sole purpose of downloading images dinamically

# TODO: exlude by file size
# TODO: exlude by image dimension
# TODO: skip if filename already exists in folder

## Examples

# imageboards
    $ ruby reaper.rb https://imageboard-url/board/thread/ wallpaper -e=png

# imgur
    $ ruby reaper.rb https://imgur.com/gallery/nHLVf <wallpaper>

# Options
    -h, --help              Shows help
    -s, --sort              Sort files in increasing order
    -f, --folder            Specify folder (data)
    -ignore, --ignore       Ignore specific file extension
=end

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

ARGS = {}
ARGV.each do |flags|
    case flags
        when '-h', '--help'     then ARGS[:help]   = true
        when '-s', '--sort'     then ARGS[:sort]   = true
        when '-i', '--ignore'   then ARGS[:exlude] = true
    end
end

# get input, create folder 'data' if not specified
BEGIN { require 'fileutils'
        FileUtils::mkdir_p ENV['folder'] = (ARGV[1].nil? ? 'data' : ARGV[1].to_s);
        ARGV[0].nil? ? (puts "type --help") : (URL = ARGV[0].split(','));
        URL =~ /^(?<http>!.*http|https:\/\/).*$/i ? $~[:http] += $` : nil }

# --sort, -p: files numerically in increasing order
def sort; ->(i) {->(_) {Dir[$_=(_.nil? ? "." : _) + "/*"].each {|f| f.to_enum(:scan, /(?<type>\.(png|jpg|jpeg|gif|webm|mp4|pdf))$/im). \
        map {p f;$_=f; test(?e, ($_) + i.to_s + $1) ? next : File.rename(f, File.dirname(f) + File::SEPARATOR + (i += 1).to_s + $~[:type])}}} \
        ::(ENV['folder'])}.(0) end

def help
print <<HELP
        ruby reaper.rb <folder> <options>

        OPTIONS: 
        -h, --help          Shows this help
        -s, --sort          Sort files in inscreasing order
        -i, --ignore        Ignore specific file extension
HELP
end

# -- ignore: ignore certain file extensions
def ignore(*ext)

end

help   if ARGS[:help]
sort   if ARGS[:sort]
ignore if ARGS[:ignore]

trap("SIGINT") { throw :ctrl_c }

catch :ctrl_c do
    begin
        URL.map do |url|
            Thread.new do
                Nokogiri::HTML(open(url,
                "User-Agent" => "Ruby/#{RUBY_VERSION}",
                :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE,
                :allow_redirections => :all)). \
                xpath("//a[@class='fileThumb']",
                      "//p[@class='fileinfo']/a",
                      "//a[@class='imgLink']",
                      "//td[@class='reply']/a[3]",
                      "//div[@class='post_content_inner']/div",
                      "//div[@class='post-image']/a"). \
                    each_with_index do |data, i|
                    uri = URI.join(url, (data['href'] || data['src'] || data.text.gsub(/\_\d+/m, '_1280'))).to_s
                    puts "[#{(i+=1).to_s.blue}/#{uri.length.blue}#{" - #{Thread.current}" if URL.size > 1}]" \
                          "[#{File.basename(uri).to_s.blue}] ► #{__dir__ + "/" + ENV['folder']}"
                    File.open(ENV['folder'] + File::SEPARATOR + File.basename(uri), 'wb') { |f| f.write(open(uri).read) }
                end
            end
        end.each(&:join)
    rescue OpenURI::HTTPError => e
        res = e.io
        if res.status[0] == '403'
            warn "Attempt to bypass Cloudflare"
            fetch = /(?:\d+\.){3}(?:\d+)(?::\d*)/.match(Net::HTTP.post_form(URI("http://www.crimeflare.com/cgi-bin/cfsearch.cgi"), 'cfS' => URL).body)
            fetch.nil? ? (puts "Could not bypass protection :(") : (URL = fetch; retry)
            puts fetch
        end
    rescue Exception
        warn "Bypassing SSL verification...".red
        OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
        retry
    end
end

at_exit { $! ? (warn "Oops, something happened :(") : (abort "The folder #{ENV['folder']} now has: #{Dir["#{ENV['folder']}/*"].length} files.") }