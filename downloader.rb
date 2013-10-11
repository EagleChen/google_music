#!/usr/bin/env ruby
require "eventmachine"
require "optparse"
require "open-uri"
require "nokogiri"
require "fileutils"

options = {}
opts_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby downloader.rb <album_url> [-d DIRECTORY] [-b BASEURL]"

  opts.on('-d DIRECTORY') { |dir| options[:dir] = dir }
  opts.on('-b BASEURL') { |baseurl| options[:baseurl] = baseurl }
  opts.on('-h', '--help', 'Display this screen' ) do
    puts opts
    exit
   end
end
album_url, = opts_parser.parse!
usage unless album_url
puts album_url
BASE_URL = options[:baseurl] || "http://www.google.cn"
BASE_FOLDER = options[:dir] || "."
CONCURRENCY = 3

def usage
  puts "Usage: ruby downloader.rb <album_url> [-d DIRECTORY] [-b BASEURL]"
  exit
end

def handle_title(origin)
  origin[1, origin.length-2]
end

def create_album_folder(name)
  begin
    dir = File.join(BASE_FOLDER, name) 
    FileUtils.mkdir_p(dir)
    Dir.chdir(dir)
  rescue 
    raise "Can't handle directory #{dir}"
  end
end

def download_album(album_url)
  puts "begin..."

  page_content = Nokogiri::HTML(open(album_url))
  title = page_content.xpath('//span[@class="Title"]')[0].text
  title = handle_title(title)
  create_album_folder(title)

  EM.run do
    trs  = page_content.xpath('//table[@id="song_list"]/tbody/tr')
    size = trs.size
    @song_list = {}

    EM.threadpool_size = CONCURRENCY
    trs.each do |tr|
      node = tr.xpath('./td')[7].xpath('./a')[0]
      song_name = tr.xpath('./td')[2].xpath('./a')[0].text
      @song_list[song_name] = 0
      EM.defer(
        proc do
          song_url = get_song_url(node['onclick'])
          get_song(song_url, 0)
        end,
        proc do
          size -= 1
          if 0 >= size
            EM.stop
            progress
            puts "Download finished!"
          end
        end)
    end

    @first_output = true
    EM.add_periodic_timer(1) {progress}
  end
end

def get_song_url(text)
  "http://www.google.cn/music/top100/musicdownload?id=" + text[/id%3D(.*)\\x26resnum/, 1]
end

def get_song(url, times)
  begin
    page_content = Nokogiri::HTML(open(url))
    song_name = page_content.xpath('//td[@class="td-song-name"]')[1].text
    path = page_content.xpath('//div[@class="download"]/a')[0]['href']
    
    total_len = 0
    data = open(BASE_URL + path,
      :content_length_proc => lambda do |len|
        if len && 0 < len
          total_len = len
        end
      end,
      :progress_proc => lambda { |s| 
        @song_list[song_name] = s*100/total_len
      }) {|f| f.read}

    open(song_name + ".mp3", "wb") do |file|
      file.write(data)
    end
  rescue
    if 3 > times
      puts "Can't download #{song_name}. Will retry"
      get_song(url, times+1)
    else
      puts "#{song_name} download failed"
    end
  end
end

def progress
  printf "\033M"*@song_list.size + "\r" unless @first_output
  @first_output = false
  @song_list.each {|k, v| printf "%-50s\t%3d%%\n", k, v}
end

download_album(album_url)
