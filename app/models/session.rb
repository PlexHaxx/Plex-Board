class Session < ActiveRecord::Base
  require 'open-uri'
  require 'uri'
  require 'fileutils'
  # require 'carrierwave/orm/activerecord'
  belongs_to :service
  delegate :token, :to => :service, :prefix => true
  # mount_uploader :image, ImageUploader
  before_destroy :delete_thumbnail
  before_save :init
  after_save :get_plex_now_playing_img

  validates_presence_of :session_key
  validates_presence_of :user_name
  validates_presence_of :service_id

  validates :session_key, uniqueness: { scope: :service_id }

  validates_presence_of :connection_string
  validates_presence_of :media_title

  @@images_dir = "public/images"

  def init
    self.thumb_url ||= "http://placehold.it/400x592"
    self.image ||= "http://placehold.it/400x592"
    if !File.directory?(@@images_dir)
      FileUtils::mkdir_p @@images_dir
    end
  end

  def delete_thumbnail()
    if self.image != "http://placehold.it/400x592"
      begin
        FileUtils.rm(self.image)
        logger.debug("Deleted #{self.image}")
      rescue => error
      logger.debug(error)
      end
    end
  end

  def get_plex_now_playing_img()
    #I'll be honest. I don't know why I needed to add this..
    #but the ".jpeg" name image problem seems to be fixed for now sooo....
    if self.id.blank?
      return nil
    end
    #Check if the file exists, if it does return the name of the image
    if File.file?("#{@@images_dir}/#{self.id}.jpeg")
      logger.debug("Image #{self.image} found!")
      return self.image
    end
    begin
      logger.debug("Image was not found, fetching...")
      File.open("#{@@images_dir}/#{self.id}.jpeg", 'wb') do |f|
        f.write open("#{self.connection_string}#{self.thumb_url}",
        "X-Plex-Token" => self.service_token, "Accept" => "image/jpeg",
        ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE).read
      end
      self.update(image: "#{self.id}.jpeg")
      return self.image
    rescue => error
      logger.debug(error)
      return nil
    end

  end

  def get_percent_done()
    ((self.progress.to_f / self.total_duration.to_f) * 100).to_i
  end

  def get_description()
    # limit the length of the description to 200 characters, if over 200, add ellipsis
    self.description[0..200].gsub(/\s\w+\s*$/,'...')
  end


end
