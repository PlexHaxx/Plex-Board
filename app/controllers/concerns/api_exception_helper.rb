class ApiExceptionHelper < RestClient::Exception
  extend ActiveSupport::Concern

  def initialize(message, response)
    self.message = message
    self.response = response
  end
end