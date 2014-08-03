require 'rubygems'
require 'bundler/setup'

require 'mechanize'
require 'parallel'
require 'ruby-progressbar'
# require 'thread'

class ImageScraper
  def initialize(hash = {})
    @agent = Mechanize.new
    @logged_in = false
    @image_count = Hash.new(0)
    @links = Hash.new
    @progress = Hash.new
    @options = hash
    @options[:save_to] ||= './'
  end

  def login_wallbase(name, password)
    unless name && password
      puts "Enter your name:"
      name = gets.strip

      puts "Enter your password:"
      password = gets.strip
    end

    login_page = @agent.get('http://wallbase.cc/user/login')
    response = login_page.form_with(:action => 'http://wallbase.cc/user/do_login') do |f|
      f.username  = name
      f.password  = password
      f.csrf      = f['csrf']
    end.click_button

    if response.content =~ /#{name}/
      @logged_in = true
      puts "Successfully logged in as #{name}!"
    end
  end

  def prepare_links(query, purity, amount=nil)
    count = 0

    page = @agent.get("http://wallbase.cc/search?q=#{query}&purity=#{purity}")

    while page.search("div.notice1").empty? do
      break if amount && amount <= count

      page = @agent.get("http://wallbase.cc/search/index/#{count}?q=#{query}&purity=#{purity}")

      @image_count[query] += page.links_with(:href => /wallpaper\/\d*/).each do |link|
        ((@links[query] ||= []) << link.click.image_with(:class => /wall|wide|stage/)).uniq!
        @progress[query].increment
      end.count

      count += 32
    end

  end

  def fetch_images(query)
    @agent.pluggable_parser['image'] = Mechanize::DirectorySaver.save_to("#{@options[:save_to]}/#{query}", {:overwrite => true})
    @progress[query].progress = 0
    @progress[query].title = "Downloading #{query}"
    @progress[query].total = @image_count[query]

    Parallel.each(@links[query], :in_processes => 4, :finish => lambda {|_,_,_|@progress[query].increment}) do |link|
      link.fetch
    end
    nil
  end

  def fetch_query(query, purity, amount=nil)
    amount ||= 64 # Default value

    @progress[query] = ProgressBar.create(:title => "Preparing links for '#{query}'", :total => nil, :format => "%t: |%B| %c/#{amount}")

    unless @links[query]
      prepare_links(query, purity, amount)
    end
    fetch_images(query)
  end

end


# Use it in following order,
# You can fetch images without login, just set purity as 110
# @wallbase = ImageScraper.new({:save_to => '/store/wallbase'})
# @wallbase.login_wallbase _, _ # Your yousername and password is going here
# @wallbase.fetch_query 'girls', 111