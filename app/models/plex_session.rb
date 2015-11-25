class PlexSession < PlexObject

  has_one :plex_object, as: :plex_object_flavor, dependent: :destroy
  delegate :id, :to => :plex_object, :prefix => true
  validates_presence_of :user_name
  validates_presence_of :session_key
  # validates :session_key, uniqueness: { scope: :plex_object_id }
end
