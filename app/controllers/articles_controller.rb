class ArticlesController < ApplicationController

  before_action :check_for_valid_cms_mode

  def index
    
    @response = []
    
    case @cms_mode 
      when :occrp_joomla
        url = ENV['occrp_joomla_url']
    
        # Shortcut
        # We need the request to look like this, so we have to get the correct key.
        # At the moment it makes the call twice. We need to cache this.
        response = HTTParty.get(url, headers: {'Cookie' => get_cookie()})
        body = response.body
    
        @response = JSON.parse(response.body)
    
        @response['results'] = clean_up_response @response['results']
      when :wordpress
        url = ENV['wordpress_url'] 

        response = HTTParty.get(url, headers: {'Cookie' => get_cookie()})
        body = response.body

        @response = JSON.parse(response.body)
    
        #@response['results'] = clean_up_response @response['results']
      when :newscoop
        url = ENV['newscoop_url']
         
        response = HTTParty.get(url, headers: {'Cookie' => get_cookie()})
        body = response.body

        @response = JSON.parse(response.body)
    end
    
    respond_to do |format|
      format.json
    end

  end
  
  def search
    case @cms_mode
      when :occrp_joomla
        @response = search_occrp_joomla
      when :wordpress
        @response = search_wordpress
    end 
    
    respond_to do |format|
      format.json
    end
  end

  def search_occrp_joomla
    url = ENV['occrp_joomla_url']

    query = params['q']
    # Get the search results from Google
    url = "https://www.googleapis.com/customsearch/v1?key=AIzaSyCahDlxYxTgXsPUV85L91ytd7EV1_i72pc&cx=003136008787419213412:ran67-vhl3y&q=#{query}"
    response = HTTParty.get(url)
    # Go through all the responses, and then make a call to the Joomla server to get all the correct responses
    url = "https://www.occrp.org/index.html?option=com_push&format=json&view=urllookup&u="
    @response = {items: []}
    links = []
    response['items'].each do |result|
      url << URI.encode(result['link'])
      if result != response['items'].last
        url << ","
      end
    end

    response = HTTParty.get(url, headers: {'Cookie' => get_cookie()})

    # Turn all the responses into something that looks nice and is expected
    search_results = clean_up_response JSON.parse(response.body)
    @response = {query: query,
                 start_date: "19700101",
                 end_date: DateTime.now.strftime("%Y%m%d"),
                 total_results: search_results.size,
                 page: "1",
                 results: search_results
                }

    return @response
  end
  
  def search_wordpress
      @response = {query: query,
                 start_date: "19700101",
                 end_date: DateTime.now.strftime("%Y%m%d"),
                 total_results: search_results.size,
                 page: "1",
                 results: search_results
                }
      return @response
  end

  private
  
  def check_for_valid_cms_mode
    @cms_mode
    cms_mode = ENV['cms_mode']
    case cms_mode
      when "occrp-joomla"
        @cms_mode = :occrp_joomla
      when "wordpress"
        @cms_mode = :wordpress
      else
        raise "CMS type #{cms_type} not valid for this version of Push."
    end
  end
  
  def get_cookie
    url = "https://www.occrp.org/index.html?option=com_push&format=json&view=urllookup&u="
    response = HTTParty.get(url)
    cookies = response.headers['set-cookie']
    correct_cookie = nil
    cookies.split(', ').each do |cookie|
      if cookie.include? "[lang]"
        return cookie
        break
      end
    end

    return nil
  end

  def clean_up_response articles
    articles.delete_if{|article| article['headline'].blank?}
    articles.each do |article|
      # If there is no body (which is very prevalent in the OCCRP data for some reason)
      # this takes the intro text and makes it the body text
      if article['body'].nil? || article['body'].empty?
        article['body'] = article['description']
      end
      # Limit description to number of characters since most have many paragraphs

      article['description'] = ActionView::Base.full_sanitizer.sanitize(article['description']).squish
      if article['description'].length > 140
        article['description'] = article['description'].slice(0, 140) + "..."
      end

      # Extract all image urls in the article and put them into a single array.
      article['image_urls'] = []
      elements = Nokogiri::HTML article['body']
      elements.css('img').each do |image|
        image_address = image.attributes['src'].value
        if !image_address.starts_with?("http")
          article['image_urls'] << "https://www.occrp.org/" + image.attributes['src'].value
        else
          article['image_urls'] << image_address
        end
      end

      # Just in case the dates are improperly formatted
      begin
        published_date = DateTime.strptime(article['publish_date'], '%F %T')
      rescue => error
        published_date = DateTime.new(1970,01,01)
      end

      # right now we only support dates on the mobile side, this will be time soon.
      article['publish_date'] = published_date.strftime("%Y%m%d")
    end

    return articles
  end
end
