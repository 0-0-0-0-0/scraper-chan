#!/usr/bin/env ruby

=begin
  web crawler for http://www.allitebooks.com/
  usage: ruby ebook-dl.rb <url> <folder>
=end

require 'mechanize'
require 'fileutils'
require 'uri'
require 'net/http'

exit if ARGV[0].nil?

url    = URI.parse(URI.encode(ARGV[0].to_s.strip))
mech   = Mechanize::new
page   = mech.get(url)
books  = []
pg_num = 1

FileUtils::mkdir_p folder = ARGV[1] || 'ebooks'

mech.request_headers     = { "Accept-Encoding" => "" }
mech.ignore_bad_chunking = true
mech.follow_meta_refresh = true

begin
  page.links.map { |link|
    Thread.new {
      if link.rel.to_s =~ /bookmark/im
        page = link.click
        puts "[+] #{page.title}"

        page.links.each { |lnk|
          books << lnk.href.to_s if lnk.href.to_s =~ /http\:\/\/file\.allitebooks\.com/im
        }
      end
    }
  }.each(&:join)
rescue Mechanize::ResponseCodeError, Net::HTTPNotFound
  page = mech.get("http://www.allitebooks.com/page/#{pg_num+=1}/")
  puts "[!] Going to next page..."
  retry
end

books.map.with_index { |book, i|
  puts "(#{-~i}) Downloading #{book}"
  File.open(folder + File::SEPARATOR + File.basename(book), 'wb') { |f| f << mech.get(book).body }
}