class Show < ActiveRecord::Base
  require 'figaro'

  has_many :trackings
  has_many :users, through: :trackings

  attr_accessible :title, :last_episode, :last_title, :last_airdate, :next_episode, :next_title, :next_airdate, :status, :airtime, :banner

  scope :active?

  def ended_statuses
    ["Ended", "Canceled/Ended"]
  end

  def ended?
    ended_statuses.include?(status)
  end

  # Called by #batch_update_next_airdate!
  def update_inactive_data!
    show_data = Show.check_for_show_data(title)

    latest_episode = next_episode = status = airtime = nil

    show_data.split("\n").each do |data|
      latest_episode = data if data[/^Latest Episode/]
      next_episode   = data if data[/^Next Episode/]
      status         = data if data[/^Status/]
      airtime        = data if data[/^Airtime/]
    end

    self.update_attributes({
      last_episode: latest_episode && latest_episode[/(\d+x\d+)/],
      last_title:   latest_episode && latest_episode.match(/\^(.+)\^/).captures.first,
      last_airdate: latest_episode && latest_episode.match(/\^(\D{3}\/\d{2}\/\d{4})$/).captures.first,
      next_episode: next_episode && next_episode[/(\d+x\d+)/],
      next_title:   next_episode && next_episode.match(/\^(.+)\^/).captures.first,
      next_airdate: next_episode && valid_date_format?(next_episode) && next_episode.match(/\^(\D{3}\/\d{2}\/\d{4})$/).captures.first,
      status:       status.match(/@(.+)$/).captures.first,
      airtime:      airtime && airtime.match(/@(.+)$/).captures.first,
    })
  end

  def valid_date_format?(string)
    string.match(/\^(\D{3}\/\d{2}\/\d{4})$/)
  end

  # Sometimes a show may be canceled but then brought back. Users can manually resurrect those shows here,
  # because cron will not in its current form.
  def resurrect
    show_data = Show.check_for_show_data(title)
    new_show_status = nil
    show_data.split("\n").each {|data| new_show_status = data.match(/@(.+)$/).captures.first if data[/^Status/] }

    return false if self.status == new_show_status

    self.update_inactive_data!
  end

  class << self
    def active?
      where("status IN(?)", active_statuses)
    end

    def active_statuses
      ["Returning Series", "Final Season", "In Development", "TBD/On The Bubble", "New Series"]
    end

    def show_available?(query)
      canonical_title = check_for_show_data(query)

      canonical_title.present? ? canonical_title.match(/Show Name@(.+)\nShow URL{1}/).captures.first : false 
    end

    def create_show_data(query, canonical_title, show_id)
      show_data = check_for_show_data(canonical_title)
      return false unless show_data

      latest_episode = next_episode = status = airtime = nil

      show_data.split("\n").each do |data|
        latest_episode = data if data[/^Latest Episode/]
        next_episode   = data if data[/^Next Episode/]
        status         = data if data[/^Status/]
        airtime        = data if data[/^Airtime/]
      end

      Show.find(show_id).update_attributes({
        title:        canonical_title,
        last_episode: latest_episode && latest_episode[/(\d+x\d+)/],
        last_title:   latest_episode && latest_episode.match(/\^(.+)\^/).captures.first,
        last_airdate: latest_episode && latest_episode.match(/\^(\D{3}\/\d{2}\/\d{4})$/).captures.first,
        next_episode: next_episode && next_episode[/(\d+x\d+)/],
        next_title:   next_episode && next_episode.match(/\^(.+)\^/).captures.first,
        next_airdate: next_episode && next_episode.match(/\^(\D{3}\/\d{2}\/\d{4})$/).captures.first,
        status:       status.match(/@(.+)$/).captures.first,
        airtime:      airtime && airtime.match(/@(.+)$/).captures.first,
        banner:       fetch_show_banner(query, canonical_title)
      })
    end

    # To be called by a cron job to systematically update all recurring shows' next airdates
    def batch_update_next_airdate!
      Show.active?.where('next_airdate < ? OR next_airdate IS NULL', DateTime.now).each{ |show| show.update_inactive_data!}
    end

    def check_for_show_data(query)
      response = HTTParty.get('http://services.tvrage.com/tools/quickinfo.php', :query => {:show => query}, :format => :html)

      Crack::XML.parse(response)["pre"]
    end

    def fetch_show_banner(query, canonical_title)
      tvdb = TvdbParty::Search.new(Figaro.env.tvdb_api_key)

      begin
        show   = tvdb.get_series_by_id(tvdb.search(canonical_title).first["seriesid"])
      rescue NoMethodError
        show   = tvdb.get_series_by_id(tvdb.search(query).first["seriesid"])
      rescue NoMethodError
        banner = "#{Rails.root.join('app', 'assets', 'images', '404banner.jpg')}"
      end

      show ? show.series_banners('en').first.url : banner
    end
  end
end