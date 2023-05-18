require 'faraday'

module Faraday
  class Response
    # Add an alias of status to code to feel more like httpclient
    alias code status
  end
end