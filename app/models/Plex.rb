class Plex < Service

  has_many :plex_sessions, dependent: :destroy

  def plex_api(method = :get, path = "", headers = {})
    if self.online_status == false
      logger.debug("Service: " + self.name + " is offline, cant grab plex data")
      return nil
    end
    if self.token.nil?
      if !get_plex_token()
        return nil
      end
    end

    defaults = { "Accept" => "application/json", "Connection" => "Keep-Alive",
                 "X-Plex-Token" => self.token }
    headers.merge!(defaults)

    begin
      JSON.parse(RestClient::Request.execute method: method,
                   url: "https://#{connect_method()}:#{self.port}#{path}",
                   headers: headers, verify_ssl: OpenSSL::SSL::VERIFY_NONE,
                   timeout: 5, open_timeout: 5)
    rescue => error
      logger.debug(error)
      return nil
    end

  end

  def get_plex_token()
    url = "https://my.plexapp.com/users/sign_in.json"
    headers = {
        "X-Plex-Client-Identifier" => "Plex-Board"
    }
    begin
      response = RestClient::Request.execute method: :post, url: url,
                                             user: self.username, password: self.password, headers: headers
      self.update(token: (JSON.parse response)['user']['authentication_token'])
      return true #yes, I know that Ruby has implicit returns, but it helps readability
    rescue Exception => error
      logger.error("There was an error getting the plex toke")
      logger.error(error)

      return false
    end

    # logger.debug(response)
    # logger.debug(self.token)
  end


  def get_plex_sessions()

    sess = plex_api(:get, "/status/sessions")

    # logger.debug(sess)
    # logger.debug(!sess.nil?)
    if sess.nil? #does plex have any sessions?
      logger.debug("Plex doesn't have any sessions")
      return nil
    end
    #chop off the stupid children tag thing
    #so the shit is in a single element array. this is terribly messy... yuck
    plex_sessions = sess["_children"]

    #if plex has nothing, then fucking nuke that shit
    if plex_sessions.empty?
      logger.debug("plex_sessions was empty... Deleting all sessions")
      self.plex_sessions.destroy_all
      return nil
    end

    #A set is like an array that requires its elements to be unique
    # new_sessions = Set.new []

    #If we don't know about shit, then yes, add the new shit
    # if self.sessions.empty?
    #   plex_sessions.each do |new_session|
    #     new_sessions << new_session
    #   end
    #   new_sessions.each do |add_session|
    #     add_plex_session(add_session)
    #   end
    #   return true
    # end

    # stale_ids = []

    # References for the code below:
    # http://stackoverflow.com/questions/10230227/find-values-in-common-between-two-arrays
    # http://stackoverflow.com/questions/3794039/how-to-find-a-hash-key-containing-a-matching-value
    # http://stackoverflow.com/questions/24295763/find-intersection-of-arrays-of-hashes-by-hash-value
    # http://stackoverflow.com/questions/8639857/rails-3-how-to-get-the-difference-between-two-arrays

    stale_sessions = self.plex_sessions.map {|known_session| known_session.session_key} - plex_sessions.map {|new_session| new_session["sessionKey"]}

    logger.debug("stale_sessions #{stale_sessions}")

    stale_sessions.each do |stale_session|
      begin
        PlexSession.find_by(session_key: stale_session).destroy
      rescue Exception => error
        logger.error("Service.get_plex_sessions() could not delete session:")
        logger.error(error)
      end
    end


    sessions_to_update = plex_sessions.map {|new_session| new_session["sessionKey"]} & self.plex_sessions.map {|known_session| known_session.session_key}
    logger.debug("sessions_to_update #{sessions_to_update}")

    new_view_offsets = {}

    plex_sessions.each do |new_session|
      new_view_offsets.merge!(new_session["sessionKey"] => new_session["viewOffset"])
    end

    logger.debug("new_view_offsets #{new_view_offsets}")
    sessions_to_update.each do |known_session_key|
      logger.debug("new_view_offsets at known_session key: #{new_view_offsets[known_session_key]}")
      update_plex_session(self.plex_sessions.find_by(session_key: known_session_key), new_view_offsets[known_session_key])
    end

    new_sessions = plex_sessions.map {|new_session| new_session["sessionKey"]} - self.plex_sessions.map {|known_session| known_session.session_key}

    logger.debug("new_sessions #{new_sessions}")
    sessions_to_add = plex_sessions.select {|matched| new_sessions.include?(matched["sessionKey"])}

    logger.debug("sessions_to_add #{sessions_to_add}")
    sessions_to_add.each {|new_session| add_plex_session(new_session)}


  end

  def add_plex_session(new_session)
    begin
      #expression will get the username out of the messy nested json
      expression = new_session["_children"].find { |e| e["_elementType"] == "User" }["title"]
      #if the user's title (read username) is blank, set it to "Local"
      #otherwise, set the name of the session to the user's username
      new_session_name = expression == "" ? "Local" : expression #check that shit out
      # TV shows need a parent thumb for their cover art
      if new_session.has_key? "parentThumb"
        temp_thumb = new_session["parentThumb"]
      else
        temp_thumb = new_session["thumb"]
      end
      #create a new sesion object with the shit we found in the json blob
      self.plex_sessions.create!(user_name: new_session_name, description: new_session["summary"],
                                 media_title: new_session["title"], total_duration: new_session["duration"],
                                 progress: new_session["viewOffset"], thumb_url: temp_thumb,
                                 connection_string: "https://#{connect_method()}:#{self.port}",
                                 session_key: new_session["sessionKey"])


    rescue => error
      logger.error("add_plex_session(new_session) in service.rb error")
      logger.error(error)
      return nil
    end
  end

  def update_plex_session(existing_session, updated_session_viewOffset)
    begin
      existing_session.update!(:progress => updated_session_viewOffset)
    rescue Exception => error
      logger.error("Could not update plex session:")
      logger.error(error)
    end

  end



  def plex_recently_added()

  end
end
